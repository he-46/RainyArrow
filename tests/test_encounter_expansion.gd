extends RefCounted
## T11-A: actual effective gains, short safe offers, exact old offers and immutable flight.

var assertion: Callable
const NEW_IDS: Array[String] = ["steady_power", "tempered_tip", "quick_nock"]

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T11-A: " + message)

func entitle(run: RunModel, pending: int = 1) -> void:
	var count: int = 0
	for amount: int in run.encounter_picks.values(): count += amount
	run.defeated_count = (count + pending) * 10
	run.difficulty_step = run.defeated_count
	run.encounter_rewards_generated = run.defeated_count / 10
	run.boss_round = run.defeated_count / 100
	run.boss_next_defeats = (run.boss_round + 1) * 100
	run.pending_encounters = pending
	run.reward_queue.clear()
	run.phase = RunModel.Phase.PLAYING
	run.choices.clear()
	run.offer_exhausted = false

func capped(run: RunModel) -> void:
	run.encounter_picks = {"windfall": 12, "rainfall": 31, "steady_power": 83332, "tempered_tip": 333334}
	run.shots_left = 100000
	run.rebuild_stats()
	entitle(run)

func run_all(tree: SceneTree) -> void:
	_catalog_and_effects()
	_effective_caps()
	_drafts()
	_storage_and_skip()
	_boss_caps()
	await _flight(tree)
	await _percent_revision(tree)
	await _actual_ui(tree)

func _catalog_and_effects() -> void:
	var ordinary: int = 0
	var traits: int = 0
	var groups: Dictionary = {}
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: traits += 1
		else: ordinary += 1; groups[reward.candidate_group()] = true
	verify(EncounterCatalog.ALL.size() == 24 and ordinary == 6 and traits == 18 and groups.size() == 6, "expanded catalog contains six ordinary directions and eighteen traits")
	for id: String in NEW_IDS:
		var session := GameSession.new()
		var run: RunModel = session.start_run()
		var reward: EncounterData = EncounterCatalog.find(id)
		verify(not reward.is_trait and not reward.has_debuff and run.encounter_has_gain(reward), "new entry is a repeatable safe gain: " + id)
		entitle(run, 2)
		run.offer_encounter()
		run.choices.assign(NEW_IDS)
		var preview: Dictionary = run.preview_encounter(reward).to_dict()
		var token: int = run.encounter_offer_id
		verify(run.choose_encounter(id, token) and run.stats.to_dict() == preview and run.encounter_picks[id] == 1, "preview equals claimed first gain: " + id)
		verify(not run.choose_encounter(id, token), "old token cannot claim next queued reward: " + id)
		run.choices.assign(NEW_IDS)
		verify(run.choose_encounter(id, run.encounter_offer_id) and run.encounter_picks[id] == 2, "ordinary gain stacks across distinct offers: " + id)
		var stats: Dictionary = run.stats.to_dict()
		run.rebuild_stats()
		verify(run.stats.to_dict() == stats and RunModel.from_dict(run.to_dict()).stats.to_dict() == stats, "stack recomputation and restoration remain stable: " + id)
		match id:
			"steady_power": verify(run.stats.damage == 48, "two damage stacks add twelve each")
			"tempered_tip": verify(run.stats.armor_penetration == 6, "two penetration stacks add three each")
			"quick_nock": verify(is_equal_approx(run.stats.damage, 26.4) and is_equal_approx(run.stats.reload_seconds, 0.65), "two percent stacks add ten percent damage without changing reload")
	var run := RunModel.new()
	run.skill_levels["quantity"] = 2
	run.encounter_picks = {"rainfall": 2, "steady_power": 2, "unified_arrow": 1, "swarm_precision": 1, "critical_forging": 1, "critical_ricochet": 1, "tempered_tip": 2}
	run.rebuild_stats()
	verify(run.stats.arrow_count == 1 and is_equal_approx(run.stats.damage, 48 * pow(0.85, 2) * 5), "additive new damage precedes quantity penalty and unity")
	verify(run.stats.armor_penetration == 15 and run.stats.crit_chance == 0 and run.stats.crit_multiplier == 1 and run.stats.bounces == 5, "new penetration adds to the full conversion chain without erasing sources")
	verify(is_equal_approx(run.preview_encounter(EncounterCatalog.find("steady_power")).damage, 60 * pow(0.85, 2) * 5), "damage preview follows current conversion sources")
	verify(run.preview_encounter(EncounterCatalog.find("tempered_tip")).armor_penetration == 18, "penetration preview retains converted penetration")
	verify(run.encounter_comparison(EncounterCatalog.find("quick_nock")).contains("增伤 0% → 5%"), "percent card shows accumulated bonus and effective damage")
	run.encounter_picks["quick_nock"] = 2
	run.skill_levels["damage"] = 2
	run.rebuild_stats()
	verify(is_equal_approx(run.stats.damage, 64 * 1.1 * pow(0.85, 2) * 5), "percent bonus scales all additive sources before quantity and unity")
	verify(run.stat_explanations(run.evaluate_stats(run.skill_levels, run.encounter_picks))[0].contains("+10%"), "history explains additive percent stacks")
	verify(GameCatalog.BASE_BOW.damage == 24 and is_equal_approx(GameCatalog.BASE_BOW.reload_seconds, 0.65), "new source additions never mutate the base resource")

