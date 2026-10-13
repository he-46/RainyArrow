extends SceneTree
## Rendered T10-C rewards, button selection, Continue, history/result and audio streams.

var assertions: int = 0
var failures: int = 0
var capture_prefix: String = "t10c-"

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BOSS REWARDS WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/" + capture_prefix + name + ".png") == OK, "capture " + name)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="): capture_prefix = argument.trim_prefix("--capture-prefix=")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "boss-rewards-window-test"
	main._new_run()
	main.world.set_physics_process(false)
	var base: RefCounted = preload("res://tests/test_boss.gd").new(check)
	base.prime(main.run, 100)
	main.world._physics_process(0)
	await capture("health")
	check(main.world.boss.hp == 2880 and main.hud.boss_title.text.contains("2880 / 2880"), "tripled production health is visible")
	var streams: Dictionary = {}
	for cue: String in ["boss_entry", "boss_phase", "shield_block", "shield_pass", "boss_weak", "boss_victory"]:
		var sound: AudioStreamWAV = main.audio.sounds[cue]
		check(sound.get_length() > 0.09 and not streams.has(hash(sound.data)), "distinct nonempty PCM cue: " + cue)
		streams[hash(sound.data)] = true
	main.run.shots_left = 1
	base.fire(main.world, 100000, 3, 21)
	# Fixture overrides only the launched arrows; future offer previews use the real build.
	main.run.rebuild_stats()
	base.tick(main.world, 240)
	await capture("reward")
	check(main.run.phase == RunModel.Phase.CHOICE and paused and main.run.shots_left == 3, "real final volley pauses on victory supply and safe selection")
	check(main.hud.encounter_panel.choice_buttons.size() == 3 and main.run.boss_reward_log.size() == 1 and main.run.gold == 840, "panel contains three choices and one credited record")
	var token: int = main.run.encounter_offer_id
	var cards: Array[String] = main.run.choices.duplicate()
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty() and payload["run"]["boss_reward_log"].size() == 1, "native hub saves pending victory reward")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	await capture("continued")
	check(main.run.choices == cards and main.run.encounter_offer_id == token and main.run.shots_left == 3 and paused, "disk Continue preserves the same paused cards without extra supply")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("reward-small")
	var button: Button
	for candidate: Button in main.hud.encounter_panel.choice_buttons:
		if EncounterCatalog.find(String(candidate.name)).draws == 0: button = candidate; break
	check(button != null, "safe ordinary reward is selectable")
	var chosen: String = String(button.name)
	var predicted: Dictionary = main.run.preview_encounter(EncounterCatalog.find(chosen)).to_dict()
	button.pressed.emit()
	main.world._physics_process(0)
	await capture("field-returned")
	check(not paused and main.run.phase == RunModel.Phase.PLAYING and main.world.targets.size() == 3 and main.run.stats.to_dict() == predicted, "actual reward button resumes the field with its selected gain")
	check(main.run.shots_left == 3 and main.run.boss_reward_log[0]["choice"] == chosen and not main.run.boss_active, "choice consumes the source without replaying victory supply")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main._on_action("encounters", null)
	await capture("history")
	check(main.hud.encounter_log_open and paused, "Boss loot history uses existing paused encounter page")
	main._on_action("encounter_close", null)
	main.run.shots_left = 0
	main.run.settle_volley()
	if main.run.phase == RunModel.Phase.SUPPLY:
		check(main.world.arrows.is_empty(), "Boss reward settles before affordable supply choice")
		main._on_action("supply_end", main.run.supply_offer_id)
	await capture("result")
	check(main.run.is_finished() and main.run.gold == 0 and main.session.last_run_summary["boss_reward_totals"]["draws"] == 3, "exhaustion renders permanent growth and Boss summary with cleared local coins")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("result-small")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("BOSS REWARDS WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
