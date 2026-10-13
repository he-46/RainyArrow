extends RefCounted
## T06: reward entitlement, safe drafting, exact offers, real paused flight and migration.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T06: " + message)

func _ordinary_only(run: RunModel) -> void:
	# T06 regression fixtures exercise ordinary stacking; real trait drafting is T07.
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: run.seen_encounters.append(reward.id)

func run_all(tree: SceneTree) -> void:
	_thresholds_and_effects()
	_draft_rules()
	_batch_settlement()
	await _paused_flight(tree)
	await _last_arrow(tree)
	_migrate_v5()

func _thresholds_and_effects() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	_ordinary_only(run)
	var random_before: int = run.rng.state
	for index: int in range(9): session.record_defeat("early-%d" % index, 0, 8)
	verify(run.pending_encounters == 0 and not run.offer_encounter() and run.rng.state == random_before, "nine kills and menu access cannot manufacture or reroll rewards")
	session.record_defeat("tenth", 0, 8)
	verify(run.pending_encounters == 1 and run.phase == RunModel.Phase.PLAYING, "tenth kill queues reward without interrupting current draw")
	verify(not session.record_defeat("tenth", 0, 8) and run.pending_encounters == 1, "duplicate threshold kill cannot queue twice")
	for index: int in range(10, 35): session.record_defeat("later-%d" % index, 0, 8)
	verify(run.defeated_count == 35 and run.pending_encounters == 3 and run.encounter_rewards_generated == 3, "10/20/30 thresholds accumulate before a pause")
	verify(run.offer_encounter() and run.phase == RunModel.Phase.CHOICE and run.choices.size() == 3, "earned offer pauses and has exactly three options")
	var choices: Array[String] = run.choices.duplicate()
	var token: int = run.encounter_offer_id
	random_before = run.rng.state
	verify(not run.offer_encounter() and run.choices == choices and run.rng.state == random_before, "opening an existing offer cannot reroll")
	verify(not run.choose_encounter("unknown", token) and not run.choose_encounter("windfall", token + 1), "unknown and stale offers cannot be claimed")
	verify(not run.consume_shot() and not run.open_skills() and not run.buy(SkillCatalog.ALL[0]), "combat and skills cannot bypass a choice")
	# Keep the original three-card effects fixture deterministic after pool expansion.
	run.choices.assign(["windfall", "rainfall", "second_wind"])
	verify(run.choose_encounter("windfall", token) and run.pending_encounters == 2 and run.stats.gold_multiplier == 1.25, "gold reward applies once then advances queued offer")
	verify(not run.choose_encounter("second_wind", token) and run.pending_encounters == 2, "double click on old offer cannot claim another queued reward")
	run.choices.assign(["windfall", "rainfall", "second_wind"])
	verify(run.choose_encounter("rainfall", run.encounter_offer_id) and run.stats.arrow_count == 2, "ordinary arrow reward increases per-draw count")
	run.shots_left = 0
	run.choices.assign(["windfall", "rainfall", "second_wind"])
	verify(run.choose_encounter("second_wind", run.encounter_offer_id) and run.shots_left == 3 and run.pending_encounters == 0 and run.phase == RunModel.Phase.PLAYING, "last queued draw reward restores three opportunities before resuming")
	verify(not run.choose_encounter("second_wind", run.encounter_offer_id), "completed offer cannot replay instant ammo")
	var restored: RunModel = RunModel.from_dict(run.to_dict())
	restored.rebuild_stats()
	restored.rebuild_stats()
	verify(restored.shots_left == 3 and restored.stats.to_dict() == run.stats.to_dict() and restored.encounter_picks == run.encounter_picks, "reload and rebuild never replay grants or compound stats")
	verify(run.consume_shot() and run.shots_left == 2, "extra arrow still costs one draw")
	var gold_before: float = run.gold_earned
	session.record_defeat("after-gold", 0, 8)
	verify(is_equal_approx(run.gold_earned - gold_before, 10), "gold reward affects subsequent kill income")
	session.return_to_lobby()
	verify(not run.choose_encounter("windfall", run.encounter_offer_id), "paused lobby cannot claim offers")
	var next: RunModel = session.start_run(true)
	verify(next.encounter_picks.is_empty() and next.pending_encounters == 0 and next.choices.is_empty() and next.seen_encounters.is_empty() and next.stats.arrow_count == 1, "new run clears all encounter state and effects")
	var combined := GameSession.new()
	combined.profile.record_defeat(450)
	combined.purchase_talent("economy_root")
	combined.purchase_talent("damage_root")
	run = combined.start_run()
	_ordinary_only(run)
	for index: int in range(50): combined.record_defeat("combined-%d" % index, 0, 0)
	run.offer_encounter()
	for id: String in ["windfall", "rainfall", "windfall", "rainfall", "second_wind"]:
		run.choices.assign(["windfall", "rainfall", "second_wind"])
		run.choose_encounter(id, run.encounter_offer_id)
	run.skill_levels["quantity"] = 2
	run.rebuild_stats()
	verify(run.stats.arrow_count == 5 and is_equal_approx(run.stats.damage, 28 * pow(0.85, 2)), "ordinary arrows combine with quantity skill and talent damage in a stable order")
	verify(is_equal_approx(run.stats.gold_multiplier, 1.65) and run.encounter_picks["windfall"] == 2, "repeat ordinary gold stacks with permanent efficiency")
	var unchanged: Dictionary = run.to_dict()
	run.rebuild_stats()
	verify(run.to_dict() == unchanged, "stat rebuild does not change entitlement, picks or instant grants")

