extends RefCounted
## T07-A: real trait pool, launch snapshots, post-exit split, budget and v6 migration.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T07-A: " + message)

func run_all(tree: SceneTree) -> void:
	_attributes_and_pool()
	await _split_flight(tree)
	await _bounce(tree)
	await _eligibility(tree)
	await _budget(tree)
	await _ui_and_launch(tree)
	await _migrate_v6(tree)

func _equip(run: RunModel, ids: Array[String]) -> void:
	for id: String in ids:
		run.encounter_picks[id] = 1
		if not run.seen_encounters.has(id): run.seen_encounters.append(id)
	# Historical all-trait stress fixtures represent migrated pre-backpack runs.
	run.artifact_capacity = maxi(RunModel.ARTIFACT_SLOTS, run.artifact_ids().size())
	# Fixture builds still represent enough earned rewards for strict save validation.
	var picked: int = 0
	for count: Variant in run.encounter_picks.values(): picked += int(count)
	run.defeated_count = maxi(run.defeated_count, picked * EncounterCatalog.RULES.kills_per_reward)
	run.encounter_rewards_generated = run.defeated_count / EncounterCatalog.RULES.kills_per_reward
	run.rebuild_stats()

func _attributes_and_pool() -> void:
	var run := RunModel.new()
	_equip(run, ["swarm_precision"])
	verify(is_equal_approx(run.stats.crit_chance, 0.1), "one arrow gives no extra crit")
	run.encounter_picks["rainfall"] = 3
	run.skill_levels = {"quantity": 2, "critical": 1}
	run.rebuild_stats()
	var raw: BowStats = run.calculate_raw_stats(run.skill_levels, run.encounter_picks)
	verify(raw.arrow_count == 6 and is_equal_approx(raw.crit_chance, 0.15) and is_equal_approx(run.stats.crit_chance, 0.25), "raw skill and ordinary sources precede arrow-count linkage")
	verify(is_equal_approx(run.stats.damage, 24 * pow(0.85, 2)), "linkage never changes quantity damage penalty")
	var expected: Dictionary = run.stats.to_dict()
	for index: int in range(30): run.rebuild_stats()
	verify(run.stats.to_dict() == expected and raw.crit_chance < run.stats.crit_chance, "rebuild does not compound or overwrite original crit")
	run.open_skills()
	run.gold = 10000
	var preview: Dictionary = run.preview_skill(SkillCatalog.find(&"quantity")).to_dict()
	verify(run.buy(SkillCatalog.find(&"quantity")) and run.stats.to_dict() == preview and is_equal_approx(run.stats.crit_chance, 0.27), "later quantity purchase updates linkage and matches actual preview")
	verify(SkillCatalog.find(&"quantity").comparison(BowStats.from_dict(expected), run.stats).contains("联动暴击"), "quantity card explains crit gained by linkage")
	run.close_skills()
	preview = run.preview_encounter(EncounterCatalog.find("rainfall")).to_dict()
	verify(int(preview["arrow_count"]) == 8 and is_equal_approx(float(preview["crit_chance"]), 0.29) and run.encounter_picks["rainfall"] == 3, "ordinary arrow preview also includes linkage without modifying picks")
	var restored: RunModel = RunModel.from_dict(run.to_dict())
	verify(restored.stats.to_dict() == run.stats.to_dict(), "linked stats restore exactly")
	run.encounter_picks["rainfall"] = 100000
	run.skill_levels["critical"] = 8
	run.rebuild_stats()
	verify(run.stats.arrow_count == 32 and run.stats.crit_chance == 1 and run.calculate_raw_stats(run.skill_levels, run.encounter_picks).arrow_count > 32, "effective arrow count and crit cap retain unmodified raw sources")
	_equip(run, ["piercing_split", "ricochet_haste"])
	var effects: ArrowEffects = run.projectile_effects()
	verify(effects.split_count == 2 and effects.bounce_multiplier == 1.25, "multiple selected traits coexist in launch effects")
	var fresh := RunModel.new()
	verify(fresh.projectile_effects().split_count == 0 and fresh.projectile_effects().bounce_multiplier == 1 and fresh.stats.crit_chance == 0.1, "new run clears all three trait effects")
	var seen: Array[String] = []
	var random := RandomNumberGenerator.new()
	random.seed = 314159
	var safe_all: bool = true
	var unique_all: bool = true
	for iteration: int in range(20):
		var before: Array[String] = seen.duplicate()
		var safe: bool = false
		for id: String in EncounterCatalog.draft(random, seen, EncounterCatalog.ALL):
			var reward: EncounterData = EncounterCatalog.find(id)
			if reward.is_trait: unique_all = unique_all and not before.has(id) and seen.has(id)
			else: safe = safe or not reward.has_debuff
		safe_all = safe_all and safe
	var trait_count: int = 0
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: trait_count += 1
	verify(safe_all and unique_all and seen.size() == trait_count, "actual traits are shown once with an ordinary safe option in every offer")
	var depleted: Array[String] = EncounterCatalog.draft(random, seen, EncounterCatalog.ALL)
	var ordinary_only: bool = depleted.size() == 3
	for id: String in depleted: ordinary_only = ordinary_only and not EncounterCatalog.find(id).is_trait
	verify(ordinary_only, "trait pool depletion drafts distinct ordinary choices from the expanded pool")

