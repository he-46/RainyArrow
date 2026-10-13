extends RefCounted
## T11-B: real swept exits/bounces, immutable combinations and disk continuation.

const IDS: Array[String] = ["piercing_edge", "armor_surplus", "echo_strike", "wall_forging"]
const STATE_KEYS: Array[String] = ["combat_schema", "penetration_stacks", "bounce_stacks", "echo_ready", "penetration_exits"]
const EFFECT_KEYS: Array[String] = ["penetration_damage", "penetration_limit", "excess_damage", "excess_limit", "echo_damage", "bounce_penetration", "bounce_penetration_limit"]
var assertion: Callable
var base: RefCounted
var offers: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T11-B: " + message)

func setup(tree: SceneTree, ids: Array[String]) -> Dictionary:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	base._equip(run, ids)
	offers.entitle(run, 0)
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	run.stats.damage = 100
	run.stats.armor_penetration = 20
	run.stats.bounces = 8
	var world: ArcheryWorld = base._world(tree, session)
	world.boss_enabled = false
	for target: ArcheryTarget in world.targets:
		target.hp = 10000
		target.max_hp = 10000
	return {"session": session, "world": world}

func run_all(tree: SceneTree) -> void:
	_catalog()
	await _exit_and_split(tree)
	await _overlapping_and_caps(tree)
	await _bounce_and_echo(tree)
	await _bounce_gate(tree)
	await _boss_and_surplus(tree)
	await _boss_family_storage(tree)
	await _selection_and_snapshots(tree)
	await _storage(tree)
	await _legacy(tree)

func _catalog() -> void:
	var run := RunModel.new()
	var stats: Dictionary = run.stats.to_dict()
	for id: String in IDS:
		var reward: EncounterData = EncounterCatalog.find(id)
		verify(reward != null and reward.is_trait and not reward.has_debuff and reward.trait_key == id, "unique safe trait metadata: " + id)
		verify(not run.encounter_comparison(reward).is_empty(), "actual coefficient preview: " + id)
	base._equip(run, IDS)
	verify(run.stats.to_dict() == stats, "four dynamic effects leave character base stats unchanged")
	var effects: ArrowEffects = run.projectile_effects()
	verify(effects.penetration_damage == 0.15 and effects.penetration_limit == 5 and effects.excess_damage == 0.02 and effects.excess_limit == 1 and effects.echo_damage == 0.5 and effects.bounce_penetration == 3 and effects.bounce_penetration_limit == 5, "all configured defaults sampled together")
	verify(ArrowEffects.from_dict(effects.to_dict()).to_dict() == effects.to_dict(), "effect parameters round trip without aliases")
	verify(RunModel.from_dict(run.to_dict()).projectile_effects().to_dict() == effects.to_dict(), "selected new effects restore from sources")
	var random := RandomNumberGenerator.new()
	random.seed = 90601
	var seen: Array[String] = []
	var safe_all: bool = true
	var unique_all: bool = true
	for iteration: int in range(60):
		var before: Array[String] = seen.duplicate()
		var safe: bool = false
		for id: String in EncounterCatalog.draft(random, seen, EncounterCatalog.ALL):
			var reward: EncounterData = EncounterCatalog.find(id)
			if reward.is_trait: unique_all = unique_all and not before.has(id)
			else: safe = safe or not reward.has_debuff
		safe_all = safe_all and safe
	verify(seen.size() == 18 and safe_all and unique_all, "twenty-four-entry pool exposes eighteen traits once and preserves safe ordinary choices")

func _exit_and_split(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, ["piercing_edge", "piercing_split"])
	var world: ArcheryWorld = fixture.world
	var parent: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	parent._physics_process(0.03)
	verify(world.targets[0].hp == 9900 and parent.penetration_stacks == 0 and parent.penetration_exits.size() == 1, "first hit is unboosted and records a future far-edge exit")
	verify(world.arrows.size() == 1 and parent.split_pending, "split and penetration both wait while head is inside target")
	var state: Dictionary = world.snapshot()
	var copy := ArcheryWorld.new()
	copy.run = RunModel.from_dict(world.run.to_dict())
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(state)
	base._freeze(copy)
	verify(copy.snapshot() == state, "pending penetration plus split restores exact captured volumes")
	for field: ArcheryWorld in [world, copy]:
		field.arrows[0]._physics_process(0.04)
		base._freeze(field)
		verify(field.arrows.size() == 3 and field.arrows[0].penetration_stacks == 1, "same-edge exit gains one layer before child spawn")
		for child: Arrow in field.arrows.slice(1):
			verify(child.penetration_stacks == 1 and child.penetration_exits.is_empty() and child.stats.damage == 50 and child.effects.split_count == 0, "child inherits accumulated gain, half base damage and no phantom pending crossings")
	verify(world.snapshot() == copy.snapshot(), "original and resumed post-exit split remain deterministic")
	parent._physics_process(0.18)
	verify(is_equal_approx(world.targets[1].hp, 9885) and parent.penetration_stacks == 2, "second target receives fifteen-percent gain then exits for next layer")
	verify(parent.stats.damage == 100 and world.run.stats.damage == 100, "real hit boosts never mutate launch or character snapshots")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame

