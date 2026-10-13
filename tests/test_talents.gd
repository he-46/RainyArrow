extends RefCounted
## T05: authoritative tree rules, run effects, draw ordering and in-flight persistence.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T05: " + message)

func run_all(tree: SceneTree) -> void:
	_tree_rules()
	_opening_snapshot()
	_coin_and_combo()
	_refunds()
	await _real_refunds(tree)
	await _geometry(tree)
	await _pending_flight(tree)
	await _ui(tree)
	await _migrate_v4(tree)

func _rich_session() -> GameSession:
	var session := GameSession.new()
	session.profile.record_defeat(1000000)
	return session

func _learn(session: GameSession, id: String, ranks: int = 1) -> void:
	for index: int in range(ranks):
		verify(session.purchase_talent(id), "learn " + id)

func _tree_rules() -> void:
	var session: GameSession = _rich_session()
	verify(TalentCatalog.ALL.size() == 36, "four trees include sixteen advanced and capstone nodes")
	verify(not session.purchase_talent("unknown"), "unknown node cannot spend points")
	var before: int = session.profile.talent_points
	verify(not session.purchase_talent("damage_left") and session.profile.talent_points == before, "branch cannot bypass parent")
	verify(not session.profile.invest_talent("damage_root", 2), "caller cannot override catalog cost")
	for prefix: String in ["quiver", "economy", "damage", "field"]:
		var start: int = session.profile.talent_points
		_learn(session, prefix + "_root", 3)
		verify(start - session.profile.talent_points == 6, "root rank costs rise 1,2,3: " + prefix)
		verify(not session.purchase_talent(prefix + "_root"), "max rank rejects purchase: " + prefix)
		_learn(session, prefix + "_left")
		verify(not session.purchase_talent(prefix + "_master_left"), "terminal requires branch rank two: " + prefix)
		_learn(session, prefix + "_right", 2)
		_learn(session, prefix + "_left")
		_learn(session, prefix + "_master_left")
		verify(not session.purchase_talent(prefix + "_master_right"), "terminal exclusion is enforced: " + prefix)
		verify(start - session.profile.talent_points == 20, "early branches coexist and deeper costs rise: " + prefix)
	var original: Dictionary = session.profile.to_dict()
	var bow: BowStats = session.start_run().stats
	verify(bow.damage == 72 and bow.armor_penetration == 4 and is_equal_approx(bow.gold_multiplier, 1.45), "power specialization and economy root affect opening stats")
	verify(is_equal_approx(session.run.talent_effects["combo_gold"], 0.14) and is_equal_approx(session.run.talent_effects["kill_refund"], 0.36), "combo and kill-refund specializations contribute their full bonuses")
	var restored: PlayerProfile = PlayerProfile.from_dict(original)
	verify(restored.to_dict() == original, "all ranks and actual spending round-trip")
	verify(restored.reset_talents() == 80 and restored.reset_talents() == 0, "respec refunds exact ledger once")
	var bad: Dictionary = original.duplicate(true)
	bad["talents"]["unknown"] = 2
	bad["talent_spending"]["unknown"] = 7
	bad["talents"]["field_master_right"] = 1
	bad["talent_spending"]["field_master_right"] = 4
	var cleaned: PlayerProfile = PlayerProfile.from_dict(bad)
	verify(not cleaned.talents.has("unknown") and not cleaned.talents.has("field_master_right"), "restore drops unknown and excluded nodes without losing points")
	bad = original.duplicate(true)
	bad["talents"].erase("quiver_root")
	var pruned: PlayerProfile = PlayerProfile.from_dict(bad)
	verify(not pruned.talents.has("quiver_left") and not pruned.talents.has("quiver_master_left"), "restore prunes orphaned descendants")
	var poor := GameSession.new()
	verify(not poor.purchase_talent("quiver_root") and poor.profile.talent_points == 0, "insufficient points do not mutate profile")