func _effective_caps() -> void:
	var run := RunModel.new()
	run.encounter_picks["steady_power"] = 79998
	run.rebuild_stats()
	verify(run.stats.damage == 960000 and run.encounter_has_gain(EncounterCatalog.find("quick_nock")), "last partial percentage gain remains eligible")
	verify(run.preview_encounter(EncounterCatalog.find("quick_nock")).damage == 1000000, "percent preview stops at the damage cap")
	run.encounter_picks["quick_nock"] = 1
	run.rebuild_stats()
	verify(not run.encounter_has_gain(EncounterCatalog.find("quick_nock")), "percent gain is filtered once damage cap is reached")
	capped(run)
	var none: bool = true
	for reward: EncounterData in EncounterCatalog.ALL:
		if not reward.is_trait: none = none and not run.encounter_has_gain(reward)
	verify(none and run.stats.damage == 1000000 and run.stats.armor_penetration == 1000000, "all ordinary effective caps are detected including draw cap")
	verify(run.encounter_comparison(EncounterCatalog.find("tempered_tip")).contains("暂无收益"), "stored capped option explains lack of gain")
	verify(RunModel.from_dict(run.to_dict()).encounter_picks == run.encounter_picks, "high stack history survives restore without dropping below cap")
	for id: String in ["steady_power", "tempered_tip"]:
		run.encounter_picks[id] -= 1
		run.rebuild_stats()
		verify(run.encounter_has_gain(EncounterCatalog.find(id)), "last partial gain remains selectable: " + id)
		var after: BowStats = run.preview_encounter(EncounterCatalog.find(id))
		verify(after.damage == 1000000 and after.armor_penetration == 1000000, "partial gain preview clamps exactly: " + id)
		run.encounter_picks[id] += 1
	capped(run)
	run.encounter_picks["rainfall"] = 30
	run.encounter_picks["unified_arrow"] = 1
	run.encounter_picks["swarm_precision"] = 1
	run.encounter_picks["critical_forging"] = 1
	run.rebuild_stats()
	verify(run.stats.arrow_count == 1 and run.stats.damage == 1000000 and run.encounter_has_gain(EncounterCatalog.find("rainfall")), "unified single arrow can still gain effective size from source quantity")
	run.encounter_picks["rainfall"] = 31
	run.rebuild_stats()
	verify(not run.encounter_has_gain(EncounterCatalog.find("rainfall")), "unity source quantity cap prevents phantom gains")

