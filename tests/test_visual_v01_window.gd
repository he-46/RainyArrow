extends SceneTree
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V01 WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/v01-" + name + ".png") == OK, "capture " + name)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v01-window-test"
	main._on_action("start", null)
	main.session.profile.unlock_active("sunshot")
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.run.active.energy = 100
	main._refresh()
	var rng_state: int = main.run.rng.state
	await capture("range")
	check(main.run.rng.state == rng_state, "rendering scenery preserves combat randomness")
	check(main.hud.energy_bar.size.y <= 10 and main.hud.progress.size.y <= 12, "thin bars do not overlap labels")
	check(main.hud.active_panel.position.y >= Arrow.FIELD.end.y * 2, "active skill panel clears combat field")
	check(main.hud.active_icon.skill == "sunshot" and main.hud.energy_ruler.cost == 60, "skill emblem and cost marker")
	await key(KEY_R)
	await capture("attributes")
	check(paused and main.world.ui_blocked, "real R pauses world")
	await key(KEY_Q)
	check(main.run.active.energy == 100, "Q blocked under attributes")
	await key(KEY_F1)
	await capture("help")
	check(main.hud.help_label.visible and paused, "F1 switches to help")
	await key(KEY_ESCAPE)
	check(not paused and main.router.route == "range", "Escape returns to field")
	# Actual pointer drag at the unchanged bow anchor.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = ArcheryWorld.BOW * 2
	Input.parse_input_event(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = ArcheryWorld.BOW * 2 + Vector2(-100, 24)
	Input.parse_input_event(motion)
	await process_frame
	check(main.world.dragging and main.world.pull > 0, "bow remains reachable by real drag")
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.pressed = false
	Input.parse_input_event(press)
	await process_frame
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	check(main.run.shot_sequence == 1 and main.hud.instruction.modulate.a < 0.4, "pointer release fires and fades instruction")
	await capture("shot")
	await key(KEY_Q)
	check(main.run.active.remaining == 1, "Q works after modal closes")
	await capture("armed")
	# Rebuild a legitimate threshold field with no active volley.
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process(false)
	preload("res://tests/test_boss.gd").new(check).prime(main.run, 100)
	main.world._physics_process(0.01)
	check(main.world.boss != null, "boss enters threshold field")
	await capture("boss")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.15).timeout
	await capture("small-boss")
	main.world.boss.hp = main.world.boss.max_hp * 0.4
	main.world.boss.refresh_phase()
	await capture("small-boss-phase-two")
	await key(KEY_R)
	await capture("small-attributes")
	check(main.hud.stats_label.get_rect().end.x <= 650 and main.hud.stats_label.get_rect().end.y <= 405, "attributes fit card")
	await key(KEY_ESCAPE)
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.run.active.id = "quickdraw"
	main.run.active.energy = 100
	main._refresh()
	await capture("small-range")
	check(main.hud.active_icon.skill == "quickdraw" and main.hud.energy_ruler.cost == 40, "quickdraw icon and cost")
	main.run.active.id = "hunters_mark"
	main._refresh()
	await capture("mark")
	check(main.hud.active_icon.skill == "hunters_mark" and main.hud.energy_ruler.cost == 50, "mark icon and cost")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V01 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