func _overlapping_and_caps(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, ["piercing_edge"])
	var world: ArcheryWorld = fixture.world
	world.targets[1].anchor.x = 184
	world.targets[1].tick(0, 0)
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.04)
	verify(world.targets[0].hp == 9900 and world.targets[1].hp == 9900 and arrow.penetration_exits.size() == 2 and arrow.penetration_stacks == 0, "overlapping targets queue independent exits without premature boosting")
	arrow._physics_process(0.04)
	verify(arrow.penetration_exits.is_empty() and arrow.penetration_stacks == 2, "both overlapping volumes yield one gain each when exited")
	arrow.velocity = -arrow.velocity
	arrow._physics_process(0.07)
	verify(arrow.penetration_stacks == 2 and world.targets[0].hp == 9900 and world.targets[1].hp == 9900, "returning through the same slots cannot hit or stack again")
	world.queue_free()
	await tree.process_frame
	fixture = setup(tree, ["piercing_edge"])
	world = fixture.world
	for index: int in range(7):
		var target: ArcheryTarget
		if index < 3: target = world.targets[index]
		else:
			target = ArcheryTarget.new()
			target.configure(GameCatalog.TARGETS[0], Vector2.ZERO, 1, index)
			world.add_child(target)
			world.targets.append(target)
		target.anchor = Vector2(130 + index * 65, 150)
		target.tick(0, 0)
		target.hp = 10000
		target.max_hp = 10000
		target.armor = 0
	arrow = base._primary(world, Vector2(100, 150), Vector2(1000, 0))
	arrow._physics_process(0.45)
	verify(arrow.penetration_stacks == 5 and arrow.penetration_exits.is_empty() and arrow.hit_slots.size() == 7, "seven real penetrations stop at five layers")
	verify(is_equal_approx(world.targets[5].hp, 9825) and is_equal_approx(world.targets[6].hp, 9825), "later targets retain capped seventy-five-percent gain")
	world.queue_free()
	await tree.process_frame

func _bounce_and_echo(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, ["echo_strike", "wall_forging", "ricochet_haste"])
	var world: ArcheryWorld = fixture.world
	var arrow: Arrow = base._primary(world, Vector2(630, 150), Vector2(500, 0))
	arrow._physics_process(0.005)
	verify(arrow.bounce_stacks == 1 and arrow.echo_ready and arrow.remaining_bounces == 7 and is_equal_approx(arrow.velocity.x, -625), "actual reflection gains local penetration, echo and existing speed bonus once")
	var armor: int = arrow.stats.armor_penetration
	verify(arrow.contact_stats(world.targets[0], world.targets[0].global_position, "body").armor_penetration == armor + 3 and world.run.stats.armor_penetration == armor, "wall gain remains arrow-local")
	arrow._physics_process(0.6)
	verify(world.targets[2].hp == 9850 and world.targets[1].hp == 9900 and not arrow.echo_ready, "echo boosts only first damage hit after bounce and is consumed")
	for index: int in range(7):
		arrow.position = Vector2(630, 90)
		arrow.velocity = Vector2(500, 0)
		arrow._physics_process(0.002)
	verify(arrow.bounce_stacks == 5 and arrow.echo_ready and arrow.remaining_bounces == 0, "consecutive reflections cap local penetration and only refresh one echo")
	verify(is_equal_approx(arrow.contact_stats(world.targets[0], Vector2(180, 90), "body").damage, 150), "many bounces cannot compound pending echo damage")
	world.queue_free()
	await tree.process_frame
	fixture = setup(tree, ["echo_strike", "wall_forging"])
	world = fixture.world
	arrow = base._primary(world, Vector2(629, 305), Vector2(100, 100))
	arrow._physics_process(0.02)
	verify(arrow.velocity.x < 0 and arrow.velocity.y < 0 and arrow.remaining_bounces == 7 and arrow.bounce_stacks == 1, "corner reflects both axes but spends and strengthens only once")
	var child := Arrow.new()
	child.setup(arrow.position, arrow.velocity, arrow.stats, 1, world.run.rng)
	child.effects = ArrowEffects.from_dict(arrow.effects.to_dict())
	child.inherit_combat(arrow)
	verify(child.echo_ready and child.bounce_stacks == 1 and child.contact_stats(world.targets[0], Vector2(180, 150), "body").damage == 150, "child carries earned local penetration and pending echo")
	child.free()
	world.queue_free()
	await tree.process_frame

