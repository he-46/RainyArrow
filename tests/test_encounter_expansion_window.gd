extends SceneTree
## Real rendered choice layouts, button claims, old offers and disk Continue.

var assertions: int = 0
var failures: int = 0
var main: Node
var fixture: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("EXPANDED ENCOUNTERS WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t11a-percent-" + name + ".png") == OK, "capture " + name)

func new_field() -> void:
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process_unhandled_input(false)
	main.world.boss_enabled = false

func mark_traits() -> void:
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait and not main.run.seen_encounters.has(reward.id): main.run.seen_encounters.append(reward.id)

func find_button(parent: Node, text: String) -> Button:
	if parent is Button and (parent as Button).text == text: return parent as Button
	for child: Node in parent.get_children():
		var result: Button = find_button(child, text)
		if result != null: return result
	return null

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_encounter_expansion.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "encounter-expansion-window-test"
	new_field()
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	main.world.arrows[0].set_physics_process(false)
	main.world.arrows[0].position = Vector2(260, 238)
	fixture.entitle(main.run)
	main.run.offer_encounter()
	main.run.choices.assign(fixture.NEW_IDS)
	main._refresh()
	main._save_checkpoint()
	var old: Dictionary = main.world.snapshot()
	await capture("new-choices")
	check(paused and main.hud.encounter_panel.choice_buttons.size() == 3, "new three choices render above a frozen live arrow")
	check(main.run.encounter_comparison(EncounterCatalog.find("steady_power")).contains("24.0 → 36.0") and main.run.encounter_comparison(EncounterCatalog.find("tempered_tip")).contains("0 → 3"), "new effective damage and penetration previews are exact")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("new-choices-small")
	var pick: Button
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == "quick_nock": pick = button
	check(pick != null and not pick.disabled, "percent damage choice has an enabled native button")
	pick.pressed.emit()
	check(not paused and is_equal_approx(main.run.stats.damage, 25.2) and is_equal_approx(main.run.stats.reload_seconds, 0.65) and main.world.snapshot() == old, "native choice adds five percent future damage while live arrow and countdown remain unchanged")
	await capture("damage-claimed")
	check(not main.saves.read().is_empty(), "native claimed gain and live world save together")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	new_field()
	for reward: EncounterData in EncounterCatalog.ALL:
		if not reward.is_trait: main.run.encounter_picks[reward.id] = 2
	fixture.entitle(main.run, 0)
	main.run.rebuild_stats()
	main._on_action("encounters", null)
	await capture("history")
	var history: ScrollContainer = main.hud.encounter_panel.find_child("EncounterHistory", true, false) as ScrollContainer
	check(history != null and main.hud.encounter_log_open and paused, "all six ordinary stacks are available in scrollable native history")
	history.scroll_vertical = 10000
	await capture("history-bottom")
	main._on_action("encounter_close", null)
	new_field()
	fixture.capped(main.run)
	mark_traits()
	main.run.shots_left = 99999
	main.run.encounter_picks["tempered_tip"] = 333333
	main.run.rebuild_stats()
	main.run.offer_encounter()
	await capture("two-choices")
	check(main.hud.encounter_panel.choice_buttons.size() == 2 and main.run.choices.has("tempered_tip") and main.run.choices.has("second_wind"), "two real gains are centered without filler capped options")
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == "tempered_tip": pick = button
	pick.pressed.emit()
	check(not paused and main.run.stats.armor_penetration == 1000000, "last partial penetration gain stops exactly at cap")
	fixture.entitle(main.run)
	main.run.offer_encounter()
	await capture("one-choice")
	check(main.hud.encounter_panel.choice_buttons.size() == 1 and main.run.choices == ["second_wind"], "single gain remains selectable at capped attributes")
	main.hud.encounter_panel.choice_buttons[0].pressed.emit()
	check(main.run.shots_left == 100000 and not paused, "native supply button grants only one available draw")
	fixture.entitle(main.run)
	main.run.offer_encounter()
	main.run.offer_exhausted = false
	main.run.choices.assign(["windfall", "rainfall", "second_wind"])
	main._refresh()
	main._save_checkpoint()
	await capture("old-capped-choices")
	var disabled: bool = true
	for button: Button in main.hud.encounter_panel.choice_buttons: disabled = disabled and button.disabled
	check(disabled and main.run.can_skip_encounter(), "legacy capped three cards remain visible with acknowledgement")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("old-capped-small")
	var skip: Button = find_button(main.hud.encounter_panel, "保持构筑 · 继续射箭")
	check(skip != null, "legacy safe acknowledgement has a native button")
	skip.pressed.emit()
	check(not paused and main.run.pending_encounters == 0, "legacy acknowledgement resumes the same run")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	fixture.entitle(main.run)
	main.run.offer_encounter()
	main._save_checkpoint()
	await capture("exhausted")
	check(main.run.offer_exhausted and main.hud.encounter_panel.choice_buttons.is_empty(), "new exhausted ordinary offer is explicit without forced debuffs")
	var token: int = main.run.encounter_offer_id
	var random_state: int = main.run.rng.state
	var stats: Dictionary = main.run.stats.to_dict()
	main._on_action("hub", null)
	var saved: Dictionary = main.saves.read()
	check(not saved.is_empty() and saved["run"]["offer_exhausted"], "native hub checkpoint preserves exhausted fixed offer")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.boss_enabled = false
	await capture("exhausted-continued")
	check(paused and main.run.offer_exhausted and main.run.encounter_offer_id == token and main.run.rng.state == random_state and main.run.stats.to_dict() == stats, "disk Continue keeps exact exhausted state and high stack history")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("exhausted-small")
	skip = find_button(main.hud.encounter_panel, "保持构筑 · 继续射箭")
	check(skip != null and not skip.disabled, "exhausted small-window acknowledgement stays accessible")
	skip.pressed.emit()
	check(not paused and main.run.pending_encounters == 0 and main.run.stats.to_dict() == stats and main.run.shots_left == 100000, "native acknowledgement resumes without changing capped build or replaying supplies")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("EXPANDED ENCOUNTERS WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
