extends "res://tests/test_journey_window.gd"
## Native desktop lifecycle. Focus notification is injected; no claim of physical Alt-Tab.

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "desktop-test"
	main._new_run("normal", {}, false)
	var w: ArcheryWorld = main.world
	w.direction = Vector2.RIGHT
	w.pull = 1
	w._release()
	await process_frame
	# Enable the production focus handler for this explicit notification.
	main.capture_path = ""
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.capture_path = "desktop-test"
	check(paused and main.router.route == "pause" and main.run.suspended, "focus loss suspends active run")
	var saved: Dictionary = w.snapshot().duplicate(true)
	await create_timer(0.3).timeout
	check(w.snapshot() == saved, "in-flight arrows and reload freeze while paused")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(paused, "focus return requires explicit resume")
	main._on_action("back", null)
	check(not paused and not main.run.suspended, "explicit resume")
	w.dragging = true
	w.pull = 0.8
	var shots: int = main.run.shots_left
	main.capture_path = ""
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.capture_path = "desktop-test"
	check(not w.dragging and is_zero_approx(w.pull) and main.run.shots_left == shots, "focus loss cancels drag without spending")
	check(not main.saves.read().is_empty(), "focus checkpoint is readable")
	main._on_action("back", null)
	main._on_action("skills", null)
	main.capture_path = ""
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.capture_path = "desktop-test"
	main._on_action("back", null)
	check(main.run.phase == RunModel.Phase.SHOP and paused, "focus roundtrip preserves shop phase")
	main._on_action("continue", null)
	for enabled: bool in [true, false, true, false]:
		main._on_action("setting", {"key": "fullscreen", "value": enabled})
		await create_timer(0.15).timeout
		check(DisplayServer.window_get_mode() == (DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED), "fullscreen toggle")
	main._navigate("home")
	for extent: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(extent)
		await create_timer(0.2).timeout
		await capture("desktop-" + str(extent.x))
		check(DisplayServer.window_get_size() == extent, "desktop resize")
	await process_frame
	var baseline: int = get_node_count()
	for cycle: int in range(30):
		for page: String in ["hub", "talents", "settings", "home"]:
			main._navigate(page)
			await process_frame
		check(main.audio.players.size() == 10 and main.audio.music_players.size() == 3, "fixed audio players during navigation")
	await create_timer(0.8).timeout
	check(get_node_count() <= baseline + 2, "navigation releases old page nodes")
	var playing: int = 0
	for player: AudioStreamPlayer in main.audio.music_players.values():
		if player.playing: playing += 1
	check(playing == 1, "crossfade settles to one music stream")
	for index: int in range(100): main.audio.play("hit")
	var active_voices: int = 0
	for player: AudioStreamPlayer in main.audio.players:
		if player.playing: active_voices += 1
	check(active_voices <= AudioService.VOICES and active_voices > 0, "sound burst stays within voice pool")
	main._save_checkpoint()
	check(not main.saves.read().is_empty(), "desktop roundtrip saves intact")
	var output := {"assertions": assertions, "failures": failures, "screen_count": DisplayServer.get_screen_count(), "screen_dpi": DisplayServer.screen_get_dpi(), "audio_driver": AudioServer.get_driver_name(), "audio_devices": AudioServer.get_output_device_list(), "method": "injected focus notifications, real window modes/sizes; no cross-monitor DPI or listening claim"}
	var file := FileAccess.open("res://artifacts/t09c-desktop-" + AudioServer.get_driver_name() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("T09C DESKTOP: %d assertions, %d failures" % [assertions, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