func _drafts() -> void:
	var run := RunModel.new()
	var all_seen: Dictionary = {}
	var safe: bool = true
	for seed: int in range(100):
		run.rng.seed = seed
		run.seen_encounters.clear()
		var cards: Array[String] = EncounterCatalog.draft(run.rng, run.seen_encounters, EncounterCatalog.ALL, run.encounter_has_gain)
		var ordinary: bool = false
		var groups: Dictionary = {}
		for id: String in cards:
			var reward: EncounterData = EncounterCatalog.find(id)
			all_seen[id] = true
			safe = safe and not groups.has(reward.candidate_group())
			groups[reward.candidate_group()] = true
			ordinary = ordinary or (not reward.is_trait and not reward.has_debuff and run.encounter_has_gain(reward))
			if reward.is_trait: safe = safe and run.seen_encounters.has(id)
		safe = safe and cards.size() == 3 and ordinary
	verify(safe and all_seen.size() == 22 and not all_seen.has("branch_harvest") and not all_seen.has("branch_ricochet"), "seeded pre-split pool exposes every eligible entry while preserving safe gains and trait reservation")
	capped(run)
	run.seen_encounters.clear()
	var before: int = run.rng.state
	verify(run.offer_encounter() and run.choices.is_empty() and run.offer_exhausted and run.can_skip_encounter(), "no safe gain opens explicit acknowledgement rather than forcing traits")
	verify(run.rng.state == before and run.seen_encounters.is_empty(), "empty offer neither rolls RNG nor consumes unseen traits")
	verify(not run.offer_encounter() and run.rng.state == before, "reopening exhausted offer cannot reroll")
	var seen: Array[String] = []
	verify(EncounterCatalog.draft(run.rng, seen, [], run.encounter_has_gain).is_empty(), "fallback cannot reintroduce capped ordinary entries")
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: seen.append(reward.id)
	run.shots_left = 99999
	var cards: Array[String] = EncounterCatalog.draft(run.rng, seen, EncounterCatalog.ALL, run.encounter_has_gain)
	verify(cards == ["second_wind"], "one eligible ordinary entry produces one real card")
	run.encounter_picks["tempered_tip"] = 333333
	run.rebuild_stats()
	cards = EncounterCatalog.draft(run.rng, seen, [], run.encounter_has_gain)
	verify(cards.size() == 2 and cards.has("second_wind") and cards.has("tempered_tip"), "two eligible entries produce two unique cards even through fallback")
	run.encounter_picks["windfall"] = 11
	run.rebuild_stats()
	cards = EncounterCatalog.draft(run.rng, seen, [], run.encounter_has_gain)
	verify(cards.size() == 3 and cards.has("windfall"), "three eligible entries restore normal three-card layout")

func _storage_and_skip() -> void:
	var path: String = "user://tests/t11a-expanded.json"
	clean(path)
	var store := SaveStore.new(path)
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	capped(run)
	run.offer_encounter()
	var random_state: int = run.rng.state
	var token: int = run.encounter_offer_id
	verify(store.write(session.to_dict()), "exhausted fixed offer is valid current data")
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(restored.run.offer_exhausted and restored.run.can_skip_encounter() and restored.run.choices.is_empty() and restored.run.rng.state == random_state, "exhausted offer restores without reroll or loss of caps")
	var before: Dictionary = restored.run.stats.to_dict()
	verify(not restored.run.skip_encounter(token + 1), "exhausted acknowledgement respects offer token")
	restored.run.suspended = true
	verify(not restored.run.skip_encounter(token), "suspended lobby cannot acknowledge an offer")
	restored.run.suspended = false
	verify(restored.run.skip_encounter(token) and not restored.run.skip_encounter(token), "acknowledgement consumes entitlement exactly once")
	verify(restored.run.stats.to_dict() == before and restored.run.shots_left == 100000 and restored.run.rng.state == random_state and restored.run.pending_encounters == 0, "acknowledgement changes no stats, draws, RNG or picks")
	verify(store.write(restored.to_dict()), "consumed exhausted offer saves normally")
	var bad: Dictionary = session.to_dict()
	bad["run"]["shots_left"] = 99999
	verify(not store.write(bad), "forged empty offer with available safe draw gain is rejected")
	bad = session.to_dict()
	bad["run"]["offer_exhausted"] = "true"
	verify(not store.write(bad), "invalid exhausted flag type is rejected")
	bad = session.to_dict()
	bad["run"]["offer_exhausted"] = false
	verify(not store.write(bad), "empty offer requires explicit exhausted state")
	# Existing v10 cards remain fixed even when the directory expands or caps apply.
	run.offer_exhausted = false
	run.choices.assign(["windfall", "rainfall", "second_wind"])
	var old: Dictionary = session.to_dict()
	old["run"].erase("offer_exhausted")
	var bytes: String = JSON.stringify({"version": 10, "payload": old}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var migrated: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v10") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v10 original bytes are archived before current replacement")
	verify(migrated.run.choices == run.choices and migrated.run.encounter_offer_id == token and migrated.run.rng.state == random_state, "old capped fixed cards and token survive expansion unchanged")
	verify(migrated.run.can_skip_encounter() and not migrated.run.choose_encounter("rainfall", token), "old no-gain cards refuse a wasted claim and allow acknowledgement")
	verify(store.migration_notice.contains("后续选择") and not store.migration_notice.contains("三倍"), "v10 upgrade notice does not claim another health rescale")
	verify(migrated.run.skip_encounter(token) and store.write(migrated.to_dict()), "old capped offer can complete and persist")
	clean(path)
	# An old offer may contain optional debuffs alongside a now-capped ordinary card.
	capped(run)
	run.offer_encounter()
	run.offer_exhausted = false
	run.choices.assign(["windfall", "unified_arrow", "critical_forging"])
	run.seen_encounters.assign(["unified_arrow", "critical_forging"])
	verify(run.can_skip_encounter() and run.skip_encounter(run.encounter_offer_id) and not run.encounter_picks.has("unified_arrow"), "old fixed debuffs remain optional when their ordinary fallback has capped")

