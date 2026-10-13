extends RefCounted

var assertion: Callable
var fixture: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	fixture = preload("res://tests/test_traits.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T12-A: " + message)

func equip(run: RunModel, ids: Array[String]) -> void:
	fixture._equip(run, ids)

func full(run: RunModel) -> void:
	for skill: RunSkillData in SkillCatalog.ALL: run.skill_levels[String(skill.id)] = skill.max_level
	run.rebuild_stats()

func run_all(tree: SceneTree) -> void:
	_curves_and_purchase()
	_quantity()
	_caps_and_conversions()
	await _flight(tree)
	await _migration(tree)
	_invalid()

func _curves_and_purchase() -> void:
	var starts: Array[int] = [150, 282, 763, 889, 177, 282]
	var first: Array[Dictionary] = [
		{"damage": 24 * pow(0.87, 6) * 1.01, "arrow_count": 7},
		{"crit_chance": 0.52, "crit_multiplier": 4.2, "damage": 24.24},
		{"damage": 119.48}, {"armor_penetration": 23, "damage": 24.24},
		{"bounces": 7, "armor_penetration": 2, "launch_speed": 496},
		{"arrow_size": 3.95, "launch_speed": 498},
	]
	for index: int in range(SkillCatalog.ALL.size()):
		var skill: RunSkillData = SkillCatalog.ALL[index]
		var run := RunModel.new()
		run.skill_levels[String(skill.id)] = skill.max_level
		run.rebuild_stats()
		run.gold = 1000000000
		verify(skill.mastery_price(0) == starts[index] and skill.mastery_price(0) > skill.price(skill.max_level - 1), "first mastery is dearer than final base rank: " + String(skill.id))
		verify(skill.mastery_price(1) > skill.mastery_price(0) and skill.mastery_price(100) <= 1000000000 and skill.mastery_price(99) <= skill.mastery_price(100), "mastery price grows safely to bounded cap: " + String(skill.id))
		verify(skill.mastery_weight(1) == 1 and skill.mastery_weight(3) - skill.mastery_weight(2) < skill.mastery_weight(2) - skill.mastery_weight(1), "marginal weighted benefit diminishes: " + String(skill.id))
		verify(not run.buy(skill) and run.mastery_levels.is_empty(), "playing cannot purchase mastery: " + String(skill.id))
		run.open_skills()
		var wallet: int = run.gold
		var preview: Dictionary = run.preview_skill(skill).to_dict()
		verify(run.skill_is_mastery(skill) and run.skill_rank(skill) == 0 and run.buy(skill) and run.gold == wallet - starts[index], "base maximum opens and charges first mastery once: " + String(skill.id))
		verify(run.stats.to_dict() == preview and run.skill_levels[String(skill.id)] == skill.max_level and run.mastery_levels[String(skill.id)] == 1 and run.mastery_unlocks.has(String(skill.id)), "preview and purchase use separate immutable base ranks: " + String(skill.id))
		var correct: bool = true
		for field: String in first[index]: correct = correct and is_equal_approx(float(run.stats.get(field)), float(first[index][field]))
		verify(correct, "first mastery numeric effects: " + String(skill.id))
		preview = run.stats.to_dict()
		for repeat: int in range(20): run.rebuild_stats()
		verify(run.stats.to_dict() == preview and GameCatalog.BASE_BOW.damage == 24 and RunModel.from_dict(run.to_dict()).stats.to_dict() == preview, "source rebuild and roundtrip do not compound: " + String(skill.id))
		run.suspended = true
		wallet = run.gold
		verify(not run.buy(skill) and run.gold == wallet, "lobby rejects mastery purchases: " + String(skill.id))
		run.suspended = false
		run.gold = run.skill_price(skill) - 1
		verify(not run.buy(skill) and run.mastery_levels[String(skill.id)] == 1, "insufficient coins cannot increase mastery: " + String(skill.id))
	var fresh := RunModel.new()
	fresh.gold = 10000
	fresh.open_skills()
	verify(not fresh.skill_is_mastery(SkillCatalog.find(&"damage")) and fresh.buy(SkillCatalog.find(&"damage")) and fresh.skill_levels["damage"] == 1 and fresh.mastery_levels.is_empty(), "uncapped ordinary base purchase remains unchanged")
	verify(not fresh.can_buy(SkillCatalog.ALL[0].duplicate() as RunSkillData), "uncatalogued duplicate resource cannot purchase")
	var precision := RunModel.new()
	precision.skill_levels["size"] = 8
	equip(precision, ["broad_precision"])
	precision.open_skills()
	verify(precision.skill_comparison(SkillCatalog.find(&"size")).contains("靶心增伤") and is_equal_approx(precision.preview_skill(SkillCatalog.find(&"size")).collision_radius(), 7.9), "mastery size preview includes true head radius and conditional center damage")

