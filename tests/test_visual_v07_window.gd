extends SceneTree
## Three-size acceptance atlas plus live navigation/input checks; isolated test saves only.
var main: Node
var assertions: int = 0
var failures: int = 0
var suffix: String

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V07: " + message)

func capture(id: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame.get_size() == DisplayServer.window_get_size(), "render size matches window: " + id)
	check(frame.save_png("res://artifacts/v07-" + id + "-" + suffix + ".png") == OK, "capture " + id)

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func click(button: Button) -> void:
	check(button != null, "reachable button")
	if button == null: return
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame

func freeze() -> void:
	main.world.set_process(false)
	main.world.set_physics_process(false)
	main.world.vfx.set_process(false)
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v07-window-test"
	var fixture: RefCounted = preload("res://tests/test_backpack.gd").new(check)
	for extent: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		suffix = str(extent.x)
		DisplayServer.window_set_size(extent)
		await create_timer(0.15).timeout
		main._navigate("home")
		await capture("home")
		for page: String in ["hub", "talents", "active_skills", "contracts", "cosmetics", "settings", "leaderboard"]:
			main._navigate(page)
			await capture(page)
		main._navigate("tutorial")
		await capture("tutorial")
		main._stop_tutorial()
		main._new_run("normal", null, true)
		freeze()
		await capture("range")
		# Real keyboard pause/resume and cancel a drag without spending a draw.
		main.world.dragging = true
		main.world.pull = 1
		var shots: int = main.run.shots_left
		await key(KEY_ESCAPE)
		check(not main.world.dragging and main.run.shots_left == shots and main.router.route == "range", "cancel drag is free")
		await key(KEY_ESCAPE)
		await capture("pause")
		var before: Dictionary = main.world.snapshot().duplicate(true)
		await create_timer(0.05).timeout
		check(main.world.snapshot() == before and paused, "paused field stays frozen")
		main._on_action("back", null)
		check(main.router.route == "range" and not paused, "pause returns to field")
		for action: String in ["combat_details", "combat_help"]:
			main._on_action(action, null)
			await capture(action)
		main._on_action("details_close", null)
		main.run.gold = 10000
		fixture.equip(main.run, fixture.SIX)
		main._on_action("skills", null)
		await capture("skills")
		main._on_action("continue", null)
		check(not main.hud.encounters_button.disabled and not main.hud.skills_button.disabled, "closing upgrade immediately restores field buttons")
		await click(main.hud.encounters_button)
		await capture("backpack")
		await click(main.hud.encounter_panel.find_child("Details_critical_forging", true, false))
		await capture("artifact-details")
		await click(main.hud.encounter_panel.find_child("CloseArtifactDetails", true, false))
		main._on_action("encounter_close", null)
		fixture.offer(main.run, "heavy_draw")
		main._refresh()
		await capture("choice")
		await click(main.hud.encounter_panel.choice_buttons[0])
		await capture("replacement")
		await click(main.hud.encounter_panel.find_child("Replace_critical_forging", true, false))
		await capture("replacement-confirm")
		for skill: String in ["sunshot", "quickdraw", "hunters_mark"]:
			main._new_run("normal", null, true)
			freeze()
			main.run.active.id = skill
			main.run.active.energy = 100
			main.world.direction = (main.world.targets[0].position - ArcheryWorld.BOW).normalized()
			main._refresh()
			await key(KEY_Q)
			check(main.run.active.remaining == int(ActiveAbility.ALL[skill].draws), "real Q arms " + skill)
			await capture(skill)
		main._new_run("normal", null, true)
		freeze()
		preload("res://tests/test_boss.gd").new(check).prime(main.run, 100)
		main.world._physics_process(0)
		await capture("boss-one")
		main.world.boss.hp = main.world.boss.max_hp * 0.4
		main.world.boss.refresh_phase()
		main.world.boss.tick(0.65, 0)
		await capture("boss-two")
		main._on_action("setting", {"key": "reduced_effects", "value": true})
		await capture("boss-reduced")
		check(main.world.vfx.reduced, "reduced effect setting applies")
		main._on_action("setting", {"key": "reduced_effects", "value": false})
		await key(KEY_M)
		check(main.audio.muted == main.session.profile.settings.muted, "mute reflects saved setting")
		main._new_run("normal", null, true)
		freeze()
		main.run.shots_left = 0
		main.run.gold = 0
		main.run.settle_volley()
		main._refresh()
		await capture("result")
		check(main.run.is_finished(), "empty quiver reaches result")
	main.queue_free()
	paused = false
	await process_frame
	print("V07 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