func _bounce_gate(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, IDS)
	var world: ArcheryWorld = fixture.world
	world.run.stats.armor_penetration = 0
	world.targets[2].armor = 2
	world.targets[1].armor = 3
	var arrow: Arrow = base._primary(world, Vector2(630, 150), Vector2(500, 0))
	arrow._physics_process(0.8)
	verify(arrow.bounce_stacks == 1 and arrow.hit_slots == [2, 1] and arrow.penetration_stacks == 1 and arrow.done, "wall armor enables first penetration, but equal armor at second still stops the arrow")
	verify(is_equal_approx(world.targets[2].hp, 9847) and is_equal_approx(world.targets[1].hp, 9885) and world.targets[0].hp == 10000, "first echo/surplus hit and later exit gain follow actual collision armor")
	verify(arrow.stats.armor_penetration == 0 and world.run.stats.armor_penetration == 0, "successful local penetration does not rewrite zero base armor")
	world.queue_free()
	await tree.process_frame

func _boss_family_storage(tree: SceneTree) -> void:
	var combat: RefCounted = preload("res://tests/test_boss_combat.gd").new(assertion)
	var world: ArcheryWorld = combat.setup(tree, 480.0)
	var session: GameSession = combat.session(world)
	world.run.encounter_picks.clear()
	var all_traits: Array[String] = []
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: all_traits.append(reward.id)
	base._equip(world.run, all_traits)
	world.run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1}
	world.run.rebuild_stats()
	var arrow: Arrow = combat.shot(world, Vector2(400, 205), Vector2(500, 0), world.run.stats.damage, world.run.stats.armor_penetration, world.run.stats.bounces)
	world.waiting_for_settle = true
	arrow.bounce_stacks = 5
	arrow.echo_ready = true
	arrow._physics_process(0.07)
	verify(arrow.hit_slots == [-2] and arrow.echo_ready and world.targets.is_empty(), "all ten traits coexist in active Boss battle after a real shield pass")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t11b-boss-family.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "active Boss, passed shield, local armor and charged echo form a valid transaction")
	var loaded := GameSession.from_dict(store.read())
	var copy: ArcheryWorld = combat.base.field(tree, loaded, loaded.world_snapshot)
	base._freeze(copy)
	verify(world.snapshot() == copy.snapshot() and loaded.run.rng.state == world.run.rng.state, "Boss pose, HP, rewards, aliases and dynamic arrow restore exactly")
	for field: ArcheryWorld in [world, copy]:
		field.arrows[0]._physics_process(0.13)
		base._freeze(field)
		verify(field.arrows.size() == 3 and field.arrows[0].penetration_stacks == 1 and field.arrows[1].bounce_stacks == 5 and field.arrows[1].penetration_stacks == 1 and not field.arrows[1].echo_ready, "Boss post-exit split inherits armor and gain with consumed echo")
	verify(world.snapshot() == copy.snapshot() and world.boss.hp > 0 and loaded.profile.total_score == 0, "all-ten resumed contacts preserve one shared HP hit and no nonlethal rewards")
	loaded.capture_checkpoint(copy.snapshot())
	verify(store.write(loaded.save_payload()), "Boss split family remains valid after amplified hit")
	var hp: float = copy.boss.hp
	combat.base.tick(copy, 1800)
	verify(copy.boss.hp == hp and loaded.profile.total_score == 0 and loaded.run.bosses_defeated == 0, "reflected parent and descendants cannot damage or reward the shared core again")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _boss_and_surplus(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, IDS)
	var world: ArcheryWorld = fixture.world
	var boss := ArcheryBoss.new()
	boss.configure_boss(RunModel.BOSS_RULES, 1)
	world.add_child(boss)
	var arrow: Arrow = base._primary(world, Vector2(400, 205), Vector2(500, 0))
	arrow.stats.armor_penetration = 30
	verify(arrow.contact_stats(boss, boss.global_position, "weak").damage == 144, "surplus reads reduced core armor eight, not body twenty")
	verify(arrow.contact_stats(boss, boss.global_position + Vector2(0, 30), "body").damage == 120, "body surplus uses current hit armor")
	arrow.stats.armor_penetration = 20
	verify(arrow.contact_stats(boss, boss.global_position + Vector2(0, 30), "body").damage == 100, "equal penetration has no surplus gain")
	arrow.stats.armor_penetration = 1000
	verify(arrow.contact_stats(boss, boss.global_position + Vector2(0, 30), "body").damage == 200, "excess amplification stops at one hundred percent")
	verify(arrow.stats.damage == 100 and arrow.penetration_stacks == 0, "surplus queries never permanently compound")
	boss.combat_schema = 0
	verify(arrow.contact_stats(boss, boss.global_position, "body").damage == 200 and boss.contact_armor(boss.global_position, "body") == 20, "old static boss retains original armor without modern core reduction")
	world.queue_free()
	await tree.process_frame
	# Use real phase-two shield -> shared body contacts; only HP contact consumes echo.
	fixture = setup(tree, IDS)
	world = fixture.world
	for target: ArcheryTarget in world.targets:
		world.remove_child(target)
		target.queue_free()
	world.targets.clear()
	boss = ArcheryBoss.new()
	boss.configure_boss(RunModel.BOSS_RULES, 1)
	world.add_child(boss)
	boss.hp = boss.max_hp * 0.5
	boss.refresh_phase()
	arrow = base._primary(world, Vector2(400, 205), Vector2(500, 0))
	arrow.stats.armor_penetration = 29
	arrow.echo_ready = true
	arrow._physics_process(0.07)
	verify(arrow.hit_slots == [-2] and arrow.echo_ready and arrow.penetration_exits.is_empty() and arrow.penetration_stacks == 0 and boss.hp == boss.max_hp * 0.5, "passing shield deals no HP damage, consumes no echo and queues no penetration gain")
	arrow._physics_process(0.13)
	verify(is_equal_approx(boss.hp, boss.max_hp * 0.5 - 100 * 1.42 * 1.5 * 1.75) and not arrow.echo_ready, "core receives surplus plus preserved echo plus boss weakness once")
	verify(arrow.hit_slots.has(-1) and arrow.hit_slots.has(-3) and arrow.penetration_stacks == 1 and world.pending_volleys["1"].size() == 2, "shared body aliases yield one penetration layer and one HP event, alongside shield event")
	world.queue_free()
	await tree.process_frame

