extends RefCounted
## T11-D: prerequisite pool, source-frozen rewards, bounded children and tradeoffs.

const IDS: Array[String] = ["branch_harvest", "branch_ricochet", "slender_gale", "heavy_draw"]
var assertion: Callable
var base: RefCounted
var fixture: RefCounted
var offers: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)
	fixture = preload("res://tests/test_penetration_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T11-D: " + message)

func setup(tree: SceneTree, ids: Array[String]) -> Dictionary:
	return fixture.setup(tree, ids)

func equip(run: RunModel, ids: Array[String]) -> void:
	base._equip(run, ids)

func run_all(tree: SceneTree) -> void:
	_catalog_and_pool()
	_sources()
	await _collision_and_launch(tree)
	await _children(tree)
	await _reward_flight(tree)
	await _boss_reward(tree)
	await _freeze_selection(tree)
	await _legacy(tree)

func _catalog_and_pool() -> void:
	var run := RunModel.new()
	var traits: int = 0
	var costs: int = 0
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: traits += 1
		if reward.has_debuff: costs += 1
	verify(EncounterCatalog.ALL.size() == 24 and traits == 18 and costs == 5, "final catalog has six ordinary and eighteen traits, five with costs")
	for id: String in IDS:
		var reward: EncounterData = EncounterCatalog.find(id)
		verify(reward.is_trait and reward.trait_key == id and not run.encounter_comparison(reward).is_empty(), "trait metadata and explanation: " + id)
	for id: String in ["branch_harvest", "branch_ricochet"]:
		verify(EncounterCatalog.find(id).requires_trait == "piercing_split" and not run.encounter_has_gain(EncounterCatalog.find(id)) and run.encounter_description(EncounterCatalog.find(id)).contains("需要先获得"), "children require selected split: " + id)
	var seen: Dictionary = {}
	var safe_all: bool = true
	for seed_value: int in range(240):
		run.rng.seed = seed_value + 31554
		var reserved: Array[String] = []
		var safe: bool = false
		for id: String in EncounterCatalog.draft(run.rng, reserved, EncounterCatalog.ALL, run.encounter_has_gain):
			seen[id] = true
			var reward: EncounterData = EncounterCatalog.find(id)
			safe = safe or (not reward.is_trait and not reward.has_debuff)
		safe_all = safe_all and safe
	verify(safe_all and seen.size() == 22 and not seen.has(IDS[0]) and not seen.has(IDS[1]), "pre-split seeded drafts never expose unusable children but expose both costs with safe alternatives")
	equip(run, ["piercing_split"])
	verify(run.encounter_has_gain(EncounterCatalog.find(IDS[0])) and run.encounter_has_gain(EncounterCatalog.find(IDS[1])), "selecting split unlocks both child traits")
	var reserved: Array[String] = ["piercing_split"]
	var before: Array[String]
	var unique: bool = true
	for index: int in range(90):
		before = reserved.duplicate()
		var safe: bool = false
		for id: String in EncounterCatalog.draft(run.rng, reserved, EncounterCatalog.ALL, run.encounter_has_gain):
			var reward: EncounterData = EncounterCatalog.find(id)
			if reward.is_trait: unique = unique and not before.has(id)
			else: safe = safe or not reward.has_debuff
		safe_all = safe_all and safe
	verify(reserved.size() == 18 and unique and safe_all and reserved.has(IDS[0]) and reserved.has(IDS[1]), "unlocked pool displays remaining seventeen traits exactly once including unchosen children")
	var f := RunModel.new()
	offers.entitle(f)
	f.offer_encounter()
	f.choices.assign(["second_wind", "branch_harvest", "heavy_draw"])
	verify(not f.choose_encounter("branch_harvest", f.encounter_offer_id), "manual/cached choice cannot bypass missing split")
	offers.capped(f)
	var rng_state: int = f.rng.state
	var old_seen: Array[String] = f.seen_encounters.duplicate()
	f.offer_encounter()
	verify(f.choices.is_empty() and f.can_skip_encounter() and f.rng.state == rng_state and f.seen_encounters == old_seen, "capped ordinary pool never forces a cost or consumes unseen prerequisite traits")
	verify(f.skip_encounter(f.encounter_offer_id) and f.phase == RunModel.Phase.PLAYING, "exhausted confirmation remains usable")

