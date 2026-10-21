extends Node
## Composition root: coordinates state, lazy world creation and presentation signals.

var run: RunModel
var session: GameSession
var world: ArcheryWorld
var audio: AudioService
var saves: SaveStore
var root: Control
var hud: GameHUD
var router: PageRouter
var tutorial: TutorialController
var tutorial_origin: String = "home"
var tutorial_world_mode: int = Node.PROCESS_MODE_PAUSABLE
var tutorial_log_open: bool = false

var debug_visible: bool = false
var save_notice: String = ""
var capture_frames: int = 0
var capture_path: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	var test_mode: bool = OS.get_cmdline_user_args().has("--test-mode")
	var test_path: String = "user://tests/scene-save.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			test_path = "user://tests/capture-save.json"
	saves = SaveStore.new(test_path, []) if test_mode else SaveStore.new(SaveStore.DEFAULT_PATH, SaveStore.default_legacy_paths())
	if test_mode:
		DirAccess.make_dir_recursive_absolute("user://tests")
	var saved: Dictionary = {} if test_mode else saves.read()
	save_notice = saves.last_error if not saves.last_error.is_empty() else saves.migration_notice
	session = GameSession.from_dict(saved) if not saved.is_empty() else GameSession.new()
	run = session.run
	if run != null:
		run.changed.connect(_refresh)
	audio = AudioService.new()
	add_child(audio)
	_apply_settings()
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameUI.make_theme()
	layer.add_child(root)
	hud = GameHUD.new()
	root.add_child(hud)
	hud.action.connect(_on_action)
	router = PageRouter.new()
	root.add_child(router)
	router.action.connect(_on_action)
	_navigate("home")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
			capture_frames = 30
		if test_mode and argument.begins_with("--preview="):
			_preview(argument.trim_prefix("--preview="))

func _navigate(destination: String) -> void:
	if destination == "tutorial":
		_start_tutorial()
		return
	if destination == "range":
		_enter_range()
		return
	session.return_to_lobby()
	hud.encounter_log_open = false
	hud.details_open = false
	if world != null:
		world.reset_shake()
		world.dragging = false
		world.pull = 0.0
		world.visible = false
	get_tree().paused = true
	hud.hide()
	router.show_page(destination, session, save_notice)
	_sync_music()
	_save_checkpoint()

func _start_tutorial() -> void:
	if tutorial != null: return
	tutorial_origin = router.route
	tutorial_log_open = hud.encounter_log_open
	if world != null:
		tutorial_world_mode = world.process_mode
		world.dragging = false
		world.pull = 0
		world.reset_shake()
		world.hide()
		world.process_mode = Node.PROCESS_MODE_DISABLED
	session.return_to_lobby()
	_save_checkpoint()
	hud.hide()
	router.show_page("tutorial", session)
	router.hide()
	tutorial = TutorialController.new()
	add_child(tutorial)
	tutorial.completed.connect(_tutorial_completed)
	tutorial.leave_requested.connect(_stop_tutorial)
	tutorial.mute_requested.connect(_toggle_mute)
	tutorial.start(audio, session.profile.settings, root, session.profile.equipped_cosmetics)

func _tutorial_completed() -> void:
	if tutorial == null or tutorial.step != TutorialController.Step.COMPLETE: return
	session.profile.tutorial_completed = true
	_save_checkpoint()

func _stop_tutorial() -> void:
	if tutorial == null: return
	tutorial.dispose()
	remove_child(tutorial)
	tutorial.queue_free()
	tutorial = null
	if world != null: world.process_mode = tutorial_world_mode
	hud.encounter_log_open = tutorial_log_open
	if tutorial_origin == "range" and world != null:
		if session.has_active_run(): session.resume_run()
		_show_range()
		_save_checkpoint()
	else: _navigate(tutorial_origin)

func _enter_range() -> void:
	if not session.has_active_run():
		if router.route == "pause" and world != null:
			_show_range()
			return
		_new_run()
		return
	run = session.resume_run()
	if world == null:
		_create_world(session.world_snapshot)
	_show_range()
	_save_checkpoint()

func _show_range() -> void:
	world.show()
	get_tree().paused = false
	router.show_page("range", session)
	hud.show()
	_refresh()

func _create_world(snapshot: Dictionary = {}) -> void:
	world = ArcheryWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.run = run
	world.scale = Vector2(2, 2)
	add_child(world)
	world.feedback.connect(audio.play)
	world.volley_settled.connect(_save_checkpoint)
	world.shot_settled.connect(_settle_shot)
	world.build_field(snapshot)
	world.apply_settings(session.profile.settings)
	world.apply_cosmetics(session.profile.equipped_cosmetics)

