extends SceneTree
## Window-only checks. Run with --script ... -- --test-mode, never player saves.

var failures: int = 0
var assertions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WINDOW SETTINGS: " + message)

func capture(path: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame.save_png(path) == OK, "capture " + path)
	return frame

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Window checks require a window and --test-mode")
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Avoid incidental window focus events in the deterministic capture fixture.
	main.capture_path = "window-test"
	main._on_action("settings", null)
	check(AudioServer.get_bus_count() == 5, "project loads all five sound buses")
	main._on_action("sound_preview", null)
	check(main.audio.players.any(func(player: AudioStreamPlayer) -> bool: return player.playing and player.bus == "Bow"), "preview actually starts Bow voice")
	await capture("res://artifacts/t08a-settings.png")
	main._on_action("setting", {"key": "fullscreen", "value": true})
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen applies to actual OS window")
	await capture("res://artifacts/t08a-fullscreen.png")
	main._on_action("setting", {"key": "fullscreen", "value": false})
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "returns to actual window mode")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("res://artifacts/t08a-settings-small.png")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.set_process_input(false)
	main.world.set_process_unhandled_input(false)
	main.world.dragging = true
	main.world.pull = 0.8
	main.world.direction = Vector2(1, -0.3).normalized()
	main.world.queue_redraw()
	var on: Image = await capture("res://artifacts/t08a-guide-on.png")
	var before: Dictionary = main.world.snapshot()
	main._on_action("setting", {"key": "trajectory_guide", "value": false})
	var off: Image = await capture("res://artifacts/t08a-guide-off.png")
	check(on.get_data() != off.get_data(), "trajectory switch changes rendered image")
	check(before == main.world.snapshot() and main.world.dragging and main.world.pull == 0.8, "trajectory does not change active pull or combat")
	main.world.dragging = false
	main.world._kick_shake(true)
	main.world._update_shake(0.001)
	check(root.canvas_transform != Transform2D.IDENTITY, "actual rendered shake is active")
	main._on_action("setting", {"key": "screen_shake", "value": false})
	check(root.canvas_transform == Transform2D.IDENTITY, "disabling shake resets actual rendered transform")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("WINDOW SETTINGS RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