func _sources() -> void:
	var run := RunModel.new()
	var original: Dictionary = run.stats.to_dict()
	equip(run, ["slender_gale", "heavy_draw"])
	verify(is_equal_approx(run.stats.arrow_size, 0.7) and is_equal_approx(run.stats.launch_speed, 612.5) and is_equal_approx(run.stats.damage, 33.6) and is_equal_approx(run.stats.reload_seconds, 0.8775), "tradeoffs apply each configured factor exactly once")
	verify(GameCatalog.BASE_BOW.to_dict() == original, "base resource is not rewritten by tradeoffs")
	var expected: Dictionary = run.stats.to_dict()
	for index: int in range(40): run.rebuild_stats()
	verify(run.stats.to_dict() == expected and RunModel.from_dict(run.to_dict()).stats.to_dict() == expected, "repeat rebuild and restore do not compound factors")
	run.encounter_picks["rainfall"] = 3
	run.encounter_picks["steady_power"] = 2
	run.encounter_picks["quick_nock"] = 2
	equip(run, ["unified_arrow", "swarm_precision", "critical_forging", "critical_ricochet", "broad_precision"])
	run.skill_levels = {"quantity": 2, "damage": 2, "size": 2, "critical": 2, "penetration": 1}
	run.rebuild_stats()
	var evaluation: StatEvaluation = run.evaluate_stats(run.skill_levels, run.encounter_picks)
	verify(is_equal_approx(evaluation.raw.damage, (24 + 24 + 16) * 1.1 * pow(0.85, 2) * 1.4) and is_equal_approx(evaluation.raw.arrow_size, 1.7 * 0.7), "all additive/percent/quantity sources precede tradeoff factors")
	verify(run.stats.arrow_count == 1 and is_equal_approx(run.stats.damage, evaluation.raw.damage * 6) and is_equal_approx(run.stats.arrow_size, 1.7 * 0.7 * sqrt(6)) and run.stats.crit_chance == 0 and run.stats.bounces == 7, "unity and critical conversions consume modified raw sources without circular recomputation")
	for skill: RunSkillData in [SkillCatalog.find(&"damage"), SkillCatalog.find(&"size")]:
		run.phase = RunModel.Phase.SHOP
		run.gold = 10000
		var preview: Dictionary = run.preview_skill(skill).to_dict()
		verify(run.buy(skill) and run.stats.to_dict() == preview, "future skill purchase matches factored preview: " + String(skill.id))
	verify(run.skill_comparison(SkillCatalog.find(&"size")).contains("靶心增伤") and run.stat_explanations(run.evaluate_stats(run.skill_levels, run.encounter_picks)).size() > 6, "size precision and full tradeoff trace remain visible")
	var cap := RunModel.new()
	cap.encounter_picks = {"slender_gale": 1, "heavy_draw": 1, "steady_power": 100000}
	cap.rebuild_stats()
	verify(cap.stats.damage == 1000000 and cap.stats.arrow_size >= 0.5 and cap.stats.launch_speed <= 1000 and cap.stats.reload_seconds <= 3, "factored stats retain existing safety caps")
	cap.encounter_picks.erase("heavy_draw")
	cap.rebuild_stats()
	verify(not cap.encounter_has_gain(EncounterCatalog.find("heavy_draw")), "damage-capped build does not offer pure reload cost")
	cap.legacy_skill_levels = {"velocity": 20, "haste": 10}
	cap.encounter_picks.erase("slender_gale")
	cap.encounter_picks["heavy_draw"] = 1
	cap.rebuild_stats()
	verify(cap.stats.launch_speed == 1000 and cap.stats.reload_seconds == 0.15 and not cap.encounter_has_gain(EncounterCatalog.find("slender_gale")), "speed ceiling filters size-only cost and reload floor survives source factor")
	var slow := RunModel.new()
	slow.legacy_skill_levels["haste"] = 2
	slow.rebuild_stats()
	var next: BowStats = slow.preview_encounter(EncounterCatalog.find("heavy_draw"))
	verify(is_equal_approx(next.reload_seconds, slow.stats.reload_seconds * 1.35), "reload cost is a source factor, not frozen additive time")

