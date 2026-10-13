extends SceneTree
## Actual lesson flow and rendered screens. Always uses the isolated test profile.

var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TUTORIAL WINDOW: " + message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t08b-" + name + ".png") == OK, "capture " + name)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Window checks require --test-mode and a window")
		quit(1)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "tutorial-window-test"
	main._on_action("tutorial", null)
	var lesson: TutorialController = main.tutorial
	var checks = preload("res://tests/test_tutorial.gd").new(check)
	await capture("tutorial-draw")
	# System pointer motion must not modify the fixture aim after window transitions.
	lesson.world.set_process_input(false)
	lesson.world.set_process_unhandled_input(false)
	lesson.world.direction = Vector2(1, -0.138).normalized()
	lesson.world.pull = 1
	lesson.world._release()
	check(lesson.step == TutorialController.Step.BULLSEYE, "real release advances draw step")
	await capture("tutorial-bullseye")
	for index: int in range(250):
		if lesson.step == TutorialController.Step.UPGRADE: break
		await physics_frame
	check(lesson.step == TutorialController.Step.UPGRADE and lesson.run.gold == 24, "actual ballistic bullseye earns upgrade money")
	lesson.page.hud.skills_button.pressed.emit()
	await capture("tutorial-shop")
	checks.skill_button(lesson, "伤害").pressed.emit()
	lesson.page.action.emit("continue", null)
	await capture("tutorial-encounter-field")
	lesson.world.direction = Vector2(1, -0.138).normalized()
	lesson.world.pull = 1
	lesson.world._release()
	for index: int in range(250):
		if lesson.run.phase == RunModel.Phase.CHOICE: break
		await physics_frame
	check(lesson.run.phase == RunModel.Phase.CHOICE and lesson.run.defeated_count == 10, "real tenth kill opens choice")
	await capture("tutorial-choice")
	lesson.page.hud.encounter_panel.choice_buttons[0].pressed.emit()
	check(main.session.profile.tutorial_completed and lesson.page.complete_panel.visible, "window lesson completes and persists record")
	await capture("tutorial-complete")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("tutorial-small")
	lesson.page.leave_button.pressed.emit()
	check(main.router.route == "home" and main.session.run == null and main.session.profile.total_score == 0, "window return keeps permanent rewards clean")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("TUTORIAL WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
