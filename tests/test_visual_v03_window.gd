extends SceneTree
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V03 WINDOW: " + message)

func capture(name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame.save_png("res://artifacts/v03-" + name + ".png") == OK, "capture " + name)
	return frame

func freeze_debris(world: ArcheryWorld, age: float) -> void:
	for child: Node in world.get_children():
		if child is TargetBreakup:
			child.set_process(false)
			child.age = age
			child.queue_redraw()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v03-window-test"
	main.session.profile.unlock_active("sunshot")
	main._new_run()
	main.world.set_process(false)
	main.world.set_physics_process(false)
	main.run.active.energy = 100
	main._refresh()
	var before: Dictionary = main.world.snapshot().duplicate(true)
	var rng: int = main.run.rng.state
	await capture("range")
	check(main.world.snapshot() == before and main.run.rng.state == rng, "render preserves world and randomness")
	for i: int in range(3):
		main.world.targets[i].spawn(GameCatalog.TARGETS[i], 0)
		main.world.targets[i].scale = Vector2.ONE * 2
		main.world.targets[i].tick(0, 0)
	var pristine: Image = await capture("materials")
	for target: ArcheryTarget in main.world.targets:
		target.hp = target.max_hp * 0.25
		target.queue_redraw()
	var damaged: Image = await capture("damaged")
	check(pristine.get_region(Rect2i(600, 360, 64, 180)).get_data() != damaged.get_region(Rect2i(600, 360, 64, 180)).get_data(), "low health visibly changes wood surface")
	for target: ArcheryTarget in main.world.targets:
		target.difficulty_parameters["bullseye_scale"] = 0.5
		target.queue_redraw()
	await capture("narrow-core")
	var bow := BowStats.new()
	bow.damage = 100000
	main.world.targets[0].receive_hit(bow, 1, main.world.targets[0].global_position, 1)
	freeze_debris(main.world, 0.16)
	await capture("breakup")
	main._new_run()
	main.world.set_process(false)
	main.world.set_physics_process(false)
	preload("res://tests/test_boss.gd").new(check).prime(main.run, 100)
	main.world._physics_process(0)
	freeze_debris(main.world, 0.18)
	await capture("boss-entry")
	for child: Node in main.world.get_children():
		if child is TargetBreakup: child.queue_free()
	var boss: ArcheryBoss = main.world.boss
	await capture("boss-one")
	boss.hp = boss.max_hp * 0.4
	boss.refresh_phase()
	boss.tick(0, 0)
	await capture("boss-two")
	boss.tick(0.65, 0)
	await capture("boss-exposed")
	var saved: Dictionary = boss.snapshot().duplicate(true)
	boss.restore(saved)
	boss.queue_redraw()
	check(boss.snapshot() == saved, "continued boss pose and damage unchanged")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("small-boss")
	boss.receive_contact(bow, 1, boss.global_position, 1, "weak")
	freeze_debris(main.world, 0.16)
	await capture("boss-broken")
	main._new_run()
	main.world.set_process(false)
	main.world.set_physics_process(false)
	await capture("small-range")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V03 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
