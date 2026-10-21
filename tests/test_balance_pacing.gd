extends RefCounted
var check: Callable
const PATH: String = "user://tests/t09b-migration.json"
func _init(assertion: Callable) -> void: check = assertion

func run_all(tree: SceneTree) -> void:
	DirAccess.make_dir_recursive_absolute("user://tests")
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "normal", {})
	check.call(run.initial_shots == 16 and run.shots_left == 16 and run.balance_revision == 3, "T09B: new contract run starts with 16 draws")
	var restricted := RunModel.new("hell", {"quiver": 2})
	check.call(restricted.initial_shots == 12, "T09B: quiver contract still subtracts four draws")
	var rules: FieldRules = ArcheryTarget.RULES
	var previous_hp: float = 0
	var previous_armor: int = 0
	for step: int in [0, 1, 5, 10, 25, 50, 100, 200, 1000, 1000000]:
		var values: Dictionary = rules.target_values(GameCatalog.TARGETS[0], step, run.field_parameters())
		check.call(is_finite(values.max_hp) and values.max_hp > previous_hp and values.armor >= previous_armor, "T09B: finite monotonic growth at " + str(step))
		previous_hp = values.max_hp
		previous_armor = values.armor
	var modern: Dictionary = rules.target_values(GameCatalog.TARGETS[0], 100, run.field_parameters())
	var legacy: Dictionary = rules.target_values(GameCatalog.TARGETS[0], 100)
	check.call(is_equal_approx(modern.max_hp, 48 * pow(8.5, 0.8)) and modern.armor == 10, "T09B: known hundred-kill curve point")
	check.call(legacy.max_hp == 336 and legacy.armor == 20 and legacy.reward_gold == modern.reward_gold and legacy.reward_score == modern.reward_score, "T09B: legacy growth and reward economy remain intact")
	var old: Dictionary = run.to_dict()
	old.erase("balance_revision")
	old.initial_shots = 10
	old.shots_left = 7
	session.run = RunModel.from_dict(old)
	check.call(session.run.balance_revision == 0 and session.run.shots_left == 7, "T09B: missing revision means old rules without refill")
	var fixture: RefCounted = preload("res://tests/test_boss.gd").new(check)
	var world: ArcheryWorld = fixture.field(tree, session)
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	payload.run.erase("balance_revision")
	var bytes: String = JSON.stringify({"version": 23, "payload": payload}, "", true, true)
	for suffix: String in ["", ".bak", ".legacy-v23"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(PATH, [])
	var restored := GameSession.from_dict(store.read())
	check.call(store.last_error.is_empty() and restored.run.balance_revision == 0 and restored.run.shots_left == 6, "T09B: v23 migration preserves spent draws")
	check.call(FileAccess.get_file_as_string(PATH + ".legacy-v23") == bytes, "T09B: v23 original bytes archived")
	var copy: ArcheryWorld = fixture.field(tree, restored, restored.world_snapshot)
	check.call(copy.arrows[0].snapshot() == world.arrows[0].snapshot(), "T09B: old in-flight arrow survives migration")
	check.call(copy.targets[0].difficulty_parameters.get("growth_revision", 0) == 0, "T09B: old target respawns retain old growth")
	restored.start_run(true, "normal", {})
	check.call(restored.run.balance_revision == 3 and restored.run.shots_left == 16, "T09B: only next new adventure uses new pacing")
	restored.capture_checkpoint({})
	check.call(store.write(restored.save_payload()) and GameSession.from_dict(store.read()).run.balance_revision == 3, "T09B: modern pacing persists through disk")
	var invalid: Dictionary = restored.to_dict()
	invalid.run.balance_revision = 4
	check.call(not store.write(invalid), "T09B: unknown revision rejected")
	invalid.run.balance_revision = 0.5
	check.call(not store.write(invalid), "T09B: fractional revision rejected")
	invalid.run.erase("balance_revision")
	check.call(not store.write(invalid), "T09B: current writer requires explicit revision")
	for node: ArcheryWorld in [world, copy]: node.queue_free()
	await tree.process_frame