func _opening_snapshot() -> void:
	var session: GameSession = _rich_session()
	_learn(session, "quiver_root", 3)
	_learn(session, "damage_root", 3)
	_learn(session, "damage_left", 2)
	_learn(session, "damage_right", 2)
	_learn(session, "damage_master_right")
	var run: RunModel = session.start_run()
	verify(run.initial_shots == 16 and run.shots_left == 16, "capacity is draw attempts, applied once at opening")
	verify(run.stats.damage == 52 and run.stats.armor_penetration == 10, "damage and penetration branches affect effective bow")
	verify(not session.purchase_talent("economy_root") and session.reset_talents() == 0, "active field cannot edit permanent talents")
	run.consume_shot()
	run.skill_levels["quantity"] = 1
	run.rebuild_stats()
	verify(run.shots_left == 15 and run.stats.arrow_count == 2 and is_equal_approx(run.stats.damage, 52 * 0.85), "multishot costs one draw and penalty follows talent damage")
	session.return_to_lobby()
	verify(session.reset_talents() == 26, "lobby reset returns actual investment")
	verify(session.resume_run() == run and run.initial_shots == 16 and run.shots_left == 15 and run.stats.armor_penetration == 10, "respec cannot rewrite current opening snapshot")
	var restored: RunModel = RunModel.from_dict(run.to_dict())
	verify(restored.stats.to_dict() == run.stats.to_dict() and restored.shots_left == 15, "reload neither refills nor compounds talents")
	var next: RunModel = session.start_run(true)
	verify(next.shots_left == 10 and next.stats.damage == 24 and next.stats.armor_penetration == 0, "next run takes latest cleared talents")

func _hit(id: String, broken: bool = true, critical: bool = false, bullseye: bool = false, damage: float = 1.0) -> Dictionary:
	return {"hit_id": id + "-hit", "event_id": id, "effective": damage, "broken": broken,
		"critical": critical, "bullseye": bullseye, "reward_score": 40.0 if broken else 0.0, "reward_gold": 10.0 if broken else 0.0}

func _draw(session: GameSession, hits: Array) -> void:
	session.run.consume_shot()
	session.settle_shot(session.run.shot_sequence, hits)

func _coin_and_combo() -> void:
	var session: GameSession = _rich_session()
	_learn(session, "economy_root")
	_learn(session, "economy_left")
	_learn(session, "economy_right")
	var run: RunModel = session.start_run()
	_draw(session, [_hit("a"), _hit("b"), _hit("b")])
	verify(run.combo == 1 and run.defeated_count == 2 and is_equal_approx(run.gold_earned, 23), "multishot advances combo once and duplicate kill pays once")
	_draw(session, [_hit("nonlethal", false)])
	verify(run.combo == 2 and run.defeated_count == 2 and run.gold == 23, "nonlethal effective hit extends combo without granting coins")
	_draw(session, [_hit("c", true, false, true)])
	verify(run.combo == 3 and is_equal_approx(run.gold_earned, 37.904), "prior draw combo, bullseye and economy multiply exactly once")
	_draw(session, [])
	verify(run.combo == 0, "whole draw miss breaks combo")
	_draw(session, [_hit("d", true, false, true)])
	verify(is_equal_approx(run.gold_earned, 51.704), "first hit after miss has no combo bonus")
	var before: Dictionary = run.to_dict()
	verify(not session.settle_shot(run.shot_sequence, [_hit("extra")]) and run.to_dict() == before, "replaying settled draw cannot grant coins, XP or combo")
	verify(not session.settle_shot(run.shot_sequence + 1, [_hit("future")]), "unfired draw cannot settle")
	run.combo = 100
	var gold_before: float = run.gold_earned
	_draw(session, [_hit("capped")])
	verify(is_equal_approx(run.gold_earned - gold_before, 13.8), "combo coin bonus caps at five prior hits")
	session.return_to_lobby()
	verify(not session.settle_shot(run.shot_sequence, []), "paused draw cannot settle")
	var snapshot: GameSession = GameSession.from_dict(session.to_dict())
	verify(snapshot.run.combo == 101 and snapshot.run.last_settled_shot == run.last_settled_shot, "draw counter and combo survive reload")

