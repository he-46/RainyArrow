extends RefCounted

var assertion: Callable
var bosses: RefCounted
const PATH: String = "user://tests/t14a-difficulty.json"

func _init(check: Callable) -> void:
	assertion = check
	bosses = preload("res://tests/test_boss.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T14-A: " + message)

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v18"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func run_all(tree: SceneTree) -> void:
	_values()
	await _ordinary(tree)
	await _boss_and_disk(tree)
	await _migration(tree)

func _values() -> void:
	verify(DifficultyCatalog.ALL.size() == 3 and DifficultyCatalog.find("unknown") == null, "exactly three known modes")
	for id: String in ["normal", "hard", "hell"]:
		var run := RunModel.new(id)
		var params: Dictionary = run.mode_parameters
		var multiplier: float = 1 if id == "normal" else 1.5
		var score: float = 1 if id == "normal" else (1.5 if id == "hard" else 2)
		var growth: float = 0.1 if id == "hell" else 0.06
		verify(run.mode_id == id and params == {"target_health": multiplier, "boss_health": 1.0 if id == "normal" else 2.0, "score": score, "health_growth": growth}, "confirmed mode parameters " + id)
		params["score"] = 9
		verify(run.mode_parameters["score"] == score, "exposed parameter copy cannot mutate this run " + id)
		for kind: TargetData in GameCatalog.TARGETS:
			for count: int in [0, 1, 5, 99, 1000, 1000001]:
				var step: int = mini(count, 1000000)
				var values: Dictionary = ArcheryTarget.RULES.target_values(kind, count, run.mode_parameters)
				var normal: Dictionary = ArcheryTarget.RULES.target_values(kind, count)
				verify(is_equal_approx(values["max_hp"], kind.durability * multiplier * (1 + step * growth)), "linear target HP " + id + "/" + str(kind.id) + "/" + str(count))
				verify(values["armor"] == normal["armor"] and values["reward_gold"] == normal["reward_gold"] and values["spawn_difficulty"] == step, "mode leaves armor/coins/kill index unchanged " + id + "/" + str(count))
				verify(values["reward_score"] == normal["reward_score"] * score, "target score multiplies once after original reward rounding " + id + "/" + str(count))
		for round_number: int in [1, 2, 3, 10]:
			var baseline: Dictionary = RunModel.BOSS_RULES.values(round_number)
			var values: Dictionary = RunModel.BOSS_RULES.values(round_number, run.mode_parameters)
			verify(values["max_hp"] == baseline["max_hp"] * (1 if id == "normal" else 2), "Boss HP grows independently " + id + "/" + str(round_number))
			verify(values["reward_score"] == baseline["reward_score"] * score and values["armor"] == baseline["armor"] and values["reward_gold"] == baseline["reward_gold"], "Boss reward multiplier affects score only " + id + "/" + str(round_number))
		verify(RunModel.from_dict(run.to_dict()).to_dict() == run.to_dict(), "mode and sampled parameters round trip " + id)
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "hell")
	run.gold = 100
	verify(session.start_run(true, "unknown") == null and session.run == run and run.gold == 100, "invalid mode cannot abandon a real run")
	verify(session.start_run(false, "hard") == null and run.mode_id == "hell", "starting another difficulty requires replacement")
	session.return_to_lobby()
	session.resume_run()
	verify(run.mode_id == "hell" and run.difficulty_step == 0, "same-run navigation keeps mode")
	var next: RunModel = session.start_run(true, "hard")
	verify(next.mode_id == "hard" and next.difficulty_step == 0 and next.gold == 0 and next.supply_total_bought == 0, "new difficulty resets local growth and supply")
	# Already-started runs keep their parameter snapshot across resource changes.
	var definition: DifficultyData = DifficultyCatalog.find("hard")
	var old: float = definition.health_growth
	definition.health_growth = 0.12
	verify(next.mode_parameters["health_growth"] == 0.06 and RunModel.from_dict(next.to_dict()).mode_parameters["health_growth"] == 0.06, "existing run and Continue do not resample edited resources")
	definition.health_growth = old

