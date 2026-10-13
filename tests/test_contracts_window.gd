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
		push_error("T17 WINDOW: " + message)

func control(id: String) -> Control:
	return main.find_child(id, true, false) as Control

func click(target: Control) -> void:
	if target == null:
		check(false, "missing click target")
		return
	var point: Vector2 = target.get_global_rect().get_center()
	check(point.x >= 0 and point.x < 1280 and point.y >= 0 and point.y < 720, "control inside logical viewport: " + target.name)
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
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t17-" + name + ".png") == OK, "capture " + name)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "contracts-window-test"
	main._navigate("hub")
	await process_frame
	await click(control("Mode_hard"))
	check(main.router.selected_contracts == ContractCatalog.preset("hard"), "actual preset selects contract composition")
	await click(control("OpenContracts"))
	check(main.router.route == "contracts" and not main.session.has_active_run(), "configure before committing a run")
	for item: Dictionary in ContractCatalog.ALL:
		await click(control(item.id + "_1"))
		check(main.router.selected_contracts.get(item.id) == 1, "select I " + item.id)
		await click(control(item.id + "_2"))
		check(main.router.selected_contracts.get(item.id) == 2, "II replaces I " + item.id)
	await capture("all-contracts")
	root.size = Vector2i(960, 540)
	await process_frame
	await capture("contracts-960")
	await click(control("health_0"))
	check(not main.router.selected_contracts.has("health"), "small window can disable a selected modifier")
	root.size = Vector2i(1280, 720)
	await process_frame
	await click(control("Preset_normal"))
	check(main.router.selected_contracts.is_empty(), "ordinary preset clears contracts")
	await click(control("Preset_hell"))
	check(main.router.selected_contracts == ContractCatalog.preset("hell"), "Hell shortcut is editable preset")
	await click(control("Preset_normal"))
	for pair: Array in [["health", 1], ["boss", 2], ["quiver", 1], ["prices", 1], ["slots", 2], ["bullseye", 2]]:
		await click(control(pair[0] + "_" + str(pair[1])))
	var selected: Dictionary = main.router.selected_contracts.duplicate()
	await capture("custom-contracts")
	await click(control("ContractsStart"))
	check(main.router.route == "range" and main.run.challenge.selection == selected and main.run.initial_shots == 8 and main.run.artifact_capacity == 4 and main.world.targets[0].max_hp == 60, "start commits actual selected rules to battlefield")
	await capture("range")
	await click(main.hud.encounters_button)
	check(main.hud.encounter_panel.find_child("ArtifactSlots", true, false).get_child_count() == 4, "backpack renders four restricted slots")
	await capture("four-slots")
	await click(control("CloseBackpack"))
	main._on_action("hub", null)
	await process_frame
	await capture("locked-hub")
	await click(control("OpenContracts"))
	for item: Dictionary in ContractCatalog.ALL:
		for rank: int in [0, 1, 2]:
			check((control(item.id + "_" + str(rank)) as Button).disabled, "locked category button " + item.id + str(rank))
	await click(control("health_2"))
	main._on_action("contract_select", {"id": "health", "rank": 2})
	check(main.run.challenge.selection == selected and main.router.selected_contracts == selected, "disabled clicks and stale action cannot alter active run")
	await capture("locked-contracts")
	await click(control("ContractsStart"))
	check(main.run.shots_left == 8 and not main.run.suspended, "resume does not create a different challenge")
	main.world.set_physics_process(false)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty() and ContractCatalog.normalize(payload.run.challenge.selection) == selected and payload.run.shots_left == 7 and payload.world.arrows.size() == 1, "actual UI checkpoints live flight and locked contract")
	var challenge: Dictionary = main.run.challenge
	main.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "contracts-window-test"
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("resume_hub", null)
	await process_frame
	await click(control("OpenContracts"))
	check(main.run.challenge == challenge and (control("Preset_normal") as Button).disabled, "fresh scene opens continued immutable contract")
	await click(control("ContractsStart"))
	check(main.world.arrows.size() == 1 and main.world.targets[0].max_hp == 60 and main.run.shots_left == 7, "continued flight uses same target health and draws")
	main.session.record_defeat("ui-rank", 40, 8)
	main.session.end_run("abandoned")
	main._on_action("leaderboard", null)
	await process_frame
	check(main.session.profile.leaderboard.entries.size() == 1 and main.session.profile.leaderboard.entries[0].challenge == challenge, "UI completion records challenge in top three")
	await capture("leaderboard")
	await click(control("Rank1"))
	check(control("CloseRecord") != null, "click rank opens details")
	await capture("record-details")
	await click(control("CloseRecord"))
	check(control("CloseRecord") == null, "record closes")
	main._on_action("new_run", null)
	check(main.run.challenge == challenge and main.run.shots_left == 8, "retry keeps contract composition and resets draws")
	main.run.shots_left = 0
	main.run.settle_volley()
	await capture("result")
	main._new_run("hell", null, true)
	main._on_action("hub", null)
	await process_frame
	await click(control("OpenContracts"))
	check(main.run.challenge.is_empty() and main.run.mode_parameters.score == 2 and (control("boss_2") as Button).disabled, "legacy Hell is inspectable and cannot be changed")
	await capture("legacy-contracts")
	main.queue_free()
	paused = false
	await process_frame
	await create_timer(0.1).timeout
	print("T17 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