func _favorable_rng(run: RunModel, chance: float) -> void:
	var probe := RandomNumberGenerator.new()
	for seed_value: int in range(1, 10000):
		probe.seed = seed_value
		if probe.randf() < chance:
			run.rng.seed = seed_value
			return

func _refunds() -> void:
	var session: GameSession = _rich_session()
	_learn(session, "quiver_root")
	_learn(session, "quiver_left", 2)
	_learn(session, "quiver_right", 2)
	_learn(session, "quiver_master_left")
	var run: RunModel = session.start_run()
	run.shots_left = 1
	run.consume_shot()
	_favorable_rng(run, float(run.talent_effects["kill_refund"]))
	session.settle_shot(run.shot_sequence, [_hit("kill-crit", true, true), _hit("another", true, true)])
	run.settle_volley()
	verify(run.shots_left == 1 and not run.is_finished() and run.defeated_count == 2, "last draw refund precedes exhaustion; multikill/critical shares cap one")
	var saved_rng: int = run.rng.state
	session.settle_shot(run.shot_sequence, [_hit("kill-crit", true, true)])
	verify(run.shots_left == 1 and run.rng.state == saved_rng, "replayed refund cannot consume RNG or add draws")
	run.consume_shot()
	_favorable_rng(run, float(run.talent_effects["crit_refund"]))
	session.settle_shot(run.shot_sequence, [_hit("crit-only", false, true)])
	verify(run.shots_left == 1 and run.defeated_count == 2, "effective nonlethal critical can restore a draw")
	run.consume_shot()
	_favorable_rng(run, float(run.talent_effects["crit_refund"]))
	saved_rng = run.rng.state
	session.settle_shot(run.shot_sequence, [_hit("zero", false, true, false, 0.0)])
	verify(run.shots_left == 0 and run.rng.state == saved_rng and run.combo == 0, "zero damage cannot trigger refund or sustain combo")
	run.settle_volley()
	verify(run.is_finished() and session.in_lobby, "unrefunded last draw ends normally")
	var plain := GameSession.new()
	plain.start_run()
	saved_rng = plain.run.rng.state
	_draw(plain, [_hit("plain", true, true)])
	verify(plain.run.shots_left == 9 and plain.run.rng.state == saved_rng, "no refund talents means no refund RNG draws")

func _real_refunds(tree: SceneTree) -> void:
	for kill: bool in [true, false]:
		var session: GameSession = _rich_session()
		_learn(session, "quiver_root")
		_learn(session, "quiver_left" if kill else "quiver_right", 2)
		_learn(session, "quiver_master_left" if kill else "quiver_master_right")
		var world := ArcheryWorld.new()
		world.run = session.start_run()
		world.shot_settled.connect(session.settle_shot)
		tree.root.add_child(world)
		world.set_physics_process(false)
		world.build_field()
		world.run.shots_left = 1
		world.run.stats.gravity = 0
		world.run.stats.crit_chance = 0 if kill else 1
		world.targets[0].anchor = Vector2(180, 238)
		world.targets[0].position = Vector2(180, 238)
		world.targets[0].hp = 1 if kill else 100
		world.targets[0].max_hp = world.targets[0].hp
		world.direction = Vector2.RIGHT
		world.pull = 1
		world._release()
		var arrow: Arrow = world.arrows[0]
		arrow.set_physics_process(false)
		arrow._physics_process(0.2)
		_favorable_rng(world.run, float(world.run.talent_effects["kill_refund" if kill else "crit_refund"]))
		world._physics_process(0.01)
		verify(world.run.shots_left == 1 and not world.run.is_finished() and world.is_settled(), "actual final projectile refund prevents exhaustion: " + ("kill" if kill else "critical"))
		verify(world.run.defeated_count == (1 if kill else 0), "critical refund does not manufacture a defeat")
		if not kill:
			verify(is_equal_approx(world.run.talent_effects["crit_refund"], 0.1) and world.targets[0].hp == 52, "critical specialization triggers from real effective damage")
		world.queue_free()
		await tree.process_frame

