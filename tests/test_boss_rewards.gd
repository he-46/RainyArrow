extends RefCounted
## T10-C: last draw, one reward per family, typed fixed queue, v9 health migration.

var assertion: Callable
var base: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_boss.gd").new(check)

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T10-C: " + message)

func setup(tree: SceneTree) -> ArcheryWorld:
	var session := GameSession.new()
	base.prime(session.start_run(), 100)
	var world: ArcheryWorld = base.field(tree, session)
	world.set_meta("session", session)
	world._physics_process(0)
	return world

func owner(world: ArcheryWorld) -> GameSession:
	return world.get_meta("session") as GameSession

func run_all(tree: SceneTree) -> void:
	tree.paused = false
	verify(is_equal_approx(RunModel.BOSS_RULES.values(1)["max_hp"], 2880) and is_equal_approx(RunModel.BOSS_RULES.values(2)["max_hp"], 4608) and is_equal_approx(RunModel.BOSS_RULES.values(3)["max_hp"], 6336), "all round health values use triple baseline")
	verify(RunModel.BOSS_RULES.draw_reward(1) == 3 and RunModel.BOSS_RULES.draw_reward(2) == 3 and RunModel.BOSS_RULES.draw_reward(3) == 4 and RunModel.BOSS_RULES.draw_reward(99) == 6, "finite victory supply scales every two rounds and caps at six")
	await _family_and_continue(tree)
	await _queue_and_caps(tree)
	await _migration(tree)
	await _actual_ui(tree)

