extends SceneTree

var assertions: int = 0
var failures: int = 0
var main: Node
var suite: RefCounted
var base: RefCounted
var bosses: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T12-B WINDOW: " + message)

func freeze() -> void:
	main.world.boss_enabled = false
	main.world.set_process(false)
	main.world.set_physics_process(false)
	main.world.set_process_unhandled_input(false)
	base._freeze(main.world)

func equip(ids: Array[String]) -> void:
	suite.viable(main.run)
	suite.equip(main.run, ids)

func upgrade_button(id: String) -> Button:
	return main.hud.find_child("Upgrade_" + id, true, false) as Button

func capture(name: String) -> void:
	main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var overlay: EncounterPanel = main.hud.encounter_panel as EncounterPanel
	if overlay != null:
		for label: Node in overlay.find_children("Comparison", "Label", true, false):
			check(label.get_minimum_size().y <= 56, "choice comparison stays inside card " + name)
		for button: Button in overlay.choice_buttons:
			var font: Font = button.get_theme_font("font")
			check(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x < button.size.x - 12, "choice caption fits " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t12b-" + name + ".png") == OK, "capture " + name)

func small(name: String) -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture(name)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	suite = preload("res://tests/test_trait_upgrades.gd").new(check)
	base = suite.base
	bosses = suite.bosses
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "trait-upgrades-window-test"
	main._new_run()
	freeze()
	equip(["piercing_split", "branch_harvest", "branch_ricochet", "charged_breach", "bullseye_wave", "ricochet_haste", "wall_forging", "echo_strike", "piercing_edge", "armor_surplus", "critical_flow", "broad_precision"])
	main.world.boss_enabled = false
	main.run.gold = 1000000
	for i: int in range(main.world.targets.size()):
		var target: ArcheryTarget = main.world.targets[i]
		target.anchor = Vector2(300 + 90 * i, 150)
		target.tick(0, 0)
		target.hp = 10000
		target.max_hp = 10000
		target.armor = 0
	var parent: Arrow = base._primary(main.world, Vector2(280, 150), Vector2(500, 0))
	var frozen: Dictionary = parent.snapshot()
	main.world.reload_left = 0.31
	main._on_action("encounters", null)
	await capture("upgrade-entry")
	await small("upgrade-entry-small")
	check(paused and main.run.trait_shop_open and upgrade_button("piercing_split") != null, "history exposes real trait purchase while paused")
	for id: String in main.run.encounter_picks:
		var button: Button = upgrade_button(id)
		var wallet: int = main.run.gold
		var price: int = TraitUpgradeCatalog.find(id).price(0)
		check(button != null and not button.disabled, "native selected upgrade available: " + id)
		button.pressed.emit()
		button.pressed.emit()
		check(main.run.trait_rank(id) == 1 and main.run.gold == wallet - price and parent.snapshot() == frozen and main.world.reload_left == 0.31 and paused, "native purchase/stale duplicate/frozen arrow: " + id)
		await process_frame
	main.hud.encounter_panel.history_scroll.scroll_vertical = 500
	await process_frame
	var scrolled: int = main.hud.encounter_panel.history_scroll.scroll_vertical
	var second_price: int = TraitUpgradeCatalog.find("charged_breach").price(1)
	var second_wallet: int = main.run.gold
	upgrade_button("charged_breach").pressed.emit()
	await process_frame
	await process_frame
	check(main.run.trait_rank("charged_breach") == 2 and main.run.gold == second_wallet - second_price and main.hud.encounter_panel.history_scroll.scroll_vertical == scrolled, "real second rank keeps scrolled list at same position")
	await capture("upgrades-scrolled")
	main.hud.encounter_panel.history_scroll.scroll_vertical = 0
	await capture("upgrades-bought")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "upgraded world commits on lobby transition")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	freeze()
	check(main.run.trait_levels.size() == 12 and main.world.arrows[0].effects.split_damage == 0.5 and main.world.reload_left == 0.31, "disk Continue preserves selected ranks and old mother/reload")
	main._on_action("encounters", null)
	await capture("continued-upgrades")
	main._on_action("encounter_close", null)
	parent = main.world.arrows[0]
	parent._physics_process(0.13)
	freeze()
	check(main.world.arrows.size() == 3 and main.world.arrows[1].effects.child_gold_bonus == 0.5 and main.world.arrows[1].effects.child_bounces == 2, "continued old mother splits with old benefits")
	await capture("old-split")
	main.world.reload_left = 0
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	freeze()
	check(main.world.arrows.back().effects.split_damage == 0.6 and main.world.arrows.back().effects.child_gold_bonus == 0.75 and main.run.shots_left == 8, "next native release uses upgraded parameters at one draw cost")
	await capture("new-volley")
	main._on_action("encounters", null)
	main.run.gold = 0
	main._refresh()
	await capture("insufficient-gold")
	check(upgrade_button("piercing_split").disabled and upgrade_button("piercing_split").text.contains("金币不足"), "empty wallet displays no available purchase")
	main.run.gold = 100000
	main.run.trait_levels["piercing_split"] = 3
	main._refresh()
	await capture("max-rank")
	check(upgrade_button("piercing_split").disabled and upgrade_button("piercing_split").text.contains("满阶"), "maximum trait shows retained effect and disables further rank")
	main._on_action("encounter_close", null)
	main._new_run()
	freeze()
	equip(["critical_flow", "critical_forging", "broad_precision"])
	main.run.skill_levels.erase("size")
	main.run.rebuild_stats()
	main.run.gold = 100000
	main._on_action("encounters", null)
	await capture("no-gain")
	check(upgrade_button("critical_flow").disabled and upgrade_button("broad_precision").disabled, "converted crit and base-size center trait refuse no-gain purchase")
	main._on_action("encounter_close", null)
	main._new_run()
	freeze()
	bosses.prime(main.run, 100)
	main.run.encounter_picks["windfall"] = 8
	equip(["charged_breach", "piercing_split"])
	main.world.boss_enabled = true
	main.world._physics_process(0)
	main.run.shots_left = 1
	bosses.fire(main.world, 100000, 3, 21)
	bosses.tick(main.world, 400)
	check(main.run.phase == RunModel.Phase.CHOICE and main.run.shots_left == 3 and paused and main.world.targets.is_empty(), "real last draw Boss victory pauses for construction reward")
	main.run.rebuild_stats()
	main._refresh()
	await capture("boss-free-choice")
	await small("boss-free-choice-small")
	var choice_panel: EncounterPanel = main.hud.encounter_panel as EncounterPanel
	check(choice_panel != null, "native Boss reward panel exists")
	var picked: String = ""
	for button: Button in choice_panel.choice_buttons:
		if button.text.begins_with("免费强化"):
			picked = main.run.choices[choice_panel.choice_buttons.find(button)]
			var wallet: int = main.run.gold
			button.pressed.emit()
			button.pressed.emit()
			check(main.run.gold == wallet and main.run.trait_levels.size() == 1 and main.run.pending_encounters == 0, "native free upgrade grants once with no charge")
			break
	check(not picked.is_empty() and main.run.boss_reward_log[0]["choice"] == picked, "journal records exact selected rank")
	main.world._physics_process(0)
	main._on_action("encounters", null)
	await capture("boss-upgrade-journal")
	await small("boss-upgrade-journal-small")
	check(main.world.targets.size() == 3 and not main.run.boss_active, "free choice restores continuous ordinary arena")
	var all_ids: Array[String] = []
	for id: String in TraitUpgradeCatalog.ALL: all_ids.append(id)
	for group: int in range(6):
		main._new_run()
		freeze()
		var ids: Array[String] = []
		for index: int in range(group * 3, group * 3 + 3): ids.append(all_ids[index])
		if ids.has("branch_harvest") or ids.has("branch_ricochet"): ids.append("piercing_split")
		equip(ids)
		main.run.boss_round = 1
		main.run.boss_next_defeats = 200
		main.run.bosses_defeated = 1
		main.run.credited_defeats["boss1"] = true
		main.run.boss_reward_log.assign([{"round": 1, "score": 1200, "gold": 240, "draws": 3, "choice": ""}])
		main.run.reward_queue.assign([{"kind": "boss", "round": 1}])
		main.run.pending_encounters = 1
		main.run.encounter_offer_id = 1
		main.run.phase = RunModel.Phase.CHOICE
		main.run.choices.clear()
		for index: int in range(group * 3, group * 3 + 3): main.run.choices.append(TraitUpgradeCatalog.token(all_ids[index], 1))
		main._refresh()
		await capture("free-previews-%d" % group)
		if group == 5: await small("free-previews-small")
	main.queue_free()
	paused = false
	await process_frame
	print("TRAIT UPGRADES WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