func _ordinary(tree: SceneTree) -> void:
	for id: String in ["normal", "hard", "hell"]:
		var session := GameSession.new()
		var run: RunModel = session.start_run(false, id)
		var world: ArcheryWorld = bosses.field(tree, session)
		world.boss_enabled = false
		var first: ArcheryTarget = world.targets[0]
		var second: ArcheryTarget = world.targets[1]
		var original_hp: float = second.max_hp
		first.anchor = Vector2(180, 238)
		first.tick(0, 0)
		for index: int in range(1, world.targets.size()):
			world.targets[index].anchor = Vector2(350 + index * 80, 100)
			world.targets[index].tick(0, 0)
		var expected: float = 40 * float(run.mode_parameters["score"])
		verify(first.max_hp == (48 if id == "normal" else 72) and first.reward_score == expected and first.reward_gold == 8, "real starting target values " + id)
		bosses.fire(world, 1000, 3)
		bosses.tick(world, 220)
		verify(run.defeated_count == 1 and run.defeat_score == expected and session.profile.total_score == expected and session.profile.total_defeats == 1, "real three-arrow kill grants one multiplied score and XP " + id)
		verify(run.gold == 8 and run.gold_earned == 8 and run.shots_left == 9, "difficulty grants no extra gold or draws " + id)
		world._settle_shots()
		verify(run.defeat_score == expected and session.profile.total_score == expected, "repeat settlement cannot multiply or repay " + id)
		verify(second.max_hp == original_hp, "existing live target keeps sampled HP after growth " + id)
		first.respawn_left = 0
		world._physics_process(0)
		var grown: Dictionary = ArcheryTarget.RULES.target_values(GameCatalog.TARGETS[0], 1, run.mode_parameters)
		verify(first.generation == 1 and first.max_hp == grown["max_hp"] and first.reward_score == grown["reward_score"], "real respawn samples one linear growth step " + id)
		var frozen: Dictionary = first.snapshot()
		session.return_to_lobby()
		world._physics_process(20)
		verify(first.snapshot() == frozen and run.mode_id == id, "paused field does not regrow or change mode " + id)
		world.queue_free()
		await tree.process_frame

