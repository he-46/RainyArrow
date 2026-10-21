extends RefCounted
var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "V02: " + message)

func run_all(tree: SceneTree) -> void:
	for angle: float in [-1.1, -0.5, 0.0, 0.4]:
		var aim := Vector2.RIGHT.rotated(angle)
		for tension: float in [0.0, 0.5, 1.0]:
			var pose: ArcherPose = ArcherPose.sample(aim, true, tension)
			verify(pose.draw_hand.is_equal_approx(ArcherPose.string_anchor(ArcherPose.GRIP, aim, tension)), "drawing hand follows string at angle %s, pull %s" % [angle, tension])
		verify((ArcherPose.string_anchor(ArcheryWorld.BOW, aim, 1.0) + aim * 23).is_equal_approx(ArcheryWorld.BOW), "full-draw arrow head meets actual launch point")
	var idle: ArcherPose = ArcherPose.sample(Vector2.RIGHT)
	verify(idle.state == "idle" and idle.loaded, "idle carries an arrow")
	verify(ArcherPose.sample(Vector2.RIGHT, true, 0.5).state == "draw" and ArcherPose.sample(Vector2.RIGHT, true, 1).state == "hold", "pull distinguishes draw and full hold")
	var early: ArcherPose = ArcherPose.sample(Vector2.RIGHT, false, 0, 0.6, 0.65)
	var late: ArcherPose = ArcherPose.sample(Vector2.RIGHT, false, 0, 0.05, 0.65)
	verify(early.state == "reload" and not early.loaded and early.draw_hand.distance_to(Vector2(-7, 8)) < late.draw_hand.distance_to(Vector2(-7, 8)), "reload reaches quiver then returns to string")
	var session := GameSession.new()
	session.profile.unlock_active("quickdraw")
	var run: RunModel = session.start_run()
	var world := ArcheryWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.run = run
	tree.paused = false
	tree.root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.build_field()
	world.dragging = true
	world.pull = 1
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	world._input(escape)
	verify(world.visual_pose().state == "idle" and run.shot_sequence == 0, "cancelled draw returns to idle without release animation")
	world.pull = 1
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	verify(world.visual_pose().state == "release" and not world.visual_pose().loaded, "release follows an actual emitted shot")
	var before: Dictionary = world.snapshot().duplicate(true)
	var rng_state: int = run.rng.state
	world._process(0.15)
	verify(world.visual_pose().state == "reload", "release recovers into actual outstanding reload")
	verify(before == world.snapshot() and rng_state == run.rng.state, "presentation ticks never change saved combat or randomness")
	run.active.energy = 100
	verify(world.activate_skill() and world.reload_left == 0 and world.visual_pose().state == "cast", "quickdraw clears reload and gives casting posture")
	world.dragging = true
	world.pull = 1
	verify(world.visual_pose().state == "hold", "new input immediately overrides cast animation")
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	verify(world.reload_left == 0 and run.shot_sequence == 2, "quickdraw shot has no artificial animation reload")
	world.dragging = true
	world.pull = 0.5
	verify(world.visual_pose().state == "draw", "rapid new draw overrides release posture")
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	verify(run.shot_sequence == 3 and world.reload_left == 0, "second quickdraw shot can fire immediately")
	world.set_process(true)
	tree.paused = true
	var cast_before: float = world.cast_pose_left
	var recoil_before: float = world.recoiling
	await tree.create_timer(0.06, true).timeout
	verify(world.cast_pose_left == cast_before and world.recoiling == recoil_before, "pause freezes cast and recoil timers")
	world.set_process(false)
	tree.paused = false
	world._process(0.3)
	verify(world.visual_pose().state == "idle", "unpaused timers finish normally")
	world.pull = 1
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	before = world.snapshot().duplicate(true)
	world.build_field(before)
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)
	verify(world.visual_pose().state == "reload" and world.snapshot() == before, "restored reload reconstructs posture without changing save geometry")
	world.queue_free()
	await tree.process_frame