func _draft_rules() -> void:
	var pool: Array[EncounterData] = []
	var by_id: Dictionary = {}
	for reward: EncounterData in EncounterCatalog.ALL: by_id[reward.id] = reward
	for index: int in range(8):
		var fixture := EncounterData.new()
		fixture.id = "fixture-%d" % index
		fixture.is_trait = true
		fixture.has_debuff = index % 2 == 0
		fixture.group = "conversion" if index < 3 else fixture.id
		pool.append(fixture)
		by_id[fixture.id] = fixture
	var seen: Array[String] = []
	var random := RandomNumberGenerator.new()
	random.seed = 23847
	var valid: bool = true
	var repeated_trait: bool = false
	for iteration: int in range(50):
		var before: Array[String] = seen.duplicate()
		var offered: Array[String] = EncounterCatalog.draft(random, seen, pool)
		var groups: Dictionary = {}
		var safe: bool = false
		for id: String in offered:
			var reward: EncounterData = by_id[id]
			valid = valid and not groups.has(reward.candidate_group())
			groups[reward.candidate_group()] = true
			if reward.is_trait:
				repeated_trait = repeated_trait or before.has(id)
				valid = valid and seen.has(id)
			elif not reward.has_debuff: safe = true
		valid = valid and safe and offered.size() == 3
	verify(valid and not repeated_trait, "all drafts have unique groups, a safe ordinary option, and no redisplayed trait even when unchosen")
	verify(seen.size() == 8, "shown traits leave pool independent of selection")
	var after_exhaustion: Array[String] = EncounterCatalog.draft(random, seen, pool)
	var ordinary: bool = after_exhaustion.size() == 3
	for id: String in after_exhaustion: ordinary = ordinary and not EncounterCatalog.find(id).is_trait
	verify(ordinary, "ordinary rewards fill exhausted trait pool without duplicate cards")
	var all_debuff: Array[EncounterData] = []
	for reward: EncounterData in pool:
		if reward.has_debuff: all_debuff.append(reward)
	seen.clear()
	var guarantee: bool = true
	for index: int in range(20):
		var safe: bool = false
		for id: String in EncounterCatalog.draft(random, seen, all_debuff):
			var reward: EncounterData = by_id[id]
			if not reward.has_debuff and not reward.is_trait: safe = true
		guarantee = guarantee and safe
	verify(guarantee, "a debuff-heavy pool can never force the player to take a debuff")
	verify(EncounterCatalog.draft(random, seen, []).size() == 3, "empty optional pool falls back to three distinct ordinary rewards")

func _batch_settlement() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for index: int in range(9): session.record_defeat("seed-%d" % index, 0, 0)
	run.shots_left = 1
	run.consume_shot()
	var hits: Array[Dictionary] = []
	for index: int in range(23):
		hits.append({"hit_id": "batch-hit-%d" % index, "event_id": "batch-kill-%d" % index, "effective": 1.0,
			"broken": true, "critical": false, "bullseye": false, "reward_score": 40.0, "reward_gold": 8.0})
	verify(session.settle_shot(run.shot_sequence, hits), "multi-threshold draw settles")
	verify(run.defeated_count == 32 and run.gold == 184 and session.profile.total_score == 920 and run.pending_encounters == 3 and run.phase == RunModel.Phase.CHOICE, "entire draw awards all kills before opening choice; three thresholds survive")
	run.settle_volley()
	verify(not run.is_finished() and run.shots_left == 0, "pending choice delays final-ammo exhaustion")
	var saved: Dictionary = session.to_dict()
	var restored: GameSession = GameSession.from_dict(saved)
	verify(restored.run.choices == run.choices and restored.run.rng.state == run.rng.state and restored.run.pending_encounters == 3, "offered cards, queue and RNG restore without redraw")
	var before: Dictionary = restored.run.to_dict()
	verify(not restored.settle_shot(run.shot_sequence, hits) and restored.run.to_dict() == before, "replayed threshold draw cannot create extra encounters")
	verify(session.end_run("abandoned") and run.choices.is_empty() and run.pending_encounters == 0, "abandoning an offer clears terminal choice state")
	var store := SaveStore.new("user://tests/t06-terminal.json")
	verify(store.write(session.to_dict()), "terminal choice abandonment remains a valid save")
	_clean("user://tests/t06-terminal.json")

