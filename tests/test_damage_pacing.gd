extends RefCounted
var check: Callable
func _init(assertion: Callable) -> void: check = assertion

func run_all(tree: SceneTree) -> void:
	var skill: RunSkillData = SkillCatalog.find("damage")
	var run := RunModel.new("normal", {})
	var old := RunModel.new("normal", {})
	old.balance_revision = 2
	var prices: Array[int] = [12, 18, 27, 39, 52, 67, 82, 99, 117, 137]
	var last_bonus: float = 0.0
	var last_gain: float = INF
	for rank: int in range(11):
		run.skill_levels["damage"] = rank
		old.skill_levels["damage"] = rank
		run.rebuild_stats()
		old.rebuild_stats()
		check.call(old.stats.damage == 24 + 8 * rank, "damage pacing: frozen v25 remains linear")
		if rank > 0:
			var gain: float = run.stats.damage - 24 - last_bonus
			check.call(gain > 0 and gain < last_gain, "damage pacing: positive diminishing base gains")
			last_gain = gain
		last_bonus = run.stats.damage - 24
		if rank < 10: check.call(run.skill_price(skill) == prices[rank], "damage pacing: known price ladder")
	check.call(run.stats.damage == 104 and run.stats.damage == old.stats.damage, "damage pacing: same full-rank damage ceiling")
	check.call(run.skill_price(skill) == 206 and old.skill_price(skill) == 763, "damage pacing: mastery entry price joins new base ladder")
	var previous_price: int = 0
	for rank: int in range(101):
		run.mastery_levels["damage"] = rank
		run.rebuild_stats()
		var price: int = run.skill_price(skill)
		check.call(price >= previous_price and price <= 1000000000 and is_finite(run.stats.damage), "damage pacing: bounded mastery price and stats " + str(rank))
		previous_price = price
	for other: RunSkillData in SkillCatalog.ALL:
		if other == skill: continue
		for rank: int in [0, 3, other.max_level]:
			run.skill_levels[String(other.id)] = rank
			old.skill_levels[String(other.id)] = rank
			check.call(run.skill_price(other) == old.skill_price(other), "damage pacing: other branch price unchanged")
	for picks: Dictionary in [{}, {"unified_arrow": 1}, {"critical_forging": 1, "critical_ricochet": 1}, {"heavy_draw": 1, "swarm_precision": 1}]:
		var converted := RunModel.new("normal", {"prices": 2})
		converted.encounter_picks = picks.duplicate()
		converted.skill_levels = {"damage": 2, "quantity": 3, "critical": 2}
		converted.rebuild_stats()
		converted.gold = 1000
		converted.open_skills()
		var preview: Dictionary = converted.preview_skill(skill).to_dict()
		var price: int = converted.skill_price(skill)
		check.call(price == 41 and converted.buy(skill) and converted.gold == 1000 - price and converted.gold_spending.basic == price, "damage pacing: contract rounds price once and books actual debit")
		check.call(converted.stats.to_dict() == preview, "damage pacing: converted preview matches actual purchase")
		converted.rebuild_stats()
		check.call(converted.stats.to_dict() == preview, "damage pacing: rebuild applies curve once")
	check.call(skill.additions.damage == 8 and skill.mastery_price(0) == 763 and GameCatalog.BASE_BOW.damage == 24, "damage pacing: shared resource and legacy prices stay immutable")
	await _migration_and_flight(tree)

func _migration_and_flight(tree: SceneTree) -> void:
	DirAccess.make_dir_recursive_absolute("user://tests")
	var helper: RefCounted = preload("res://tests/test_boss.gd").new(check)
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "normal", {})
	run.balance_revision = 2
	run.skill_levels = {"damage": 4, "quantity": 2}
	run.rebuild_stats()
	var world: ArcheryWorld = helper.field(tree, session)
	world.direction = Vector2.RIGHT.rotated(-0.6)
	world.pull = 1
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	var path: String = "user://tests/damage-pacing.json"
	for suffix: String in ["", ".bak", ".legacy-v25"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var bytes: String = JSON.stringify({"version": 25, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path, [])
	var migrated: Dictionary = store.read()
	check.call(not migrated.is_empty() and FileAccess.get_file_as_string(path + ".legacy-v25") == bytes, "damage pacing: original v25 bytes archived")
	var restored := GameSession.from_dict(migrated)
	var skill := SkillCatalog.find("damage")
	check.call(restored.run.balance_revision == 2 and restored.run.stats.to_dict() == run.stats.to_dict() and restored.run.skill_price(skill) == 61, "damage pacing: old run keeps stats and future prices")
	var copy: ArcheryWorld = helper.field(tree, restored, restored.world_snapshot)
	check.call(copy.arrows[0].snapshot() == world.arrows[0].snapshot(), "damage pacing: old in-flight arrow retained")
	restored.start_run(true, "normal", {})
	var current: RunModel = restored.run
	current.gold = 10000
	current.open_skills()
	check.call(current.balance_revision == 3 and current.skill_description(skill).contains("满级共 +80"), "damage pacing: only new run opts in and explains curve")
	check.call(current.buy(skill) and is_equal_approx(current.stats.damage, 55.8485736442798), "damage pacing: first upgrade crosses early target threshold")
	current.close_skills()
	var fresh: ArcheryWorld = helper.field(tree, restored)
	fresh.direction = Vector2.RIGHT.rotated(-0.6)
	fresh.pull = 1
	fresh._release()
	for arrow: Arrow in fresh.arrows: arrow.set_physics_process(false)
	var sampled: float = fresh.arrows[0].stats.damage
	current.open_skills()
	check.call(current.buy(skill) and fresh.arrows[0].stats.damage == sampled and current.stats.damage > sampled, "damage pacing: upgrades preserve launched projectile damage")
	current.close_skills()
	restored.capture_checkpoint(fresh.snapshot())
	check.call(store.write(restored.save_payload()), "damage pacing: new flight saves")
	var latest := GameSession.from_dict(store.read())
	var resumed: ArcheryWorld = helper.field(tree, latest, latest.world_snapshot)
	check.call(latest.run.balance_revision == 3 and is_equal_approx(resumed.arrows[0].stats.damage, sampled) and is_equal_approx(latest.run.stats.damage, current.stats.damage), "damage pacing: new run and sampled flight restore independently")
	for node: ArcheryWorld in [world, copy, fresh, resumed]: node.queue_free()
	await tree.process_frame