func _collision_and_launch(tree: SceneTree) -> void:
	for slim: bool in [false, true]:
		var ids: Array[String] = []
		if slim: ids.append("slender_gale")
		var f: Dictionary = setup(tree, ids)
		var world: ArcheryWorld = f.world
		var target: ArcheryTarget = world.targets[0]
		var edge: float = target.collision_volumes()[0]["rect"].end.y
		var arrow: Arrow = base._primary(world, Vector2(160, edge + 1.7), Vector2(500, 0))
		arrow._physics_process(0.1)
		verify((target.hp == 10000) == slim and is_equal_approx(arrow.stats.collision_radius(), 1.4 if slim else 2.0), "actual round head collider shrinks and old grazing contact disappears: " + str(slim))
		world.queue_free()
		await tree.process_frame
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	equip(run, ["slender_gale", "heavy_draw"])
	var world: ArcheryWorld = base._world(tree, session)
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	base._freeze(world)
	verify(is_equal_approx(world.arrows[0].velocity.x, 612.5) and is_equal_approx(world.reload_left, 0.8775) and is_equal_approx(world.arrows[0].stats.damage, 33.6) and run.shots_left == 9, "real release uses speed, damage, size and reload at one draw cost")
	world.queue_free()
	await tree.process_frame

func _children(tree: SceneTree) -> void:
	for budget: int in [0, 8, 31, 32]:
		var f: Dictionary = setup(tree, ["piercing_split", "branch_ricochet", "branch_harvest", "ricochet_haste", "wall_forging", "echo_strike", "critical_flow"])
		var world: ArcheryWorld = f.world
		var parent: Arrow = base._primary(world, Vector2(160, 160), Vector2(500, 0))
		parent.remaining_bounces = budget
		parent.critical_stacks = 2
		parent.bounce_stacks = 1
		parent._physics_process(0.07)
		base._freeze(world)
		verify(world.arrows.size() == 3 and parent.remaining_bounces == budget, "real split does not add mother budget: " + str(budget))
		var child: Arrow = world.arrows[1]
		verify(child.remaining_bounces == mini(32, budget + 2) and child.parent_source_id == parent.source_id and child.split_spent and child.effects.split_count == 0 and child.effects.child_gold_bonus == 0.5 and child.critical_stacks == 2, "child extra budget, source, half frozen damage and non-recursion: " + str(budget))
		var before_damage: float = child.stats.damage
		child.position = Vector2(629, 90)
		child.velocity = Vector2(500, 0)
		child._physics_process(0.005)
		verify(child.velocity.x < 0 and is_equal_approx(child.velocity.length(), 625) and child.remaining_bounces == mini(32, budget + 2) - 1 and child.bounce_stacks == 2 and child.echo_ready and child.stats.damage == before_damage, "extra child reflection triggers existing haste/armor/echo once: " + str(budget))
		var size_before: int = world.arrows.size()
		child.position = Vector2(250, 150)
		child.velocity = Vector2(500, 0)
		child._physics_process(0.25)
		verify(world.arrows.size() <= size_before and not child.split_pending, "child real next-target hit never spawns grandchildren")
		world.queue_free()
		await tree.process_frame
	var f: Dictionary = setup(tree, ["piercing_split", "branch_ricochet"])
	var world: ArcheryWorld = f.world
	world.run.stats.arrow_count = 32
	world.run.stats.spread_degrees = 0
	world.run.stats.bounces = 0
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	base._freeze(world)
	for parent: Arrow in world.arrows.duplicate():
		parent.position = Vector2(160, 160)
		parent.velocity = Vector2(500, 0)
		parent._physics_process(0.07)
	base._freeze(world)
	verify(world.arrows.size() == 96 and world.projectile_ledger["1"]["children"] == 64 and world.run.shots_left == 9, "extra child bounce does not raise 32/64 family cap or draw cost")
	world.queue_free()
	await tree.process_frame

