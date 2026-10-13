extends RefCounted
## T07-B: persistent source -> linkage -> conversion -> cap, UI and live flight.

var assertion: Callable
const CONVERSIONS: Array[String] = ["unified_arrow", "critical_forging", "critical_ricochet"]

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T07-B: " + message)

func run_all(tree: SceneTree) -> void:
	_basics()
	_thresholds()
	_combinations_and_pool()
	await _live_family(tree)
	await _actual_choices(tree)
	await _old_v7(tree)

func _equip(run: RunModel, ids: Array[String]) -> void:
	for id: String in ids:
		run.encounter_picks[id] = 1
		if not run.seen_encounters.has(id): run.seen_encounters.append(id)
	var count: int = 0
	for value: Variant in run.encounter_picks.values(): count += int(value)
	run.defeated_count = maxi(run.defeated_count, count * EncounterCatalog.RULES.kills_per_reward)
	run.encounter_rewards_generated = run.defeated_count / EncounterCatalog.RULES.kills_per_reward
	run.rebuild_stats()

func _basics() -> void:
	var run := RunModel.new()
	_equip(run, ["unified_arrow"])
	verify(run.stats.arrow_count == 1 and run.stats.damage == 24 and run.stats.arrow_size == 1, "one source arrow unity causes no invented damage or size")
	run.encounter_picks["rainfall"] = 1
	run.skill_levels = {"quantity": 2}
	run.rebuild_stats()
	var stage: StatEvaluation = run.evaluate_stats(run.skill_levels, run.encounter_picks)
	verify(stage.raw.arrow_count == 4 and stage.linked.arrow_count == 4 and stage.converted.arrow_count == 1 and stage.effective.arrow_count == 1, "unity preserves original and linked count before converting to one")
	verify(is_equal_approx(run.stats.damage, 24 * pow(0.85, 2) * 4) and run.stats.arrow_size == 2, "unity multiplies damage by source count and size by square root after skill penalty")
	verify(stage.raw.damage < stage.effective.damage and stage.raw.arrow_size == 1 and GameCatalog.BASE_BOW.damage == 24, "raw and shared base never absorb conversion result")
	run.open_skills()
	run.gold = 10000
	var expected: Dictionary = run.preview_skill(SkillCatalog.find(&"quantity")).to_dict()
	var prior: float = run.stats.damage
	verify(run.buy(SkillCatalog.find(&"quantity")) and run.stats.to_dict() == expected and run.stats.arrow_count == 1 and run.stats.damage > prior and run.stats.arrow_size > 2, "later quantity upgrade still improves unity and exactly matches preview")
	verify(run.skill_comparison(SkillCatalog.find(&"quantity")).contains("原箭数") and run.skill_comparison(SkillCatalog.find(&"quantity")).contains("伤害"), "quantity card explains source arrows rather than useless one-to-one count")
	expected = run.preview_skill(SkillCatalog.find(&"damage")).to_dict()
	verify(run.buy(SkillCatalog.find(&"damage")) and run.stats.to_dict() == expected, "damage purchase also feeds sustained unity")
	expected = run.preview_skill(SkillCatalog.find(&"size")).to_dict()
	verify(run.buy(SkillCatalog.find(&"size")) and run.stats.to_dict() == expected, "size purchase feeds sustained unity")
	var next: BowStats = run.preview_encounter(EncounterCatalog.find("rainfall"))
	verify(next.arrow_count == 1 and next.damage > run.stats.damage and next.arrow_size > run.stats.arrow_size and run.encounter_picks["rainfall"] == 1, "ordinary extra-arrow preview improves unity without modifying sources")
	run = RunModel.new()
	_equip(run, ["critical_forging"])
	verify(run.stats.crit_chance == 0 and run.stats.armor_penetration == 5 and run.stats.crit_multiplier == 2, "base ten percent chance becomes five penetration and only chance is sacrificed")
	var hit: Dictionary = CombatMath.resolve_hit(run.stats, 1, false, 100, 0, 4)
	verify(not hit["critical"] and hit["pierced"] and hit["effective"] == 24, "converted chance is truly absent in combat while penetration pierces")
	run.open_skills()
	run.gold = 10000
	expected = run.preview_skill(SkillCatalog.find(&"critical")).to_dict()
	verify(run.buy(SkillCatalog.find(&"critical")) and run.stats.to_dict() == expected and run.stats.armor_penetration == 7 and run.stats.crit_chance == 0, "later crit chance still converts with floor remainder")
	verify(run.skill_comparison(SkillCatalog.find(&"critical")).contains("原暴击") and run.skill_comparison(SkillCatalog.find(&"critical")).contains("穿甲"), "critical skill comparison explains converted output")
	run = RunModel.new()
	_equip(run, ["critical_ricochet"])
	verify(run.stats.bounces == 5 and run.stats.crit_multiplier == 1 and run.stats.crit_chance == 0.1, "200 percent multiplier converts only extra 100 percent into exactly five bounces")
	hit = CombatMath.resolve_hit(run.stats, 1, false, 100, 0)
	verify(hit["critical"] and hit["effective"] == 24, "converted crit retains critical event but grants no extra damage")
	run.open_skills()
	run.gold = 10000
	expected = run.preview_skill(SkillCatalog.find(&"critical")).to_dict()
	verify(run.buy(SkillCatalog.find(&"critical")) and run.stats.to_dict() == expected and run.stats.bounces == 6 and run.stats.crit_multiplier == 1, "later extra crit damage also converts without restoring multiplier")
	var original: Dictionary = run.to_dict()
	for index: int in range(40): run.rebuild_stats()
	verify(run.to_dict() == original and run.stats.to_dict() == expected, "rebuild does not erase source crit, compound bounces or alter rewards")
	verify(RunModel.from_dict(original).stats.to_dict() == expected, "loaded ranks and picks reconstruct sustained conversion")