func _discard_world() -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
		world = null

func _new_run(mode: String = "", contracts: Variant = null, legacy: bool = false) -> void:
	hud.encounter_log_open = false
	hud.details_open = false
	if run != null and run.changed.is_connected(_refresh):
		run.changed.disconnect(_refresh)
	_discard_world()
	run = session.start_run(true, router.selected_mode if mode.is_empty() else mode, null if legacy else (router.selected_contracts if contracts == null else contracts))
	run.changed.connect(_refresh)
	_enter_range()

func _start_to_hub() -> void:
	# Start replaces only a confirmed active adventure; permanent profile is retained.
	session.end_run("abandoned")
	_discard_world()
	_navigate("hub")

func _confirm_start() -> void:
	if not session.has_active_run():
		_start_to_hub()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "开始新的冒险"
	dialog.dialog_text = "放弃当前冒险并清空本局金币？\n永久等级、天赋和装扮会保留。"
	dialog.ok_button_text = "开始新冒险"
	dialog.cancel_button_text = "保留当前冒险"
	dialog.confirmed.connect(func() -> void: dialog.queue_free(); _start_to_hub())
	dialog.canceled.connect(dialog.queue_free)
	root.add_child(dialog)
	dialog.popup_centered(Vector2i(460, 160))

func _refresh() -> void:
	if tutorial != null: return
	_sync_music()
	if world == null or run == null:
		return
	if run.phase != RunModel.Phase.PLAYING or hud.encounter_log_open: hud.details_open = false
	run.trait_shop_open = router.route == "range" and hud.encounter_log_open and run.phase == RunModel.Phase.PLAYING
	world.ui_blocked = run.phase != RunModel.Phase.PLAYING or router.route != "range" or hud.encounter_log_open or hud.details_open
	if router.route == "range": get_tree().paused = run.phase in [RunModel.Phase.SHOP, RunModel.Phase.CHOICE, RunModel.Phase.SUPPLY] or hud.encounter_log_open or hud.details_open
	hud.refresh(run, session.profile, audio.muted, save_notice)

func _sync_music() -> void:
	if audio == null or router == null or tutorial != null: return
	match router.route:
		"home": audio.play_music("menu")
		"hub", "talents", "active_skills", "cosmetics", "leaderboard", "contracts": audio.play_music("camp")
		"range":
			var fighting: bool = run != null and run.phase == RunModel.Phase.PLAYING and not hud.encounter_log_open
			audio.play_music("battle" if fighting else "camp")
		# Settings and pause retain the music of the page that opened them.