func _geometry(tree: SceneTree) -> void:
	for giant: bool in [false, true]:
		var session: GameSession = _rich_session()
		_learn(session, "field_root", 3)
		_learn(session, "field_left", 2)
		_learn(session, "field_right", 2)
		_learn(session, "field_master_right" if giant else "field_master_left")
		var world := ArcheryWorld.new()
		world.run = session.start_run()
		tree.root.add_child(world)
		world.set_physics_process(false)
		world.build_field()
		verify(world.targets.size() == (10 if giant else 15), "field count includes root, branch and selected specialization")
		var expected_scale: float = 2.3 if giant else 1.6
		var bounded: bool = true
		for target: ArcheryTarget in world.targets:
			bounded = bounded and is_equal_approx(target.scale.x, expected_scale) and target.position.y - target.definition.radius * target.scale.y >= 54 and target.position.y + target.definition.radius * target.scale.y <= 308
		verify(bounded, "visible size and collision scale agree inside field")
		var target: ArcheryTarget = world.targets[0]
		var shape_height: float = (target.collider.shape as RectangleShape2D).size.y * target.scale.y
		verify(is_equal_approx(shape_height, 46 * expected_scale) and target.hp == 48, "larger collider does not inflate target durability")
		var old_scale: Vector2 = target.scale
		target.spawn(GameCatalog.TARGETS[1], 20)
		target.tick(0, world.clock)
		verify(target.scale == old_scale, "replacement target preserves talent size")
		var state: Dictionary = world.snapshot()
		session.return_to_lobby()
		session.reset_talents()
		session.resume_run()
		world.build_field(state)
		verify(world.snapshot() == state, "respec and world reload preserve target count, anchors and scale")
		# Sweep against enlarged edge: the same path misses an unscaled standard target.
		var arrow := Arrow.new()
		var bow: BowStats = GameCatalog.BASE_BOW.duplicate() as BowStats
		bow.gravity = 0
		bow.crit_chance = 0
		target = world.targets[0]
		for other: ArcheryTarget in world.targets:
			if other != target: other.hp = 0
		target.spawn(GameCatalog.TARGETS[0], 0)
		target.position = Vector2(300, 200)
		arrow.setup(Vector2(100, 200 + 23 * expected_scale - 1), Vector2(20000, 0), bow, 1, world.run.rng)
		world.add_child(arrow)
		arrow.set_physics_process(false)
		arrow._physics_process(0.01)
		verify(target.hp == 24 and arrow.done, "actual swept projectile hits enlarged target edge")
		world.queue_free()
		await tree.process_frame