func _reward_flight(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["piercing_split", "branch_harvest", "branch_ricochet", "bullseye_wave"])
	var world: ArcheryWorld = f.world
	var session: GameSession = f.session
	world.run.encounter_picks["windfall"] = 2
	world.run.rebuild_stats()
	offers.entitle(world.run, 0)
	world.run.stats.damage = 100
	world.run.stats.gravity = 0
	world.run.stats.crit_chance = 0
	world.run.stats.armor_penetration = 20
	world.run.shots_left = 1
	world.targets[1].hp = 10
	world.targets[1].max_hp = 10
	world.targets[2].anchor = Vector2(330, 150)
	world.targets[2].tick(0, 0)
	world.targets[2].hp = 3
	world.targets[2].max_hp = 3
	var parent: Arrow = base._primary(world, Vector2(160, 160), Vector2(500, 0))
	parent._physics_process(0.07)
	base._freeze(world)
	var child: Arrow = world.arrows[1]
	child.position = Vector2(250, 150)
	child.velocity = Vector2(500, 0)
	child._physics_process(0.04)
	verify(world.targets[1].hp == 0 and world.targets[2].hp == 0 and session.profile.total_score == 0 and world.run.shots_left == 0, "last draw child direct and area kills wait for family settlement")
	var hits: Array = world.pending_volleys["1"]
	var boosted: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if hit.has("child_gold_bonus"): boosted.append(hit)
	verify(boosted.size() == 2 and boosted[0]["parent_source_id"] == 0 and boosted[0]["child_gold_bonus"] == 0.5 and boosted[1]["damage_kind"] == "area", "only true child kills stamp frozen bonus, including secondary source")
	verify(not hits[0].has("child_gold_bonus") and boosted[0]["reward_gold"] == 8 and boosted[1]["reward_gold"] == 8, "mother/no-kill has no premium and base reward remains unmodified in ledger")
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	var path: String = "user://tests/t11d-flight.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(payload), "child budgets and pending source-frozen premium save atomically")
	var loaded := GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	copy.shot_settled.connect(loaded.settle_shot)
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(loaded.world_snapshot)
	base._freeze(copy)
	verify(same_flight(copy.snapshot(), world.snapshot()) and copy.run.rng.state == world.run.rng.state, "disk Continue restores family, secondary victims, premium and RNG; time within serialization precision")
	for field: ArcheryWorld in [world, copy]:
		for live: Arrow in field.arrows.duplicate(): live._physics_process(0.015)
	verify(same_flight(copy.snapshot(), world.snapshot()) and copy.run.rng.state == world.run.rng.state, "resumed children do not replay kills or diverge in source/physics state")
	for field: ArcheryWorld in [world, copy]:
		# Duplicate hit is ignored by hit identity, not credited as another child gain.
		field.pending_volleys["1"].append(field.pending_volleys["1"][1].duplicate(true))
		for live: Arrow in field.arrows.duplicate(): live._finish()
		field._settle_shots()
	verify(world.run.gold == 36 and copy.run.gold == 36 and session.profile.total_score == 80 and loaded.profile.total_score == 80 and world.run.defeated_count == 62 and world.run.combo == 1, "each child kill grants base8 × child1.5 × gold1.5 once, score and progress unchanged")
	world._settle_shots()
	verify(world.run.gold == 36 and session.profile.total_score == 80, "repeat settlement cannot replay child premium")
	world.run.settle_volley()
	verify(world.run.phase == RunModel.Phase.SUPPLY, "child premium can fund final draw supply only after all children settle")
	world.run.decline_supply(world.run.supply_offer_id)
	verify(world.run.is_finished() and world.run.gold == 0 and session.last_run_summary["gold_earned"] == 36 and session.last_run_summary["defeat_score"] == 80, "terminal last draw keeps earned premium in summary but clears run coins")
	for key: String in ["child_gold_bonus", "child_bounces"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["arrows"][0]["effects"].erase(key)
		verify(not store.write(bad), "reject missing frozen child field: " + key)
	for change: Array in [["child_gold_bonus", NAN], ["child_gold_bonus", 3.0], ["child_bounces", 33], ["child_bounces", 1.5]]:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["arrows"][1]["effects"][change[0]] = change[1]
		verify(not store.write(bad), "reject illegal child effect: " + str(change[0]) + str(change[1]))
	for change: Array in [["parent_source_id", -1], ["parent_source_id", 1], ["child_gold_bonus", NAN], ["child_gold_bonus", 0.0], ["broken", false], ["effective", 0.0]]:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["pending_volleys"]["1"][1][change[0]] = change[1]
		verify(not store.write(bad), "reject forged premium source/kill: " + str(change[0]) + str(change[1]))
	var bad: Dictionary = payload.duplicate(true)
	bad["world"]["arrows"][1]["remaining_bounces"] = 33
	verify(not store.write(bad), "reject child budget above total cap")
	verify(store.read() == JSON.parse_string(JSON.stringify(payload, "", true, true)), "rejected premium writes retain prior good family transaction")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _boss_reward(tree: SceneTree) -> void:
	# Boundary fixture creates children before their first Boss contact; shared HP still applies.
	var combat: RefCounted = preload("res://tests/test_boss_combat.gd").new(assertion)
	var world: ArcheryWorld = combat.setup(tree)
	equip(world.run, ["piercing_split", "branch_harvest", "branch_ricochet"])
	var parent: Arrow = combat.shot(world, Vector2(430, 235), Vector2(500, 0), 3000, 30)
	world.waiting_for_settle = true
	world._on_split(parent)
	base._freeze(world)
	parent.split_spent = true
	var child: Arrow = world.arrows[1]
	child._physics_process(0.15)
	verify(world.boss.hp == 0 and world.pending_volleys["1"].size() == 1 and world.pending_volleys["1"][0]["child_gold_bonus"] == 0.5 and child.hit_slots.has(-1) and child.hit_slots.has(-3), "valid child Boss kill stamps one premium and claims shared body/core life")
	var session: GameSession = combat.session(world)
	for live: Arrow in world.arrows.duplicate(): live._finish()
	world._settle_shots()
	verify(session.profile.total_score == 1200 and world.run.bosses_defeated == 1 and world.run.boss_reward_log.size() == 1 and world.run.boss_reward_log[0]["gold"] == 1260 and world.run.defeated_count == 130, "Boss premium multiplies only coins, one victory/choice/draw grant and no ordinary progress")
	world.queue_free()
	await tree.process_frame

func _freeze_selection(tree: SceneTree) -> void:
	for id: String in IDS:
		var f: Dictionary = setup(tree, ["piercing_split"])
		var world: ArcheryWorld = f.world
		world.reload_left = 0.31
		var arrow: Arrow = base._primary(world, Vector2(160, 160), Vector2(500, 0))
		var before: Dictionary = arrow.snapshot()
		offers.entitle(world.run)
		world.run.offer_encounter()
		world.run.choices.assign(["second_wind", id, "steady_power"])
		if not world.run.seen_encounters.has(id): world.run.seen_encounters.append(id)
		verify(world.run.choose_encounter(id, world.run.encounter_offer_id) and arrow.snapshot() == before and world.reload_left == 0.31, "new choice preserves active arrow and timer: " + id)
		var next: Arrow = base._primary(world, Vector2(160, 90), Vector2(500, 0))
		verify(next.effects.to_dict() == world.run.projectile_effects().to_dict() and next.stats.to_dict() == world.run.stats.to_dict(), "next draw alone samples new stats/effects: " + id)
		arrow._physics_process(0.07)
		base._freeze(world)
		var child: Arrow = world.arrows[2]
		verify(child.effects.child_bounces == 0 and child.effects.child_gold_bonus == 0 and child.stats.damage == float(before["stats"]["damage"]) * 0.5, "future split of already flying mother retains old child coefficients: " + id)
		world.queue_free()
		await tree.process_frame

func _legacy(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["piercing_split", "charged_breach", "bullseye_wave", "critical_flow", "broad_precision", "piercing_edge", "wall_forging", "echo_strike"])
	var world: ArcheryWorld = f.world
	var session: GameSession = f.session
	world.run.stats.crit_chance = 1
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow.bounce_stacks = 2
	arrow.echo_ready = true
	arrow._physics_process(0.03)
	world.reload_left = 0.31
	offers.entitle(world.run)
	world.run.offer_encounter()
	world.run.choices.assign(["second_wind", "steady_power", "quick_nock"])
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	for state: Dictionary in payload["world"]["arrows"]:
		state["combat_schema"] = 2
		state["effects"].erase("child_gold_bonus")
		state["effects"].erase("child_bounces")
	var path: String = "user://tests/t11d-v14.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 14, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v14") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v14 archived byte-for-byte before upgrading current version")
	var migrated: Dictionary = loaded.world_snapshot["arrows"][0]
	verify(migrated["combat_schema"] == 3 and migrated["effects"]["child_gold_bonus"] == 0 and migrated["effects"]["child_bounces"] == 0 and migrated["critical_stacks"] == 1 and migrated["area_slots"].size() == 1 and int(migrated["area_slots"][0]) == 1 and migrated["penetration_exits"].size() == 1 and migrated["split_pending"], "neutral child upgrade preserves all older dynamic/secondary/exit state")
	verify(loaded.run.choices == world.run.choices and loaded.run.encounter_offer_id == world.run.encounter_offer_id and loaded.run.rng.state == world.run.rng.state and loaded.world_snapshot["reload_left"] == 0.31, "catalog expansion does not reroll old fixed group or timing/RNG")
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(loaded.world_snapshot)
	base._freeze(copy)
	verify(copy.snapshot() == world.snapshot(), "upgraded full simulation matches original flight exactly")
	for field: ArcheryWorld in [world, copy]: field.arrows[0]._physics_process(0.04)
	base._freeze(world)
	base._freeze(copy)
	verify(copy.snapshot() == world.snapshot() and copy.arrows[1].effects.child_bounces == 0 and copy.arrows[1].critical_stacks == 1, "continued old pending split keeps existing inheritance without retroactive new effects")
	loaded.capture_checkpoint(copy.snapshot())
	verify(store.write(loaded.save_payload()) and not store.read().is_empty() and store.migration_notice.is_empty(), "current version repeat read does not migrate or replay gains")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v14"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func same_flight(a: Dictionary, b: Dictionary) -> bool:
	# JSON rounds a 0.07+0.04 elapsed sum by one ULP; every other field stays exact.
	if a["arrows"].size() != b["arrows"].size(): return false
	for index: int in range(a["arrows"].size()):
		if absf(float(a["arrows"][index]["elapsed"]) - float(b["arrows"][index]["elapsed"])) > 1.0e-12: return false
		a["arrows"][index]["elapsed"] = 0.0
		b["arrows"][index]["elapsed"] = 0.0
	return a == b