func _boss_caps() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	capped(run)
	run.shots_left = 99999
	run.pending_encounters = 0
	run.boss_active = true
	verify(session.record_boss_defeat("boss%d" % run.boss_round, 1200, 240) and run.shots_left == 100000, "Boss victory still grants its finite supply before cap filtering")
	run.boss_active = false
	verify(run.offer_encounter() and run.reward_source()["kind"] == "boss" and run.choices.is_empty(), "Boss safe pool obeys the same effective-gain filter")
	var totals: Dictionary = run.boss_reward_totals()
	verify(totals["draws"] == 1 and run.skip_encounter(run.encounter_offer_id) and run.boss_reward_log[0]["choice"] == RunModel.NO_GAIN, "Boss acknowledgement records skipped gain while retaining actual supply")
	verify(run.boss_reward_totals() == totals and run.gold == 960 and run.shots_left == 100000, "skipping capped Boss gain does not erase or replay already credited rewards")
	var path: String = "user://tests/t11a-boss-cap.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.to_dict()) and GameSession.from_dict(store.read()).run.boss_reward_log == JSON.parse_string(JSON.stringify(run.boss_reward_log, "", true, true)), "skipped Boss record remains valid across disk continuation")
	clean(path)

func _flight(tree: SceneTree) -> void:
	var base: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
	for id: String in NEW_IDS:
		var session := GameSession.new()
		var run: RunModel = session.start_run()
		var world: ArcheryWorld = base.field(tree, session)
		world.boss_enabled = false
		world.direction = Vector2.RIGHT
		world.pull = 1
		world._release()
		for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
		var state: Dictionary = world.snapshot()
		entitle(run)
		run.offer_encounter()
		run.choices.assign(NEW_IDS)
		var next: Dictionary = run.preview_encounter(EncounterCatalog.find(id)).to_dict()
		verify(run.choose_encounter(id, run.encounter_offer_id) and world.snapshot() == state, "choosing preserves every existing projectile and reload countdown: " + id)
		world.reload_left = 0
		world.pull = 1
		world._release()
		for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
		verify(world.arrows.size() == 2 and world.arrows[1].stats.to_dict() == next and world.reload_left == run.stats.reload_seconds, "next launch samples new stats and reload duration: " + id)
		world.queue_free()
		await tree.process_frame