func _family_and_continue(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	var session: GameSession = owner(world)
	var run: RunModel = session.run
	var seen: Array[String] = run.seen_encounters.duplicate()
	run.shots_left = 1
	base.fire(world, 100000, 3, 21)
	base.tick(world, 92)
	verify(world.boss.hp == 0 and not world.arrows.is_empty() and run.bosses_defeated == 0 and run.shots_left == 0, "lethal three-arrow volley waits for the whole family with no early supply")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t10c-reward.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "lethal in-flight transaction saves before reward")
	var loaded: GameSession = GameSession.from_dict(store.read())
	var copy: ArcheryWorld = base.field(tree, loaded, loaded.world_snapshot)
	for arrow: Arrow in copy.arrows: arrow.set_physics_process(false)
	base.tick(copy, 200)
	verify(loaded.run.phase == RunModel.Phase.CHOICE and not loaded.run.is_finished() and loaded.run.shots_left == 3, "last draw victory supplies three draws before the pending choice can end the run")
	verify(loaded.run.bosses_defeated == 1 and loaded.run.boss_reward_log.size() == 1 and loaded.run.pending_encounters == 1, "three arrows produce exactly one victory record and choice")
	verify(loaded.run.defeated_count == 100 and loaded.run.encounter_rewards_generated == 10 and loaded.profile.total_defeats == 0, "Boss reward does not count ordinary kills or ten-kill rewards")
	verify(loaded.profile.total_score == 1200 and loaded.run.gold == 840 and loaded.run.boss_reward_log[0]["gold"] == 840, "score and actual multiplied coins are credited once and recorded")
	verify(loaded.run.reward_source() == {"kind": "boss", "round": 1} and copy.targets.is_empty() and copy.boss.hp == 0, "source and dead Boss remain explicit until reward choice")
	var safe: bool = loaded.run.choices.size() == 3
	var chosen: String = ""
	for id: String in loaded.run.choices:
		var reward: EncounterData = EncounterCatalog.find(id)
		safe = safe and not reward.is_trait and not reward.has_debuff and loaded.run.encounter_has_gain(reward)
		if reward.draws == 0: chosen = id
	verify(safe and not chosen.is_empty(), "Boss draft offers three distinct safe ordinary gains")
	verify(loaded.run.seen_encounters == seen, "safe Boss offer does not reserve or remove unshown traits")
	var choices: Array[String] = loaded.run.choices.duplicate()
	var token: int = loaded.run.encounter_offer_id
	var random_state: int = loaded.run.rng.state
	loaded.return_to_lobby()
	loaded.capture_checkpoint(copy.snapshot())
	verify(store.write(loaded.save_payload()), "pending Boss choice saves with terminal body and no ordinary targets")
	var again: GameSession = GameSession.from_dict(store.read())
	verify(again.run.suspended and again.run.choices == choices and again.run.encounter_offer_id == token and again.run.rng.state == random_state, "disk Continue keeps exact choice, token and RNG")
	verify(again.run.shots_left == 3 and again.run.boss_reward_log == JSON.parse_string(JSON.stringify(loaded.run.boss_reward_log, "", true, true)) and again.run.reward_queue == JSON.parse_string(JSON.stringify(loaded.run.reward_queue, "", true, true)), "Continue never repeats supply or victory income")
	again.resume_run()
	var resumed: ArcheryWorld = base.field(tree, again, again.world_snapshot)
	verify(not again.run.choose_encounter(chosen, token - 1) and again.run.shots_left == 3, "stale choice token cannot collect a Boss reward")
	verify(not again.record_boss_defeat("boss1", 1200, 240), "victory identity cannot pay twice while selection is pending")
	var good: String = FileAccess.get_file_as_string(path)
	var bad: Dictionary = loaded.save_payload()
	bad["run"]["reward_queue"].append({"kind": "boss", "round": 1})
	bad["run"]["pending_encounters"] += 1
	verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "duplicate Boss reward source refuses to overwrite good disk")
	bad = loaded.save_payload()
	bad["run"]["choices"][0] = "unified_arrow"
	bad["run"]["seen_encounters"].append("unified_arrow")
	verify(not store.write(bad), "Boss offer cannot be forged into a debuff trait")
	bad = loaded.save_payload()
	bad["run"]["reward_queue"][0]["round"] = 2
	verify(not store.write(bad), "queue cannot reference an unearned Boss victory")
	bad = loaded.save_payload()
	bad["run"]["boss_reward_log"][0]["draws"] = 7
	verify(not store.write(bad), "supply record cannot exceed the finite cap")
	bad = loaded.save_payload()
	bad["run"].erase("boss_reward_schema")
	verify(not store.write(bad), "current write requires reward schema")
	verify(again.run.choose_encounter(chosen, token) and not again.run.choose_encounter(chosen, token), "one choice consumes the token once")
	resumed._physics_process(0)
	verify(not again.run.boss_active and resumed.boss == null and resumed.targets.size() == 3 and again.run.shots_left == 3, "selection reopens same-run field without additional supply")
	verify(again.run.boss_reward_log[0]["choice"] == chosen and again.run.reward_queue.is_empty(), "chosen gain is recorded and source is consumed")
	again.capture_checkpoint(resumed.snapshot())
	verify(store.write(again.save_payload()), "completed Boss reward transaction saves and resumes")
	var completed: GameSession = GameSession.from_dict(store.read())
	verify(completed.run.gold == 840 and completed.run.shots_left == 3 and completed.run.boss_reward_log == again.run.boss_reward_log, "completed disk reward never replays supply or gain")
	# A pending selection blocks termination even if no draw remains for another reason.
	loaded.resume_run()
	loaded.run.shots_left = 0
	loaded.run.settle_volley()
	verify(loaded.run.phase == RunModel.Phase.CHOICE and loaded.has_active_run(), "zero draws cannot discard a pending victory choice")
	loaded.run.choose_encounter(chosen, token)
	copy._physics_process(0)
	verify(loaded.run.phase == RunModel.Phase.SUPPLY, "victory choice completes before affordable supply decision")
	loaded.run.decline_supply(loaded.run.supply_offer_id)
	verify(loaded.run.is_finished() and loaded.run.gold == 0 and loaded.last_run_summary["boss_reward_totals"]["draws"] == 3, "after choosing, true exhaustion clears coins and keeps Boss summary")
	for field: ArcheryWorld in [world, copy, resumed]: field.queue_free()
	await tree.process_frame
	clean(path)