func _thresholds() -> void:
	var run := RunModel.new()
	var cases: Array = [[0.0, 0], [0.019, 0], [0.02, 1], [0.03999, 1], [0.04, 2], [0.1, 5], [0.3, 15], [0.58, 29], [1.0, 50], [1.3, 50]]
	for value: Array in cases:
		var raw := BowStats.new()
		raw.crit_chance = value[0]
		raw.armor_penetration = 3
		var evaluated: StatEvaluation = run._evaluate_raw(raw, {"critical_forging": 1})
		verify(evaluated.converted_penetration == value[1] and evaluated.effective.armor_penetration == 3 + int(value[1]) and evaluated.effective.crit_chance == 0 and raw.crit_chance == value[0], "chance threshold %.5f converts without source mutation" % float(value[0]))
	cases = [[1.0, 0], [1.1999, 0], [1.2, 1], [1.4, 2], [1.6, 3], [2.0, 5], [2.2, 6], [2.25, 6], [10.0, 45], [12.0, 45]]
	for value: Array in cases:
		var raw := BowStats.new()
		raw.crit_multiplier = value[0]
		raw.bounces = 2
		var evaluated: StatEvaluation = run._evaluate_raw(raw, {"critical_ricochet": 1})
		verify(evaluated.converted_bounces == value[1] and evaluated.effective.bounces == mini(2 + int(value[1]), 32) and evaluated.effective.crit_multiplier == 1 and raw.crit_multiplier == value[0], "extra damage threshold %.4f converts after removing baseline" % float(value[0]))
	var giant := BowStats.new()
	giant.arrow_count = 100000
	giant.arrow_size = 6
	giant.damage = 1000000
	giant.crit_chance = 0.9
	giant.crit_multiplier = 10
	giant.bounces = 6
	var extreme: StatEvaluation = run._evaluate_raw(giant, {"unified_arrow": 1, "swarm_precision": 1, "critical_forging": 1, "critical_ricochet": 1})
	verify(extreme.source_arrows == 32 and extreme.crit_source == 1 and extreme.converted_penetration == 50, "source arrow and chance caps prevent unbounded conversion")
	verify(extreme.effective.arrow_count == 1 and extreme.effective.arrow_size == 6 and extreme.effective.damage == 1000000 and extreme.effective.bounces == 32, "post-conversion limits bound damage, size and bounce outputs")
	verify(extreme.linked.crit_chance > 1 and extreme.raw.arrow_count == 100000 and extreme.converted.bounces == 51, "trace keeps raw and pre-cap intermediate values for explanation")