func _percent_revision(tree: SceneTree) -> void:
	var base: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.encounter_picks["quick_nock"] = 2
	run.rebuild_stats()
	var world: ArcheryWorld = base.field(tree, session)
	world.boss_enabled = false
	world.pull = 1
	world._release()
	world.arrows[0].set_physics_process(false)
	# Real v11 launch values remain immutable even though future build rules change.
	world.arrows[0].stats.damage = 24
	world.arrows[0].stats.reload_seconds = 0.53
	world.reload_left = 0.31
	entitle(run)
	run.offer_encounter()
	run.choices.assign(NEW_IDS)
	session.capture_checkpoint(world.snapshot())
	var old: Dictionary = session.save_payload()
	var path: String = "user://tests/t11a-percent-revision.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 11, "payload": old}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v11") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v11 bytes archived before damage-bonus revision")
	verify(loaded.run.encounter_picks["quick_nock"] == 2 and is_equal_approx(loaded.run.stats.damage, 26.4) and is_equal_approx(loaded.run.stats.reload_seconds, 0.65), "old two stacks become ten percent damage, future reload returns to base")
	verify(loaded.run.choices == run.choices and loaded.run.encounter_offer_id == run.encounter_offer_id and loaded.run.rng.state == run.rng.state, "percent replacement retains fixed offer and RNG")
	verify(loaded.world_snapshot == JSON.parse_string(JSON.stringify(old["world"], "", true, true)) and store.migration_notice.contains("每层伤害 +5%"), "old flight, countdown and documented conversion survive revision")
	var restored: ArcheryWorld = base.field(tree, loaded, loaded.world_snapshot)
	restored.boss_enabled = false
	for arrow: Arrow in restored.arrows: arrow.set_physics_process(false)
	var state: Dictionary = restored.snapshot()
	verify(loaded.run.choose_encounter("quick_nock", loaded.run.encounter_offer_id) and is_equal_approx(loaded.run.stats.damage, 27.6) and restored.snapshot() == state, "third new stack becomes fifteen percent while old arrow stays unchanged")
	loaded.capture_checkpoint(restored.snapshot())
	verify(store.write(loaded.save_payload()) and is_equal_approx(GameSession.from_dict(store.read()).run.stats.damage, 27.6), "repeated disk restore does not compound percent stacks")
	for field: ArcheryWorld in [world, restored]: field.queue_free()
	await tree.process_frame
	clean(path)

func _actual_ui(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	main.world.boss_enabled = false
	capped(main.run)
	main.run.offer_encounter()
	verify(tree.paused and main.hud.encounter_panel.choice_buttons.is_empty(), "real exhausted offer pauses on an acknowledgement panel")
	main._save_checkpoint()
	verify(not main.saves.read().is_empty(), "real exhausted panel produces a valid checkpoint")
	main._on_action("encounter_skip", main.run.encounter_offer_id)
	verify(not tree.paused and main.run.pending_encounters == 0, "actual acknowledgement route resumes the same field")
	capped(main.run)
	main.run.shots_left = 99999
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: main.run.seen_encounters.append(reward.id)
	main.run.offer_encounter()
	verify(tree.paused and main.hud.encounter_panel.choice_buttons.size() == 1 and not main.run.can_skip_encounter(), "real one-card offer remains selectable without unnecessary skip")
	main.hud.encounter_panel.choice_buttons[0].pressed.emit()
	verify(not tree.paused and main.run.shots_left == 100000, "actual draw choice grants only the remaining one draw at cap")
	capped(main.run)
	main.run.offer_encounter()
	main.run.offer_exhausted = false
	main.run.choices.assign(["windfall", "rainfall", "second_wind"])
	main._refresh()
	var disabled: bool = main.hud.encounter_panel.choice_buttons.size() == 3
	for button: Button in main.hud.encounter_panel.choice_buttons: disabled = disabled and button.disabled
	verify(disabled and main.run.can_skip_encounter(), "old fixed capped cards stay visible but disabled, with safe acknowledgement")
	main._on_action("encounter_skip", main.run.encounter_offer_id)
	main.queue_free()
	await tree.process_frame
	tree.paused = false

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v10", ".legacy-v11"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
