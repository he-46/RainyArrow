extends RefCounted

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T08-B: " + message)

func fire(tree: SceneTree, lesson: TutorialController, endpoint: Vector2 = Vector2(80, 493.65)) -> void:
	lesson.world.reload_left = 0
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(208, 476)
	tree.root.push_input(motion, true)
	await tree.process_frame
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	tree.root.push_input(press, true)
	await tree.process_frame
	verify(lesson.world.dragging, "viewport mouse press starts practice draw")
	motion = InputEventMouseMotion.new()
	motion.position = endpoint
	tree.root.push_input(motion, true)
	await tree.process_frame
	var release := InputEventMouseButton.new()
	release.position = endpoint
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	tree.root.push_input(release, true)
	await tree.process_frame
	verify(lesson.run.shot_sequence > 0 and not lesson.world.dragging, "viewport release launches a real arrow")
	for index: int in range(300):
		if lesson.world.arrows.is_empty() and lesson.world.pending_volleys.is_empty(): break
		await tree.physics_frame
	verify(lesson.world.arrows.is_empty() and lesson.world.pending_volleys.is_empty(), "practice volley fully settles")

func skill_button(lesson: TutorialController, title: String) -> Button:
	for node: Node in lesson.page.hud.content.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(title + " "): return node as Button
	return null

