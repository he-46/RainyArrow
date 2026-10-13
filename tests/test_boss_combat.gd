extends RefCounted
## T10-B: shared HP/part aliases, real shield contacts, moving recovery and v8 continuity.

var assertion: Callable
var base: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_boss.gd").new(check)

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T10-B: " + message)

func setup(tree: SceneTree, health: float = 960) -> ArcheryWorld:
	var session := GameSession.new()
	base.prime(session.start_run(), 100)
	var world: ArcheryWorld = base.field(tree, session)
	world.set_meta("session", session)
	world._physics_process(0)
	# Fixed 960 HP fixture isolates combat arithmetic from production balance changes.
	world.boss.max_hp = 960
	world.boss.hp = health
	world.boss.refresh_phase()
	return world

func shot(world: ArcheryWorld, origin: Vector2, velocity: Vector2, damage: float = 100, penetration: int = 0, bounces: int = 0) -> Arrow:
	var bow: BowStats = world.run.stats.duplicate() as BowStats
	bow.damage = damage
	bow.gravity = 0
	bow.crit_chance = 0
	bow.armor_penetration = penetration
	bow.bounces = bounces
	world.run.consume_shot()
	var arrow := Arrow.new()
	arrow.setup(origin, velocity, bow, 1, world.run.rng)
	arrow.shot_id = world.run.shot_sequence
	arrow.effects = world.run.projectile_effects()
	world._attach_arrow(arrow)
	arrow.set_physics_process(false)
	return arrow

func session(world: ArcheryWorld) -> GameSession:
	return world.get_meta("session") as GameSession

func run_all(tree: SceneTree) -> void:
	tree.paused = false
	await _phase_and_math(tree)
	await _shield_contacts(tree)
	await _aliases_and_traits(tree)
	await _moving_restore(tree)
	await _legacy_v8(tree)
	await _live_ui(tree)