func _boss_and_disk(tree: SceneTree) -> void:
	for id: String in ["normal", "hard", "hell"]:
		clean()
		var session := GameSession.new()
		var run: RunModel = session.start_run(false, id)
		bosses.prime(run, 100)
		var world: ArcheryWorld = bosses.field(tree, session)
		world._physics_process(0)
		var max_hp: float = 2880 if id == "normal" else 5760
		verify(world.boss.max_hp == max_hp and world.targets.is_empty() and run.boss_round == 1, "hundred ordinary kills clear field for mode Boss " + id)
		world.boss.hp = max_hp * 0.4
		world.boss.refresh_phase()
		world.boss.tick(0.47, 0)
		bosses.fire(world, 100000, 3, 1000)
		world.reload_left = 0.27
		# Save during actual flight, before any damage or victory is credited.
		session.capture_checkpoint(world.snapshot())
		var payload: Dictionary = session.save_payload()
		var store := SaveStore.new(PATH)
		verify(store.write(payload), "mode and moving Boss flight save " + id)
		var disk: Dictionary = store.read()
		var loaded := GameSession.from_dict(disk)
		var copy: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
		for arrow: Arrow in copy.arrows: arrow.set_physics_process(false)
		verify(loaded.run.to_dict() == run.to_dict() and copy.snapshot() == world.snapshot(), "disk preserves mode, injured Boss, shield pose, arrows, reload and RNG " + id)
		for field: ArcheryWorld in [world, copy]: bosses.tick(field, 160)
		var expected: float = 1200 * float(run.mode_parameters["score"])
		verify(run.phase == RunModel.Phase.CHOICE and loaded.run.phase == RunModel.Phase.CHOICE and run.bosses_defeated == 1 and loaded.run.bosses_defeated == 1, "three arrows still yield one victory choice " + id)
		verify(run.defeat_score == expected and loaded.run.defeat_score == expected and session.profile.total_score == expected and loaded.profile.total_score == expected and run.boss_reward_log[0]["score"] == expected, "Boss score, XP and log share single multiplied value " + id)
		verify(run.gold == 840 and loaded.run.gold == 840 and run.boss_reward_log[0]["gold"] == 840 and run.shots_left == 12 and run.supply_remaining() == 2, "victory coins/draws/supply retain normal rules " + id)
		verify(run.choices == loaded.run.choices and run.rng.state == loaded.run.rng.state, "same restored RNG keeps same fixed Boss offer " + id)
		var before: Dictionary = session.to_dict()
		verify(not session.record_boss_defeat("boss1", expected, 240) and session.to_dict() == before, "duplicate Boss cannot pay mode score again " + id)
		for change: Array in [["mode_id", "unknown"], ["mode_id", 1], ["mode_schema", 2]]:
			var bad: Dictionary = disk.duplicate(true)
			bad["run"][change[0]] = change[1]
			verify(not store.write(bad), "reject malformed mode " + str(change))
		for key: String in ["mode_schema", "mode_id", "mode_parameters"]:
			var bad: Dictionary = disk.duplicate(true)
			bad["run"].erase(key)
			verify(not store.write(bad), "current save requires " + key)
		for key: String in ["target_health", "boss_health", "score", "health_growth"]:
			for value: Variant in [NAN, INF, -1.0, 11.0, "bad"]:
				var bad: Dictionary = disk.duplicate(true)
				bad["run"]["mode_parameters"][key] = value
				verify(not store.write(bad), "reject invalid sampled mode value " + key + "/" + str(value))
		bosses.choose_safe(run)
		world._physics_process(0)
		verify(not run.boss_active and world.targets.size() == 3 and world.targets[0].max_hp == ArcheryTarget.RULES.target_values(world.targets[0].definition, 100, run.mode_parameters)["max_hp"], "post-Boss targets retain this mode and actual kill growth " + id)
		session.end_run("abandoned")
		verify(session.last_run_summary["mode_id"] == id and session.last_run_summary["defeat_score"] == expected, "terminal summary carries mode and actual score " + id)
		for field: ArcheryWorld in [world, copy]: field.queue_free()
		await tree.process_frame
		clean()

func _migration(tree: SceneTree) -> void:
	clean()
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 200
	run.open_skills()
	run.buy_supply(run.supply_token())
	run.close_skills()
	bosses.prime(run, 100)
	var world: ArcheryWorld = bosses.field(tree, session)
	world._physics_process(0)
	world.boss.hp = 1000
	world.boss.refresh_phase()
	world.boss.tick(0.31, 0)
	bosses.fire(world, 24)
	world.reload_left = 0.3
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.to_dict()
	for key: String in ["mode_schema", "mode_id", "mode_parameters"]: payload["run"].erase(key)
	var bytes: String = JSON.stringify({"version": 18, "payload": payload}, "", true, true)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(PATH)
	var disk: Dictionary = store.read()
	var loaded := GameSession.from_dict(disk)
	verify(FileAccess.get_file_as_string(PATH + ".legacy-v18") == bytes and JSON.parse_string(FileAccess.get_file_as_string(PATH))["version"] == SaveStore.VERSION, "v18 original bytes archive before upgrade")
	verify(loaded.run.mode_id == "normal" and loaded.world_snapshot == JSON.parse_string(bytes)["payload"]["world"], "old Boss and all flight data preserve existing values without scaling")
	verify(loaded.run.gold == run.gold and loaded.run.gold_spent == 24 and loaded.run.supply_total_bought == 1 and loaded.run.rng.state == run.rng.state and loaded.profile.total_score == session.profile.total_score, "old supplies, wallet, ledger, RNG and XP do not reset or repay")
	var current: String = FileAccess.get_file_as_string(PATH)
	store.read()
	verify(FileAccess.get_file_as_string(PATH) == current and store.migration_notice.is_empty(), "repeated read never rescales or remigrates")
	world.queue_free()
	await tree.process_frame
	clean()