func _pending_flight(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 0
	main.run.stats.armor_penetration = 1
	main.run.stats.bounces = 2
	main.world.targets[0].position = Vector2(180, 238)
	main.world.targets[0].anchor = Vector2(180, 238)
	main.world.targets[0].hp = 1
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	var arrow: Arrow = main.world.arrows[0]
	arrow.set_physics_process(false)
	arrow._physics_process(0.2)
	verify(main.world.targets[0].hp == 0 and main.run.defeated_count == 0 and main.world.pending_volleys["1"].size() == 1, "in-flight kill is buffered until its draw settles")
	main._navigate("hub")
	var payload: Dictionary = main.saves.read()
	verify(payload["world"]["pending_volleys"]["1"].size() == 1 and payload["world"]["arrows"].size() == 1, "pause saves pending hit together with live arrow and spent draw")
	var bad: Dictionary = payload.duplicate(true)
	bad["world"]["pending_volleys"]["1"][0]["effective"] = "bad"
	verify(not main.saves.write(bad), "malformed pending hit cannot replace a valid checkpoint")
	var expected: Dictionary = main.world.snapshot()
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	main.world.set_physics_process(false)
	for live: Arrow in main.world.arrows: live.set_physics_process(false)
	verify(main.world.snapshot() == expected, "restored pending flight keeps exact target, arrow and event states")
	# A later completed draw must wait for the earlier in-flight one.
	main.run.consume_shot()
	main.world.pending_volleys["2"] = []
	main.world._settle_shots()
	verify(main.run.last_settled_shot == -1 and main.run.combo == 0, "later miss cannot settle ahead of earlier live draw")
	arrow = main.world.arrows[0]
	main.world._on_arrow_expired(arrow)
	arrow.queue_free()
	main.world._settle_shots()
	verify(main.run.defeated_count == 1 and main.run.gold == 8 and main.session.profile.total_score == 40 and main.run.combo == 0 and main.run.last_settled_shot == 2, "draws settle in launch order: hit reward first, later miss clears combo")
	main.world._settle_shots()
	verify(main.run.defeated_count == 1 and main.run.gold == 8 and main.world.pending_volleys.is_empty(), "settled pending queue cannot replay a kill")
	main.queue_free()
	await tree.process_frame

func _ui(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	main.session.profile.record_defeat(250)
	main._navigate("talents")
	var page: TalentPage = main.router.page.get_child(1)
	verify(page.nodes.size() == 36 and page.selected == "quiver_root", "talent route builds all tree nodes")
	(page.detail.get_node("PurchaseTalent") as Button).pressed.emit()
	verify(main.session.profile.talents.get("quiver_root") == 1 and main.session.profile.talent_points == 1, "real upgrade button spends points once")
	var disk: GameSession = GameSession.from_dict(main.saves.read())
	verify(disk.profile.talents.get("quiver_root") == 1 and disk.profile.talent_points == 1, "UI purchase is persisted")
	page = main.router.page.get_child(1)
	(page.nodes["quiver_master_right"] as Button).pressed.emit()
	verify(main.router.selected_talent == "quiver_master_right" and (page.detail.get_node("PurchaseTalent") as Button).disabled, "locked node can be inspected but not bought")
	main._on_action("talent_reset", null)
	verify(main.session.profile.talents.is_empty() and main.session.profile.talent_points == 2 and main.router.selected_talent == "quiver_master_right", "reset refunds and preserves inspected selection")
	main.queue_free()
	await tree.process_frame

func _migrate_v4(tree: SceneTree) -> void:
	var path: String = "user://tests/t05-migration.json"
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v4"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var session := GameSession.new()
	session.start_run()
	session.run.shots_left = 7
	session.record_defeat("slot0-life0", 40, 8)
	var payload: Dictionary = session.to_dict()
	for key: String in ["shot_sequence", "last_settled_shot", "combo"]: payload["run"].erase(key)
	var projectile := Arrow.new()
	projectile.setup(Vector2(202, 238), Vector2(490, 0), session.run.stats, 1, session.run.rng)
	projectile.hit_slots = [0]
	var old_arrow: Dictionary = projectile.snapshot()
	old_arrow.erase("shot_id")
	old_arrow.erase("source_id")
	projectile.free()
	payload["world"] = {"clock": 0.0, "arrows": [old_arrow], "direction": [1.0, 0.0], "waiting_for_settle": true,
		"targets": [{"hp": 0.0, "respawn_left": 0.3}, {"hp": 48.0}, {"hp": 48.0}]}
	var original: String = JSON.stringify({"version": 4, "payload": payload})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store := SaveStore.new(path)
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v4") == original, "v4 exact bytes archived before upgrade")
	verify(restored.run.shots_left == 7 and restored.run.combo == 0 and restored.run.last_settled_shot == -1, "v4 introduces draw metadata without refilling")
	verify(JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "migrated envelope is current version")
	var world := ArcheryWorld.new()
	world.run = restored.run
	world.shot_settled.connect(restored.settle_shot)
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.build_field(restored.world_snapshot)
	var live: Arrow = world.arrows[0]
	live.set_physics_process(false)
	verify(world.pending_volleys.has("0") and live.shot_id == 0 and live.hit_slots == [0] and world.targets[1].anchor == Vector2(429, 164), "legacy flight receives one pending draw and retains old geometry/exclusions")
	world._on_arrow_expired(live)
	live.queue_free()
	world._settle_shots()
	verify(restored.run.defeated_count == 1 and restored.run.gold == 8 and restored.profile.total_score == 40 and restored.run.last_settled_shot == 0, "legacy paid kill cannot replay during its restored draw settlement")
	world.queue_free()
	await tree.process_frame
	store.read()
	verify(store.migration_notice.is_empty(), "v5 read does not remigrate")
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v4"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