func _quantity() -> void:
	var run := RunModel.new()
	run.skill_levels["quantity"] = 6
	run.rebuild_stats()
	run.open_skills()
	var skill: RunSkillData = SkillCatalog.find(&"quantity")
	var monotonic: bool = true
	var first_six: bool = true
	for rank: int in range(40):
		run.gold = 1000000000
		var total: float = run.stats.damage * run.stats.arrow_count
		var single: float = run.stats.damage
		monotonic = run.buy(skill) and run.stats.damage * run.stats.arrow_count > total and run.stats.damage > single and monotonic
		if rank < 6: first_six = first_six and run.stats.arrow_count == 7
	verify(monotonic and first_six, "forty quantity mastery ranks never reduce volley or single damage; first six improve efficiency before adding arrows")
	verify(run.stats.arrow_count == 32 and run.skill_levels["quantity"] == 6 and run.skill_comparison(skill).contains("伤害"), "quantity source cap retains damage benefit and truthful preview")
	var unity := RunModel.new()
	unity.skill_levels["quantity"] = 6
	equip(unity, ["unified_arrow", "swarm_precision", "critical_forging"])
	unity.mastery_unlocks.assign(["quantity"])
	unity.mastery_levels["quantity"] = 6
	unity.rebuild_stats()
	unity.open_skills()
	unity.gold = 1000000000
	var previous: BowStats = unity.stats.duplicate() as BowStats
	verify(unity.buy(skill) and unity.stats.arrow_count == 1 and unity.stats.damage > previous.damage and unity.stats.armor_penetration > previous.armor_penetration and unity.stats.arrow_size > previous.arrow_size, "seventh quantity mastery adds source arrows without penalty and feeds unity/linkage/conversion")

func _caps_and_conversions() -> void:
	var saturated := RunModel.new()
	saturated.skill_levels["critical"] = 8
	saturated.encounter_picks["rainfall"] = 100
	equip(saturated, ["swarm_precision"])
	saturated.open_skills()
	saturated.gold = 1000000
	var saturated_damage: float = saturated.stats.damage
	verify(saturated.stats.crit_chance == 1 and saturated.buy(SkillCatalog.find(&"critical")) and saturated.stats.crit_chance == 1 and saturated.stats.crit_multiplier > 4 and saturated.stats.damage > saturated_damage, "one hundred percent crit still gains mastery critical damage and damage benefit")
	var run := RunModel.new()
	full(run)
	equip(run, ["unified_arrow", "swarm_precision", "critical_forging", "critical_ricochet", "slender_gale", "heavy_draw", "broad_precision"])
	run.open_skills()
	var old: BowStats = run.stats.duplicate() as BowStats
	run.gold = 1000000000
	var crit: RunSkillData = SkillCatalog.find(&"critical")
	var comparison: String = run.skill_comparison(crit)
	var preview: Dictionary = run.preview_skill(crit).to_dict()
	verify(run.buy(crit) and run.stats.to_dict() == preview and run.stats.crit_chance == 0 and run.stats.crit_multiplier == 1 and run.stats.armor_penetration > old.armor_penetration and run.stats.bounces > old.bounces, "both critical conversions consume new mastery sources without restoring removed crit")
	verify(comparison.contains("穿甲") and comparison.contains("反弹"), "critical mastery card shows actual converted outputs for the purchased rank")
	var raw: BowStats = run.calculate_raw_stats(run.skill_levels, run.encounter_picks)
	var expected: float = (104 * pow(0.85, 6) * 1.01) * 1.4 * 7
	verify(is_equal_approx(run.stats.damage, expected) and is_equal_approx(raw.arrow_size, 3.8 * 0.7) and is_equal_approx(raw.reload_seconds, 0.65 * 1.35), "mastery damage percentage precedes quantity, cost factors and unity exactly once")
	var before_levels: Dictionary = run.mastery_levels.duplicate()
	var explained: Array[String] = run.stat_explanations(run.preview_skill_evaluation(crit))
	verify("\n".join(explained).contains("暴击精通 2/100") and run.mastery_levels == before_levels, "tooltip explains future mastery rank without mutating sources")
	var capped := RunModel.new()
	capped.skill_levels = {"quantity": 6, "size": 1, "critical": 8, "ricochet": 6}
	capped.encounter_picks["rainfall"] = 100
	equip(capped, ["unified_arrow", "critical_ricochet"])
	capped.open_skills()
	capped.gold = 1000000000
	var size: RunSkillData = SkillCatalog.find(&"size")
	var coins: int = capped.gold
	var speed: float = capped.stats.launch_speed
	verify(capped.stats.arrow_size == 6 and capped.skill_is_mastery(size) and capped.buy(size) and capped.skill_levels["size"] == 1 and capped.stats.launch_speed > speed and capped.gold == coins - size.mastery_price(0), "already capped basic size opens actual speed mastery instead of charging empty base ranks")
	verify(capped.mastery_unlocks.has("size") and RunModel.from_dict(capped.to_dict()).mastery_unlocks.has("size"), "early cap unlock is permanent for this run and survives restore")
	capped.encounter_picks["rainfall"] = 25
	capped.encounter_picks["slender_gale"] = 1
	capped.rebuild_stats()
	verify(capped.skill_is_mastery(size), "later size conversion changes cannot relock purchased mastery")
	capped.encounter_picks["steady_power"] = 1000000
	capped.skill_levels["damage"] = 10
	capped.rebuild_stats()
	var power: RunSkillData = SkillCatalog.find(&"damage")
	coins = capped.gold
	verify(not capped.skill_has_gain(power) and not capped.buy(power) and capped.gold == coins and not capped.mastery_levels.has("damage"), "fully capped damage purchase has no benefit and never charges coins")
	var maximum := RunModel.new()
	full(maximum)
	maximum.open_skills()
	maximum.gold = 1000000000
	for skill: RunSkillData in SkillCatalog.ALL:
		maximum.mastery_levels[String(skill.id)] = skill.mastery_max_level
		maximum.mastery_unlocks.append(String(skill.id))
	maximum.rebuild_stats()
	var stable: Dictionary = maximum.stats.to_dict()
	var all_blocked: bool = true
	for skill: RunSkillData in SkillCatalog.ALL: all_blocked = not maximum.buy(skill) and maximum.preview_skill(skill).to_dict() == stable and all_blocked
	verify(all_blocked and maximum.gold == 1000000000 and maximum.stats.arrow_count == 32 and maximum.stats.bounces == 32 and maximum.stats.arrow_size == 6, "all six bounded mastery maxima refuse further purchase and retain safety caps")
	verify(RunModel.new().mastery_levels.is_empty() and RunModel.new().mastery_unlocks.is_empty(), "new run clears mastery and cap unlocks")

