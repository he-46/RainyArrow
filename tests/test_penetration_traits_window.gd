extends SceneTree
## Native cards, live combinations, history and exact disk Continue.

var assertions: int = 0
var failures: int = 0
var main: Node
var fixture: RefCounted
var offers: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("T11-B WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t11b-" + name + ".png") == OK, "capture " + name)

func new_field() -> void:
	main._new_run()
	main.world.set_physics_process(false)
	main.world.boss_enabled = false
	main.world.set_process_unhandled_input(false)

func prepare_offer(ids: Array[String]) -> void:
	offers.entitle(main.run)
	main.run.offer_encounter()
	main.run.choices.assign(ids)
	for id: String in ids:
		if EncounterCatalog.find(id).is_trait and not main.run.seen_encounters.has(id): main.run.seen_encounters.append(id)
	main._refresh()

func claim(id: String) -> void:
	var pick: Button
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == id: pick = button
	check(pick != null and not pick.disabled, "native trait button available: " + id)
	if pick != null: pick.pressed.emit()
	check(main.run.encounter_picks.get(id, 0) == 1 and not paused, "native claim resumes same field: " + id)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "penetration-traits-window-test"
	new_field()
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	fixture._freeze(main.world)
	var old: Dictionary = main.world.snapshot()
	prepare_offer(["second_wind", "piercing_edge", "armor_surplus"])
	main._save_checkpoint()
	await capture("penetration-choices")
	check(paused and main.hud.encounter_panel.choice_buttons.size() == 3, "two penetration traits appear alongside safe ordinary reward")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("penetration-choices-small")
	claim("piercing_edge")
	check(main.world.snapshot() == old, "claim keeps exact preexisting arrow and reload")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	prepare_offer(["second_wind", "armor_surplus", "echo_strike"])
	await capture("surplus-echo-choices")
	claim("armor_surplus")
	prepare_offer(["second_wind", "echo_strike", "wall_forging"])
	await capture("bounce-choices")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("bounce-choices-small")
	claim("wall_forging")
	prepare_offer(["second_wind", "echo_strike", "steady_power"])
	claim("echo_strike")
	check(main.run.projectile_effects().penetration_limit == 5 and main.run.projectile_effects().bounce_penetration == 3 and main.run.projectile_effects().excess_limit == 1 and main.run.projectile_effects().echo_damage == 0.5, "all four native choices coexist without exclusions")
	check(main.world.snapshot() == old, "all four claims preserve old immutable projectile")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	new_field()
	var combined: Array[String] = ["piercing_edge", "armor_surplus", "echo_strike", "wall_forging", "piercing_split", "ricochet_haste"]
	fixture._equip(main.run, combined)
	offers.entitle(main.run, 0)
	main.run.skill_levels = {"penetration": 2, "ricochet": 2, "damage": 2}
	main.run.rebuild_stats()
	for index: int in range(main.world.targets.size()):
		var target: ArcheryTarget = main.world.targets[index]
		target.anchor = Vector2(300 + index * 90, 150)
		target.tick(0, 0)
		target.hp = 1000
		target.max_hp = 1000
		target.armor = 0
	var arrow: Arrow = fixture._primary(main.world, Vector2(280, 150), Vector2(500, 0))
	arrow.stats.gravity = 0
	arrow.stats.crit_chance = 0
	arrow._physics_process(0.03)
	main._refresh()
	main._save_checkpoint()
	await capture("pending-exit")
	check(arrow.penetration_stacks == 0 and arrow.penetration_exits.size() == 1 and arrow.split_pending, "native in-target checkpoint has pending penetration and split")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "native pending exit stored on disk")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.boss_enabled = false
	fixture._freeze(main.world)
	check(JSON.parse_string(JSON.stringify(main.world.snapshot(), "", true, true)) == payload["world"] and main.run.rng.state == int(payload["run"]["rng_state"]), "native disk Continue retains exact pending volumes and RNG")
	await capture("continued-exit")
	arrow = main.world.arrows[0]
	arrow._physics_process(0.04)
	fixture._freeze(main.world)
	main._refresh()
	await capture("split-inheritance")
	check(main.world.arrows.size() == 3 and arrow.penetration_stacks == 1 and main.world.arrows[1].penetration_stacks == 1, "rendered split children inherit post-exit stack")
	arrow.position = Vector2(629, 90)
	arrow.trail.clear()
	arrow.velocity = Vector2(500, 0)
	arrow._physics_process(0.005)
	main._refresh()
	main._save_checkpoint()
	await capture("bounce-combination")
	check(arrow.bounce_stacks == 1 and arrow.echo_ready and arrow.velocity.x < 0, "real window reflection applies haste, armor and echo")
	main._on_action("encounters", null)
	await capture("history")
	var history := main.hud.encounter_panel.find_child("EncounterHistory", true, false) as ScrollContainer
	check(history != null and paused and main.hud.encounter_log_open, "four trait descriptions included in scrollable history")
	history.scroll_vertical = 10000
	await capture("history-bottom")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("history-small")
	main._on_action("encounter_close", null)
	check(not paused, "history closes back to same build")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T11-B WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