func _combinations_and_pool() -> void:
	var run := RunModel.new()
	run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1, "ricochet": 1}
	run.encounter_picks["rainfall"] = 1
	_equip(run, ["swarm_precision", "unified_arrow", "critical_forging", "critical_ricochet", "piercing_split", "ricochet_haste"])
	var evaluated: StatEvaluation = run.evaluate_stats(run.skill_levels, run.encounter_picks)
	verify(evaluated.raw.arrow_count == 4 and is_equal_approx(evaluated.raw.crit_chance, 0.2) and is_equal_approx(evaluated.linked.crit_chance, 0.26), "arrow crit linkage reads original four arrows before unity")
	verify(run.stats.arrow_count == 1 and run.stats.crit_chance == 0 and run.stats.crit_multiplier == 1 and run.stats.armor_penetration == 15 and run.stats.bounces == 8, "all six traits coexist in fixed order with independent conversions")
	var expected: Dictionary = run.stats.to_dict()
	var source_state: Dictionary = run.to_dict()
	var reverse := RunModel.new()
	reverse.skill_levels = run.skill_levels.duplicate()
	var keys: Array = run.encounter_picks.keys()
	keys.reverse()
	for key: String in keys: reverse.encounter_picks[key] = run.encounter_picks[key]
	reverse.rebuild_stats()
	verify(reverse.stats.to_dict() == expected, "selection insertion order cannot change linkage or conversion order")
	for index: int in range(40): run.rebuild_stats()
	verify(run.to_dict() == source_state and run.stats.to_dict() == expected, "combined repeated evaluation leaves raw sources and active build unchanged")
	var tooltip: String = "\n".join(run.stat_explanations(evaluated))
	verify(tooltip.contains("转化来源 4") and tooltip.contains("联动 6.0%") and tooltip.contains("转换 13") and tooltip.contains("转换 7"), "trace explains unity, linked chance, armor and extra damage conversion")
	var after: BowStats = run.preview_encounter(EncounterCatalog.find("rainfall"))
	verify(after.arrow_count == 1 and after.damage > run.stats.damage and after.arrow_size > run.stats.arrow_size and after.armor_penetration == 16, "ordinary count improves unity and converts added linked chance to penetration")
	var comparison: String = run.encounter_comparison(EncounterCatalog.find("rainfall"))
	verify(comparison.contains("发射仍为 1") and comparison.contains("穿甲 15 → 16"), "ordinary count card previews every converted benefit despite effective count one")
	verify(run.encounter_description(EncounterCatalog.find("rainfall")).contains("原箭数 +1") and run.encounter_description(EncounterCatalog.find("rainfall")).contains("主箭仍为 1"), "ordinary card explains source count under unity instead of promising an extra emitted arrow")
	var restored: RunModel = RunModel.from_dict(source_state)
	verify(restored.stats.to_dict() == expected and restored.projectile_effects().split_count == 2 and restored.projectile_effects().bounce_multiplier == 1.25, "combined conversion restore retains independent projectile effects")
	var fresh := RunModel.new()
	verify(fresh.stats.arrow_count == 1 and fresh.stats.damage == 24 and fresh.stats.crit_chance == 0.1 and fresh.stats.crit_multiplier == 2 and fresh.stats.bounces == 0 and fresh.stats.armor_penetration == 0, "new run clears every conversion")
	var random := RandomNumberGenerator.new()
	random.seed = 123456
	var seen: Array[String] = []
	var safe_all: bool = true
	var repeated: bool = false
	var groups_all: bool = true
	for iteration: int in range(30):
		var before: Array[String] = seen.duplicate()
		var safe: bool = false
		var groups: Dictionary = {}
		for id: String in EncounterCatalog.draft(random, seen, EncounterCatalog.ALL):
			var reward: EncounterData = EncounterCatalog.find(id)
			groups_all = groups_all and not groups.has(reward.candidate_group())
			groups[reward.candidate_group()] = true
			if reward.is_trait: repeated = repeated or before.has(id)
			elif not reward.has_debuff: safe = true
		safe_all = safe_all and safe
	verify(safe_all and groups_all and not repeated and seen.size() == 18, "expanded trait pool including five debuffs never forces a debuff or redisplays a trait")
	for id: String in CONVERSIONS:
		var reward: EncounterData = EncounterCatalog.find(id)
		verify(reward.is_trait and reward.has_debuff and not reward.trait_key.is_empty(), "conversion is marked unique and costly: " + id)

