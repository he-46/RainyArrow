extends RefCounted

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T08-A: " + message)

func run_all(tree: SceneTree) -> void:
	var profile := PlayerProfile.new()
	verify(not profile.set_setting("unknown", true), "unknown setting rejected")
	verify(not profile.set_setting("fullscreen", 1) and not profile.set_setting("muted", "true"), "boolean types are strict")
	verify(not profile.set_setting("sfx_volume", "0.5") and not profile.set_setting("master_volume", NAN), "invalid volume rejected")
	profile.set_setting("master_volume", -2)
	profile.set_setting("sfx_volume", 4)
	verify(profile.settings["master_volume"] == 0 and profile.settings["sfx_volume"] == 1, "numeric volume clamps")
	var loaded: PlayerProfile = PlayerProfile.from_dict({"settings": {"muted": "true", "master_volume": INF, "sfx_volume": -3, "music_volume": 8, "fullscreen": 1}})
	verify(not loaded.settings["muted"] and not loaded.settings["fullscreen"] and loaded.settings["master_volume"] == 1, "malformed loaded options retain defaults")
	verify(loaded.settings["sfx_volume"] == 0 and loaded.settings["music_volume"] == 1, "loaded numeric volumes clamp")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._on_action("settings", null)
	var settings: SettingsPage = main.router.page.get_child(1) as SettingsPage
	verify(settings != null and settings.sliders.size() == 3 and settings.toggles.size() == 5 and settings.toggles.has("reduced_effects"), "actual settings page has eight options including reduced effects")
	for key: String in ["master_volume", "sfx_volume", "music_volume"]:
		(settings.sliders[key] as HSlider).value = 0.32
		verify(is_equal_approx(main.session.profile.settings[key], 0.32), "actual slider updates matching setting " + key)
	verify(is_equal_approx(AudioServer.get_bus_volume_db(0), -4 + linear_to_db(0.32)), "master slider affects real audio bus")
	for bus: String in ["Bow", "Impact", "UI"]:
		var trim: float = -2 if bus == "Bow" else (-3 if bus == "Impact" else -5)
		verify(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)), trim + linear_to_db(0.32)), "sfx affects bus " + bus)
	verify(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -8 + linear_to_db(0.32)), "music volume reserved in real bus")
	(settings.sliders["sfx_volume"] as HSlider).value = 0
	verify(AudioServer.is_bus_mute(AudioServer.get_bus_index("Bow")) and is_finite(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Bow"))), "zero sfx truly silent with finite dB")
	(settings.sliders["sfx_volume"] as HSlider).value = 0.32
	verify(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Bow")), "raising zero sfx unmutes")
	(settings.toggles["muted"] as CheckButton).button_pressed = true
	verify(main.audio.muted and AudioServer.is_bus_mute(0), "UI mute applies")
	main._toggle_mute()
	verify(not main.audio.muted and not (settings.toggles["muted"] as CheckButton).button_pressed, "shortcut syncs same page without rebuilding")
	verify(main.router.page.get_child(1) == settings and (settings.sliders["master_volume"] as HSlider).value == 0.32, "mute preserves slider instance and values")
	(settings.sliders["master_volume"] as HSlider).value = 0
	main._toggle_mute()
	main._toggle_mute()
	verify(AudioServer.is_bus_mute(0) and not main.audio.muted, "master zero remains silent even when mute flag off")
	(settings.sliders["master_volume"] as HSlider).value = 0.32
	verify(not AudioServer.is_bus_mute(0), "master raising volume restores sound")
	var payload: Dictionary = main.saves.read()
	verify(payload["profile"]["settings"] == main.session.profile.settings, "real settings persisted")
	verify(GameSession.from_dict(payload).profile.settings == main.session.profile.settings, "settings survive disk reload")
	main._on_action("back", null)
	verify(main.router.route == "home" and main.world == null, "home return creates no run")
	main._on_action("start", null)
	main._on_action("settings", null)
	main._on_action("back", null)
	verify(main.router.route == "hub", "hub settings return to hub")
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	var combat: Dictionary = main.world.snapshot()
	var old_stats: Dictionary = main.world.arrows[0].stats.to_dict()
	var rng_state: int = main.run.rng.state
	var shot_count: int = main.run.shots_left
	var aim: Vector2 = main.world._aim_position(Vector2(100, 400))
	main.world._kick_shake(true)
	main.world._update_shake(0.001)
	verify(main.world.shake_offset.length() > 0 and tree.root.canvas_transform != Transform2D.IDENTITY, "hit shake changes rendering canvas")
	verify(main.world._aim_position(Vector2(100, 400)).distance_to(aim) < 0.0001, "shake cannot change mapped aim")
	verify(main.world.snapshot() == combat and main.run.rng.state == rng_state, "shake cannot change physics snapshot or combat RNG")
	main._on_action("pause", null)
	main._on_action("settings", null)
	settings = main.router.page.get_child(1) as SettingsPage
	(settings.toggles["screen_shake"] as CheckButton).button_pressed = false
	(settings.toggles["trajectory_guide"] as CheckButton).button_pressed = false
	verify(not main.world.screen_shake and not main.world.trajectory_guide and main.world.shake_offset == Vector2.ZERO and tree.root.canvas_transform == Transform2D.IDENTITY, "live visual settings apply and reset canvas")
	main.world._kick_shake(true)
	main.world._update_shake(0.001)
	verify(main.world.shake_offset == Vector2.ZERO, "disabled shake stays off")
	main._on_action("back", null)
	verify(main.router.route == "pause" and tree.paused, "settings return preserves pause page")
	main._on_action("back", null)
	verify(main.router.route == "range" and not tree.paused and main.run.shots_left == shot_count, "second return resumes same draw count")
	verify(main.world.snapshot() == combat and main.world.arrows[0].stats.to_dict() == old_stats and main.run.rng.state == rng_state, "inflight setting navigation preserves exact combat")
	payload = main.saves.read()
	var restored_arrow := Arrow.new()
	restored_arrow.restore(payload["world"]["arrows"][0], main.run.rng)
	verify(restored_arrow.snapshot() == combat["arrows"][0] and not payload["profile"]["settings"]["trajectory_guide"], "disk preserves arrow and new options")
	restored_arrow.free()
	# Settings saved during a drag must merge only options into the older checkpoint.
	var checkpoint: Dictionary = main.saves.read()
	main.world.dragging = true
	main.session.profile.total_score += 10
	main._toggle_mute()
	payload = main.saves.read()
	verify(payload["profile"]["total_score"] == checkpoint["profile"]["total_score"] and payload["world"] == checkpoint["world"], "drag option save cannot mix new XP with old world")
	verify(payload["profile"]["settings"]["muted"] == main.audio.muted, "drag save still persists latest mute")
	main.session.profile.total_score -= 10
	main.world.dragging = false
	# Fixed candidates, queue and RNG survive nested pause/settings navigation.
	for index: int in range(10): main.session.record_defeat("settings-%d" % index, 40, 8)
	main.run.offer_encounter()
	var choices: Array[String] = main.run.choices.duplicate()
	var offer: int = main.run.encounter_offer_id
	rng_state = main.run.rng.state
	main._on_action("pause", null)
	main._on_action("settings", null)
	main._on_action("setting", {"key": "trajectory_guide", "value": true})
	main._on_action("back", null)
	main._on_action("back", null)
	verify(main.run.phase == RunModel.Phase.CHOICE and tree.paused and main.hud.encounter_panel.visible, "CHOICE resumes same modal pause")
	verify(main.run.choices == choices and main.run.encounter_offer_id == offer and main.run.rng.state == rng_state, "settings never redraw candidates or consume RNG")
	var restored: GameSession = GameSession.from_dict(main.saves.read())
	verify(restored.run.choices == choices and restored.run.encounter_offer_id == offer and restored.profile.settings["trajectory_guide"], "fixed offer and settings restore together")
	main.queue_free()
	await tree.process_frame
	verify(tree.root.canvas_transform == Transform2D.IDENTITY, "destroying world restores canvas")
