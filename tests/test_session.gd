extends RefCounted
## T01 regression coverage. All filesystem fixtures live below a dedicated test directory.

const DIR: String = "user://tests/t01"
var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T01: " + message)

func run_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clean_fixtures()
	_profile_progression()
	_session_lifecycle()
	_atomic_checkpoint()
	_legacy_migration()
	_recovery_and_validation()
	_clean_fixtures()

func _profile_progression() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.record_defeat(250.0)
	verify(profile.level == 3 and profile.talent_points == 2, "one reward can cross multiple levels")
	verify(profile.grant_talent_points() == 0 and profile.talent_points == 2, "repeated level grant is idempotent")
	verify(profile.invest_talent("damage_root", 1), "spending ledger accepts available points")
	verify(not profile.invest_talent("damage_left", 2), "higher-cost node requires sufficient points")
	profile.record_defeat(200.0)
	verify(profile.level == 4 and profile.invest_talent("damage_left", 2), "higher tier spends its full cost")
	profile.equip_cosmetic("bow_moon")
	profile.settings["muted"] = true
	profile.tutorial_completed = true
	var payload: Dictionary = profile.to_dict()
	for iteration: int in range(3):
		profile = PlayerProfile.from_dict(payload)
		payload = profile.to_dict()
	verify(profile.level == 4 and profile.talent_points == 0, "repeated restore never grants spent points again")
	verify(profile.total_score == 450.0 and profile.total_defeats == 2, "restore does not replay defeat rewards")
	verify(profile.settings["muted"] and profile.equipped_cosmetics["bow"] == "bow_moon" and profile.tutorial_completed, "settings, cosmetics and tutorial persist")
	verify(profile.reset_talents() == 3 and profile.talent_points == 3, "reset refunds actual investment, not node count")
	verify(profile.reset_talents() == 0 and profile.talent_points == 3, "repeated reset cannot mint points")
	profile.record_defeat(-1.0)
	profile.record_defeat(INF)
	verify(profile.total_score == 450.0 and profile.total_defeats == 2, "invalid experience is rejected")
	var exported: Dictionary = profile.to_dict()
	exported["settings"]["muted"] = false
	verify(profile.settings["muted"], "serialized dictionaries do not alias live profile")

func _session_lifecycle() -> void:
	var session: GameSession = GameSession.new()
	verify(session.in_lobby and not session.has_active_run() and session.resume_run() == null, "fresh profile has no resumable run")
	session.profile.record_defeat(250.0)
	session.profile.invest_talent("damage_root", 1)
	session.profile.settings["muted"] = true
	var run: RunModel = session.start_run()
	var first_id: String = run.run_id
	run.gold = 63
	run.shots_left = 3
	run.legacy_skill_levels["power"] = 2
	run.encounters.append("lucky")
	run.rebuild_stats()
	verify(session.start_run() == null and run.shots_left == 3, "start cannot silently replace an active run")
	session.return_to_lobby()
	verify(run.suspended and not run.consume_shot(), "lobby suspends gameplay mutations")
	verify(not session.record_defeat("blocked", 100), "lobby cannot mint experience")
	verify(session.resume_run() == run and run.shots_left == 3 and run.gold == 63, "resume preserves ammo and local currency")
	session.profile.reset_talents()
	verify(run.talent_snapshot.get("damage_root") == 1, "respec leaves opening talent snapshot unchanged")
	verify(session.record_defeat("stage1-slot0-life0", 100), "defeat is accepted once")
	verify(not session.record_defeat("stage1-slot0-life0", 100), "duplicate defeat cannot award twice")
	verify(run.defeated_count == 1 and run.difficulty_step == 1 and session.profile.total_score == 350, "one event updates run and profile together")
	var restored: GameSession = GameSession.from_dict(session.to_dict())
	verify(not restored.record_defeat("stage1-slot0-life0", 100), "deduplication survives save/load")
	verify(restored.profile.total_score == 350 and restored.run.legacy_skill_levels.get("power") == 2 and restored.run.encounters == run.encounters, "build and permanent progress round-trip independently")
	var old_profile: Dictionary = session.profile.to_dict()
	var second: RunModel = session.start_run(true)
	verify(second.run_id != first_id and second.gold == 0 and second.shots_left == second.initial_shots, "new run receives only initial ammo and zero coins")
	verify(second.defeated_count == 0 and second.difficulty_step == 0 and second.skill_levels.is_empty() and second.encounters.is_empty(), "new run resets difficulty, skills and encounters")
	var after_profile: Dictionary = session.profile.to_dict()
	after_profile["leaderboard"] = old_profile["leaderboard"]
	verify(after_profile == old_profile and session.profile.leaderboard.entries.size() == 1 and session.profile.leaderboard.entries[0]["score"] == 100, "new run preserves permanent progress and records abandoned run score")
	verify(second.talent_snapshot.is_empty(), "new run takes the latest respec snapshot")
	second.gold = 91
	second.gold_fraction = 0.5
	verify(session.end_run() and second.gold == 0 and second.gold_fraction == 0 and session.in_lobby, "ending discards all local currency")
	verify(not session.end_run() and not session.has_active_run(), "ending twice is harmless")
	verify(session.last_run_summary["gold_discarded"] == 91 and not session.profile.to_dict().has("gold"), "summary records discarded gold without banking it")
	var ended: GameSession = GameSession.from_dict(session.save_payload())
	verify(not ended.has_active_run() and ended.run.gold == 0, "terminal transition replaces any older playable checkpoint")
	var won: GameSession = GameSession.new()
	won.start_run()
	won.run.shots_left = 0

	won.run.settle_volley()
	verify(won.run.finished_reason == "exhausted" and won.run.gold == 0, "continuous exhaustion uses the same end transition")

