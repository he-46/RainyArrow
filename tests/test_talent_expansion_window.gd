extends SceneTree

var main: Node
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T15 WINDOW: " + message)

func page() -> TalentPage:
	return main.router.page.get_child(1) as TalentPage

func click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	check(point.y >= 0 and point.y < 720, "mouse target is in logical viewport")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = point
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)
	await process_frame
	await process_frame

func wheel(down: bool, steps: int = 8) -> void:
	for index: int in range(steps):
		var event := InputEventMouseButton.new()
		event.position = Vector2(600, 300)
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.pressed = true
		root.push_input(event, true)
		var release: InputEventMouseButton = event.duplicate() as InputEventMouseButton
		release.pressed = false
		root.push_input(release, true)
	await process_frame
	await process_frame

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t15-" + name + ".png") == OK, "capture " + name)

func inspect(id: String) -> void:
	await wheel(true)
	var button: Button = page().nodes[id]
	check(page().tree_scroll.get_global_rect().encloses(button.get_global_rect()), "new node fully visible after scroll " + id)
	await click(button)
	check(page().selected == id and main.router.selected_talent == id, "real selection " + id)
	var description: Label = page().detail.get_node("TalentDescription")
	check(description.get_line_count() <= 2 and description.get_global_rect().end.x < (page().detail.get_node("PurchaseTalent") as Button).get_global_rect().position.x, "description fits beside purchase button " + id)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "talent-expansion-window-test"
	main.session.profile.record_score(1.0e12)
	main._navigate("talents")
	await process_frame
	await process_frame
	check(page().nodes.size() == 36, "four extended trees render all thirty-six nodes")
	check(page().tree_scroll.scroll_vertical == 0, "opening begins at roots")
	await capture("roots")
	await wheel(true)
	check(page().tree_scroll.scroll_vertical > 0, "real mouse wheel scrolls tree")
	await inspect("damage_capstone_right")
	check((page().detail.get_node("PurchaseTalent") as Button).disabled, "locked terminal cannot buy")
	await capture("locked-terminal")
	await wheel(false)
	check(page().tree_scroll.scroll_vertical == 0, "wheel returns to roots")
	for prefix: String in ["quiver", "economy", "damage", "field"]:
		for side: String in ["left", "right"]:
			main.session.reset_talents()
			check(main.session.purchase_talent(prefix + "_root"), "setup root")
			check(main.session.purchase_talent(prefix + "_" + side) and main.session.purchase_talent(prefix + "_" + side), "setup branch")
			check(main.session.purchase_talent(prefix + "_master_" + side), "setup specialization")
			main._navigate("talents")
			await process_frame
			await process_frame
			var advanced: String = prefix + "_advanced_" + side
			await inspect(advanced)
			for rank: int in range(2):
				var points: int = main.session.profile.talent_points
				await click(page().detail.get_node("PurchaseTalent"))
				check(main.session.profile.talents.get(advanced) == rank + 1 and points - main.session.profile.talent_points == (5 if rank == 0 else 7), "real advanced purchase spends exact increasing cost")
				check(page().selected == advanced and page().tree_scroll.scroll_vertical > 0, "purchase preserves deep selected node and scroll visibility")
			var terminal: String = prefix + "_capstone_" + side
			await inspect(terminal)
			await click(page().detail.get_node("PurchaseTalent"))
			check(main.session.profile.talents.get(terminal) == 1 and (page().detail.get_node("PurchaseTalent") as Button).disabled, "real capstone purchase becomes full")
			var disk: GameSession = GameSession.from_dict(main.saves.read())
			check(disk.profile.to_dict() == main.session.profile.to_dict(), "UI saves exact expanded ranks and ledger")
			await capture(prefix + "-" + side)
			var original_points: int = main.session.profile.talent_points
			for child: Node in page().get_children():
				if child is Button and child.text.begins_with("免费重置"):
					await click(child)
					break
			check(main.session.profile.talents.is_empty() and main.session.profile.talent_points == original_points + 32, "real reset refunds actual path investment")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(.1).timeout
	await capture("small-terminal")
	await wheel(false)
	await capture("small-roots")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(.1).timeout
	main._navigate("hub")
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	var frozen: Dictionary = main.run.talent_snapshot.duplicate(true)
	main._navigate("talents")
	await process_frame
	await process_frame
	await wheel(false)
	await click(page().nodes["quiver_root"])
	await click(page().detail.get_node("PurchaseTalent"))
	check(main.session.profile.talents.get("quiver_root") == 1 and main.run.talent_snapshot == frozen and main.run.shots_left == 10, "native lobby purchase affects only next run")
	await capture("next-run-only")
	main.queue_free()
	await process_frame
	print("T15 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
