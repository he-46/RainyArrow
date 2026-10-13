extends SceneTree

var failures: int = 0
var assertions: int = 0
var main: Node
var fixture: RefCounted
var mastery_test: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T12-A WINDOW: " + message)

func equip(ids: Array[String]) -> void:
	fixture._equip(main.run, ids)

func freeze() -> void:
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.boss_enabled = false
	main.world.set_process_unhandled_input(false)
	fixture._freeze(main.world)

func new_field() -> void:
	main._new_run()
	freeze()

func skill_button(id: String) -> Button:
	return main.hud.content.get_child(2).get_node(NodePath(id)) as Button

func capture(name: String, shop: bool = true) -> void:
	main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if shop:
		for button: Button in main.hud.content.get_child(2).get_children():
			var font: Font = button.get_theme_font("font")
			var size: int = button.get_theme_font_size("font_size")
			var fits: bool = true
			for line: String in button.text.split("\n"):
				fits = fits and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= button.size.x - 20
			check(fits and button.text.split("\n").size() * font.get_height(size) <= button.size.y - 14, "skill card text fits: " + name + "/" + str(button.name))
		check(main.hud.content.get_global_rect().end.y <= main.hud.phase_card.get_global_rect().end.y - 16, "return button and all cards contained: " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t12a-" + name + ".png") == OK, "capture " + name)

func small_capture(name: String, shop: bool = true) -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture(name, shop)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_traits.gd").new(check)
	mastery_test = preload("res://tests/test_mastery.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "mastery-window-test"
	new_field()
	main.run.gold = 1000
	main._on_action("skills", null)
	await capture("basic-skills")
	check(not skill_button("damage").text.contains("精通") and paused, "ordinary six base skills remain recognizable and pause")
	main._on_action("continue", null)
	mastery_test.full(main.run)
	equip(["piercing_split", "branch_harvest", "branch_ricochet", "broad_precision"])
	main.run.gold = 1000000
	for index: int in range(main.world.targets.size()):
		var target: ArcheryTarget = main.world.targets[index]
		target.anchor = Vector2(300 + 90 * index, 150)
		target.tick(0, 0)
		target.hp = 1000
		target.max_hp = 1000
		target.armor = 0
	main.world.reload_left = 0.31
	var parent: Arrow = fixture._primary(main.world, Vector2(280, 150), Vector2(500, 0))
	var frozen: Dictionary = parent.snapshot()
	main._on_action("skills", null)
	await capture("mastery-entry")
	await small_capture("mastery-entry-small")
	for skill: RunSkillData in SkillCatalog.ALL:
		var preview: Dictionary = main.run.preview_skill(skill).to_dict()
		var wallet: int = main.run.gold
		var price: int = main.run.skill_price(skill)
		var button: Button = skill_button(String(skill.id))
		check(not button.disabled and button.text.contains("精通 0/100"), "native first mastery available: " + String(skill.id))
		button.pressed.emit()
		check(main.run.mastery_levels[String(skill.id)] == 1 and main.run.gold == wallet - price and main.run.stats.to_dict() == preview, "native purchase matches shown cost and effect: " + String(skill.id))
		check(parent.snapshot() == frozen and main.world.reload_left == 0.31 and paused, "native purchase preserves old arrow and reload: " + String(skill.id))
	await capture("mastery-bought")
	await small_capture("mastery-bought-small")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty() and payload["run"]["mastery_levels"].size() == 6, "hub atomically saves all six purchases and frozen projectile")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	freeze()
	check(paused and main.run.mastery_levels.size() == 6 and main.world.arrows[0].snapshot() == frozen and main.world.reload_left == 0.31 and main.run.rng.state == int(payload["run"]["rng_state"]), "native disk Continue restores paused mastery and exact old flight/RNG")
	await capture("continued-masteries")
	main._on_action("continue", null)
	parent = main.world.arrows[0]
	parent._physics_process(0.13)
	freeze()
	check(main.world.arrows.size() == 3 and main.world.arrows[1].stats.damage == float(frozen["stats"]["damage"]) * 0.5 and main.world.arrows[1].remaining_bounces == 8, "real old mother splits using old half damage and frozen child bounce budget")
	await capture("old-split", false)
	main.world.reload_left = 0
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	freeze()
	check(main.world.arrows.size() == 10 and main.world.arrows[3].stats.to_dict() == main.run.stats.to_dict() and main.run.shots_left == 8, "new real seven-arrow volley samples mastery and spends one draw")
	main._refresh()
	await capture("new-volley", false)
	main._on_action("encounters", null)
	await capture("mastery-history", false)
	check(main.hud.encounter_log_open and paused, "mastery source explanation appears in paused encounter history")
	main._on_action("continue", null)
	new_field()
	mastery_test.full(main.run)
	equip(["unified_arrow", "swarm_precision", "critical_forging", "critical_ricochet", "slender_gale", "heavy_draw", "broad_precision"])
	main.run.gold = 1000000
	main._on_action("skills", null)
	await capture("converted-masteries")
	await small_capture("converted-masteries-small")
	check(skill_button("critical").text.contains("穿甲") and skill_button("critical").text.contains("反弹"), "conversion mastery card shows real effective gains")
	new_field()
	main.run.skill_levels = {"quantity": 6, "size": 1}
	main.run.encounter_picks["rainfall"] = 100
	equip(["unified_arrow"])
	main.run.gold = 1000000
	main._on_action("skills", null)
	await capture("capped-basic")
	await small_capture("capped-basic-small")
	check(skill_button("size").text.contains("精通") and skill_button("size").text.contains("初速") and not skill_button("size").disabled, "capped low-rank size offers real speed mastery without empty purchase")
	skill_button("size").pressed.emit()
	check(main.run.skill_levels["size"] == 1 and main.run.mastery_levels["size"] == 1 and main.run.mastery_unlocks.has("size"), "early cap mastery persists access without altering base rank")
	new_field()
	mastery_test.full(main.run)
	main.run.encounter_picks["steady_power"] = 1000000
	equip([])
	main.run.gold = 1000000
	main._on_action("skills", null)
	await capture("no-gain")
	check(skill_button("damage").disabled and skill_button("damage").text.contains("暂无有效收益"), "fully capped damage is disabled with explicit no-gain reason")
	new_field()
	mastery_test.full(main.run)
	for skill: RunSkillData in SkillCatalog.ALL:
		main.run.mastery_unlocks.append(String(skill.id))
		main.run.mastery_levels[String(skill.id)] = 90
	main.run.rebuild_stats()
	main.run.gold = 0
	main._on_action("skills", null)
	await capture("late-prices")
	await small_capture("late-prices-small")
	check(skill_button("damage").disabled and skill_button("damage").text.contains("亿") and skill_button("damage").tooltip_text.contains("1000000000"), "late compact prices fit while tooltip preserves exact billion-coin cost")
	for skill: RunSkillData in SkillCatalog.ALL: main.run.mastery_levels[String(skill.id)] = 100
	main.run.rebuild_stats()
	main._refresh()
	await capture("mastery-max")
	check(skill_button("quantity").disabled and skill_button("quantity").text.contains("精通已满"), "bounded mastery maximum has explicit disabled state")
	main.queue_free()
	paused = false
	await process_frame
	await create_timer(0.2).timeout
	print("T12-A WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
