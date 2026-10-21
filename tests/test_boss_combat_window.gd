extends SceneTree
## Native T10-B rendering, contacts and disk Continue; --test-mode only.

var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BOSS COMBAT WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var prefix: String = "t10b-"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="): prefix = argument.trim_prefix("--capture-prefix=")
	check(root.get_texture().get_image().save_png("res://artifacts/" + prefix + name + ".png") == OK, "capture " + name)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "boss-combat-window-test"
	main._new_run()
	# Frozen T10-B contact amounts also exercise continued pre-resilience saves.
	# The current rules are exercised by test_balance_window --resilient.
	main.run.balance_revision = 1
	main.world.set_physics_process(false)
	var base: RefCounted = preload("res://tests/test_boss.gd").new(check)
	var combat: RefCounted = preload("res://tests/test_boss_combat.gd").new(check)
	base.prime(main.run, 100)
	main.world._physics_process(0)
	await capture("phase-one")
	check(main.world.targets.is_empty() and main.world.boss.battle_phase == 1, "phase one renders without ordinary targets")
	check(main.hud.boss_title.text.contains("阶段 1") and main.hud.boss_hint.text.contains("1.75"), "HUD explains actual phase and weak multiplier")
	var arrow: Arrow = combat.shot(main.world, Vector2(340, 205), Vector2(10000, 0), 1000)
	arrow._physics_process(0.02)
	main.world._physics_process(0)
	check(main.world.boss.hp == 1138 and main.world.boss.battle_phase == 2, "real weak contact crosses half health without healing")
	check(main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1 and main.run.bosses_defeated == 0, "phase switch spends one draw and grants no victory")
	await capture("phase-two")
	check(main.hud.boss_title.text.contains("阶段 2") and main.hud.boss_hint.text.contains("护板甲 28"), "phase two HUD exposes shield armor")
	main.world.labels.clear()
	arrow = combat.shot(main.world, Vector2(340, 205), Vector2(10000, 0), 100, 28)
	arrow._physics_process(0.02)
	main.world._physics_process(0)
	check(main.world.boss.hp == 1138 and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 2, "equal armor blocks a real shield contact")
	await capture("shield-blocked")
	main.world.labels.clear()
	arrow = combat.shot(main.world, Vector2(340, 205), Vector2(10000, 0), 100, 29)
	arrow._physics_process(0.02)
	check(main.world.boss.hp == 963 and arrow.hit_slots.has(-2) and arrow.hit_slots.has(-3), "higher penetration passes shield and applies weak damage once")
	check(main.world.labels.size() == 2, "shield and weak feedback are both visible")
	await capture("shield-passed")
	arrow._physics_process(0.1)
	main.world._physics_process(0)
	main.world.labels.clear()
	main.world.boss.tick(0.65, main.world.clock)
	var boss: ArcheryBoss = main.world.boss
	check(absf(boss.shield_position.y - boss.position.y) > 23, "shield visibly opens a weak shot lane")
	await capture("weak-exposed")
	var body_pose: Vector2 = boss.position
	var shield_pose: Vector2 = boss.shield_position
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "native live moving Boss saves successfully")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	for restored: Arrow in main.world.arrows: restored.set_physics_process(false)
	await capture("continued")
	check(main.world.boss.position == body_pose and main.world.boss.shield_position == shield_pose, "disk Continue preserves both rendered poses")
	check(main.world.boss.hp == 963 and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 3 and main.world.targets.is_empty(), "Continue preserves damage and spent draws without ordinary targets")
	arrow = combat.shot(main.world, Vector2(340, body_pose.y), Vector2(10000, 0), 100, 0)
	arrow._physics_process(0.02)
	main.world._physics_process(0)
	check(main.world.boss.hp == 796, "exposed weak point takes actual unpiercing arrow contact")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("small")
	check(main.hud.boss_panel.get_rect().end.x <= 1280 and main.hud.boss_panel.get_rect().end.y < 286, "logical HUD remains above the combat area at 960x540")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("BOSS COMBAT WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