func _atomic_checkpoint() -> void:
	var session: GameSession = GameSession.new()
	session.start_run()
	session.capture_checkpoint({"clock": 1.25, "targets": [{"hp": 18.0}]})
	session.run.consume_shot()
	session.record_defeat("in-flight", 100)
	session.return_to_lobby()
	session.profile.settings["muted"] = true
	var snapshot: Dictionary = session.save_payload()
	verify(snapshot["profile"]["total_score"] == 0 and snapshot["run"]["shots_left"] == 10, "mid-volley save never mixes new XP with old ammo")
	verify(snapshot["profile"]["settings"]["muted"], "settings can persist during an unsettled volley")
	verify(snapshot["in_lobby"] and snapshot["run"]["suspended"], "pause persists without committing partially settled rewards")
	session.resume_run()
	verify(not session.save_payload()["in_lobby"], "resume updates checkpoint navigation without refilling ammo")
	session.capture_checkpoint({"clock": 2.0, "targets": [{"hp": 0.0, "respawn_left": 1.2}]})
	var store: SaveStore = SaveStore.new(DIR.path_join("checkpoint.json"))
	verify(store.write(session.save_payload()), "save a settled profile/run transaction")
	var loaded: GameSession = GameSession.from_dict(store.read())
	verify(loaded.profile.total_score == 100 and loaded.run.shots_left == 9 and loaded.world_snapshot["clock"] == 2.0, "profile, ammo and world restore at the same boundary")
	verify(not loaded.record_defeat("in-flight", 100), "restored kill cannot award a second permanent point")
	loaded.return_to_lobby()
	loaded.capture_checkpoint(loaded.world_snapshot)
	verify(store.write(loaded.save_payload()), "lobby checkpoint can be saved")
	var resumed: GameSession = GameSession.from_dict(store.read())
	verify(resumed.in_lobby and resumed.run.suspended and resumed.resume_run().shots_left == 9, "saved lobby state resumes without refilling ammo")

