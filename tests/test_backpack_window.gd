extends SceneTree

var main: Node
var assertions: int = 0
var failures: int = 0
var fixture: RefCounted

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T16 WINDOW: " + message)

func button(id: String) -> Button:
	return main.hud.encounter_panel.find_child(id, true, false) as Button

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
	check(root.get_texture().get_image().save_png("res://artifacts/t16-" + name + ".png") == OK, "capture " + name)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_backpack.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "backpack-window-test"
	main._new_run()
	await process_frame
	await click(main.hud.encounters_button)
	check(paused and main.hud.encounter_log_open and main.hud.encounter_panel.find_child("ArtifactSlots", true, false).get_child_count() == 6, "real HUD opens paused six empty slots")
	await capture("empty-backpack")
	await click(button("CloseBackpack"))
	check(not paused and not main.hud.encounter_log_open, "close resumes field")
	fixture.equip(main.run, fixture.SIX)
	main.run.skill_levels = {"quantity": 3, "critical": 2, "penetration": 2, "ricochet": 2, "size": 2}
	main.run.gold = 10000
	main.run.rebuild_stats()
	main._refresh()
	await click(main.hud.encounters_button)
	check(main.run.artifact_ids().size() == 6 and paused, "full six slots shown")
	for id: String in fixture.SIX:
		check(main.hud.encounter_panel.history_scroll.get_global_rect().encloses(button("Upgrade_" + id).get_global_rect()), "both rows have fully visible controls " + id)
	await capture("full-backpack")
	var wallet: int = main.run.gold
	var price: int = TraitUpgradeCatalog.find("critical_forging").price(0)
	await click(button("Upgrade_critical_forging"))
	check(main.run.trait_rank("critical_forging") == 1 and main.run.gold == wallet - price, "actual upgrade click spends price and retains inventory")
	var before: Dictionary = main.run.to_dict()
	await click(button("Discard_critical_forging"))
	check(button("ConfirmArtifact") != null and main.run.to_dict() == before, "discard opens review before mutation")
	await capture("discard-confirmation")
	await click(button("CancelArtifact"))
	check(main.run.to_dict() == before and button("ConfirmArtifact") == null, "cancel preserves all state")
	await click(button("Discard_critical_forging"))
	await click(button("ConfirmArtifact"))
	check(main.run.artifact_ids().size() == 5 and main.run.discarded_artifacts.get("critical_forging") == 1 and main.run.gold == wallet - price and main.run.stats.crit_chance > 0, "confirmed discard restores converted crit without refund")
	check(main.saves.read().run.discarded_artifacts.critical_forging == 1, "UI discard persists immediately")
	await capture("discarded-backpack")
	await click(button("CloseBackpack"))
	fixture.offer(main.run, "heavy_draw")
	main._refresh()
	await process_frame
	await click(button("heavy_draw"))
	check(main.run.artifact_ids().size() == 6 and main.run.encounter_picks.has("heavy_draw"), "ordinary encounter equips empty slot directly")
	fixture.offer(main.run, "echo_strike")
	main._refresh()
	await process_frame
	var choices: Array[String] = main.run.choices.duplicate()
	var rng_state: int = main.run.rng.state
	await capture("full-choice")
	await click(button("echo_strike"))
	check(button("Replace_unified_arrow") != null and main.run.choices == choices, "full choice opens outgoing item selection without consuming it")
	await capture("replacement-list")
	await click(button("BackToChoices"))
	check(main.run.rng.state == rng_state and main.run.choices == choices, "back never rerolls offer")
	await click(button("echo_strike"))
	await click(button("Replace_unified_arrow"))
	await capture("replacement-confirmation")
	var expected: Dictionary = main.run.preview_artifact_change("unified_arrow", "echo_strike").to_dict()
	await click(button("ConfirmArtifact"))
	check(main.run.encounter_picks.has("echo_strike") and main.run.discarded_artifacts.has("unified_arrow") and main.run.artifact_ids().size() == 6 and main.run.stats.to_dict() == expected, "actual replacement is atomic with exact preview")
	check(main.run.phase == RunModel.Phase.PLAYING and not paused and main.run.rng.state == rng_state, "replacement resumes play with RNG unchanged")
	await click(main.hud.encounters_button)
	await capture("replaced-backpack")
	root.size = Vector2i(960, 540)
	await process_frame
	await capture("backpack-960")
	check(main.hud.encounter_panel.history_scroll.get_global_rect().encloses(button("Discard_echo_strike").get_global_rect()), "small window keeps logical controls in viewport")
	root.size = Vector2i(1280, 720)
	await process_frame
	await wheel(true, 16)
	check(main.hud.encounter_panel.history_scroll.scroll_vertical > 0, "history and calculations reachable by real wheel")
	await capture("history")
	await wheel(false, 30)
	await click(button("CloseBackpack"))
	main._navigate("hub")
	var saved: Dictionary = main.saves.read()
	check(not saved.is_empty() and saved.run.discarded_artifacts.size() == 2, "hub checkpoint retains both discarded items")
	main.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "backpack-window-test"
	# Test mode ignores player saves. Inject the payload read from disk before recreating main.
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	await process_frame
	await click(main.hud.encounters_button)
	check(main.run.artifact_ids().size() == 6 and main.run.discarded_artifacts.size() == 2 and button("Upgrade_echo_strike") != null and button("Upgrade_unified_arrow") == null, "recreated composition restores inventory without deleted effects")
	await capture("continued-backpack")
	main.queue_free()
	await process_frame
	paused = false
	await create_timer(0.1).timeout
	print("T16 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
