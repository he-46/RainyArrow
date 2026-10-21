extends SceneTree
## Rendered Boss lifecycle and viewport mouse input, isolated from player saves.

var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BOSS WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var prefix: String = "t10a-"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="): prefix = argument.trim_prefix("--capture-prefix=")
	check(root.get_texture().get_image().save_png("res://artifacts/" + prefix + name + ".png") == OK, "capture " + name)

func press(position: Vector2, held: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = held
	root.push_input(event, true)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "boss-window-test"
	main._new_run()
	main.world.set_physics_process(false)
	preload("res://tests/test_boss.gd").new(check).prime(main.run, 99)
	main._refresh()
	await capture("progress")
	check(main.hud.boss_hint.text.contains("99 / 100") and not main.hud.boss_panel.visible, "ordinary HUD shows the next hundred-kill threshold")
	preload("res://tests/test_boss.gd").new(check).prime(main.run, 100)
	main.world._physics_process(0)
	await capture("boss-entry")
	check(main.world.targets.is_empty() and main.world.boss != null and main.hud.boss_panel.visible, "entry renders one Boss with no ordinary targets")
	check(main.hud.boss_title.text.contains("2880 / 2880") and main.hud.boss_hint.text.contains("击败后"), "rendered health and field restriction match actual state")
	main.run.stats.damage = 160
	main.run.stats.crit_chance = 0
	main.world.reload_left = 0
	main.world.set_physics_process(true)
	press(Vector2(208, 476), true)
	await process_frame
	check(main.world.dragging, "viewport mouse press starts a real Boss draw")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(85, 512)
	root.push_input(motion, true)
	await process_frame
	press(motion.position, false)
	await process_frame
	check(main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1 and not main.world.arrows.is_empty(), "viewport release launches and consumes exactly one draw")
	for index: int in range(160): await physics_frame
	main.world.set_physics_process(false)
	check(main.world.boss.hp < 2880 and main.world.boss.hp > 0 and main.run.bosses_defeated == 0, "real ballistic shot damages the Boss without a victory reward")
	await capture("boss-damaged")
	var health: float = main.world.boss.hp
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	await capture("boss-continued")
	check(main.world.boss.hp == health and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1 and main.world.targets.is_empty(), "disk Continue restores rendered damage and spent draw")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("boss-small")
	check(main.hud.boss_panel.get_rect().end.x <= 1280 and main.hud.boss_panel.get_rect().end.y < 286, "Boss HUD stays above its hit area at the logical layout")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main.world.reload_left = 0
	main.world.direction = (main.world.boss.position - ArcheryWorld.BOW).normalized()
	main.run.stats.damage = 100000
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 0
	main.run.stats.arrow_count = 3
	main.run.stats.spread_degrees = 0
	main.world.pull = 1
	main.world._release()
	main.world.set_physics_process(true)
	for index: int in range(180): await physics_frame
	main.world.set_physics_process(false)
	preload("res://tests/test_boss.gd").new(check).choose_safe(main.run)
	main.world._physics_process(0)
	await capture("field-returned")
	check(not main.run.boss_active and main.run.bosses_defeated == 1 and main.world.targets.size() == 3, "live victory renders freshly generated ordinary targets")
	check(not main.hud.boss_panel.visible and main.hud.boss_hint.text.contains("100 / 200") and main.run.defeated_count == 100, "victory HUD keeps ordinary progress and advances only Boss threshold")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("BOSS WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