func _queue_and_caps(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	var session: GameSession = owner(world)
	var run: RunModel = session.run
	# Model-level ordering: a prior ordinary entitlement precedes new Boss loot.
	run.encounter_picks["windfall"] = 9
	run.pending_encounters = 1
	run.shots_left = 0
	verify(session.record_boss_defeat("boss1", 1200, 240), "Boss reward can join an already earned ordinary queue")
	verify(run.reward_queue == [{"kind": "ordinary", "round": 0}, {"kind": "boss", "round": 1}] and run.pending_encounters == 2, "ordinary then Boss sources share one ordered queue")
	run.offer_encounter()
	verify(run.reward_source()["kind"] == "ordinary", "ordinary entitlement is offered first")
	var first: String = run.choices[0]
	for id: String in run.choices:
		if not EncounterCatalog.find(id).is_trait: first = id; break
	run.choose_encounter(first, run.encounter_offer_id)
	verify(run.phase == RunModel.Phase.CHOICE and run.reward_source()["kind"] == "boss" and run.pending_encounters == 1, "choosing ordinary immediately exposes the Boss source")
	run.choices.assign(["windfall", "rainfall", "second_wind"])
	var token: int = run.encounter_offer_id
	var before: int = run.shots_left
	verify(run.choose_encounter("second_wind", token) and run.shots_left == before + 3, "safe draw reward adds its own grant once")
	verify(not run.choose_encounter("second_wind", token) and run.boss_reward_log[0]["choice"] == "second_wind", "safe supply choice cannot be replayed")
	world.queue_free()
	await tree.process_frame
	world = setup(tree)
	run = world.run
	run.boss_round = 7
	run.boss_next_defeats = 800
	run.shots_left = 99999
	verify(owner(world).record_boss_defeat("boss7", 4800, 960) and run.shots_left == 100000 and run.boss_reward_log[0]["draws"] == 1, "global draw cap records only the amount actually granted")
	verify(not owner(world).record_boss_defeat("boss7", 4800, 960) and run.boss_reward_log.size() == 1, "dedup also prevents capped supply replay")
	world.queue_free()
	await tree.process_frame

func _migration(tree: SceneTree) -> void:
	var world: ArcheryWorld = setup(tree)
	world.boss.max_hp = 960
	world.boss.hp = 400
	world.boss.refresh_phase()
	world.boss.tick(0.41, 0)
	base.fire(world, 120)
	owner(world).capture_checkpoint(world.snapshot())
	var old: Dictionary = owner(world).save_payload()
	for key: String in ["boss_reward_schema", "reward_queue", "boss_reward_log", "economy_schema"]: old["run"].erase(key)
	old["world"]["boss"].erase("health_revision")
	var path: String = "user://tests/t10c-v9.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 9, "payload": old}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var disk: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v9") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v9 bytes are archived before health/reward migration")
	verify(disk.world_snapshot["boss"]["hp"] == 1200 and disk.world_snapshot["boss"]["max_hp"] == 2880 and disk.world_snapshot["boss"]["battle_phase"] == 2, "active Boss triples HP while preserving remaining fraction and phase")
	verify(disk.world_snapshot["boss"]["phase_clock"] == old["world"]["boss"]["phase_clock"] and disk.world_snapshot["boss"]["shield_position"] == old["world"]["boss"]["shield_position"], "health adjustment preserves moving pose and timing")
	verify(disk.world_snapshot["arrows"] == JSON.parse_string(JSON.stringify(old["world"]["arrows"], "", true, true)) and disk.run.shots_left == 9 and disk.run.rng.state == world.run.rng.state, "migration preserves launched arrow stats, draws and RNG")
	verify(disk.run.boss_reward_log.is_empty() and disk.run.reward_queue.is_empty(), "old history mints no retroactive Boss supplies or choices")
	var current: String = FileAccess.get_file_as_string(path)
	var twice: GameSession = GameSession.from_dict(store.read())
	verify(twice.world_snapshot["boss"]["hp"] == 1200 and FileAccess.get_file_as_string(path) == current and store.migration_notice.is_empty(), "repeat reading never triples health a second time")
	# A v9 victory that was already credited must only reopen the field.
	old["world"]["boss"]["hp"] = 0.0
	old["world"]["arrows"] = []
	old["world"]["pending_volleys"] = {}
	old["world"]["projectile_ledger"] = {}
	old["run"]["bosses_defeated"] = 1
	old["run"]["credited_defeats"]["boss1"] = true
	var historical: GameSession = GameSession.from_dict(old)
	var history_world: ArcheryWorld = base.field(tree, historical, historical.world_snapshot)
	history_world._physics_process(0)
	verify(historical.run.bosses_defeated == 1 and historical.run.boss_reward_log.is_empty() and historical.run.pending_encounters == 0, "credited historical victory never generates retroactive loot")
	verify(historical.run.shots_left == 9 and history_world.boss == null and history_world.targets.size() == 3, "credited dead Boss returns to field without a free supply replay")
	historical.capture_checkpoint(history_world.snapshot())
	verify(store.write(historical.save_payload()), "history without synthetic reward records remains a valid current save")
	history_world.queue_free()
	# Same v9 migration keeps an ordinary fixed offer and synthesizes its queue source.
	var normal := GameSession.new()
	normal.start_run()
	for index: int in range(10): normal.record_defeat("old-normal-%d" % index, 40, 8)
	normal.run.offer_encounter()
	old = normal.to_dict()
	for key: String in ["boss_reward_schema", "reward_queue", "boss_reward_log", "economy_schema"]: old["run"].erase(key)
	var restored: GameSession = GameSession.from_dict(old)
	verify(restored.run.choices == normal.run.choices and restored.run.rng.state == normal.run.rng.state and restored.run.reward_source()["kind"] == "ordinary", "old fixed ordinary offer is preserved without redraft")
	world.queue_free()
	await tree.process_frame
	clean(path)