func run_all(tree: SceneTree) -> void:
	var session := GameSession.new()
	session.start_run()
	session.capture_checkpoint({"clock": 3.0})
	session.profile.total_score = 250
	session.profile.tutorial_completed = true
	var independent: Dictionary = session.save_payload()
	verify(independent["profile"]["tutorial_completed"] and independent["profile"]["total_score"] == 0 and independent["world"]["clock"] == 3, "completion flag merges independently of newer combat XP")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._on_action("tutorial", null)
	var lesson: TutorialController = main.tutorial
	verify(main.router.route == "tutorial" and main.world == null and main.run == null and not tree.paused, "home tutorial starts without formal adventure")
	verify(lesson.session != main.session and lesson.session.profile != main.session.profile and lesson.run != main.run, "practice owns separate session, profile and run")
	verify(lesson.world.targets.size() == 1 and lesson.world.targets[0].hp == 12, "single easy target prepared")
	verify(lesson.page.hud.skills_button.disabled and lesson.page.hud.encounters_button.disabled, "future lesson buttons gated")
	lesson.world.pull = 0.05
	lesson.world._release()
	verify(lesson.step == TutorialController.Step.DRAW and lesson.run.shot_sequence == 0, "invalid tiny pull cannot advance tutorial")
	lesson.page.action.emit("pause", null)
	verify(lesson.paused_by_user and tree.paused and lesson.page.hud.pause_button.text == "继续", "practice pause keeps page interactive and labels resume")
	lesson.page.action.emit("pause", null)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	verify(lesson.paused_by_user and tree.paused and main.router.route == "tutorial", "focus loss pauses practice without leaving")
	lesson.page.hud.pause_button.pressed.emit()
	verify(not lesson.paused_by_user and not tree.paused, "actual resume button resumes practice after focus loss")
	lesson.page.leave_button.pressed.emit()
	verify(main.tutorial == null and main.router.route == "home" and not main.session.profile.tutorial_completed and not main.saves.read()["profile"]["tutorial_completed"], "early skip does not mark tutorial complete")
	main._on_action("tutorial", null)
	lesson = main.tutorial
	await fire(tree, lesson, Vector2(80, 420))
	verify(lesson.step == TutorialController.Step.BULLSEYE and lesson.run.defeated_count == 0 and lesson.run.shots_left == 10, "miss advances only release lesson and refunds practice draws")
	lesson.page.restart_button.pressed.emit()
	verify(lesson.step == TutorialController.Step.DRAW and lesson.run.gold == 0 and lesson.run.shot_sequence == 0, "actual restart button resets only disposable practice")
	await fire(tree, lesson)
	verify(lesson.step == TutorialController.Step.UPGRADE and tree.paused and lesson.run.defeated_count == 1, "real bullseye kill advances to upgrade lesson")
	verify(lesson.run.gold == 24 and lesson.session.profile.level == 2 and lesson.session.profile.talent_points == 1, "practice defeat awards real coins, level and talent point")
	verify(main.session.profile.total_score == 0 and main.session.profile.total_defeats == 0 and not main.session.profile.tutorial_completed, "practice rewards never reach permanent profile")
	verify(not lesson.page.hud.skills_button.disabled and lesson.world.ui_blocked, "upgrade coach opens skills while shooting blocked")
	lesson.page.hud.skills_button.pressed.emit()
	verify(lesson.run.phase == RunModel.Phase.SHOP and lesson.page.hud.overlay.visible, "actual skills button opens same real shop")
	verify(not lesson.page.hud.supply_enabled and lesson.page.hud.content.find_child("SupplyBuy", true, false) == null, "unlimited practice hides formal supply purchase")
	lesson.page.action.emit("continue", null)
	verify(lesson.step == TutorialController.Step.UPGRADE and tree.paused and not lesson.purchased, "closing shop without purchase cannot skip task")
	lesson.page.hud.skills_button.pressed.emit()
	var damage: Button = skill_button(lesson, "伤害")
	verify(damage != null and not damage.disabled, "real damage purchase card affordable")
	lesson.set_paused(true)
	var before: Dictionary = lesson.run.to_dict()
	damage.pressed.emit()
	verify(lesson.run.to_dict() == before and not lesson.purchased, "user pause rejects purchase without side effects")
	lesson.set_paused(false)
	damage = skill_button(lesson, "伤害")
	damage.pressed.emit()
	verify(lesson.purchased and lesson.run.skill_levels.get("damage", 0) == 1 and lesson.run.gold == 12 and lesson.run.stats.damage == 32, "real card buys actual skill with practice coins")
	lesson.page.action.emit("continue", null)
	verify(lesson.step == TutorialController.Step.ENCOUNTER and not tree.paused and lesson.run.defeated_count == 9 and lesson.run.pending_encounters == 0, "demo progress prepares next real threshold without early choice")
	await fire(tree, lesson)
	verify(lesson.run.defeated_count == 10 and lesson.run.phase == RunModel.Phase.CHOICE and tree.paused, "actual next kill triggers tenth-kill choice")
	verify(lesson.page.hud.encounter_panel.choice_buttons.size() == 3, "real three-card encounter interface shown")
	var token: int = lesson.run.encounter_offer_id
	lesson.page.action.emit("encounter_pick", {"id": lesson.run.choices[0], "offer_id": token - 1})
	verify(lesson.step == TutorialController.Step.ENCOUNTER and lesson.run.encounter_picks.is_empty(), "stale candidate cannot complete lesson")
	var safe: Button
	for button: Button in lesson.page.hud.encounter_panel.choice_buttons:
		if not EncounterCatalog.find(button.name).is_trait: safe = button; break
	verify(safe != null, "real lesson candidates retain safe ordinary option")
	safe.pressed.emit()
	verify(lesson.step == TutorialController.Step.COMPLETE and lesson.page.complete_panel.visible and tree.paused, "actual choice completes all tasks")
	verify(main.session.profile.tutorial_completed and main.saves.read()["profile"]["tutorial_completed"], "completion persisted immediately before leaving")
	verify(main.saves.read()["run"] == null and main.saves.read()["world"].is_empty() and main.saves.read()["profile"]["total_score"] == 0, "disk contains no practice run, arrows or rewards")
	verify(GameSession.from_dict(main.saves.read()).profile.tutorial_completed, "completion flag survives disk load")
	lesson.page.restart_button.pressed.emit()
	verify(lesson.step == TutorialController.Step.DRAW and main.session.profile.tutorial_completed, "replay retains permanent completion record")
	lesson.page.leave_button.pressed.emit()
	verify(main.tutorial == null and main.router.route == "home" and tree.paused and main.run == null, "skip replay returns to exact home without creating run")
	await tree.process_frame
	# Live formal projectile is frozen, isolated by parent world, and restored unchanged.
	main._on_action("start", null)
	main._on_action("range", null)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	var formal_world: ArcheryWorld = main.world
	var formal_arrow: Arrow = formal_world.arrows[0]
	var formal: Dictionary = formal_world.snapshot()
	var formal_run: Dictionary = main.run.to_dict()
	var formal_profile: Dictionary = main.session.profile.to_dict()
	main._on_action("tutorial", null)
	lesson = main.tutorial
	verify(formal_world.process_mode == Node.PROCESS_MODE_DISABLED and not formal_world.visible, "formal world disabled rather than advancing behind tutorial")
	for index: int in range(6): await tree.physics_frame
	verify(formal_world.snapshot() == formal and formal_arrow == formal_world.arrows[0], "formal arrow frozen even while tutorial tree unpaused")
	await fire(tree, lesson)
	verify(formal_world.snapshot() == formal and main.run.shots_left == formal_run["shots_left"] and main.run.rng.state == int(formal_run["rng_state"]), "practice collisions, draws and RNG cannot touch formal world")
	verify(main.session.profile.to_dict() == formal_profile, "practice leveling does not alter formal talents or cosmetics")
	main._toggle_mute()
	verify(lesson.options["muted"] == main.audio.muted, "shortcut updates practice sound settings")
	lesson.page.leave_button.pressed.emit()
	verify(main.router.route == "range" and main.world == formal_world and not tree.paused and formal_world.process_mode == Node.PROCESS_MODE_PAUSABLE, "leaving resumes same formal scene and process mode")
	verify(main.world.snapshot() == formal and main.world.arrows[0] == formal_arrow, "return preserves exact live projectile and target snapshots")
	main._on_action("pause", null)
	# CHOICE and SHOP require preserving both router return and modal phase.
	main._on_action("back", null)
	for index: int in range(10): main.session.record_defeat("tutorial-formal-%d" % index, 40, 8)
	main.run.offer_encounter()
	var choices: Array[String] = main.run.choices.duplicate()
	var offer: int = main.run.encounter_offer_id
	var rng_state: int = main.run.rng.state
	main._on_action("pause", null)
	main._on_action("tutorial", null)
	main._on_action("back", null)
	verify(main.router.route == "pause" and tree.paused, "pause tutorial returns first to pause page")
	main._on_action("back", null)
	verify(main.router.route == "range" and main.run.phase == RunModel.Phase.CHOICE and tree.paused, "return preserves CHOICE modal")
	verify(main.run.choices == choices and main.run.encounter_offer_id == offer and main.run.rng.state == rng_state, "practice cannot redraw fixed formal candidates")
	var restored: GameSession = GameSession.from_dict(main.saves.read())
	verify(restored.run.choices == choices and restored.run.encounter_offer_id == offer and restored.profile.tutorial_completed, "formal candidate and completion saved together")
	main._on_action("hub", null)
	main._on_action("tutorial", null)
	main._on_action("back", null)
	verify(main.router.route == "hub" and main.run.suspended and tree.paused, "hub tutorial returns to suspended same adventure")
	main._on_action("range", null)
	main.run.choose_encounter(main.run.choices[0], main.run.encounter_offer_id)
	main._on_action("skills", null)
	main._on_action("tutorial", null)
	main._on_action("back", null)
	verify(main.router.route == "range" and main.run.phase == RunModel.Phase.SHOP and main.hud.overlay.visible and tree.paused, "direct tutorial return preserves SHOP overlay")
	main._continue()
	main._open_encounters()
	verify(main.hud.encounter_log_open, "formal history initially open")
	main._on_action("tutorial", null)
	main._on_action("back", null)
	verify(main.router.route == "range" and main.hud.encounter_log_open and main.hud.encounter_panel.visible and tree.paused, "direct tutorial return preserves open encounter history")
	# A saved but not instantiated world must not be replaced by practice snapshots.
	var lazy_snapshot: Dictionary = main.world.snapshot()
	main._on_action("hub", null)
	main._discard_world()
	main._on_action("tutorial", null)
	main._toggle_mute()
	verify(main.world == null and main.session.world_snapshot == lazy_snapshot, "lazy formal checkpoint survives practice setting save")
	main._on_action("back", null)
	verify(main.router.route == "hub" and main.world == null and main.session.world_snapshot == lazy_snapshot, "lazy tutorial return does not instantiate formal field")
	main.queue_free()
	await tree.process_frame
	verify(tree.root.canvas_transform == Transform2D.IDENTITY and not tree.paused, "tutorial cleanup restores canvas and tree")
	# Many non-bullseye retries cannot prematurely open encounter selection.
	var host := Node.new()
	tree.root.add_child(host)
	var audio := AudioService.new()
	host.add_child(audio)
	var ui := Control.new()
	host.add_child(ui)
	var retry := TutorialController.new()
	host.add_child(retry)
	retry.start(audio, PlayerProfile.new().settings, ui)
	retry.step = TutorialController.Step.BULLSEYE
	for index: int in range(21):
		retry.run.shot_sequence += 1
		retry._settle(retry.run.shot_sequence, [{"hit_id": "retry:%d" % index, "event_id": "retry-%d" % index, "effective": 12.0, "broken": true, "critical": false, "bullseye": false, "reward_score": 100.0, "reward_gold": 24.0}])
	verify(retry.step == TutorialController.Step.BULLSEYE and retry.run.phase == RunModel.Phase.PLAYING and retry.run.pending_encounters == 0 and retry.run.defeated_count == 21, "21 off-center kills stay in aim lesson without forced encounter")
	retry.step = TutorialController.Step.UPGRADE
	retry._prepare_encounter()
	verify(retry.run.defeated_count == 29 and retry.run.pending_encounters == 0, "late learner prepares next real threshold rather than regressing kills")
	retry.dispose()
	host.queue_free()
	await tree.process_frame
	tree.paused = false