func _legacy_migration() -> void:
	var source: String = DIR.path_join("legacy.json")
	var destination: String = DIR.path_join("migrated.json")
	var prototype: RunModel = RunModel.new()
	prototype.gold = 44
	prototype.shots_left = 6
	var old_run: Dictionary = prototype.to_dict()
	old_run["lifetime_score"] = 8000.0
	old_run.erase("prototype_total_score")
	old_run.erase("skill_levels")
	old_run.erase("skill_schema")
	for key: String in ["trait_schema", "trait_levels", "mastery_schema", "mastery_levels", "mastery_unlocks"]: old_run.erase(key)
	old_run["purchases"] = {"power": 2}
	old_run.erase("encounters")
	old_run["blessings"] = ["lucky"]
	_write_json(source, {"version": 1, "payload": {"run": old_run, "muted": true, "world": {"clock": 5.5, "targets": [{"hp": 17.0}]}}})
	var original: String = FileAccess.get_file_as_string(source)
	var store: SaveStore = SaveStore.new(destination, [source])
	var migrated: Dictionary = store.read()
	verify(not migrated.is_empty() and not store.migration_notice.is_empty(), "legacy import produces a visible explanation")
	if migrated.is_empty():
		return
	var session: GameSession = GameSession.from_dict(migrated)
	verify(FileAccess.get_file_as_string(source) == original and FileAccess.get_file_as_string(destination + ".legacy-v1") == original, "legacy source and an exact archive are retained")
	verify(session.profile.total_score == 0 and session.profile.level == 1 and session.profile.talent_points == 0, "old hit-score is not converted into permanent XP")
	verify(session.profile.settings["muted"] and session.run.ruleset == "continuous_v1", "settings migrate and incompatible ruleset is labelled")
	verify(session.run.gold == 44 and session.run.shots_left == 6 and session.run.legacy_skill_levels["power"] == 2, "prototype run remains resumable with its build")
	verify(session.run.encounters == ["lucky"] and session.world_snapshot["targets"][0]["hp"] == 17, "legacy blessings and target durability survive")
	var seed_value: int = session.run.rng.randi()
	verify(seed_value == prototype.rng.randi(), "migration preserves RNG state exactly")
	session.profile.record_defeat(100)
	store.write(session.to_dict())
	var reread: GameSession = GameSession.from_dict(store.read())
	verify(reread.profile.total_score == 100 and store.migration_notice.is_empty(), "legacy import runs once and cannot overwrite newer progress")
	var bad_source: String = DIR.path_join("legacy-bad.json")
	_write_text(bad_source, "{broken")
	_write_text(bad_source + ".bak", original)
	var fallback: SaveStore = SaveStore.new(DIR.path_join("legacy-recovered.json"), [bad_source])
	verify(not fallback.read().is_empty(), "legacy backup can recover a corrupt old primary")

func _recovery_and_validation() -> void:
	var destination: String = DIR.path_join("recovery.json")
	var session: GameSession = GameSession.new()
	var store: SaveStore = SaveStore.new(destination)
	verify(store.write(session.to_dict()), "profile-only save works before the first game")
	verify(store.read()["run"] == null, "profile-only restore never fabricates an active run")
	session.start_run()
	session.run.gold = 29
	store.write(session.to_dict())
	var bad: Dictionary = session.to_dict()
	bad["profile"]["talents"] = ["invalid"]
	_write_json(destination, {"version": 2, "payload": bad})
	var restored: Dictionary = store.read()
	verify(not restored.is_empty() and restored["run"] == null, "malformed nested profile falls back to previous good backup")
	verify(not store.write(bad), "invalid state cannot overwrite a good checkpoint")
	var future_text: String = '{"version":999,"payload":{"future":true}}'
	_write_text(destination, future_text)
	store.read()
	verify(store.write_blocked and not store.write(session.to_dict()), "newer-version primary is protected even when a backup loads")
	verify(FileAccess.get_file_as_string(destination) == future_text, "future save bytes stay untouched")
	var temporary: String = DIR.path_join("temporary.json")
	_write_json(temporary + ".tmp", {"version": 2, "payload": session.to_dict()})
	var recovery: SaveStore = SaveStore.new(temporary)
	verify(recovery.read()["run"]["gold"] == 29, "complete pending write is recoverable")
	verify(ProjectSettings.get_setting("application/config/custom_user_dir_name") == "AzVGames/ArrowsLikeRain", "save directory has a stable non-display identifier")
	verify(store.last_error.contains("较新版本"), "protected save provides an actionable notice")

func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))

func _write_text(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _clean_fixtures() -> void:
	var directory: DirAccess = DirAccess.open(DIR)
	if directory != null:
		for file: String in directory.get_files():
			DirAccess.remove_absolute(DIR.path_join(file))