func _on_action(id: String, value: Variant) -> void:
	match id:
		"start": _confirm_start()
		"resume_hub":
			if session.has_active_run(): _navigate("hub")
		"home", "hub", "range", "settings", "tutorial", "talents", "active_skills", "cosmetics", "pause", "leaderboard", "contracts": _navigate(id)
		"active_unlock", "active_equip":
			if router.route != "active_skills": return
			var success: bool = session.unlock_active(str(value)) if id == "active_unlock" else session.equip_active(str(value))
			if success:
				audio.play("coin")
				_save_checkpoint()
				router.show_page("active_skills", session, save_notice)
		"combat_details", "combat_help":
			if router.route != "range" or run == null or run.phase != RunModel.Phase.PLAYING or hud.encounter_log_open: return
			var show_help: bool = id == "combat_help"
			hud.details_open = not hud.details_open or hud.details_help != show_help
			hud.details_help = show_help
			world.dragging = false
			world.pull = 0.0
			_refresh()
		"details_close":
			hud.details_open = false
			_refresh()
		"active_cast":
			if router.route == "range" and tutorial == null and world != null and world.activate_skill(): _save_checkpoint()
		"back":
			if tutorial != null: _stop_tutorial()
			else: _navigate(router.back_destination())
		"setting":
			if value is Dictionary and session.profile.set_setting(str(value.get("key", "")), value.get("value")):
				_apply_settings()
				_save_checkpoint()
		"sound_preview": audio.play("release")
		"cosmetic_equip":
			if router.route == "cosmetics" and session.in_lobby and session.profile.equip_cosmetic(str(value)):
				if world != null: world.apply_cosmetics(session.profile.equipped_cosmetics)
				_save_checkpoint()
				router.show_page("cosmetics", session, save_notice)
		"new_run":
			if run != null: _new_run(run.mode_id, run.challenge.get("selection", {}), run.challenge.is_empty())
			else: _new_run()
		"mode_select":
			if router.route == "hub" and not session.has_active_run() and value is String and DifficultyCatalog.find(value) != null:
				router.selected_mode = value
				router.selected_contracts = ContractCatalog.preset(value)
				router.show_page("hub", session, save_notice)
		"contract_preset":
			if router.route == "contracts" and not session.has_active_run() and value is String and ContractCatalog.PRESETS.has(value):
				router.selected_mode = value
				router.selected_contracts = ContractCatalog.preset(value)
				router.show_page("contracts", session)
		"contract_select":
			if router.route == "contracts" and not session.has_active_run() and value is Dictionary:
				var key: String = str(value.get("id", ""))
				var rank: Variant = value.get("rank")
				if ContractCatalog.find(key).is_empty() or not rank is int or rank < 0 or rank > 2: return
				if rank == 0: router.selected_contracts.erase(key)
				else: router.selected_contracts[key] = rank
				router.show_page("contracts", session)
		"purchase": _purchase(value as RunSkillData)
		"supply_buy":
			if router.route == "range" and value is Dictionary and run.buy_supply(value):
				audio.play("coin")
				_save_checkpoint()
		"supply_end":
			if router.route == "range" and (value is int or value is float) and value == int(value) and run.decline_supply(int(value)):
				_save_checkpoint()
		"talent_buy":
			if router.route == "talents" and session.purchase_talent(str(value)):
				audio.play("coin")
				_save_checkpoint()
				router.show_page("talents", session)
		"talent_reset":
			if router.route == "talents":
				session.reset_talents()
				_save_checkpoint()
				router.show_page("talents", session)
		"continue": _continue()
		"encounters": _open_encounters()
		"trait_upgrade":
			if router.route == "range" and hud.encounter_log_open and get_tree().paused and value is Dictionary and run.buy_trait(str(value.get("id", "")), int(value.get("rank", -1))):
				audio.play("coin")
				_save_checkpoint()
		"artifact_discard":
			if router.route == "range" and hud.encounter_log_open and get_tree().paused and value is Dictionary and run.discard_artifact(str(value.get("id", "")), int(value.get("revision", -1))):
				_save_checkpoint()
		"encounter_close":
			hud.encounter_log_open = false
			_refresh()
		"encounter_pick":
			if router.route == "range" and value is Dictionary and run.choose_encounter(str(value.get("id", "")), int(value.get("offer_id", -1)), str(value.get("outgoing", "")), int(value.get("revision", -1))):
				audio.play("coin", 1.15)
				_save_checkpoint()
		"encounter_skip":
			if router.route == "range" and run.skip_encounter(int(value)):
				_save_checkpoint()
		"skills":
			if world != null:
				world.dragging = false
				world.pull = 0.0
				run.open_skills()
				_save_checkpoint()
		"mute": _toggle_mute()
		"quit": _quit()

func _purchase(upgrade: RunSkillData) -> void:
	if run.buy(upgrade):
		audio.play("coin")
		_save_checkpoint()

func _continue() -> void:
	run.close_skills()
	_save_checkpoint()

func _open_encounters() -> void:
	if router.route != "range" or run.phase != RunModel.Phase.PLAYING: return
	world.dragging = false
	world.pull = 0.0
	if not run.offer_encounter(): hud.encounter_log_open = true
	_refresh()
	_save_checkpoint()

func _record_defeat(event_id: String, points: float, coins: float) -> void:
	var previous_level: int = session.profile.level
	if session.record_defeat(event_id, points, coins) and session.profile.level > previous_level:
		audio.play("coin", 1.25)

func _settle_shot(shot_id: int, hits: Array) -> void:
	var previous_level: int = session.profile.level
	var previous_shots: int = run.shots_left
	var previous_bosses: int = run.bosses_defeated
	var previous_gold: int = run.gold
	var previous_score: float = run.defeat_score
	session.settle_shot(shot_id, hits)
	if run.gold > previous_gold or run.defeat_score > previous_score:
		world.add_caption({"position": Vector2(200, 294), "text": "+%d 金币  +%s 得分" % [run.gold - previous_gold, GameUI.score_text(run.defeat_score - previous_score)], "life": 1.3, "color": Color("edc879")})
	if run.shots_left > previous_shots:
		world.add_caption({"position": ArcheryWorld.BOW + Vector2(-15, -38), "text": "+%d 拉弓" % (run.shots_left - previous_shots), "life": 1.5, "color": Color("8fd9ba")})
	if run.bosses_defeated > previous_bosses:
		world.add_caption({"position": Vector2(314, 114), "text": "Boss 胜利 · 战利品已入账", "life": 2.0, "color": Color("ffdc83")})
		audio.play("boss_victory")
	if session.profile.level > previous_level or run.shots_left > previous_shots:
		audio.play("coin", 1.25)
	if run.phase == RunModel.Phase.CHOICE:
		world.dragging = false
		world.pull = 0.0
		audio.play("coin", 0.9)
		_save_checkpoint()