func _seed_nine(main: Node) -> void:
	main._new_run()
	_ordinary_only(main.run)
	main.world.set_physics_process(false)
	for index: int in range(9): main.session.record_defeat("seed-%d" % index, 0, 0)
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 0
	main.world.targets[0].anchor = Vector2(180, 238)
	main.world.targets[0].position = Vector2(180, 238)
	main.world.targets[0].hp = 1
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1

func _paused_flight(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	_seed_nine(main)
	main.world.clock = 2.0
	for kind: TargetData in GameCatalog.TARGETS:
		if String(kind.id) == "moving": main.world.targets[1].spawn(kind, 0)
	for target: ArcheryTarget in main.world.targets: target.tick(0, main.world.clock)
	main.world._release()
	var first: Arrow = main.world.arrows[0]
	first.set_physics_process(false)
	main.run.consume_shot()
	var later := Arrow.new()
	later.setup(ArcheryWorld.BOW, Vector2(100, -20), main.run.stats, 1, main.run.rng)
	later.shot_id = main.run.shot_sequence
	main.world._attach_arrow(later)
	later.set_physics_process(false)
	first._physics_process(0.2)
	main.world._physics_process(0.01)
	verify(main.run.phase == RunModel.Phase.CHOICE and tree.paused and main.world.arrows.size() == 1 and main.world.pending_volleys.has("2"), "actual tenth kill pauses later live arrow and keeps its pending draw")
	main.run.choices.assign(["windfall", "rainfall", "second_wind"])
	main._refresh()
	main._save_checkpoint()
	var state: Dictionary = main.world.snapshot()
	for index: int in range(3): await tree.physics_frame
	verify(main.world.snapshot() == state and main.world.clock == 2.0, "choice freezes targets, flight, reload and world clock at one consistent boundary")
	var payload: Dictionary = main.saves.read()
	verify(payload["run"]["choices"].size() == 3 and payload["run"]["pending_encounters"] == 1 and payload["world"] == JSON.parse_string(JSON.stringify(state)), "automatic choice save contains offer and precise in-flight world")
	var bad: Dictionary = payload.duplicate(true)
	bad["run"]["choices"] = ["windfall", "windfall", "rainfall"]
	verify(not main.saves.write(bad), "duplicate offer cards cannot overwrite good checkpoint")
	bad = payload.duplicate(true)
	bad["run"]["choices"][0] = "unknown"
	verify(not main.saves.write(bad), "unknown offer is rejected")
	bad = payload.duplicate(true)
	bad["run"]["pending_encounters"] = -1
	verify(not main.saves.write(bad), "negative reward queue is rejected")
	bad = payload.duplicate(true)
	bad["run"]["encounter_rewards_generated"] = 99
	verify(not main.saves.write(bad), "entitlement counter must match defeated threshold count")
	bad = payload.duplicate(true)
	bad["run"]["pending_encounters"] = [1]
	verify(not main.saves.write(bad), "queue with invalid numeric type is rejected without a cast error")
	bad = payload.duplicate(true)
	bad["run"]["encounter_schema"] = 2
	verify(not main.saves.write(bad), "unsupported encounter schema cannot masquerade as current state")
	main._navigate("hub")
	payload = main.saves.read()
	var offered: Array = payload["run"]["choices"].duplicate()
	var token: int = main.run.encounter_offer_id
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	main.world.set_physics_process(false)
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	verify(tree.paused and main.run.phase == RunModel.Phase.CHOICE and main.run.choices == offered and main.world.snapshot() == state, "lobby and disk continuation return to exact fixed offer and moving-target flight")
	var old_stats: Dictionary = main.world.arrows[0].stats.to_dict()
	var before_rng: int = main.run.rng.state
	main._on_action("encounters", null)
	verify(main.run.choices == offered and main.run.rng.state == before_rng, "encounter button cannot redraw an active offer")
	var pick: Button
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == "rainfall": pick = button
	pick.pressed.emit()
	verify(not tree.paused and main.run.stats.arrow_count == 2 and main.world.arrows[0].stats.to_dict() == old_stats, "real card selection resumes original arrow, applying new stats to future shots")
	main._on_action("encounter_pick", {"id": "second_wind", "offer_id": token})
	verify(main.run.encounter_picks.size() == 1 and main.run.shots_left == 8, "stale selection cannot add a second reward")
	var selected_payload: Dictionary = main.saves.read()
	verify(selected_payload["run"]["encounter_picks"]["rainfall"] == 1 and selected_payload["world"]["arrows"].size() == 1, "selection and untouched live arrow persist together")
	main._on_action("encounters", null)
	verify(tree.paused and main.hud.encounter_log_open and main.run.pending_encounters == 0 and main.run.choices.is_empty(), "history button pauses and views picks without generating rewards")
	main._on_action("encounter_close", null)
	verify(not tree.paused and not main.hud.encounter_log_open, "history close resumes flight")
	later = main.world.arrows[0]
	var origin: Vector2 = later.position
	later._physics_process(0.01)
	verify(later.position != origin, "restored projectile continues after encounter selection")
	main.queue_free()
	await tree.process_frame

func _last_arrow(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	for restore: bool in [true, false]:
		_seed_nine(main)
		main.run.shots_left = 1
		main.world._release()
		var arrow: Arrow = main.world.arrows[0]
		arrow.set_physics_process(false)
		arrow._physics_process(0.2)
		main.world._physics_process(0.01)
		verify(main.run.shots_left == 0 and not main.run.is_finished() and main.run.phase == RunModel.Phase.CHOICE and tree.paused, "real final arrow tenth kill gets choice before end")
		main.run.choices.assign(["windfall", "rainfall", "second_wind"])
		main._refresh()
		main._save_checkpoint()
		var chosen: String = "second_wind" if restore else "windfall"
		for button: Button in main.hud.encounter_panel.choice_buttons:
			if button.name == chosen:
				button.pressed.emit()
				break
		main.world._physics_process(0.01)
		if restore:
			verify(main.run.shots_left == 3 and not main.run.is_finished() and main.run.phase == RunModel.Phase.PLAYING, "actual restore card rescues final draw")
		else:
			verify(main.run.is_finished() and main.run.gold == 0 and main.session.in_lobby, "declining draw restore ends once after pending choice resolves")
		var disk: GameSession = GameSession.from_dict(main.saves.read())
		verify(disk.run.encounter_picks.get(chosen) == 1 and disk.run.is_finished() == main.run.is_finished(), "final choice result survives disk save")
	main._new_run()
	verify(main.run.pending_encounters == 0 and main.run.encounter_picks.is_empty() and main.run.choices.is_empty(), "new UI run resets reward state after choices")
	main.queue_free()
	await tree.process_frame

func _migrate_v5() -> void:
	var path: String = "user://tests/t06-migration.json"
	_clean(path)
	var session := GameSession.new()
	session.start_run()
	for index: int in range(25): session.record_defeat("old-%d" % index, 0, 8)
	var payload: Dictionary = session.to_dict()
	for key: String in ["backpack_schema", "artifact_capacity", "artifact_revision", "discarded_artifacts", "trait_schema", "trait_levels", "encounter_schema", "encounter_picks", "encounter_rewards_generated", "encounter_offer_id", "boss_reward_schema", "reward_queue", "boss_reward_log"]: payload["run"].erase(key)
	payload["run"]["pending_encounters"] = 0
	var original: String = JSON.stringify({"version": 5, "payload": payload})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store := SaveStore.new(path)
	var loaded: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v5") == original, "v5 is archived byte-for-byte before encounter migration")
	verify(loaded.run.defeated_count == 25 and loaded.run.pending_encounters == 0 and loaded.run.encounter_rewards_generated == 2 and loaded.run.gold == 200, "old kills establish baseline without retroactive rewards or coin changes")
	for index: int in range(5): loaded.record_defeat("new-%d" % index, 0, 8)
	verify(loaded.run.pending_encounters == 1 and loaded.run.defeated_count == 30, "first new threshold after legacy baseline grants one reward")
	loaded.run.offer_encounter()
	loaded.capture_checkpoint({})
	verify(store.write(loaded.save_payload()), "migrated encounter offer can be saved")
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(restored.run.choices == loaded.run.choices and restored.run.encounter_offer_id == loaded.run.encounter_offer_id and store.migration_notice.is_empty(), "v6 repeated load keeps offer and does not re-migrate")
	_clean(path)

func _clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v5"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
