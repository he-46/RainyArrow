extends SceneTree
## Actual pixel comparisons and equip buttons. Never touches the player save.

var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("COSMETICS WINDOW: " + message)

func frame_image() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func capture(name: String) -> Image:
	var frame: Image = await frame_image()
	check(frame.save_png("res://artifacts/t08c-" + name + ".png") == OK, "capture " + name)
	return frame

func page(main: Node) -> CosmeticsPage:
	return main.router.page.get_child(1) as CosmeticsPage

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Window checks require --test-mode and a window")
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "cosmetics-window-test"
	main._on_action("start", null)
	main._on_action("cosmetics", null)
	await capture("cosmetics-locked")
	main.session.profile = PlayerProfile.from_dict({"total_score": PlayerProfile.RULES.threshold(5), "total_defeats": 100})
	main.router.show_page("cosmetics", main.session)
	check(main.session.profile.unlocked_cosmetics.size() == 9, "earned profile unlocks all nine")
	await capture("cosmetics-unlocked")
	main._on_action("back", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.set_process_input(false)
	main.world.set_process_unhandled_input(false)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	main.world.arrows[0].set_physics_process(false)
	main.world.arrows[0].position = Vector2(240, 130)
	main.world.arrows[0].rotation = 0
	main.world.arrows[0].queue_redraw()
	var physics: Dictionary = main.world.snapshot()
	var baseline: Image = await capture("flight-default")
	var areas: Dictionary = {"bow": Rect2i(190, 430, 55, 95), "arrow": Rect2i(440, 244, 56, 32), "archer": Rect2i(150, 438, 55, 126)}
	for id: String in ["bow_moon", "arrow_frost", "archer_crimson"]:
		main._on_action("hub", null)
		main._on_action("cosmetics", null)
		(page(main).equip_buttons[id] as Button).pressed.emit()
		main._on_action("back", null)
		main._on_action("range", null)
		var actual: Image = await frame_image()
		var area: Rect2i = areas[CosmeticCatalog.find(id).slot]
		check(actual.get_region(area).get_data() != baseline.get_region(area).get_data(), "actual component pixels change: " + id)
		check(main.world.snapshot() == physics and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1, "equip changes no in-flight physics: " + id)
		baseline = actual
	await capture("flight-cool")
	main._on_action("hub", null)
	main._on_action("cosmetics", null)
	for id: String in ["bow_ember", "arrow_sun", "archer_dusk"]: (page(main).equip_buttons[id] as Button).pressed.emit()
	check(page(main).preview.loadout == main.session.profile.equipped_cosmetics, "loadout preview follows real equipped cards")
	await capture("cosmetics-equipped")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("cosmetics-small")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main._on_action("back", null)
	main._on_action("range", null)
	await capture("flight-warm")
	check(main.world.snapshot() == physics and main.world.arrows[0].cosmetic.id == "arrow_sun", "alternate palette preserves same flight snapshot")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("COSMETICS WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