func _toggle_mute() -> void:
	session.profile.set_setting("muted", not bool(session.profile.settings["muted"]))
	_apply_settings()
	_save_checkpoint()

func _apply_settings() -> void:
	audio.apply_settings(session.profile.settings)
	if world != null: world.apply_settings(session.profile.settings)
	if tutorial != null: tutorial.apply_settings(session.profile.settings)
	if DisplayServer.get_name() != "headless":
		var desired: int = DisplayServer.WINDOW_MODE_FULLSCREEN if bool(session.profile.settings["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
		var current: int = DisplayServer.window_get_mode()
		if (desired == DisplayServer.WINDOW_MODE_FULLSCREEN and current not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]) or (desired == DisplayServer.WINDOW_MODE_WINDOWED and current in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]):
			DisplayServer.window_set_mode(desired)
	if router != null: router.sync_settings(session.profile.settings)
	if hud != null: _refresh()

func _save_checkpoint() -> void:
	if world == null:
		# An uninstantiated saved run must retain its existing target snapshot.
		session.capture_checkpoint(session.world_snapshot)
	elif not world.dragging:
		session.capture_checkpoint(world.snapshot())
	if not saves.write(session.save_payload()):
		save_notice = saves.last_error
	else:
		save_notice = saves.migration_notice

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				match router.route:
					"tutorial": tutorial.toggle_pause()
					"range":
						if hud.details_open:
							_on_action("details_close", null)
						elif hud.encounter_log_open:
							hud.encounter_log_open = false
							_refresh()
						else: _navigate("pause")
					"home": pass
					"hub": _navigate("home")
					_: _navigate(router.back_destination())
				get_viewport().set_input_as_handled()
			KEY_F3:
				debug_visible = not debug_visible
				hud.debug_label.visible = debug_visible
			KEY_M: _toggle_mute()
			KEY_Q: _on_action("active_cast", null)
			KEY_R: _on_action("combat_details", null)
			KEY_F1: _on_action("combat_help", null)

func _process(_delta: float) -> void:
	if world != null and tutorial == null:
		hud.update_availability(run, world.is_settled())
		hud.update_active(run, router.route == "range" and world.can_activate_skill())
		hud.update_boss(run, world)
	if debug_visible and world != null:
		hud.debug_label.text = "FPS %d · 在场箭矢 %d\n拉力 %.0f%% · 装填 %.2fs\n永久等级 %d · 天赋点 %d" % [Engine.get_frames_per_second(), world.arrows.size(), world.pull * 100, world.reload_left, session.profile.level, session.profile.talent_points]
	if capture_frames > 0:
		capture_frames -= 1
		if capture_frames == 0:
			_capture.call_deferred()

func _preview(view: String) -> void:
	if view.begins_with("conversion-"):
		_preview_conversions(view)
		return
	if view.begins_with("trait-"):
		_preview_traits(view)
		return
	if view in ["talents-built", "field-many", "field-giant"]:
		session.profile.record_defeat(1000000)
		for node: TalentData in TalentCatalog.ALL:
			if node.tier == 2 and node.side != (1 if view == "field-giant" else 0): continue
			for rank: int in range(node.max_rank): session.purchase_talent(node.id)
		if view == "talents-built":
			router.selected_talent = "quiver_master_right"
			_navigate("talents")
		else: _new_run()
		return
	match view:
		"menu", "home": _navigate("home")
		"hub", "settings", "tutorial", "talents", "cosmetics": _navigate(view)
		_:
			_new_run()
			if view == "pause": _navigate("pause")
			if view == "shop":
				run.gold = 65
				run.open_skills()
			if view == "choice":
				for index: int in range(10): session.record_defeat("preview-%d" % index, 40, 8)
				run.shots_left = 0
				run.offer_encounter()
			if view == "encounter-log":
				for reward: EncounterData in EncounterCatalog.ALL:
					if reward.is_trait: run.seen_encounters.append(reward.id)
				for index: int in range(30): session.record_defeat("preview-%d" % index, 40, 8)
				run.offer_encounter()
				for id: String in ["windfall", "rainfall", "second_wind"]: run.choose_encounter(id, run.encounter_offer_id)
				_open_encounters()
			if view == "result":
				session.record_defeat("preview", 250, 40)
				run.shots_left = 0
				run.settle_volley()

