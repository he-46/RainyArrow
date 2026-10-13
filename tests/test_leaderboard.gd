extends RefCounted

var assertion: Callable
var bosses: RefCounted
const PATH: String = "user://tests/t14b-leaderboard.json"

func _init(check: Callable) -> void:
	assertion = check
	bosses = preload("res://tests/test_boss.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T14-B: " + message)

func clean() -> void:
	for suffix: String in ["", ".tmp", ".bak", ".legacy-v19"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func write_bytes(bytes: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()

func _old(payload: Dictionary) -> Dictionary:
	var data: Dictionary = payload.duplicate(true)
	data["profile"].erase("leaderboard_schema")
	data["profile"].erase("leaderboard")
	for key: String in ["ranking_schema", "ranking_processed", "rank_at_finish", "ended_at"]: data["run"].erase(key)
	for key: String in ["ranking_processed", "rank_at_finish", "ended_at"]: data["last_run_summary"].erase(key)
	return data

func run_all(tree: SceneTree) -> void:
	_ordering()
	_disk_and_validation()
	await _real_endings(tree)
	await _migration(tree)
	clean()

func _ordering() -> void:
	var session := GameSession.new()
	verify(session.profile.leaderboard.entries.is_empty(), "fresh profile has empty board")
	var ids: Array[String] = []
	var points: Array[float] = [100, 300, 200, 400, 300, 50, 400]
	var modes: Array[String] = ["normal", "hard", "hell", "normal", "hard", "hell", "hell"]
	var expected: Array[int] = [1, 1, 2, 1, 3, 0, 2]
	for index: int in range(points.size()):
		var run: RunModel = session.start_run(true, modes[index])
		ids.append(run.run_id)
		session.record_defeat("ranked", points[index], 8)
		var before: Array[Dictionary] = session.profile.leaderboard.entries
		session.return_to_lobby()
		verify(session.profile.leaderboard.entries == before and not run.ranking_processed, "pause never submits " + str(index))
		session.resume_run()
		verify(session.end_run("abandoned") and run.ranking_processed and run.rank_at_finish == expected[index] and run.ended_at > 0, "completion submits exact score once " + str(index))
		verify(run.gold == 0 and session.last_run_summary["rank_at_finish"] == expected[index], "terminal wallet and ranking share summary " + str(index))
		before = session.profile.leaderboard.entries
		verify(not session.end_run() and session.profile.leaderboard.entries == before, "duplicate completion is inert " + str(index))
		verify(before.size() <= 3, "only three records retained " + str(index))
	verify(session.profile.leaderboard.entries.map(func(row: Dictionary) -> String: return row["run_id"]) == [ids[3], ids[6], ids[1]], "fourth run evicts third; equal scores retain prior completion order")
	verify(session.profile.leaderboard.entries.map(func(row: Dictionary) -> String: return row["mode_id"]) == ["normal", "hell", "hard"], "three modes share one board with mode labels")
	var copy: Array[Dictionary] = session.profile.leaderboard.entries
	copy[0]["score"] = 1
	copy.clear()
	verify(session.profile.leaderboard.entries[0]["score"] == 400, "exported records cannot mutate permanent board")
	var unchanged: Array[Dictionary] = session.profile.leaderboard.entries
	var zero: RunModel = session.start_run(true)
	session.end_run()
	verify(zero.rank_at_finish == 0 and zero.ranking_processed and session.profile.leaderboard.entries == unchanged, "zero score is processed but never occupies a place")
	var active: RunModel = session.start_run(true, "hell")
	session.record_defeat("abandon", 500)
	session.start_run(true, "hard")
	verify(active.finished_reason == "abandoned" and session.profile.leaderboard.entries[0]["run_id"] == active.run_id and session.run.defeat_score == 0, "new adventure submits old settled score and starts clean")
	var practice := GameSession.new(false)
	practice.start_run()
	practice.record_defeat("lesson", 100000)
	practice.end_run()
	verify(practice.profile.leaderboard.entries.is_empty() and practice.run.rank_at_finish == 0, "practice session explicitly never submits")
	verify(Leaderboard.from_array([{}, {}, {}, {}]).entries.is_empty(), "direct oversized import stays empty and bounded")
	verify(PlayerProfile.from_dict(session.profile.to_dict()).leaderboard.entries == session.profile.leaderboard.entries, "permanent board round trips without using cumulative XP")

func _disk_and_validation() -> void:
	clean()
	var session := GameSession.new()
	session.profile.record_score(999999)
	session.start_run(false, "hard")
	session.record_defeat("half", 64.5, 8)
	session.end_run()
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "board, terminal run, marker and summary save together")
	var good: String = FileAccess.get_file_as_string(PATH)
	var payload: Dictionary = store.read()
	var loaded := GameSession.from_dict(payload)
	verify(loaded.profile.leaderboard.entries[0]["score"] == 64.5 and loaded.profile.total_score == 1000063.5 and loaded.run.rank_at_finish == 1, "disk uses single-run half score, not cumulative XP")
	verify(not loaded.end_run() and loaded.profile.leaderboard.entries == session.profile.leaderboard.entries, "restart cannot resubmit ended run")
	verify(store.write(loaded.save_payload()), "continued ended state can immediately checkpoint")
	good = FileAccess.get_file_as_string(PATH)
	var invalid: Array[Dictionary] = []
	for key: String in ["leaderboard_schema", "leaderboard"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["profile"].erase(key)
		invalid.append(bad)
	for field: String in ["ranking_schema", "ranking_processed", "rank_at_finish", "ended_at"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["run"].erase(field)
		invalid.append(bad)
	for pair: Array in [["leaderboard_schema", 2], ["leaderboard", "bad"], ["leaderboard", [{}, {}, {}, {}]]]:
		var bad: Dictionary = payload.duplicate(true)
		bad["profile"][pair[0]] = pair[1]
		invalid.append(bad)
	for field: String in ["run_id", "mode_id", "score", "ended_at", "reason", "defeated_count", "bosses_defeated"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["profile"]["leaderboard"][0].erase(field)
		invalid.append(bad)
	for pair: Array in [["run_id", ""], ["run_id", "x".repeat(129)], ["mode_id", "unknown"], ["mode_id", 0], ["score", NAN], ["score", INF], ["score", -1], ["score", 0], ["score", "64.5"], ["ended_at", -1], ["ended_at", 0], ["ended_at", 1.5], ["defeated_count", -1], ["bosses_defeated", "1"], ["reason", "paused"]]:
		var bad: Dictionary = payload.duplicate(true)
		bad["profile"]["leaderboard"][0][pair[0]] = pair[1]
		invalid.append(bad)
	for pair: Array in [["ranking_schema", 2], ["ranking_processed", false], ["ranking_processed", 1], ["rank_at_finish", 0], ["rank_at_finish", 4], ["rank_at_finish", 1.5], ["ended_at", -1], ["ended_at", 0], ["mode_id", "hell"], ["defeat_score", 65], ["phase", RunModel.Phase.PLAYING]]:
		var bad: Dictionary = payload.duplicate(true)
		bad["run"][pair[0]] = pair[1]
		invalid.append(bad)
	for field: String in ["run_id", "rank_at_finish", "ended_at", "mode_id", "defeat_score"]:
		var bad: Dictionary = payload.duplicate(true)
		bad["last_run_summary"].erase(field)
		invalid.append(bad)
	var duplicate: Dictionary = payload.duplicate(true)
	duplicate["profile"]["leaderboard"].append(duplicate["profile"]["leaderboard"][0].duplicate())
	invalid.append(duplicate)
	var unordered: Dictionary = payload.duplicate(true)
	var larger: Dictionary = unordered["profile"]["leaderboard"][0].duplicate()
	larger["run_id"] = "other"
	larger["score"] = 65
	unordered["profile"]["leaderboard"].append(larger)
	invalid.append(unordered)
	for index: int in range(invalid.size()):
		verify(not store.write(invalid[index]) and FileAccess.get_file_as_string(PATH) == good, "invalid rank transaction preserves good bytes " + str(index))
	# A malformed current file falls back to the entire previous-good transaction.
	var corrupt: Dictionary = payload.duplicate(true)
	corrupt["profile"]["leaderboard"][0]["score"] = -1
	write_bytes(JSON.stringify({"version": SaveStore.VERSION, "payload": corrupt}))
	var recovered: Dictionary = store.read()
	verify(not recovered.is_empty() and not store.last_error.is_empty() and recovered == payload, "damaged board restores whole good snapshot, not partial records")
	var future: String = good.replace('"version":%d' % SaveStore.VERSION, '"version":999')
	write_bytes(future)
	store.read()
	verify(store.write_blocked and not store.write(payload) and FileAccess.get_file_as_string(PATH) == future, "future file remains untouched")
	clean()

func _real_endings(tree: SceneTree) -> void:
	for id: String in ["normal", "hard", "hell"]:
		var session := GameSession.new()
		var run: RunModel = session.start_run(false, id)
		var world: ArcheryWorld = bosses.field(tree, session)
		world.boss_enabled = false
		run.shots_left = 1
		world.targets[0].anchor = Vector2(180, 238)
		world.targets[0].tick(0, 0)
		for index: int in range(1, world.targets.size()):
			world.targets[index].anchor = Vector2(350 + 80 * index, 100)
			world.targets[index].tick(0, 0)
		bosses.fire(world, 1000, 3)
		bosses.tick(world, 220)
		var score: float = 40 * float(run.mode_parameters["score"])
		verify(run.is_finished() and run.rank_at_finish == 1 and run.defeat_score == score, "real last volley ends and ranks only once " + id)
		verify(session.profile.leaderboard.entries.size() == 1 and session.profile.leaderboard.entries[0]["score"] == score and session.profile.leaderboard.entries[0]["mode_id"] == id, "actual mode score is already multiplied before ranking " + id)
		world._settle_shots()
		verify(not session.end_run() and session.profile.leaderboard.entries.size() == 1, "repeat final settlement cannot duplicate " + id)
		world.queue_free()
		await tree.process_frame
	# Abandon an injured target while an uncredited killing volley is still in flight.
	var session := GameSession.new()
	session.start_run(false, "hard")
	session.record_defeat("prior-settled", 64.5)
	var world: ArcheryWorld = bosses.field(tree, session)
	world.targets[0].hp = 1
	bosses.fire(world, 1000, 3)
	var seed: int = session.run.rng.state
	session.end_run("abandoned")
	verify(session.profile.leaderboard.entries[0]["score"] == 64.5 and session.run.defeat_score == 64.5 and session.run.rng.state == seed and world.arrows.size() == 3, "abandon never settles extra in-flight damage or samples RNG")
	world.queue_free()
	await tree.process_frame
	var boss_session := GameSession.new()
	var boss_run: RunModel = boss_session.start_run(false, "hard")
	boss_session.record_defeat("ordinary-before-boss", 60, 8)
	bosses.prime(boss_run, 100)
	var arena: ArcheryWorld = bosses.field(tree, boss_session)
	arena._physics_process(0)
	bosses.fire(arena, 100000, 3, 1000)
	bosses.tick(arena, 220)
	verify(boss_run.phase == RunModel.Phase.CHOICE and boss_run.defeat_score == 1860 and boss_session.profile.leaderboard.entries.is_empty(), "Boss score waits for fixed reward and never ranks at victory alone")
	bosses.choose_safe(boss_run)
	arena._physics_process(0)
	boss_run.shots_left = 0
	arena._physics_process(0)
	verify(boss_run.phase == RunModel.Phase.SUPPLY and boss_session.profile.leaderboard.entries.is_empty(), "final affordable supply decision remains unfinished and unranked")
	boss_run.decline_supply(boss_run.supply_offer_id)
	boss_session.capture_checkpoint(arena.snapshot())
	clean()
	var store := SaveStore.new(PATH)
	verify(boss_run.is_finished() and boss_session.profile.leaderboard.entries[0]["score"] == 1860 and boss_session.profile.leaderboard.entries[0]["bosses_defeated"] == 1 and store.write(boss_session.save_payload()), "declining supply ranks settled ordinary plus actual Boss score together")
	arena.queue_free()
	await tree.process_frame

func _migration(tree: SceneTree) -> void:
	for kind: String in ["active", "terminal", "unfinalized"]:
		clean()
		var session := GameSession.new()
		var run: RunModel = session.start_run(false, "hell")
		session.record_defeat("prior", 80, 8)
		var world: ArcheryWorld = bosses.field(tree, session)
		world.targets[0].hp = 17
		bosses.fire(world, 24, 3)
		world.reload_left = 0.31
		if kind == "terminal": session.end_run("abandoned")
		if kind == "unfinalized": run.phase = RunModel.Phase.LOST
		session.capture_checkpoint(world.snapshot())
		var payload: Dictionary = _old(session.to_dict())
		var bytes: String = JSON.stringify({"version": 19, "payload": payload}, "", true, true)
		write_bytes(bytes)
		var store := SaveStore.new(PATH)
		var saved: Dictionary = store.read()
		verify(not saved.is_empty(), "v19 migrates " + kind)
		if saved.is_empty(): world.queue_free(); await tree.process_frame; continue
		var loaded := GameSession.from_dict(saved)
		verify(FileAccess.get_file_as_string(PATH + ".legacy-v19") == bytes and JSON.parse_string(FileAccess.get_file_as_string(PATH))["version"] == SaveStore.VERSION, "v19 raw bytes archived before upgrade " + kind)
		verify(loaded.profile.leaderboard.entries.is_empty() and loaded.profile.total_score == 80 and loaded.run.mode_id == "hell" and loaded.run.defeat_score == 80, "old XP/summary never becomes historical board entries " + kind)
		verify(loaded.world_snapshot == JSON.parse_string(bytes)["payload"]["world"] and loaded.run.rng.state == run.rng.state and loaded.run.supply_parameters == run.supply_parameters, "old world/mode/RNG/supply retained " + kind)
		if kind == "active":
			verify(not loaded.run.ranking_processed and loaded.has_active_run(), "unfinished legacy run remains eligible")
			loaded.end_run("abandoned")
			verify(loaded.profile.leaderboard.entries.size() == 1 and loaded.profile.leaderboard.entries[0]["score"] == 80 and store.write(loaded.save_payload()), "legacy active run can rank when actually finished")
		else:
			verify(loaded.run.ranking_processed and not loaded.has_active_run() and not loaded.end_run() and loaded.profile.leaderboard.entries.is_empty(), "old terminal run never backfills or revives " + kind)
		var current: String = FileAccess.get_file_as_string(PATH)
		store.read()
		verify(FileAccess.get_file_as_string(PATH) == current and store.migration_notice.is_empty(), "current reread never migrates or resubmits " + kind)
		world.queue_free()
		await tree.process_frame
