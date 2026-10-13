extends SceneTree
## Native T11-C buttons, secondary feedback, frozen flight and disk Continue.

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
		push_error("T11-C WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if name.contains("choices"):
		for description: Node in main.hud.encounter_panel.find_children("Description", "Label", true, false):
			var comparison := description.get_parent().get_node("Comparison") as Label
			check(description.get_rect().end.y <= comparison.position.y, "card description fits above comparison: " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t11c-" + name + ".png") == OK, "capture " + name)

func new_field() -> void:
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process(false)
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
	check(main.run.encounter_picks.get(id, 0) == 1 and not paused, "native claim resumes field: " + id)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "precision-traits-window-test"
	new_field()
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	fixture._freeze(main.world)
	var old: Dictionary = main.world.snapshot()
	prepare_offer(["second_wind", "charged_breach", "bullseye_wave"])
	main._save_checkpoint()
	await capture("charge-wave-choices")
	check(paused and main.hud.encounter_panel.choice_buttons.size() == 3, "charge/wave cards retain safe reward")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("charge-wave-choices-small")
	claim("charged_breach")
	prepare_offer(["second_wind", "bullseye_wave", "critical_flow"])
	claim("bullseye_wave")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	prepare_offer(["second_wind", "critical_flow", "broad_precision"])
	await capture("crit-size-choices")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("crit-size-choices-small")
	claim("critical_flow")
	prepare_offer(["second_wind", "broad_precision", "steady_power"])
	claim("broad_precision")
	check(main.world.snapshot() == old, "all four real claims keep original arrow, reload and field")
	var selected: ArrowEffects = main.run.projectile_effects()
	check(selected.charged_penetration == 8 and selected.bullseye_damage == 0.4 and selected.critical_limit == 5 and selected.size_bullseye == 0.15, "native four traits coexist without exclusions")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	new_field()
	var combined: Array[String] = ["charged_breach", "bullseye_wave", "critical_flow", "broad_precision", "piercing_edge", "piercing_split"]
	fixture._equip(main.run, combined)
	main.run.skill_levels = {"penetration": 2, "damage": 2, "size": 2, "critical": 2}
	main.run.rebuild_stats()
	for index: int in range(main.world.targets.size()):
		var target: ArcheryTarget = main.world.targets[index]
		target.anchor = Vector2([300, 360, 540][index], 150)
		target.tick(0, 0)
		target.hp = 20 if index == 1 else 1000
		target.max_hp = target.hp
		target.armor = 0
	var arrow: Arrow = fixture._primary(main.world, Vector2(280, 150), Vector2(500, 0))
	arrow.stats.gravity = 0
	arrow.stats.crit_chance = 1
	arrow._physics_process(0.03)
	main._refresh()
	main._save_checkpoint()
	await capture("wave-hit")
	check(arrow.critical_stacks == 1 and arrow.area_slots == [1] and main.world.targets[1].hp == 0 and main.world.targets[2].hp == 1000, "real center crit shows radius kill with far target untouched")
	check(main.world.pending_volleys["1"].size() == 2 and arrow.penetration_exits.size() == 1 and arrow.split_pending, "primary and secondary ledger coexist with pending exit/split")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "native dynamic flight checkpoint stored on disk")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.boss_enabled = false
	fixture._freeze(main.world)
	check(JSON.parse_string(JSON.stringify(main.world.snapshot(), "", true, true)) == payload["world"] and main.run.rng.state == int(payload["run"]["rng_state"]), "disk Continue retains exclusions, layers, sources and RNG")
	await capture("continued-flight")
	arrow = main.world.arrows[0]
	arrow._physics_process(0.04)
	fixture._freeze(main.world)
	main._refresh()
	await capture("critical-split")
	check(main.world.arrows.size() == 3 and main.world.arrows[1].critical_stacks == 1 and main.world.arrows[1].penetration_stacks == 1 and main.world.arrows[1].area_slots == [1], "native split children inherit earned critical/exit layers and area exclusion")
	main.run.gold = 100
	main._on_action("skills", null)
	await capture("size-preview")
	check(paused and main.run.skill_comparison(SkillCatalog.find(&"size")).contains("靶心增伤"), "size purchase explains conditional benefit while paused")
	main._on_action("continue", null)
	main._on_action("encounters", null)
	await capture("history")
	var history := main.hud.encounter_panel.find_child("EncounterHistory", true, false) as ScrollContainer
	check(history != null and paused and main.hud.encounter_log_open, "four new conditional explanations appear in native history")
	if history == null:
		quit(1)
		return
	history.scroll_vertical = 10000
	await capture("history-bottom")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("history-small")
	main._on_action("encounter_close", null)
	check(not paused, "history returns to same active build")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	new_field()
	main.world.boss_enabled = true
	var boss_fixture: RefCounted = preload("res://tests/test_boss.gd").new(check)
	boss_fixture.prime(main.run, 100)
	var precision: Array[String] = ["charged_breach", "bullseye_wave", "critical_flow", "broad_precision"]
	fixture._equip(main.run, precision)
	main.run.encounter_picks["windfall"] = 6
	main.run.rebuild_stats()
	main.world._physics_process(0)
	var combat: RefCounted = preload("res://tests/test_boss_combat.gd").new(check)
	arrow = combat.shot(main.world, Vector2(430, 205), Vector2(500, 0), 100, 0, 1)
	main.world.waiting_for_settle = true
	arrow.stats.arrow_size = 6
	arrow.stats.crit_chance = 1
	arrow._physics_process(0.1)
	main._refresh()
	check(main.world.boss.hp == 2880 - 612.5 and main.world.pending_volleys["1"].size() == 1 and main.world.targets.is_empty(), "native broad core crit hits shared Boss HP once and wave adds no victims")
	check(arrow.critical_stacks == 1 and arrow.area_slots.is_empty(), "Boss primary crit is genuine, shield/body cannot duplicate wave")
	await capture("boss-core")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T11-C WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