func _selection_and_snapshots(tree: SceneTree) -> void:
	for id: String in IDS:
		var fixture: Dictionary = setup(tree, [])
		var world: ArcheryWorld = fixture.world
		var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
		var state: Dictionary = arrow.snapshot()
		offers.entitle(world.run)
		world.run.offer_encounter()
		world.run.choices.assign(["second_wind", id, "steady_power"])
		if not world.run.seen_encounters.has(id): world.run.seen_encounters.append(id)
		verify(world.run.choose_encounter(id, world.run.encounter_offer_id) and arrow.snapshot() == state, "claim never rewrites a launched arrow: " + id)
		var next: Arrow = base._primary(world, Vector2(160, 90), Vector2(500, 0))
		verify(next.effects.to_dict() == world.run.projectile_effects().to_dict() and next.effects.to_dict() != arrow.effects.to_dict(), "next draw samples chosen effect: " + id)
		verify(not world.run.choose_encounter(id, world.run.encounter_offer_id), "trait cannot be reclaimed with stale offer: " + id)
		world.queue_free()
		await tree.process_frame
	var run := RunModel.new()
	var all_traits: Array[String] = []
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: all_traits.append(reward.id)
	base._equip(run, all_traits)
	run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1}
	run.rebuild_stats()
	verify(run.stats.arrow_count == 1 and run.stats.crit_chance == 0 and run.stats.crit_multiplier == 1 and run.stats.armor_penetration > 0 and run.stats.bounces > 0, "all ten traits coexist with six-trait conversion order")
	verify(run.projectile_effects().split_count == 2 and run.projectile_effects().penetration_limit == 5 and run.projectile_effects().echo_damage == 0.5, "conversion does not disable new dynamic effects or original split")
	var expected: Dictionary = run.to_dict()
	for index: int in range(20): run.rebuild_stats()
	verify(run.to_dict() == expected and RunModel.from_dict(expected).projectile_effects().to_dict() == run.projectile_effects().to_dict(), "combined repeated rebuild and restore do not accumulate dynamic stacks")

