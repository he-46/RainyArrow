extends SceneTree
## Render and exercise the real active-skill page and Q shortcut in a test profile.
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("ACTIVE WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/active-" + name + ".png") == OK, "capture " + name)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "active-window-test"
	main._on_action("start", null)
	main._on_action("active_skills", null)
	await capture("choices")
	for description: Node in main.router.page.find_children("SkillDescription", "Label", true, false):
		check(description.size.x <= 348.0, "description stays inside its card")
	(main.router.page.find_child("hunters_mark", true, false) as Button).pressed.emit()
	check(main.session.profile.equipped_active == "hunters_mark", "free choice equips mark")
	main._on_action("back", null)
	await capture("talents")
	main._on_action("back", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process_input(false)
	main.world.set_process_unhandled_input(false)
	main.world.direction = (main.world.targets[0].position - ArcheryWorld.BOW).normalized()
	main.run.active.energy = 100
	await capture("ready")
	check(main.hud.energy_bar.size.y <= 10.0, "energy bar stays clear of its hint")
	check(not main.hud.active_button.disabled, "ready HUD enabled")
	var event := InputEventKey.new()
	event.keycode = KEY_Q
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	check(main.run.active.energy == 50 and main.run.active.remaining == 3, "Q activates marked target")
	event = InputEventKey.new()
	event.keycode = KEY_Q
	event.pressed = false
	Input.parse_input_event(event)
	await capture("mark")
	DisplayServer.window_set_size(Vector2i(960, 540))
	main._navigate("hub")
	main._navigate("active_skills")
	await create_timer(0.15).timeout
	await capture("small")
	check((main.router.page.find_child("hunters_mark", true, false) as Button).disabled, "in-run loadout locked")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("ACTIVE WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