func _phase_and_math(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	var boss: ArcheryBoss = world.boss
	var bow: BowStats = world.run.stats.duplicate() as BowStats
	bow.damage = 120
	bow.crit_chance = 0
	var raw: Dictionary = bow.to_dict()
	var volumes: Array[Dictionary] = boss.collision_volumes()
	verify(volumes.size() == 2 and volumes[0]["slot"] == -3 and volumes[1]["slot"] == -1, "phase one exposes independent weak/body volumes without a shield")
	var weak: Dictionary = boss.receive_contact(bow, 1, boss.global_position, 0.99, "weak")
	verify(weak["effective"] == 202 and weak["boss_part"] == "weak" and weak["bullseye"] and not weak["pierced"], "weak damage multiplies before subtracting reduced armor")
	verify(boss.hp == 758 and bow.to_dict() == raw and boss.battle_phase == 1, "weak hit never mutates launch attributes or switches phase prematurely")
	boss.hp = 960
	var armored: Dictionary = boss.receive_contact(bow, 1, boss.global_position + Vector2(0, 35), 0.99, "body")
	verify(armored["effective"] == 100 and armored["boss_part"] == "body" and not armored["bullseye"], "armored body uses full armor and ordinary damage")
	boss.hp = 960
	bow.crit_chance = 1
	var crit: Dictionary = boss.receive_contact(bow, 1, boss.global_position, 0, "weak")
	verify(crit["effective"] == 412 and crit["critical"], "weak multiplier and crit combine before armor once")
	bow.crit_chance = 0
	bow.armor_penetration = 8
	boss.hp = 960
	verify(not boss.receive_contact(bow, 1, boss.global_position, 1, "weak")["pierced"], "penetration equal to weak armor does not pass")
	bow.armor_penetration = 9
	boss.hp = 960
	verify(boss.receive_contact(bow, 1, boss.global_position, 1, "weak")["pierced"], "weak point permits penetration strictly above its reduced armor")
	boss.hp = 960
	bow.arrow_size = 6
	var graze: Dictionary = boss.receive_contact(bow, 1, boss.global_position + Vector2(0, 13), 1, "weak")
	verify(graze["boss_part"] == "body" and not graze["bullseye"], "large heads grazing weak volume do not enlarge gold center qualification")
	boss.hp = 481
	bow.armor_penetration = 0
	var transitions: Array[int] = []
	boss.phase_changed.connect(func(number: int) -> void: transitions.append(number))
	boss.receive_contact(bow, 1, boss.global_position + Vector2(0, 35), 1, "body")
	verify(boss.hp == 381 and boss.battle_phase == 2 and transitions == [2] and boss.phase_clock == 0, "crossing half health starts phase two once without healing")
	var before: Vector2 = boss.position
	boss.tick(0.8, world.clock)
	verify(boss.position != before and boss.shield_position != boss.position + Vector2(-52, 0) and boss.collision_volumes().size() == 3, "phase two moves body and shield with three actual contact volumes")
	var clock: float = boss.phase_clock
	boss.receive_contact(bow, 1, boss.global_position + Vector2(0, 35), 1, "body")
	verify(transitions == [2] and boss.phase_clock == clock, "later hits never restart motion or emit another phase transition")
	verify(world.targets.is_empty() and world.run.defeated_count == 100 and session(world).profile.total_score == 0, "phase changes cannot spawn ordinary targets or mint score")
	world.queue_free()
	await tree.process_frame

func _shield_contacts(tree: SceneTree) -> void:
	for penetration: int in [27, 28, 29]:
		var world: ArcheryWorld = setup(tree, 460)
		world.run.encounter_picks = {"windfall": 9, "piercing_split": 1}
		world.run.seen_encounters.assign(["piercing_split"])
		world.run.rebuild_stats()
		var arrow: Arrow = shot(world, Vector2(340, 205), Vector2(10000, 0), 100, penetration)
		arrow._physics_process(0.02)
		var hits: Array = world.pending_volleys[str(arrow.shot_id)]
		verify(hits[0]["boss_part"] == "shield" and hits[0]["effective"] == 0 and not hits[0]["critical"], "shield is first physical contact and cannot supply crit/HP rewards at penetration %d" % penetration)
		if penetration <= 28:
			verify(arrow.done and world.boss.hp == 460 and hits.size() == 1, "insufficient/equal penetration stops at shield without touching core")
			verify(int(world.projectile_ledger[str(arrow.shot_id)]["children"]) == 0, "blocked shield cannot trigger piercing split")
			world._physics_process(0)
			verify(world.run.combo == 0 and session(world).profile.total_score == 0 and world.run.bosses_defeated == 0, "shield-only volley settles as no effective hit without refunds or coins")
		else:
			verify(not arrow.done and world.boss.hp == 285 and hits.size() == 2 and hits[1]["boss_part"] == "weak", "strictly higher penetration reaches core in the same swept step")
			verify(arrow.hit_slots.has(-2) and arrow.hit_slots.has(-3) and arrow.hit_slots.has(-1), "shield exclusion is independent while weak/body share HP exclusion")
			verify(world.projectile_ledger[str(arrow.shot_id)]["children"] == 2 and hits.size() == 2, "only actual weak penetration splits, shield pass does not spend split budget")
			verify(world.run.score == 0 and world.run.defeated_count == 100, "shield pass and nonlethal core do not count as separate kills")
		world.queue_free()
		await tree.process_frame
	# Slide the shield away and aim through the exposed gold point without penetration.
	var exposed: ArcheryWorld = setup(tree, 460)
	exposed.boss.tick(0.65, exposed.clock)
	var y: float = exposed.boss.position.y
	var low: Arrow = shot(exposed, Vector2(340, y), Vector2(10000, 0), 100, 0)
	low._physics_process(0.02)
	verify(exposed.boss.hp == 293 and low.done and not low.hit_slots.has(-2), "low-penetration arrow can time a real exposed weak-point window")
	verify(exposed.labels.any(func(label: Dictionary) -> bool: return str(label["text"]).contains("弱点")), "weak contact provides readable distinction from armor/shield")
	exposed.queue_free()
	await tree.process_frame

func _aliases_and_traits(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	world.run.encounter_picks = {"windfall": 4}
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.id in ["piercing_split", "ricochet_haste", "swarm_precision", "unified_arrow", "critical_forging", "critical_ricochet"]:
			world.run.encounter_picks[reward.id] = 1
			world.run.seen_encounters.append(reward.id)
	world.run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1}
	world.run.rebuild_stats()
	var before: Dictionary = world.run.stats.to_dict()
	var arrow: Arrow = shot(world, Vector2(430, 205), Vector2(1000, 0), world.run.stats.damage, world.run.stats.armor_penetration, world.run.stats.bounces)
	var launch: Dictionary = arrow.stats.to_dict()
	arrow._physics_process(0.1)
	var damage: float = float(launch["damage"]) * 1.75
	verify(is_equal_approx(world.boss.hp, 960 - damage) and arrow.hit_slots.has(-1) and arrow.hit_slots.has(-3), "all six traits hit shared core once with converted damage")
	verify(world.arrows.size() == 3 and int(world.projectile_ledger["1"]["children"]) == 2, "weak-point pass creates only one child pair despite overlapping body")
	verify(world.run.stats.to_dict() == before and arrow.stats.to_dict() == launch, "target weakness never multiplies original conversion sources or arrow snapshot")
	for child: Arrow in world.arrows:
		if child.parent_source_id >= 0:
			child.set_physics_process(false)
			verify(child.hit_slots.has(-1) and child.hit_slots.has(-3) and child.effects.split_count == 0 and child.stats.crit_chance == 0, "children inherit shared exclusions and cannot recursively split")
	var path: String = "user://tests/t10b-family.json"
	clean(path)
	var store := SaveStore.new(path)
	session(world).capture_checkpoint(world.snapshot())
	verify(store.write(session(world).save_payload()), "multipart collision exclusions and six-trait family form a valid save")
	var restored_session: GameSession = GameSession.from_dict(store.read())
	var restored: ArcheryWorld = base.field(tree, restored_session, restored_session.world_snapshot)
	for projectile: Arrow in restored.arrows: projectile.set_physics_process(false)
	verify(restored.boss.snapshot() == world.boss.snapshot() and restored.arrows[0].snapshot() == arrow.snapshot(), "family restoration preserves multipart launch/pose state")
	base.tick(restored, 1800)
	verify(is_equal_approx(restored.boss.hp, 960 - damage) and restored_session.run.bosses_defeated == 0 and restored_session.profile.total_score == 0, "reflected roots/children never hit shared core again after recovery")
	world.queue_free()
	restored.queue_free()
	await tree.process_frame
	clean(path)

func _moving_restore(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree, 460)
	world.boss.tick(0.73, world.clock)
	# One arrow already passed the shield; it has not reached the moving core.
	world.boss.phase_clock = 0
	world.boss._sync_pose()
	var arrow: Arrow = shot(world, Vector2(340, 205), Vector2(500, 0), 100, 29)
	arrow._physics_process(0.16)
	verify(arrow.hit_slots == [-2] and world.boss.hp == 460 and arrow.position.x < 443, "saved arrow can sit between shield and body without spending core exclusion")
	world.boss.tick(0.19, world.clock)
	var state: Dictionary = world.snapshot()
	var health: float = world.boss.hp
	var s: GameSession = session(world)
	s.return_to_lobby()
	s.capture_checkpoint(state)
	var path: String = "user://tests/t10b-motion.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(s.save_payload()), "moving Boss with shield-only pending hit and live arrow saves atomically")
	var disk: GameSession = GameSession.from_dict(store.read())
	verify(disk.run.suspended and disk.run.boss_next_defeats == 200 and disk.run.shots_left == 9, "moving save preserves same run, next threshold and spent draw")
	base.tick(world, 60)
	verify(world.snapshot() == state, "lobby pause freezes Boss clock, shield and arrow together")
	disk.resume_run()
	var copy: ArcheryWorld = base.field(tree, disk, disk.world_snapshot)
	for live: Arrow in copy.arrows: live.set_physics_process(false)
	verify(copy.boss.snapshot() == world.boss.snapshot() and copy.arrows[0].snapshot() == arrow.snapshot() and copy.boss.hp == health, "disk restores phase, exact two poses, clock and independent shield exclusion")
	var expected: Dictionary = copy.boss.snapshot()
	disk.run.open_skills()
	base.tick(copy, 30)
	verify(copy.boss.snapshot() == expected, "skills pause moving parts without resetting their phase")
	disk.run.close_skills()
	base.tick(copy, 220)
	verify(copy.boss.hp < health and copy.boss.battle_phase == 2 and disk.run.score == 0, "restored shield-passed arrow hits moving core without a second shield charge")
	disk.capture_checkpoint(copy.snapshot())
	verify(store.write(disk.save_payload()), "continued moving transaction remains valid after contact")
	var good: String = FileAccess.get_file_as_string(path)
	var bad: Dictionary = disk.to_dict()
	bad["world"]["boss"]["shield_position"][1] += 5
	verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "inconsistent shield pose cannot overwrite a good save")
	bad = disk.to_dict()
	bad["world"]["boss"]["battle_phase"] = 1
	verify(not store.write(bad), "phase rollback without corresponding HP/clock is rejected")
	bad = disk.to_dict()
	bad["world"]["boss"].erase("combat_schema")
	verify(not store.write(bad), "new writes cannot hide multipart state as an old static Boss")
	bad = disk.to_dict()
	bad["world"]["boss"]["combat_parameters"]["weak_multiplier"] = NAN
	verify(not store.write(bad), "invalid combat coefficients are rejected")
	world.queue_free()
	copy.queue_free()
	await tree.process_frame
	clean(path)

