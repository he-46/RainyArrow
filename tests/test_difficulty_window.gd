extends SceneTree

var main: Node
var bosses: RefCounted
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T14-A WINDOW: " + message)

func freeze() -> void:
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.set_process_unhandled_input(false)
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)

func mode_button(id: String) -> Button:
	return main.router.page.get_node(NodePath("Mode_" + id)) as Button

func click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
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

func capture(name: String) -> void:
	if main.world != null: main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if main.router.route == "hub":
		for id: String in ["normal", "hard", "hell"]:
			var button: Button = mode_button(id)
			check(button.get_global_rect().end.y < 248 and button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x <= button.size.x - 20, "mode button stays above cards and text fits " + name + "/" + id)
		var copy: Label = main.router.page.get_node("ModeDescription") as Label
		check(copy.get_global_rect().end.x <= 1230 and copy.get_global_rect().end.y < 248, "mode explanation contained " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t14a-" + name + ".png") == OK, "capture " + name)

func small(name: String) -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture(name)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout

func restore() -> void:
	main._on_action("hub", null)
	var data: Dictionary = main.saves.read()
	check(not data.is_empty(), "native mode checkpoint valid")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(data)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main.router.continue_button.pressed.emit()
	main._on_action("range", null)
	freeze()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	bosses = preload("res://tests/test_boss.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "difficulty-window-test"
	main._on_action("start", null)
	check(main.run == null and main.world == null and main.router.selected_mode == "normal", "new campaign reaches selection without constructing a run")
	for id: String in ["normal", "hard", "hell"]:
		if main.run != null: main._start_to_hub()
		await process_frame
		await click(mode_button(id))
		check(main.router.selected_mode == id and not main.session.has_active_run(), "real mode mouse choice selects new-run mode " + id)
		await capture("hub-" + id)
		if id == "hell": await small("hub-hell-small")
		main._on_action("range", null)
		freeze()
		check(main.run.mode_id == id and main.run.shots_left == 10 and main.run.gold == 0 and main.run.defeated_count == 0, "new run locks mode and starts clean " + id)
		check(main.world.targets[0].max_hp == (48 if id == "normal" else 72) and main.world.targets[0].reward_score == (40 if id == "normal" else (60 if id == "hard" else 80)), "real field starts with correct HP and score " + id)
		check(main.hud.mode_label.text.contains(DifficultyCatalog.title(id)), "HUD displays current mode " + id)
		await capture("field-" + id)
		# Prepare a real uncompleted volley and a previously injured target.
		main.world.boss_enabled = false
		var target: ArcheryTarget = main.world.targets[0]
		target.anchor = Vector2(180, 238)
		target.hp = target.max_hp * 0.5
		target.tick(0, 0)
		for index: int in range(1, main.world.targets.size()):
			main.world.targets[index].anchor = Vector2(350 + 80 * index, 100)
			main.world.targets[index].tick(0, 0)
		bosses.fire(main.world, 1000, 3)
		main.world.reload_left = 0.25
		main._on_action("skills", null)
		var snapshot: Dictionary = main.world.snapshot()
		var seed: int = main.run.rng.state
		main._on_action("hub", null)
		check(mode_button("normal").disabled and mode_button("hard").disabled and mode_button("hell").disabled, "all mode choices are locked in active hub " + id)
		main._on_action("mode_select", "hell" if id != "hell" else "normal")
		check(main.run.mode_id == id and main.router.selected_mode == id, "hidden mode action cannot change current adventure " + id)
		await capture("locked-" + id)
		await restore()
		check(main.run.mode_id == id and main.world.snapshot() == snapshot and main.run.rng.state == seed and main.run.phase == RunModel.Phase.SHOP and paused, "Continue preserves mode, damage, flight, reload and paused shop " + id)
		check(main.world.targets[0].max_hp == (48 if id == "normal" else 72), "continued injured target retains original maxHP " + id)
		await capture("continued-" + id)
		var before: float = main.session.profile.total_score
		main._on_action("continue", null)
		freeze()
		main.world.boss_enabled = false
		bosses.tick(main.world, 220)
		var points: float = 40 * float(main.run.mode_parameters["score"])
		check(main.run.defeat_score == points and main.session.profile.total_score == before + points and main.run.gold == 8 and main.run.defeated_count == 1, "continued real volley pays one score/XP, unchanged8gold " + id)
		var grown: ArcheryTarget = main.world.targets[0]
		grown.respawn_left = 0
		main.world._physics_process(0)
		check(grown.generation == 1 and grown.max_hp == ArcheryTarget.RULES.target_values(grown.definition, 1, main.run.mode_parameters)["max_hp"], "native replacement samples mode-specific linear growth " + id)
		main.run.rebuild_stats()
		main._refresh()
		await capture("grown-" + id)
		if id == "hard":
			grown.anchor = Vector2(180, 238)
			grown.tick(0, 0)
			bosses.fire(main.world, 1000, 3)
			bosses.tick(main.world, 220)
			points += 64.5
			main.run.rebuild_stats()
			main._refresh()
			check(main.run.defeat_score == points and main.hud.stats_label.text.ends_with("得分 124.5") and main.hud.score_label.text.contains(".5"), "hard second real kill preserves and displays half-point score/XP")
			await capture("score-half-hard")
		# Trigger a real mode Boss, preserve second-stage motion on disk, defeat it.
		bosses.prime(main.run, 100)
		main.world.boss_enabled = true
		main.world._physics_process(0)
		check(main.world.targets.is_empty() and main.world.boss.max_hp == (2880 if id == "normal" else 5760), "native hundred-kill Boss follows mode HP " + id)
		main.world.boss.hp = main.world.boss.max_hp * 0.4
		main.world.boss.refresh_phase()
		main.world.boss.tick(0.47, 0)
		await capture("boss-phase2-" + id)
		var boss_state: Dictionary = main.world.snapshot()
		await restore()
		var restored_boss_state: Dictionary = main.world.snapshot()
		# JSON may round the final clock bit after 440 increments of 1/120.
		check(absf(float(restored_boss_state["clock"]) - float(boss_state["clock"])) <= 0.000000000001, "Boss clock stays within serialization precision " + id)
		restored_boss_state["clock"] = boss_state["clock"]
		check(main.run.mode_id == id and restored_boss_state == boss_state and main.world.boss.battle_phase == 2, "native phase2 Continue preserves injured life and moving shield " + id)
		var expected: float = points + 1200 * float(main.run.mode_parameters["score"])
		bosses.fire(main.world, 100000, 3, 1000)
		bosses.tick(main.world, 220)
		check(main.run.phase == RunModel.Phase.CHOICE and main.run.defeat_score == expected and main.run.boss_reward_log[0]["score"] == expected - points and main.run.boss_reward_log[0]["gold"] == 840, "native Boss victory logs one multiplied score and unchanged gold " + id)
		main.run.rebuild_stats()
		main._refresh()
		await capture("boss-reward-" + id)
		var choice: String = ""
		for reward: String in main.run.choices:
			if EncounterCatalog.find(reward).draws == 0: choice = reward; break
		main._on_action("encounter_pick", {"id": choice, "offer_id": main.run.encounter_offer_id})
		main.world._physics_process(0)
		check(main.world.targets.size() == 3 and main.run.mode_id == id and main.run.supply_remaining() == 2, "victory returns to same mode and restores supply budget " + id)
		main.run.shots_left = 0
		main.world._physics_process(0)
		check(main.run.phase == RunModel.Phase.SUPPLY, "mode run uses existing affordable supply decision " + id)
		main._on_action("supply_end", main.run.supply_offer_id)
		check(main.run.is_finished() and main.session.last_run_summary["mode_id"] == id and main.session.last_run_summary["defeat_score"] == expected, "native terminal summary retains mode and score " + id)
		await capture("result-" + id)
		if id == "hell": await small("result-hell-small")
	# Active-mode replacement follows the existing concrete confirmation flow.
	main._new_run("hard")
	freeze()
	main._on_action("hub", null)
	main._on_action("start", null)
	var dialog: ConfirmationDialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	check(dialog != null and main.run.mode_id == "hard", "new adventure asks before abandoning active difficulty")
	dialog.canceled.emit()
	await process_frame
	check(main.session.has_active_run() and main.run.mode_id == "hard", "cancel preserves current mode")
	main._on_action("start", null)
	dialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	dialog.confirmed.emit()
	await process_frame
	check(not main.session.has_active_run() and not mode_button("hell").disabled and main.world == null, "confirmed replacement unlocks selection before new world")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T14-A WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
