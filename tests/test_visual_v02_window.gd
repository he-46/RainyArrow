extends SceneTree
var assertions: int = 0
var failures: int = 0

class PoseGallery extends Control:
	func _draw() -> void:
		var names: Array[String] = ["待机", "拉弓", "蓄满", "松弦", "装填", "施放"]
		var poses: Array[ArcherPose] = [ArcherPose.sample(Vector2.RIGHT), ArcherPose.sample(Vector2.RIGHT, true, 0.5), ArcherPose.sample(Vector2.RIGHT, true, 1), ArcherPose.sample(Vector2.RIGHT, false, 0, 0.6, 0.65, 1), ArcherPose.sample(Vector2.RIGHT, false, 0, 0.5), ArcherPose.sample(Vector2.RIGHT, false, 0, 0, 0.65, 0, 0.28)]
		draw_rect(Rect2(0, 0, 1280, 720), Color("142832"))
		for row: int in range(3):
			var skin: CosmeticData = CosmeticCatalog.find(["archer_default", "archer_crimson", "archer_dusk"][row])
			var bow_skin: CosmeticData = CosmeticCatalog.find(["bow_default", "bow_moon", "bow_ember"][row])
			for col: int in range(6):
				var origin := Vector2(65 + col * 210, 45 + row * 228)
				draw_set_transform(origin, 0, Vector2.ONE * 2.7)
				CosmeticDrawing.archer(self, skin, Vector2.ZERO, poses[col])
				CosmeticDrawing.bow(self, bow_skin, ArcherPose.GRIP, Vector2.RIGHT, poses[col].tension, poses[col].recoil)
				if poses[col].loaded: CosmeticDrawing.nocked_arrow(self, CosmeticCatalog.default_for("arrow"), ArcherPose.string_anchor(ArcherPose.GRIP, Vector2.RIGHT, poses[col].tension), Vector2.RIGHT)
				draw_set_transform(Vector2.ZERO)
				draw_string(get_theme_default_font(), origin + Vector2(-25, 192), names[col] + " · " + skin.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("eee5cc"))

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V02 WINDOW: " + message)

func capture(name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame.save_png("res://artifacts/v02-" + name + ".png") == OK, "capture " + name)
	return frame

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v02-window-test"
	main._on_action("start", null)
	main.session.profile.unlock_active("sunshot")
	main._on_action("range", null)
	main.world.set_process(false)
	main.world.set_physics_process(false)
	main.run.active.energy = 100
	main._refresh()
	var baseline: Dictionary = main.world.snapshot().duplicate(true)
	var rng_state: int = main.run.rng.state
	var idle: Image = await capture("idle")
	main.world.dragging = true
	main.world.pull = 0.5
	main.world.queue_redraw()
	var draw: Image = await capture("draw")
	main.world.pull = 1
	main.world.queue_redraw()
	var hold: Image = await capture("hold")
	var region := Rect2i(120, 420, 130, 150)
	check(idle.get_region(region).get_data() != draw.get_region(region).get_data() and draw.get_region(region).get_data() != hold.get_region(region).get_data(), "draw stages have different visible poses")
	check(main.world.snapshot() == baseline and main.run.rng.state == rng_state, "posing changes no combat data or RNG")
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	main.world.queue_redraw()
	await capture("release")
	main.world._process(0.16)
	await capture("reload")
	main.world.reload_left = 0
	main.world.activate_skill()
	await capture("cast")
	main.world.cast_pose_left = 0
	main.world.dragging = true
	main.world.pull = 1
	main.run.stats.arrow_size = 6
	main.run.stats.arrow_count = 1
	main.world.queue_redraw()
	await capture("giant")
	main.run.stats.arrow_size = 1
	main.run.stats.arrow_count = 12
	main.world.queue_redraw()
	await capture("multishot")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("small")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main._navigate("hub")
	main.session.profile = PlayerProfile.from_dict({"total_score": PlayerProfile.RULES.threshold(5), "total_defeats": 100})
	main._navigate("cosmetics")
	await capture("wardrobe")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("small-wardrobe")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	# Hide the menu layer; the world is already hidden after leaving the field.
	main.root.hide()
	var gallery := PoseGallery.new()
	gallery.theme = GameUI.make_theme()
	root.add_child(gallery)
	await capture("poses")
	gallery.queue_free()
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V02 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