func _legacy_v8(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	world.boss.combat_schema = 0
	world.boss.hp = 321
	var arrow: Arrow = shot(world, Vector2(430, 205), Vector2(500, 0), 120, 21, 1)
	arrow._physics_process(0.14)
	verify(world.boss.hp == 201 and arrow.hit_slots == [-1], "legacy fixture uses original static hit and single-slot exclusions")
	session(world).capture_checkpoint(world.snapshot())
	var payload: Dictionary = session(world).save_payload()
	for key: String in ["combat_schema", "battle_phase", "phase_clock", "combat_parameters", "body_position", "shield_position", "health_revision"]:
		payload["world"]["boss"].erase(key)
	var path: String = "user://tests/t10b-v8.json"
	clean(path)
	var original: String = JSON.stringify({"version": 8, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store := SaveStore.new(path)
	var disk: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v8") == original and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v8 bytes archived before current multipart migration")
	verify(disk.run.boss_round == 1 and disk.run.boss_active and disk.run.boss_next_defeats == 200 and disk.run.bosses_defeated == 0, "migration never re-enters or prematurely credits an active Boss")
	verify(disk.world_snapshot["boss"]["hp"] == 603 and disk.world_snapshot["boss"]["max_hp"] == 2880 and disk.world_snapshot["boss"]["combat_schema"] == 0, "legacy Boss triples remaining and maximum HP proportionally without adding a shield")
	verify(disk.run.rng.state == world.run.rng.state and disk.run.shots_left == 9 and disk.profile.total_score == 0, "legacy combat RNG, spent draw and uncredited rewards stay intact")
	var old: ArcheryWorld = base.field(tree, disk, disk.world_snapshot)
	for live: Arrow in old.arrows: live.set_physics_process(false)
	verify(old.boss.collision_volumes().size() == 1 and old.arrows[0].snapshot() == arrow.snapshot(), "old arrow and its single body exclusion restore without new weak-point contacts")
	base.tick(old, 300)
	verify(old.boss.hp == 603 and old.boss.battle_phase == 1 and old.boss.position == Vector2(470, 205) and old.targets.is_empty(), "reflected old arrow cannot gain a new contact after migration")
	base.fire(old, 100000)
	base.tick(old, 220)
	base.choose_safe(disk.run)
	old._physics_process(0)
	verify(disk.run.bosses_defeated == 1 and disk.profile.total_score == 1200 and not disk.run.boss_active, "legacy Boss still ends normally and pays once")
	base.prime(disk.run, 200)
	old._physics_process(0)
	verify(old.boss.combat_schema == 1 and old.boss.battle_phase == 1 and old.boss.max_hp == 4608, "next Boss uses new combat with tripled stronger second round")
	var bytes: String = FileAccess.get_file_as_string(path)
	store.read()
	verify(store.migration_notice.is_empty() and FileAccess.get_file_as_string(path) == bytes, "v9 subsequent reads do not remigrate active legacy fight")
	world.queue_free()
	old.queue_free()
	await tree.process_frame
	clean(path)

func _live_ui(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	base.prime(main.run, 100)
	main.world._physics_process(0)
	main.hud.update_boss(main.run, main.world)
	verify(main.hud.boss_title.text.contains("阶段 1") and main.hud.boss_hint.text.contains("弱点 ×1.75"), "actual HUD explains phase one and gold damage bonus")
	main.world.boss.hp = 460
	main.world.boss.refresh_phase()
	main.world.boss.tick(0.4, main.world.clock)
	main.hud.update_boss(main.run, main.world)
	verify(main.hud.boss_title.text.contains("阶段 2") and main.hud.boss_hint.text.contains("护板甲 28"), "actual HUD explains phase two's strict shield penetration threshold")
	var state: Dictionary = main.world.boss.snapshot()
	main._on_action("hub", null)
	var saved: Dictionary = main.saves.read()
	verify(saved["world"]["boss"]["battle_phase"] == 2 and saved["world"]["boss"]["hp"] == 460, "real lobby action persists phase two without replenishing targets")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	verify(main.world.boss.snapshot() == state and main.world.targets.is_empty(), "actual lazy Continue retains moving phase and both collider poses")
	main._on_action("tutorial", null)
	main._stop_tutorial()
	verify(main.world.boss.snapshot() == state, "practice never advances or resets formal moving Boss")
	main.queue_free()
	await tree.process_frame
	tree.paused = false

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v8"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