func _preview_traits(view: String) -> void:
	_new_run()
	run.skill_levels = {"quantity": 2, "penetration": 1, "ricochet": 2}
	run.gold = 120
	if view in ["trait-choice", "trait-linkage"]:
		run.rebuild_stats()
		for index: int in range(10): session.record_defeat("preview-%d" % index, 40, 8)
		run.offer_encounter()
		if view == "trait-choice": run.choices.assign(["windfall", "piercing_split", "ricochet_haste"])
		else: run.choices.assign(["rainfall", "swarm_precision", "second_wind"])
		for id: String in run.choices:
			if EncounterCatalog.find(id).is_trait and not run.seen_encounters.has(id): run.seen_encounters.append(id)
		_refresh()
		return
	run.encounter_picks = {"piercing_split": 1, "ricochet_haste": 1, "swarm_precision": 1, "rainfall": 1}
	run.seen_encounters.assign(["piercing_split", "ricochet_haste", "swarm_precision"])
	run.defeated_count = 40
	run.encounter_rewards_generated = 4
	run.rebuild_stats()
	if view == "trait-shop": run.open_skills()
	elif view == "trait-log": _open_encounters()
	else:
		world.set_physics_process(false)
		run.stats.gravity = 0
		world.direction = Vector2.RIGHT
		world.pull = 1
		world._release()
		var roots: Array[Arrow] = world.arrows.duplicate()
		for arrow: Arrow in roots: arrow.set_physics_process(false); arrow._physics_process(0.52)
		for arrow: Arrow in world.arrows.duplicate(): arrow.set_physics_process(false); arrow._physics_process(0.05)
		for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	_refresh()
	if view == "trait-log":
		await get_tree().process_frame
		await get_tree().process_frame
		(hud.encounter_panel.find_child("EncounterHistory", true, false) as ScrollContainer).scroll_vertical = 10000

func _preview_conversions(view: String) -> void:
	_new_run()
	run.skill_levels = {"quantity": 2, "critical": 2, "penetration": 1, "ricochet": 1}
	run.gold = 240
	if view in ["conversion-unity", "conversion-crit"]:
		run.rebuild_stats()
		for index: int in range(10): session.record_defeat("preview-%d" % index, 40, 8)
		run.offer_encounter()
		if view == "conversion-unity": run.choices.assign(["rainfall", "unified_arrow", "critical_forging"])
		else: run.choices.assign(["windfall", "critical_forging", "critical_ricochet"])
		for id: String in run.choices:
			if EncounterCatalog.find(id).is_trait and not run.seen_encounters.has(id): run.seen_encounters.append(id)
		_refresh()
		return
	run.encounter_picks = {"rainfall": 1, "swarm_precision": 1, "unified_arrow": 1, "critical_forging": 1,
		"critical_ricochet": 1, "piercing_split": 1, "ricochet_haste": 1}
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: run.seen_encounters.append(reward.id)
	run.defeated_count = 70
	run.encounter_rewards_generated = 7
	run.rebuild_stats()
	if view == "conversion-next":
		for index: int in range(10): session.record_defeat("preview-%d" % index, 40, 8)
		run.offer_encounter()
	elif view == "conversion-shop": run.open_skills()
	elif view == "conversion-log": _open_encounters()
	else:
		world.set_physics_process(false)
		run.stats.gravity = 0
		world.direction = Vector2.RIGHT
		world.pull = 1
		world._release()
		world.arrows[0].set_physics_process(false)
		world.arrows[0]._physics_process(0.52)
		for arrow: Arrow in world.arrows.duplicate(): arrow.set_physics_process(false); arrow._physics_process(0.06)
		for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	_refresh()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE ", error_string(error), " ", capture_path)
	_quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and capture_path.is_empty() and router != null and router.route == "range":
		_navigate("pause")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and capture_path.is_empty() and tutorial != null:
		tutorial.set_paused(true)

func _exit_tree() -> void:
	get_tree().paused = false

func _quit() -> void:
	if tutorial != null: tutorial.dispose()
	if world != null:
		world.dragging = false
		world.pull = 0.0
	_save_checkpoint()
	get_tree().quit()