func _world(tree: SceneTree, session: GameSession) -> ArcheryWorld:
	var world := ArcheryWorld.new()
	world.run = session.run
	world.shot_settled.connect(session.settle_shot)
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.build_field()
	for index: int in range(world.targets.size()):
		var target: ArcheryTarget = world.targets[index]
		target.anchor = Vector2(180 + index * 90, 150)
		target.tick(0, 0)
		target.hp = 100
		target.max_hp = 100
		target.armor = 0
	return world

func _primary(world: ArcheryWorld, origin: Vector2, speed: Vector2) -> Arrow:
	world.run.consume_shot()
	world.waiting_for_settle = true
	var arrow := Arrow.new()
	arrow.setup(origin, speed, world.run.stats, 1, world.run.rng)
	arrow.shot_id = world.run.shot_sequence
	arrow.effects = world.run.projectile_effects()
	world._attach_arrow(arrow)
	arrow.set_physics_process(false)
	return arrow

func _freeze(world: ArcheryWorld) -> void:
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)

func _split_flight(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	_equip(run, ["piercing_split", "ricochet_haste", "swarm_precision"])
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	run.stats.armor_penetration = 1
	run.stats.bounces = 2
	run.shots_left = 1
	var world: ArcheryWorld = _world(tree, session)
	world.targets[0].hp = 1
	world.targets[1].hp = 30
	var parent: Arrow = _primary(world, Vector2(160, 150), Vector2(500, 0))
	parent._physics_process(0.03)
	verify(parent.split_pending and parent.split_spent and world.arrows.size() == 1 and parent.position.x < 189, "penetration arms split but children wait until head exits target")
	var early: Dictionary = world.snapshot()
	var early_copy := ArcheryWorld.new()
	early_copy.run = RunModel.from_dict(run.to_dict())
	tree.root.add_child(early_copy)
	early_copy.set_physics_process(false)
	early_copy.build_field(early)
	_freeze(early_copy)
	verify(early_copy.snapshot() == early, "save inside target retains pending exit volume and consumed trigger")
	early_copy.arrows[0]._physics_process(0.04)
	_freeze(early_copy)
	verify(early_copy.arrows.size() == 3 and early_copy.arrows[1].position.x > 189, "restored pending split emits two children after exiting far edge")
	early_copy.queue_free()
	parent._physics_process(0.04)
	_freeze(world)
	verify(world.arrows.size() == 3 and world.projectile_ledger["1"] == {"next_source": 3, "children": 2}, "one split keeps parent and adds two unique sources under one draw")
	var child: Arrow = world.arrows[1]
	verify(child.parent_source_id == 0 and child.shot_id == parent.shot_id and child.source_id == 1 and world.arrows[2].source_id == 2, "children record source ancestry and same shot identity")
	verify(child.hit_slots == [0] and child.effects.split_count == 0 and child.split_spent and child.remaining_bounces == 2, "children inherit exclusions and bounce budget, without recursive splitting")
	verify(child.stats.damage == parent.stats.damage * 0.5 and child.stats.crit_chance == parent.stats.crit_chance and child.effects.bounce_multiplier == 1.25, "half damage retains launch crit and bounce-speed snapshot")
	verify(is_equal_approx(child.elapsed, parent.elapsed) and is_equal_approx(child.velocity.angle(), -deg_to_rad(12)), "children inherit lifetime and symmetric fan angles")
	world._settle_shots()
	verify(run.last_settled_shot == -1 and not run.is_finished() and run.shots_left == 0, "last draw cannot settle before descendants finish")
	var state: Dictionary = world.snapshot()
	session.capture_checkpoint(state)
	var path: String = "user://tests/t07-flight.json"
	_clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "live parent and children serialize with budget")
	var disk: GameSession = GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = disk.run
	copy.shot_settled.connect(disk.settle_shot)
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(disk.world_snapshot)
	_freeze(copy)
	verify(copy.snapshot() == state and disk.run.rng.state == run.rng.state, "disk restores flight, source counter, spent trigger, child budgets and RNG exactly")
	var bad: Dictionary = store.read().duplicate(true)
	bad["world"]["arrows"][1]["source_id"] = 0
	verify(not store.write(bad), "duplicate arrow source refuses overwrite")
	bad = store.read().duplicate(true)
	bad["world"]["arrows"][1]["effects"]["split_count"] = 2
	verify(not store.write(bad), "recursive child capability refuses overwrite")
	bad = store.read().duplicate(true)
	bad["world"]["projectile_ledger"]["1"]["children"] = 65
	verify(not store.write(bad), "budget beyond hard limit refuses overwrite")
	bad = store.read().duplicate(true)
	bad["world"]["arrows"][0]["effects"]["bounce_multiplier"] = "invalid"
	verify(not store.write(bad), "malformed effect numeric value refuses overwrite")
	bad = store.read().duplicate(true)
	bad["run"]["encounter_picks"]["piercing_split"] = 2
	verify(not store.write(bad), "trait cannot be selected twice in persisted state")
	# Identical simulation from the saved boundary checks rewards and no second split.
	for field: ArcheryWorld in [world, copy]:
		for tick: int in range(20):
			for arrow: Arrow in field.arrows.duplicate(): arrow._physics_process(0.01)
			_freeze(field)
		verify(field.projectile_ledger["1"]["children"] == 2, "later pierced targets and child hits cannot create a second split")
		verify(field.pending_volleys["1"].size() >= 3, "parent and children contribute distinct real hit events")
	verify(world.snapshot() == copy.snapshot() and run.rng.state == disk.run.rng.state, "restored descendants resolve contacts deterministically")
	for field: ArcheryWorld in [world, copy]:
		for arrow: Arrow in field.arrows.duplicate(): arrow._finish()
		field._settle_shots()
		field.run.settle_volley()
	verify(run.last_settled_shot == 1 and run.is_finished() and disk.run.is_finished() and run.score == disk.run.score, "one draw settles once after whole family ends and then exhausts")
	verify(run.defeated_count == 32 and session.profile.total_score == 80 and disk.profile.total_score == 80 and run.gold_earned == 16, "real parent and child kills award each target once, with no lost or duplicate XP/coins")
	world.queue_free()
	copy.queue_free()
	await tree.process_frame
	_clean(path)

