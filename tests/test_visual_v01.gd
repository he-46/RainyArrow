extends RefCounted
## Exercise modal input and preserve an actual in-flight volley through inspection.
var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "V01: " + message)

func run_all(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main.capture_path = "v01-test"
	main._on_action("start", null)
	main.session.profile.unlock_active("sunshot")
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.run.active.energy = 100
	main._refresh()
	verify(main.hud.instruction.modulate.a == 1.0, "first-shot instruction visible")
	main.world.pull = 0.01
	main.world._release()
	verify(main.hud.instruction.modulate.a == 1.0 and main.run.shot_sequence == 0, "cancelled pull retains instruction")
	main.world.pull = 1.0
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	verify(main.run.shot_sequence == 1 and main.hud.instruction.modulate.a < 0.4, "actual shot weakens instruction")
	var before: Dictionary = main.world.snapshot().duplicate(true)
	var draws: int = main.run.shots_left
	var rng_state: int = main.run.rng.state
	main.hud.details_button.pressed.emit()
	verify(tree.paused and main.world.ui_blocked and main.hud.details_overlay.visible, "attributes pauses and blocks field")
	verify(main.hud.stats_label.visible and not main.hud.help_label.visible, "attributes shown separately from help")
	main.world.pull = 1.0
	main.world._release()
	main._on_action("active_cast", null)
	verify(main.run.shots_left == draws and main.run.active.energy == 100, "modal blocks release and ability")
	verify(main.world.snapshot() == before, "inspection preserves live projectile snapshot")
	main._on_action("combat_help", null)
	verify(main.hud.details_open and main.hud.help_label.visible and tree.paused, "switching to help stays paused")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	main._unhandled_input(key)
	verify(not tree.paused and not main.world.ui_blocked and main.router.route == "range", "Escape closes inspection before pause menu")
	verify(main.world.snapshot() == before and main.run.rng.state == rng_state, "closing restores same volley and random stream")
	main._on_action("combat_details", null)
	main._on_action("combat_details", null)
	verify(not main.hud.details_open and not tree.paused, "attribute shortcut toggles closed")
	main._on_action("combat_details", null)
	main.run.open_skills()
	verify(not main.hud.details_open and tree.paused, "phase change closes inspection and keeps shop pause")
	main._on_action("combat_details", null)
	verify(not main.hud.details_open, "inspection cannot cover shop")
	main.run.close_skills()
	main._on_action("combat_details", null)
	main._navigate("hub")
	verify(not main.hud.details_open, "leaving field clears modal state")
	main._on_action("range", null)
	verify(not tree.paused and not main.world.ui_blocked, "returning to field restores input")
	var practice := GameHUD.new()
	practice.supply_enabled = false
	tree.root.add_child(practice)
	verify(not practice.details_button.visible and not practice.help_button.visible, "practice leaves instruction to tutorial coach")
	practice.queue_free()
	main.queue_free()
	await tree.process_frame
	tree.paused = false