func _actual_ui(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	base.prime(main.run, 100)
	main.world._physics_process(0)
	main.run.shots_left = 1
	base.fire(main.world, 100000, 3)
	base.tick(main.world, 200)
	verify(tree.paused and main.hud.encounter_panel != null and main.run.reward_source()["kind"] == "boss", "real victory pauses on the shared reward panel")
	var token: int = main.run.encounter_offer_id
	main._on_action("hub", null)
	var saved: Dictionary = main.saves.read()
	verify(saved["run"]["boss_reward_log"].size() == 1 and saved["run"]["shots_left"] == 3, "actual hub captures victory supply and pending choice")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	verify(tree.paused and main.hud.encounter_panel.choice_buttons.size() == 3 and main.run.encounter_offer_id == token, "actual Continue restores same paused three-choice panel")
	var chosen: String = main.run.choices[0]
	for id: String in main.run.choices:
		if EncounterCatalog.find(id).draws == 0: chosen = id; break
	var predicted: Dictionary = main.run.preview_encounter(EncounterCatalog.find(chosen)).to_dict()
	main._on_action("encounter_pick", {"id": chosen, "offer_id": token})
	main.world._physics_process(0)
	verify(not tree.paused and main.world.targets.size() == 3 and main.run.stats.to_dict() == predicted, "actual choice applies gain then resumes ordinary field")
	main.session.end_run("abandoned")
	verify(main.session.last_run_summary["boss_reward_log"][0]["choice"] == chosen and main.session.last_run_summary["bosses_defeated"] == 1, "result summary retains Boss victory and selected gain")
	main.queue_free()
	await tree.process_frame
	tree.paused = false

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v9"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