func _live_family(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1, "ricochet": 1}
	run.encounter_picks["rainfall"] = 1
	_equip(run, ["unified_arrow", "critical_forging", "critical_ricochet", "swarm_precision", "piercing_split", "ricochet_haste"])
	run.shots_left = 1
	run.stats.gravity = 0
	var world := ArcheryWorld.new()
	world.run = run
	world.shot_settled.connect(session.settle_shot)
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.build_field()
	world.targets[0].anchor = Vector2(180, 238)
	world.targets[0].position = Vector2(180, 238)
	world.targets[0].hp = 1
	world.targets[0].armor = 14
	world.targets[1].hp = 10000
	world.targets[1].max_hp = 10000
	world.targets[2].hp = 10000
	world.targets[2].max_hp = 10000
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	var parent: Arrow = world.arrows[0]
	parent.set_physics_process(false)
	verify(world.arrows.size() == 1 and run.shots_left == 0 and parent.stats.arrow_count == 1 and parent.stats.crit_chance == 0 and parent.stats.crit_multiplier == 1 and parent.remaining_bounces == 8, "actual launch consumes one final draw with converted snapshot and bounce budget")
	parent._physics_process(0.2)
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	verify(world.arrows.size() == 3 and parent.hit_slots == [0] and parent.stats.armor_penetration == 15, "converted penetration exceeds armor and unity still permits split after target exit")
	var child: Arrow = world.arrows[1]
	verify(child.stats.damage == parent.stats.damage * 0.5 and child.stats.arrow_size == 2 and child.stats.crit_chance == 0 and child.stats.crit_multiplier == 1 and child.remaining_bounces == 8, "children inherit half converted damage, enlarged head and converted crit/bounces")
	verify(world.pending_volleys["1"].size() == 1 and run.defeated_count == 70 and session.profile.total_score == 0, "child generation does not prematurely pay the mother's kill")
	world._settle_shots()
	verify(not run.is_finished() and run.last_settled_shot == -1, "final converted draw waits for its full family")
	var state: Dictionary = world.snapshot()
	session.capture_checkpoint(state)
	var path: String = "user://tests/t07b-flight.json"
	_clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "v7 persists all conversions and family without new schema")
	var disk: GameSession = GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = disk.run
	copy.shot_settled.connect(disk.settle_shot)
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(disk.world_snapshot)
	for arrow: Arrow in copy.arrows: arrow.set_physics_process(false)
	verify(copy.snapshot() == state and disk.run.stats.armor_penetration == 15 and disk.run.stats.bounces == 8 and disk.run.stats.arrow_count == 1, "disk restores converted build and exact in-flight family")
	var launch: Dictionary = parent.stats.to_dict()
	run.open_skills()
	run.gold = 10000
	verify(run.buy(SkillCatalog.find(&"critical")) and run.stats.armor_penetration > parent.stats.armor_penetration and run.stats.bounces > parent.stats.bounces and parent.stats.to_dict() == launch and child.stats.crit_chance == 0, "in-flight upgrade updates future conversions without mutating existing parent or children")
	run.close_skills()
	# Each world continues from the identical snapshot; child can use converted bounces and haste.
	for field: ArcheryWorld in [world, copy]:
		var live: Arrow = field.arrows[1]
		live.position = Vector2(620, 180)
		live.velocity = Vector2(500, 0)
		live._physics_process(0.05)
		verify(live.velocity == Vector2(-625, 0) and live.remaining_bounces == 7, "child uses converted bounce budget and retained speed trait after restore")
		for arrow: Arrow in field.arrows.duplicate(): arrow._finish()
		field._settle_shots()
		field.run.settle_volley()
		if field.run.phase == RunModel.Phase.SUPPLY: field.run.decline_supply(field.run.supply_offer_id)
	verify(run.defeated_count == 71 and disk.run.defeated_count == 71 and session.profile.total_score == 40 and disk.profile.total_score == 40 and run.is_finished() and disk.run.is_finished(), "converted family kill pays once then final draw exhausts after descendants")
	world.queue_free()
	copy.queue_free()
	await tree.process_frame
	_clean(path)