func _bounce(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	_equip(run, ["ricochet_haste"])
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	run.stats.bounces = 3
	var world: ArcheryWorld = _world(tree, session)
	var arrow: Arrow = _primary(world, Vector2(620, 150), Vector2(1000, 0))
	arrow._physics_process(0.02)
	verify(arrow.velocity == Vector2(-1250, 0) and arrow.remaining_bounces == 2 and is_equal_approx(arrow.position.x, 617.4999), "first reflection accelerates immediately and uses remaining frame time")
	arrow.velocity = Vector2(1900, 0)
	arrow.position = Vector2(620, 100)
	arrow._physics_process(0.02)
	verify(is_equal_approx(arrow.velocity.length(), 2000) and arrow.velocity.x < 0, "repeated haste clamps speed while preserving reflection direction")
	arrow.position = Vector2(620, 296)
	arrow.velocity = Vector2(1000, 1000)
	arrow._physics_process(0.02)
	verify(arrow.velocity == Vector2(-1250, -1250) and arrow.remaining_bounces == 0, "corner reflects both axes and applies haste only once")
	arrow._finish()
	var target: ArcheryTarget = world.targets[0]
	target.position = Vector2(600, 150)
	target.hp = 100
	arrow = _primary(world, Vector2(620, 150), Vector2(1000, 0))
	arrow._physics_process(0.04)
	verify(target.hp == 76 and arrow.done, "accelerated reflected path still detects target without tunneling")
	world.queue_free()
	await tree.process_frame

func _eligibility(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	_equip(run, ["piercing_split", "ricochet_haste"])
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	run.stats.armor_penetration = 1
	var world: ArcheryWorld = _world(tree, session)
	world.targets[0].armor = 1
	world.targets[0].hp = 1
	var arrow: Arrow = _primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.1)
	verify(arrow.done and world.targets[0].hp == 0 and world.arrows.is_empty() and world.projectile_ledger["1"]["children"] == 0, "equal penetration kills but cannot pierce or split")
	arrow = _primary(world, Vector2(620, 150), Vector2(500, 0))
	arrow._physics_process(0.1)
	verify(arrow.done and arrow.velocity == Vector2(500, 0), "haste without bounce budget grants no reflection or acceleration")
	world.queue_free()
	await tree.process_frame

func _budget(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	_equip(run, ["piercing_split"])
	var world: ArcheryWorld = _world(tree, session)
	run.consume_shot()
	var parents: Array[Arrow] = []
	for index: int in range(32):
		var arrow := Arrow.new()
		arrow.setup(Vector2(200, 150), Vector2(500, 0), run.stats, 1, run.rng)
		arrow.shot_id = 1
		arrow.source_id = index
		arrow.effects = run.projectile_effects()
		arrow.split_spent = true
		world._attach_arrow(arrow)
		arrow.set_physics_process(false)
		parents.append(arrow)
	for arrow: Arrow in parents: world._on_split(arrow)
	_freeze(world)
	verify(world.arrows.size() == 96 and world.projectile_ledger["1"] == {"next_source": 96, "children": 64}, "32 root arrows spawn at most 64 children with globally unique draw sources")
	world._on_split(parents[0])
	verify(world.arrows.size() == 96, "exhausted budget rejects extra child generation")
	var unique: Dictionary = {}
	for arrow: Arrow in world.arrows: unique[arrow.source_id] = true
	verify(unique.size() == 96, "high-count families have no source ID collisions")
	session.capture_checkpoint(world.snapshot())
	var store := SaveStore.new("user://tests/t07-budget.json")
	verify(store.write(session.to_dict()), "maximum family remains a valid checkpoint")
	var snapshot: Dictionary = world.snapshot()
	world.build_field(snapshot)
	_freeze(world)
	world._on_split(world.arrows[0])
	verify(world.arrows.size() == 96 and world.projectile_ledger["1"]["children"] == 64, "restore retains consumed budget even if parent trigger is requested again")
	world.arrows[32].elapsed = Arrow.MAX_LIFETIME - 0.001
	world.arrows[32]._physics_process(0.01)
	verify(world.arrows.size() == 95, "child cannot refresh family lifetime")
	world.queue_free()
	await tree.process_frame
	_clean("user://tests/t07-budget.json")

func _ui_and_launch(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	main.world.pull = 1
	main.world.direction = Vector2.RIGHT
	main.world._release()
	_freeze(main.world)
	var old: Arrow = main.world.arrows[0]
	var before: Dictionary = old.snapshot()
	for index: int in range(10): main.session.record_defeat("ui-%d" % index, 0, 0)
	main.run.offer_encounter()
	main.run.choices.assign(["windfall", "piercing_split", "swarm_precision"])
	main.run.seen_encounters.assign(["piercing_split", "swarm_precision"])
	main._refresh()
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == "piercing_split": button.pressed.emit(); break
	verify(main.run.encounter_picks.get("piercing_split") == 1 and not tree.paused and old.snapshot() == before, "actual trait button resumes old projectile without changing its launch effects")
	main.world.pull = 1
	main.world._release()
	_freeze(main.world)
	verify(main.world.arrows[1].effects.split_count == 2 and old.effects.split_count == 0, "only future launches receive selected split trait")
	var payload: Dictionary = main.saves.read()
	verify(payload["run"]["encounter_picks"].get("piercing_split") == 1 and payload["world"]["arrows"][0]["effects"]["split_count"] == 0, "actual selection persists trait with unchanged old-arrow snapshot")
	main._navigate("hub")
	payload = main.saves.read()
	verify(payload["world"]["arrows"][1]["effects"]["split_count"] == 2, "new launch effect survives lobby checkpoint")
	main.queue_free()
	await tree.process_frame

func _migrate_v6(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for index: int in range(10): session.record_defeat("old-%d" % index, 40, 8)
	# v6 could only offer ordinary choices; preserve that fixed group after pool expansion.
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: run.seen_encounters.append(reward.id)
	run.offer_encounter()
	run.seen_encounters.clear()
	var world := ArcheryWorld.new()
	world.run = run
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.build_field()
	var arrow := Arrow.new()
	arrow.setup(Vector2(220, 150), Vector2(490, 0), run.stats, 1, run.rng)
	arrow.shot_id = 1
	run.shot_sequence = 1
	world._attach_arrow(arrow)
	arrow.set_physics_process(false)
	var state: Dictionary = world.snapshot()
	state.erase("projectile_schema")
	state.erase("projectile_ledger")
	for key: String in ["effects", "parent_source_id", "split_spent", "split_pending", "split_exit_rect", "combat_schema", "penetration_stacks", "bounce_stacks", "echo_ready", "penetration_exits"]: state["arrows"][0].erase(key)
	session.capture_checkpoint(state)
	var path: String = "user://tests/t07-migration.json"
	_clean(path)
	var original: String = JSON.stringify({"version": 6, "payload": session.to_dict()})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store := SaveStore.new(path)
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v6") == original and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v6 archived byte-for-byte and upgraded to current schema")
	verify(restored.run.choices == run.choices and restored.run.rng.state == run.rng.state and restored.run.pending_encounters == 1 and restored.run.encounter_offer_id == run.encounter_offer_id, "pool expansion does not reroll legacy fixed choice, queue or RNG")
	verify(restored.world_snapshot["arrows"][0]["effects"]["split_count"] == 0 and restored.world_snapshot["projectile_ledger"]["1"]["next_source"] == 1, "v6 flight gains inert effects and correct source ledger without retroactive traits")
	verify(restored.run.gold == 80 and restored.profile.total_score == 400 and restored.run.shots_left == 10, "migration does not replay coins, XP or ammo grants")
	var old_volley: Dictionary = state.duplicate(true)
	old_volley["arrows"].clear()
	for index: int in range(100):
		var legacy_arrow: Dictionary = state["arrows"][0].duplicate(true)
		legacy_arrow.erase("shot_id")
		legacy_arrow.erase("source_id")
		old_volley["arrows"].append(legacy_arrow)
	old_volley.erase("pending_volleys")
	var old_payload: Dictionary = restored.to_dict()
	old_payload["world"] = ArcheryWorld.upgrade_snapshot(old_volley)
	verify(store.write(old_payload) and old_payload["world"]["projectile_ledger"]["0"]["next_source"] == 100, "pre-v5 overlapping draws grouped under reserved shot zero retain all original sources")
	store.read()
	verify(store.migration_notice.is_empty(), "v7 subsequent load does not remigrate")
	world.queue_free()
	await tree.process_frame
	_clean(path)

func _clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v6"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
