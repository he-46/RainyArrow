extends SceneTree
var assertions: int = 0
var failures: int = 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V04 WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/v04-" + name + ".png") == OK, "capture " + name)

func prepare(main: Node) -> void:
	main.world.set_process(false)
	main.world.set_physics_process(false)
	main.world.vfx.set_process(false)
	main.hud.active_icon.set_process(false)
	main.world.targets[0].position.y = ArcheryWorld.BOW.y
	main.world.targets[0].hp = 10000
	main.world.targets[0].max_hp = 10000
	main.world.direction = Vector2.RIGHT
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 1
	main.run.stats.damage = 1
	main.run.active.energy = 100
	main._refresh()

func shoot(main: Node) -> void:
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows.duplicate():
		arrow.set_physics_process(false)
		arrow._physics_process(0.6)
	main.world.queue_redraw()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v04-window-test"
	main.session.profile.record_score(10000)
	for id: String in ["sunshot", "quickdraw", "hunters_mark"]: main.session.profile.unlock_active(id)
	for id: String in ["sunshot", "quickdraw", "hunters_mark"]:
		main.session.profile.equipped_active = id
		main._new_run()
		prepare(main)
		await capture(id + "-ready")
		check(main.hud.active_icon.pulse_left > 0 and main.hud.active_hint.text.contains("就绪"), "ready pulse and text: " + id)
		main._on_action("active_cast", null)
		await capture(id + "-cast")
		check(main.world.vfx.events.any(func(e: Dictionary) -> bool: return e.kind == id), "real cast emits dedicated effect: " + id)
		shoot(main)
		await capture(id + "-hit")
		check(main.hud.active_icon.remaining == int(ActiveAbility.ALL[id].draws) - 1, "segment follows actual spent draw: " + id)
	main._new_run()
	prepare(main)
	main.run.stats.arrow_count = 32
	main.run.stats.spread_degrees = 0
	shoot(main)
	await capture("dense")
	check(main.world.labels.size() == 1 and main.world.labels[0].count == 32 and main.world.vfx.events.size() <= CombatVFX.LIMIT, "actual dense volley has one caption and bounded effects")
	main._navigate("settings")
	await capture("settings")
	var toggle: CheckButton = main.router.page.find_child("reduced_effects", true, false)
	check(toggle != null, "reduced effects is reachable in settings")
	toggle.button_pressed = true
	check(main.session.profile.settings.reduced_effects and main.world.vfx.reduced, "real toggle immediately changes field presentation")
	var saved: Dictionary = main.saves.read()
	check(saved.profile.settings.reduced_effects, "setting written to disk")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("small-settings")
	main._navigate("range")
	main.world.reload_left = 0
	shoot(main)
	await capture("reduced")
	check(main.world.vfx.events.size() <= CombatVFX.REDUCED_LIMIT and main.hud.active_icon.pulse_left == 0, "reduced field retains readable cues without ready flash")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V04 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
