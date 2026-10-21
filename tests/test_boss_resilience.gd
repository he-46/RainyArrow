extends RefCounted
var check: Callable
func _init(assertion: Callable) -> void: check = assertion

func run_all(tree: SceneTree) -> void:
	var threshold: float = 576.0
	check.call(BossRules.resilient_damage(0, 400, threshold) == 400, "resilience: low damage remains unchanged")
	check.call(is_equal_approx(BossRules.resilient_damage(0, threshold, threshold), threshold), "resilience: threshold continuous")
	var previous: float = 0
	for total: float in [1.0, 575.9, 576.0, 576.1, 1000.0, 5000.0, 1000000.0, 1.0e16]:
		var whole: float = BossRules.resilient_damage(0, total, threshold)
		check.call(is_finite(whole) and whole > previous and whole <= total, "resilience: finite monotonic total " + str(total))
		previous = whole
		for count: int in [2, 7, 32, 96]:
			var combined: float = 0
			for i: int in range(count): combined += BossRules.resilient_damage(total * i / count, total / count, threshold)
			check.call(is_equal_approx(combined, whole), "resilience: main/child/area fragmentation preserves budget " + str(count))
	check.call(BossRules.resilient_damage(1000, 100, threshold) < BossRules.resilient_damage(0, 100, threshold), "resilience: a new draw resets marginal reduction")
	check.call(BossRules.resilient_damage(0, 1000000, threshold) > 2880, "resilience: no hard invulnerability or mandatory draw gate")
	var boss := ArcheryBoss.new()
	boss.configure_boss(RunModel.BOSS_RULES, 1, {"boss_impact_revision": 1})
	tree.root.add_child(boss)
	var bow := BowStats.new()
	bow.damage = 400
	bow.crit_chance = 0
	bow.armor_penetration = 100
	var body: Vector2 = boss.global_position + Vector2(0, 40)
	var hit: Dictionary = boss.receive_contact(bow, 1, body, 1, "body", 1)
	check.call(hit.effective == 400 and hit.pierced, "resilience: armor penetration keeps original strict comparison")
	var before: Dictionary = boss.volley_pressure.duplicate()
	boss.receive_contact(bow, 1, body, 1, "shield", 1)
	check.call(boss.volley_pressure == before, "resilience: shield consumes no damage budget")
	hit = boss.receive_area(400, 100, 1)
	check.call(is_equal_approx(400 + float(hit.effective), BossRules.resilient_damage(0, 800, threshold)), "resilience: area shares the same draw budget")
	hit = boss.receive_contact(bow, 1, body, 1, "body", 2)
	check.call(hit.effective == 400 and boss.volley_pressure.size() == 2, "resilience: overlapping draws have independent budgets")
	var saved_hp: float = boss.hp
	boss.tick(10, 10)
	check.call(boss.hp == saved_hp and boss.volley_pressure.size() == 2, "resilience: waiting does not reset budgets")
	boss.queue_free()
	await tree.process_frame
	for revision: int in [1, 2]: await _disk_roundtrip(tree, revision)

func _disk_roundtrip(tree: SceneTree, revision: int) -> void:
	var helper: RefCounted = preload("res://tests/test_boss.gd").new(check)
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "normal", {})
	run.balance_revision = revision
	helper.prime(run, 100)
	var world: ArcheryWorld = helper.field(tree, session)
	helper.tick(world, 1)
	check.call(world.boss != null and world.boss.impact_revision == revision - 1, "resilience: new vs frozen run config")
	helper.fire(world, 800, 3, 100)
	for frame: int in range(120):
		helper.tick(world, 1)
		if world.boss.hp < world.boss.max_hp: break
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	var path: String = "user://tests/resilience-%d.json" % revision
	for suffix: String in ["", ".bak", ".legacy-v24"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var store := SaveStore.new(path, [])
	if revision == 1:
		payload.world.boss.erase("impact_revision")
		payload.world.boss.erase("volley_pressure")
		var bytes: String = JSON.stringify({"version": 24, "payload": payload}, "", true, true)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(bytes)
		file.close()
		payload = store.read()
		check.call(not payload.is_empty() and FileAccess.get_file_as_string(path + ".legacy-v24") == bytes, "resilience: v24 original bytes archived")
	else:
		check.call(store.write(payload), "resilience: valid in-flight Boss pressure writes " + store.last_error)
		var bad: Dictionary = payload.duplicate(true)
		bad.world.boss.erase("volley_pressure")
		check.call(not store.write(bad), "resilience: missing ledger rejected")
		bad = payload.duplicate(true)
		bad.world.boss.impact_revision = 0
		bad.world.boss.volley_pressure = {}
		check.call(not store.write(bad), "resilience: rule downgrade rejected")
		bad = payload.duplicate(true)
		bad.world.boss.volley_pressure["99999"] = 100
		check.call(not store.write(bad), "resilience: orphan draw budget rejected")
		bad = payload.duplicate(true)
		bad.world.boss.volley_pressure[str(run.shot_sequence)] = -1
		check.call(not store.write(bad), "resilience: negative pressure rejected")
	var restored := GameSession.from_dict(store.read())
	check.call(restored.run != null and restored.run.balance_revision == revision, "resilience: disk preserves rule version")
	if restored.run == null: world.queue_free(); return
	var copy: ArcheryWorld = helper.field(tree, restored, restored.world_snapshot)
	var restored_boss: Dictionary = copy.boss.snapshot()
	var original_boss: Dictionary = world.boss.snapshot()
	var same: bool = true
	for key: String in original_boss:
		if original_boss[key] is float: same = same and is_equal_approx(original_boss[key], restored_boss[key])
		else: same = same and restored_boss[key] == original_boss[key]
	check.call(same, "resilience: Boss and pressure restore within JSON float precision")
	for frame: int in range(1200):
		helper.tick(world, 1)
		helper.tick(copy, 1)
	check.call(is_equal_approx(world.boss.hp, copy.boss.hp) and world.boss.battle_phase == copy.boss.battle_phase, "resilience: continued contacts match uninterrupted fight")
	check.call(copy.boss.volley_pressure.is_empty() and world.boss.volley_pressure.is_empty(), "resilience: settled volleys release ledger entries")
	check.call(restored.run.shots_left == run.shots_left and restored.run.gold == run.gold, "resilience: resume never duplicates resources")
	restored.capture_checkpoint(copy.snapshot())
	check.call(store.write(restored.save_payload()), "resilience: settled fight can save again")
	if revision == 1:
		restored.start_run(true, "normal", {})
		check.call(restored.run.balance_revision == 3, "resilience: new adventure opts into current rule")
	world.queue_free()
	copy.queue_free()
	await tree.process_frame