func _flight(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	full(run)
	equip(run, ["piercing_split", "branch_harvest", "branch_ricochet", "charged_breach", "bullseye_wave"])
	var world: ArcheryWorld = fixture._world(tree, session)
	world.set_process(false)
	world.reload_left = 0.31
	var parent: Arrow = fixture._primary(world, Vector2(160, 150), Vector2(500, 0))
	var frozen: Dictionary = parent.snapshot()
	run.open_skills()
	for skill: RunSkillData in SkillCatalog.ALL:
		run.gold = 1000000000
		verify(run.buy(skill) and parent.snapshot() == frozen and world.reload_left == 0.31, "mastery purchase preserves old mother, effects and current reload: " + String(skill.id))
	run.close_skills()
	parent._physics_process(0.13)
	fixture._freeze(world)
	var child_effects: Dictionary = parent.effects.to_dict()
	child_effects["split_count"] = 0
	verify(world.arrows.size() == 3 and world.arrows[1].stats.damage == float(frozen["stats"]["damage"]) * 0.5 and world.arrows[1].remaining_bounces == int(frozen["remaining_bounces"]) + 2 and world.arrows[1].effects.to_dict() == child_effects, "later real split inherits pre-purchase stats, remaining budget and frozen child effects except disabling recursion")
	world.reload_left = 0
	world.direction = Vector2.RIGHT
	world.pull = 1
	var size: int = world.arrows.size()
	world._release()
	fixture._freeze(world)
	verify(world.arrows.size() == size + run.stats.arrow_count and world.arrows[size].stats.to_dict() == run.stats.to_dict() and is_equal_approx(world.reload_left, run.stats.reload_seconds) and run.shots_left == 8, "next real release samples mastery and still spends one draw for entire volley")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t12a-family.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "mastery and mixed old/new arrow families commit atomically")
	var loaded := GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.set_process(false)
	copy.build_field(loaded.world_snapshot)
	fixture._freeze(copy)
	verify(same_flight(copy.snapshot(), world.snapshot()) and loaded.run.mastery_levels == run.mastery_levels and loaded.run.stats.to_dict() == run.stats.to_dict() and loaded.run.rng.state == run.rng.state, "disk continues old/new families within one-ULP size serialization; derived mastery stats and RNG exact")
	for field: ArcheryWorld in [world, copy]:
		for arrow: Arrow in field.arrows.duplicate(): arrow._physics_process(0.01)
	fixture._freeze(world)
	fixture._freeze(copy)
	verify(same_flight(copy.snapshot(), world.snapshot()) and loaded.run.rng.state == run.rng.state, "resumed mastery simulation and subsequent RNG remain deterministic")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _migration(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	full(run)
	equip(run, ["piercing_split", "branch_harvest", "branch_ricochet", "critical_flow", "bullseye_wave"])
	var world: ArcheryWorld = fixture._world(tree, session)
	world.set_process(false)
	var parent: Arrow = fixture._primary(world, Vector2(160, 150), Vector2(500, 0))
	parent._physics_process(0.13)
	fixture._freeze(world)
	world.reload_left = 0.31
	var offers: RefCounted = preload("res://tests/test_encounter_expansion.gd").new(assertion)
	offers.entitle(run)
	run.offer_encounter()
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	for key: String in ["trait_schema", "trait_levels", "mastery_schema", "mastery_levels", "mastery_unlocks"]: payload["run"].erase(key)
	var path: String = "user://tests/t12a-v15.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 15, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v15") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v15 bytes archived before migrating current version")
	verify(loaded.run.mastery_levels.is_empty() and loaded.run.mastery_unlocks.is_empty() and loaded.run.skill_levels == run.skill_levels and loaded.run.stats.to_dict() == run.stats.to_dict(), "old basic ranks and compound stats unchanged, mastery starts at zero")
	verify(loaded.world_snapshot == JSON.parse_string(bytes)["payload"]["world"] and loaded.world_snapshot["reload_left"] == 0.31 and loaded.run.choices == run.choices and loaded.run.encounter_offer_id == run.encounter_offer_id and loaded.run.rng.state == run.rng.state, "v15 serialized mother/children/effects/pending premiums and fixed choices/token/RNG/timing preserved")
	verify(not store.read().is_empty() and store.migration_notice.is_empty(), "repeat current read does not migrate or award again")
	world.queue_free()
	await tree.process_frame
	clean(path)