func _actual_choices(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	for id: String in CONVERSIONS:
		main._new_run()
		main.world.set_physics_process(false)
		main.run.skill_levels["quantity"] = 2
		main.run.rebuild_stats()
		main.world.pull = 1
		main.world._release()
		for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
		var old: Arrow = main.world.arrows[0]
		var old_snapshot: Dictionary = old.snapshot()
		for index: int in range(10): main.session.record_defeat("choice-%d" % index, 0, 0)
		main.run.offer_encounter()
		main.run.choices.assign(["windfall", id, "second_wind"])
		if not main.run.seen_encounters.has(id): main.run.seen_encounters.append(id)
		main._refresh()
		var expected: Dictionary = main.run.preview_encounter(EncounterCatalog.find(id)).to_dict()
		for button: Button in main.hud.encounter_panel.choice_buttons:
			if button.name == id: button.pressed.emit(); break
		verify(main.run.encounter_picks.get(id) == 1 and not tree.paused and main.run.stats.to_dict() == expected and old.snapshot() == old_snapshot, "real conversion card applies exact preview while old flight stays unchanged: " + id)
		var payload: Dictionary = main.saves.read()
		verify(payload["run"]["encounter_picks"].get(id) == 1 and payload["world"]["arrows"].size() == 3, "choice saves conversion and original multi-arrow flight together: " + id)
		main._navigate("hub")
		payload = main.saves.read()
		var loaded: GameSession = GameSession.from_dict(payload)
		verify(loaded.run.stats.to_dict() == expected and loaded.world_snapshot["arrows"][0]["stats"] == JSON.parse_string(JSON.stringify(old.stats.to_dict(), "", true, true)), "lobby and disk restore future conversion without retroactive old arrow change: " + id)
		main._enter_range()
		main.world.reload_left = 0
		main.world.pull = 1
		var count: int = main.world.arrows.size()
		main.world._release()
		for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
		verify(main.world.arrows.size() == count + int(expected["arrow_count"]) and main.world.arrows[count].stats.to_dict() == expected, "actual next launch receives converted snapshot: " + id)
		main.run.gold = 10000
		main._on_action("skills", null)
		var critical: Button = _find_button(main.hud.content, "暴击")
		if critical != null: critical.pressed.emit()
		verify(main.run.skill_levels.get("critical") == 1 and main.run.stats.to_dict() == main.run.evaluate_stats(main.run.skill_levels, main.run.encounter_picks).effective.to_dict(), "real skill purchase recomputes active conversion: " + id)
		main._on_action("continue", null)
		main._on_action("encounters", null)
		verify(tree.paused and main.hud.encounter_panel.find_child("EncounterHistory", true, false) != null and _all_text(main.hud.encounter_panel).contains("原始 → 联动"), "actual history exposes conversion stages: " + id)
		main._on_action("encounter_close", null)
		verify(not tree.paused, "closing conversion history resumes world: " + id)
	main.queue_free()
	await tree.process_frame

func _find_button(parent: Node, prefix: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and child.text.begins_with(prefix): return child
		var nested: Button = _find_button(child, prefix)
		if nested != null: return nested
	return null

func _all_text(parent: Node) -> String:
	var result: String = parent.text if parent is Label else ""
	for child: Node in parent.get_children(): result += _all_text(child)
	return result

func _old_v7(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: run.seen_encounters.append(reward.id)
	for index: int in range(10): session.record_defeat("old-%d" % index, 40, 8)
	run.offer_encounter()
	run.seen_encounters.clear()
	var world := ArcheryWorld.new()
	world.run = run
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.build_field()
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t07b-old-v7.json"
	_clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "pre-conversion v7 ordinary offer remains valid")
	var original: String = FileAccess.get_file_as_string(path)
	var disk: GameSession = GameSession.from_dict(store.read())
	verify(store.migration_notice.is_empty() and FileAccess.get_file_as_string(path) == original, "reading current schema preserves conversion envelope bytes")
	verify(disk.run.choices == run.choices and disk.run.rng.state == run.rng.state and disk.run.pending_encounters == 1 and disk.run.stats.to_dict() == run.stats.to_dict(), "expanded pool keeps old fixed choices, RNG, reward queue and unconverted stats")
	var bad: Dictionary = disk.to_dict()
	bad["run"]["choices"] = ["unified_arrow", "critical_forging", "critical_ricochet"]
	bad["run"]["seen_encounters"] = CONVERSIONS.duplicate()
	verify(not store.write(bad), "all-debuff offer cannot overwrite old safe offer")
	world.queue_free()
	await tree.process_frame
	_clean(path)

func _clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
