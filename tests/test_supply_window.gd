extends SceneTree

var assertions: int = 0
var failures: int = 0
var main: Node
var bosses: RefCounted
var traits: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T13 WINDOW: " + message)

func freeze() -> void:
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.set_process_unhandled_input(false)
	main.world.boss_enabled = false
	traits._freeze(main.world)

func new_field() -> void:
	main._new_run()
	freeze()

func button(name: String) -> Button:
	return main.hud.content.find_child(name, true, false) as Button

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame

func capture(name: String, overlay: bool = true) -> void:
	main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if overlay:
		check(main.hud.content.get_global_rect().end.y <= main.hud.phase_card.get_global_rect().end.y - 16, "all content remains inside modal: " + name)
		if main.run.phase == RunModel.Phase.SHOP:
			for skill: Button in main.hud.content.get_child(2).get_children():
				var font: Font = skill.get_theme_font("font")
				var size: int = skill.get_theme_font_size("font_size")
				var fits: bool = true
				for line: String in skill.text.split("\n"):
					fits = fits and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= skill.size.x - 20
				check(fits and skill.text.split("\n").size() * font.get_height(size) <= skill.size.y - 14, "skill text fits: " + name + "/" + str(skill.name))
		var buy: Button = button("SupplyBuy")
		if buy != null:
			check(buy.get_theme_font("font").get_string_size(buy.text, HORIZONTAL_ALIGNMENT_LEFT, -1, buy.get_theme_font_size("font_size")).x <= buy.size.x - 20, "supply label fits " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t13-" + name + ".png") == OK, "capture " + name)

func small(name: String) -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture(name)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout

func restore() -> void:
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "native checkpoint is readable")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	check(not main.router.continue_button.disabled, "unfinished supply decision permits Continue")
	main.router.continue_button.pressed.emit()
	main._on_action("range", null)
	freeze()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	bosses = preload("res://tests/test_boss.gd").new(check)
	traits = preload("res://tests/test_traits.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "supply-window-test"
	new_field()
	main.run.gold = 200
	main.run.gold_earned = 200
	main._on_action("skills", null)
	await capture("skills-first")
	check(paused and not button("SupplyBuy").disabled and button("SupplyBuy").text.contains("24 金"), "skills shows affordable configured first supply")
	var token: Dictionary = main.run.supply_token()
	await click(button("SupplyBuy"))
	check(main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS + 1 and main.run.gold == 176 and main.run.gold_spent == 24 and paused, "real mouse purchase adds one draw for24 while shop stays paused")
	main._on_action("supply_buy", token)
	check(main.run.gold == 176 and main.run.supply_total_bought == 1, "native duplicate request cannot repeat charge")
	await capture("skills-bought")
	await click(button("SupplyBuy"))
	await capture("skills-limit")
	check(button("SupplyBuy").disabled and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS + 2 and main.run.gold_spent == 63, "second mouse purchase closes this segment allowance")
	await restore()
	check(paused and main.run.phase == RunModel.Phase.SHOP and main.run.supply_remaining() == 0 and main.run.supply_price() == 62 and main.run.gold == 137, "real Continue cannot reset quota, cumulative price or expense")
	for skill: RunSkillData in SkillCatalog.ALL: main.run.skill_levels[String(skill.id)] = skill.max_level
	main.run.rebuild_stats()
	main._refresh()
	await capture("mastery-and-supply")
	await small("mastery-and-supply-small")
	# A live Boss defeat earns a new segment, then its choice is handled normally.
	main._on_action("continue", null)
	bosses.prime(main.run, 100)
	main.world.boss_enabled = true
	main.world._physics_process(0)
	main.run.shots_left = 1
	bosses.fire(main.world, 100000, 3)
	bosses.tick(main.world, 220)
	check(main.run.phase == RunModel.Phase.CHOICE and main.run.bosses_defeated == 1 and main.run.supply_remaining() == 2 and main.run.supply_price() == 62, "live Boss victory restores only budget before pending reward")
	main.run.rebuild_stats()
	main._refresh()
	await capture("boss-reward", false)
	var selected: String = ""
	for id: String in main.run.choices:
		if EncounterCatalog.find(id).draws == 0: selected = id; break
	main._on_action("encounter_pick", {"id": selected, "offer_id": main.run.encounter_offer_id})
	main.world._physics_process(0)
	main._on_action("skills", null)
	await capture("boss-new-budget")
	check(not button("SupplyBuy").disabled and button("SupplyBuy").text.contains("62 金"), "victory segment shows higher third price")
	await click(button("SupplyBuy"))
	check(main.run.supply_remaining() == 1 and main.run.gold_spending["supplies"] == 125 and main.run.supply_price() == 99, "victory purchase charges third price once")
	await restore()
	check(main.run.supply_remaining() == 1 and main.run.supply_segment == 1 and main.run.supply_price() == 99, "victory allowance is checkpointed without replay")
	# A real final draw expires at the left boundary and opens the decision.
	new_field()
	main.run.gold = 100
	main.run.gold_earned = 100
	main.run.shots_left = 1
	main.world.direction = Vector2.LEFT
	main.world.pull = 1
	main.world._release()
	freeze()
	check(main.run.shots_left == 0 and main.run.phase == RunModel.Phase.PLAYING and not main.world.arrows.is_empty(), "last draw remains playable until physical projectile finishes")
	bosses.tick(main.world, 220)
	check(main.run.phase == RunModel.Phase.SUPPLY and paused and main.world.is_settled(), "real zero-draw decision freezes settled world")
	await capture("last-draw-choice")
	await small("last-draw-choice-small")
	var snapshot: Dictionary = main.world.snapshot()
	var offer: int = main.run.supply_offer_id
	await restore()
	var restored_snapshot: Dictionary = main.world.snapshot()
	# 24 increments of 1/120 serialize 0.19999999999999998 as0.2 (one ULP).
	check(absf(float(restored_snapshot["clock"]) - float(snapshot["clock"])) <= 0.000000000001, "world clock differs by at most serialization precision")
	restored_snapshot["clock"] = snapshot["clock"]
	check(paused and main.run.phase == RunModel.Phase.SUPPLY and main.run.supply_offer_id == offer and restored_snapshot == snapshot, "Continue restores exact final-draw decision and world")
	main._save_checkpoint()
	check(main.save_notice.is_empty() and not main.saves.read().is_empty(), "continued decision can checkpoint immediately without re-marking settlement")
	await capture("last-draw-continued")
	await click(button("SupplyBuy"))
	check(not paused and main.run.phase == RunModel.Phase.PLAYING and main.run.shots_left == 1 and main.run.gold == 76 and main.run.gold_spent == 24, "mouse choice pays once and resumes combat")
	await capture("last-draw-rescued", false)
	main.run.shots_left = 0
	main.world._physics_process(0)
	await capture("second-choice")
	var formal: Dictionary = main.run.to_dict()
	main._on_action("tutorial", null)
	var lesson: TutorialController = main.tutorial
	lesson.world.set_physics_process(false)
	lesson.step = TutorialController.Step.UPGRADE
	lesson.run.gold = 24
	lesson._on_action("skills", null)
	check(lesson.page.hud.content.find_child("SupplyBuy", true, false) == null, "unlimited practice shows no inert formal supply button")
	await capture("tutorial-skills", false)
	check((lesson.page.hud.content.get_child(lesson.page.hud.content.get_child_count() - 1) as Control).get_global_rect().end.y < lesson.page.coach.position.y, "tutorial shop content clears coaching panel")
	main._on_action("back", null)
	check(main.run.to_dict() == formal and main.run.phase == RunModel.Phase.SUPPLY and paused, "tutorial return retains formal supply decision and wallet")
	await click(button("SupplyEnd"))
	check(main.run.is_finished() and main.run.gold == 0 and main.session.last_run_summary["gold_spent"] == 24 and main.session.last_run_summary["gold_discarded"] == 76, "explicit mouse End clears wallet and preserves ledger")
	await capture("result-declined")
	await small("result-declined-small")
	main._on_action("hub", null)
	main._on_action("home", null)
	check(main.router.continue_button.disabled, "completed decision cannot be continued or revived")
	new_field()
	main.run.gold = 23
	main.run.gold_earned = 23
	main.run.shots_left = 0
	main.world._physics_process(0)
	check(main.run.is_finished() and main.run.supply_offer_id == 0, "insufficient gold takes direct result path")
	await capture("result-poor")
	new_field()
	main.run.gold = 1000000000
	main.run.gold_earned = 1000000000
	main._on_action("skills", null)
	main._on_action("supply_buy", main.run.supply_token())
	main._on_action("supply_buy", main.run.supply_token())
	main._on_action("continue", null)
	main.run.shots_left = 0
	main.world._physics_process(0)
	check(main.run.is_finished() and main.run.supply_offer_id == 0 and main.run.gold_spent == 63, "exhausted allowance ends directly despite huge wallet")
	await capture("result-limit")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T13 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