func _invalid() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	full(run)
	run.open_skills()
	run.gold = 10000
	run.buy(SkillCatalog.find(&"damage"))
	var payload: Dictionary = session.to_dict()
	var path: String = "user://tests/t12a-invalid.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(payload), "valid mastery transaction saves")
	var good: String = FileAccess.get_file_as_string(path)
	for mutation: int in range(12):
		var bad: Dictionary = payload.duplicate(true)
		match mutation:
			0: bad["run"].erase("mastery_schema")
			1: bad["run"]["mastery_levels"]["damage"] = 1.5
			2: bad["run"]["mastery_levels"]["damage"] = 101
			3: bad["run"]["mastery_levels"]["damage"] = -1
			4: bad["run"]["mastery_levels"]["damage"] = NAN
			5: bad["run"]["mastery_unlocks"] = []
			6: bad["run"]["mastery_unlocks"] = ["damage", "damage"]
			7: bad["run"]["mastery_levels"]["unknown"] = 1
			8: bad["run"]["skill_levels"]["quantity"] = 7
			9: bad["run"]["mastery_unlocks"].append("quantity")
			10: bad["run"]["skill_schema"] = 2.5
			11: bad["run"].erase("mastery_levels")
		verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "invalid mastery cannot overwrite good transaction: %d" % mutation)
	var recovered := GameSession.from_dict(store.read())
	verify(recovered.run.mastery_levels["damage"] == 1 and recovered.run.stats.to_dict() == run.stats.to_dict(), "rejected writes preserve actual purchased mastery")
	clean(path)

func clean(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".legacy-v15"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func same_flight(a: Dictionary, b: Dictionary) -> bool:
	# Godot JSON turns 3.8+0.15 into 3.95 by one ULP. Every other field is exact.
	if a["arrows"].size() != b["arrows"].size(): return false
	for index: int in range(a["arrows"].size()):
		if absf(float(a["arrows"][index]["stats"]["arrow_size"]) - float(b["arrows"][index]["stats"]["arrow_size"])) > 1.0e-12: return false
		a["arrows"][index]["stats"]["arrow_size"] = 0.0
		b["arrows"][index]["stats"]["arrow_size"] = 0.0
	return a == b