func _storage(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, IDS)
	var world: ArcheryWorld = fixture.world
	var session: GameSession = fixture.session
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow.bounce_stacks = 2
	arrow.echo_ready = true
	arrow._physics_process(0.03)
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	var path: String = "user://tests/t11b-flight.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(payload), "in-target exit queue and bounce gains serialize together")
	var loaded := GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(loaded.world_snapshot)
	base._freeze(copy)
	verify(copy.snapshot() == world.snapshot() and copy.run.rng.state == world.run.rng.state, "disk restores all counters, frozen coefficients, echo, exits, hits and RNG")
	for field: ArcheryWorld in [world, copy]: field.arrows[0]._physics_process(0.24)
	verify(copy.snapshot() == world.snapshot() and copy.run.rng.state == world.run.rng.state, "resumed trajectory yields exactly identical subsequent amplified hits")
	for field: String in ["penetration_stacks", "bounce_stacks", "combat_schema"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["arrows"][0][field] = 99
		verify(not store.write(bad), "reject out-of-bound dynamic state: " + field)
	for field: String in EFFECT_KEYS:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["arrows"][0]["effects"].erase(field)
		verify(not store.write(bad), "new save cannot silently lose frozen parameter: " + field)
	var bad: Dictionary = payload.duplicate(true)
	bad["world"]["arrows"][0]["penetration_exits"].append(bad["world"]["arrows"][0]["penetration_exits"][0].duplicate(true))
	verify(not store.write(bad), "reject repeated pending exit source")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["penetration_exits"][0]["slot"] = -2
	verify(not store.write(bad), "reject shield-driven gain")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["penetration_exits"][0]["rect"][2] = 0
	verify(not store.write(bad), "reject impossible zero-width exit volume")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["effects"]["echo_damage"] = NAN
	verify(not store.write(bad), "reject nonfinite damage coefficient")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["echo_ready"] = true
	bad["world"]["arrows"][0]["effects"]["echo_damage"] = 0
	verify(not store.write(bad), "reject echo charge without its frozen effect")
	verify(store.read() == JSON.parse_string(JSON.stringify(payload, "", true, true)), "invalid writes preserve last valid saved boundary")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _legacy(tree: SceneTree) -> void:
	var fixture: Dictionary = setup(tree, ["piercing_split", "ricochet_haste"])
	var world: ArcheryWorld = fixture.world
	var session: GameSession = fixture.session
	base._primary(world, Vector2(220, 150), Vector2(500, 0))
	world.reload_left = 0.31
	offers.entitle(world.run)
	world.run.offer_encounter()
	world.run.choices.assign(["second_wind", "steady_power", "quick_nock"])
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	for old: Dictionary in payload["world"]["arrows"]:
		for key: String in STATE_KEYS: old.erase(key)
		for key: String in EFFECT_KEYS: old["effects"].erase(key)
	var path: String = "user://tests/t11b-v12.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 12, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v12") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "original v12 archived byte-for-byte before v13 conversion")
	verify(loaded.world_snapshot == ArcheryWorld.upgrade_snapshot(JSON.parse_string(JSON.stringify(payload["world"], "", true, true))), "migration adds neutral fields and preserves old positions, stats, speed, split, ledger and reload")
	verify(loaded.run.choices == world.run.choices and loaded.run.encounter_offer_id == world.run.encounter_offer_id and loaded.run.rng.state == world.run.rng.state and loaded.run.reward_queue == JSON.parse_string(JSON.stringify(world.run.reward_queue)), "new catalog never rerolls old fixed group, source queue or RNG")
	var old: Dictionary = loaded.world_snapshot["arrows"][0]
	verify(old["effects"]["penetration_damage"] == 0 and old["effects"]["echo_damage"] == 0 and old["penetration_stacks"] == 0 and old["penetration_exits"].is_empty(), "old live arrow receives neutral new effects with no retroactive gains")
	var written: bool = store.write(loaded.to_dict())
	var reread: GameSession = GameSession.from_dict(store.read())
	verify(written and JSON.parse_string(JSON.stringify(reread.world_snapshot, "", true, true)) == JSON.parse_string(JSON.stringify(loaded.world_snapshot, "", true, true)) and store.migration_notice.is_empty(), "second read has no repeat migration or hidden rewrites")
	world.queue_free()
	await tree.process_frame
	clean(path)

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v12"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
