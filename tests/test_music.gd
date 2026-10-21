extends RefCounted
## Exercise real scene navigation, playback, paused fades and independent buses.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "MUSIC: " + message)

func run_all(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var audio: AudioService = main.audio
	var menu: AudioStreamPlayer = audio.music_players["menu"]
	var camp: AudioStreamPlayer = audio.music_players["camp"]
	var battle: AudioStreamPlayer = audio.music_players["battle"]
	verify(audio.music_context == "menu" and menu.playing, "home starts moonlit bow")
	for player: AudioStreamPlayer in [menu, camp, battle]:
		verify(player.bus == "Music" and (player.stream as AudioStreamOggVorbis).loop, "approved music loops on Music bus")
	await tree.create_timer(0.8).timeout
	verify(tree.paused and is_equal_approx(menu.volume_linear, 1.0), "menu fade completes while game tree paused")
	var position: float = menu.get_playback_position()
	main._on_action("settings", null)
	main._on_action("back", null)
	main._refresh()
	verify(audio.music_context == "menu" and menu.get_playback_position() >= position, "settings and refresh do not restart menu")
	main._on_action("start", null)
	verify(audio.music_context == "camp", "lobby starts campfire letters")
	main._navigate("talents")
	verify(audio.music_context == "camp", "talent upgrades share camp music")
	main._navigate("home")
	main._navigate("hub")
	await tree.create_timer(0.8).timeout
	verify(camp.playing and not menu.playing and not battle.playing and is_equal_approx(camp.volume_linear, 1.0), "rapid route changes leave only final music playing")
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	await tree.create_timer(0.8).timeout
	verify(audio.music_context == "battle" and battle.playing and not camp.playing, "shooting starts ranger skirmish")
	position = battle.get_playback_position()
	for index: int in range(10): main._refresh()
	verify(battle.get_playback_position() >= position, "combat updates never restart track")
	main._on_action("skills", null)
	verify(audio.music_context == "camp" and tree.paused, "skill shop switches to camp")
	await tree.create_timer(0.8).timeout
	verify(camp.playing and not battle.playing, "shop fade completes while paused")
	var saved_position: float = audio.music_positions["battle"]
	main._on_action("continue", null)
	await tree.create_timer(0.8).timeout
	verify(audio.music_context == "battle" and battle.get_playback_position() >= saved_position, "closing upgrades resumes battle music position")
	main._open_encounters()
	verify(main.hud.encounter_log_open and audio.music_context == "camp", "artifact backpack upgrades use camp")
	main._on_action("encounter_close", null)
	verify(audio.music_context == "battle", "closing backpack restores battle")
	for phase: int in [RunModel.Phase.CHOICE, RunModel.Phase.SUPPLY, RunModel.Phase.LOST]:
		main.run.phase = phase
		main._refresh()
		verify(audio.music_context == "camp", "rewards, supplies and result use camp")
	main.run.phase = RunModel.Phase.PLAYING
	main._refresh()
	main._navigate("pause")
	main._navigate("settings")
	verify(audio.music_context == "battle", "pause and its settings retain battle music")
	main._on_action("setting", {"key": "music_volume", "value": 0.0})
	var music_bus: int = AudioServer.get_bus_index("Music")
	verify(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Bow")), "music zero silences music independently of effects")
	main._on_action("setting", {"key": "music_volume", "value": 0.7})
	verify(not AudioServer.is_bus_mute(music_bus), "music slider restores sound")
	main._toggle_mute()
	verify(AudioServer.is_bus_mute(0) and battle.playing, "master mute silences without resetting playback")
	main._toggle_mute()
	main._on_action("back", null)
	main._on_action("back", null)
	main._start_tutorial()
	verify(audio.music_context == "battle", "practice field uses battle music")
	main.tutorial.step = TutorialController.Step.UPGRADE
	main.tutorial._refresh()
	verify(audio.music_context == "camp", "tutorial upgrade uses camp music")
	main.tutorial.restart()
	verify(audio.music_context == "battle", "restarting tutorial restores battle")
	main._stop_tutorial()
	await tree.create_timer(0.8).timeout
	battle.seek(battle.stream.get_length() - 0.15)
	await tree.create_timer(0.45).timeout
	verify(battle.playing and battle.get_playback_position() < 2.0, "battle OGG actually wraps at loop boundary")
	main._navigate("home")
	verify(audio.music_context == "menu", "return to title restores moonlit bow")
	main.queue_free()
	await tree.process_frame
	verify(not tree.paused, "music scene teardown leaves tree unpaused")
