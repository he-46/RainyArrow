extends SceneTree
## Same-profile journey. Only input, aim and simulation time are automated in fresh runs.
## Late-game fixtures live in test_supply_window/test_mastery_window, never in this profile.
var main: Node
var assertions: int = 0
var failures: int = 0
var report: Array[Dictionary] = []
var casts: int = 0

class AuditedStore extends SaveStore:
	static var rejected: int = 0
	func write(payload: Dictionary) -> bool:
		var accepted: bool = super.write(payload)
		if not accepted:
			rejected += 1
			print("JOURNEY SAVE REJECTED: ", last_error, " phase=", payload.run.phase if payload.run != null else -1)
			print_stack()
			var trace := FileAccess.open("res://artifacts/t09a-rejected.json", FileAccess.WRITE)
			trace.store_string(JSON.stringify(payload, "\t"))
			trace.close()
		return accepted

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("JOURNEY: " + message)

func named(id: String) -> Button:
	return main.root.find_child(id, true, false) as Button

func caption(parent: Node, text: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and child.text.begins_with(text) and child.is_visible_in_tree(): return child
		var found: Button = caption(child, text)
		if found != null: return found
	return null

func click(button: Button) -> void:
	check(button != null and not button.disabled, "enabled journey button")
	if button == null or button.disabled: return
	await process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event, true)
	await process_frame
	await process_frame

func capture(id: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/t09a-" + id + ".png") == OK, "capture " + id)

func freeze(world: ArcheryWorld) -> void:
	world.set_process(false)
	world.set_physics_process(false)
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)

func tick(world: ArcheryWorld, steps: int) -> void:
	for index: int in range(steps):
		if paused: break
		for arrow: Arrow in world.arrows.duplicate():
			arrow.set_physics_process(false)
			arrow._physics_process(1.0 / 120)
		world._physics_process(1.0 / 120)
		world._process(1.0 / 120)

func aim(world: ArcheryWorld) -> Vector2:
	# Low ballistic arc to the nearest live target's predicted center.
	var target: ArcheryTarget
	for candidate: ArcheryTarget in world.targets:
		if candidate.hp > 0 and (target == null or candidate.position.x < target.position.x): target = candidate
	if target == null: return Vector2.RIGHT
	var speed: float = world.run.stats.launch_speed
	var gravity: float = world.run.stats.gravity
	var x: float = target.position.x - ArcheryWorld.BOW.x - 7 * target.scale.x
	var angle: float = 0
	for iteration: int in range(5):
		var travel: float = x / (speed * cos(angle))
		var y: float = target.anchor.y + sin((world.clock + travel) * 1.6 + target.motion_phase) * target.definition.movement - ArcheryWorld.BOW.y
		var discriminant: float = pow(speed, 4) - gravity * (gravity * x * x - 2 * y * speed * speed)
		angle = atan((-speed * speed + sqrt(maxf(0, discriminant))) / (gravity * x))
	return Vector2.RIGHT.rotated(clampf(angle, -1.1, 0.4))

func draw(world: ArcheryWorld, direction: Vector2) -> void:
	# Real mouse drag/release; the world consumes the draw and creates real arrows.
	var start: Vector2 = world.to_global(ArcheryWorld.BOW)
	var end: Vector2 = world.to_global(ArcheryWorld.BOW - direction * 64)
	var motion := InputEventMouseMotion.new()
	motion.position = start
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	motion = InputEventMouseMotion.new()
	motion.position = end
	root.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.position = end
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)
	freeze(world)

func reload_disk() -> void:
	main._save_checkpoint()
	check(main.save_notice.is_empty(), "checkpoint accepted")
	var saved: Dictionary = main.saves.read()
	check(not saved.is_empty(), "disk checkpoint readable")
	var profile: Dictionary = main.session.profile.to_dict()
	var state: Dictionary = main.run.to_dict() if main.run != null else {}
	var path: String = main.saves.path
	root.remove_child(main)
	main.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "journey-test"
	main.saves = AuditedStore.new(path, [])
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	if main.run != null: main.run.changed.connect(main._refresh)
	main._navigate("home")
	check(main.session.profile.to_dict() == profile, "fresh scene reload preserves permanent profile")
	check(main.saves.last_error.is_empty() and main.save_notice.is_empty(), "first automatic save after reload succeeds")
	if main.session.has_active_run():
		check(main.run.shots_left == state.shots_left and main.run.gold == state.gold and main.run.defeat_score == state.defeat_score, "reload keeps wallet/draws/score")
		await click(main.router.continue_button)
		await click(caption(main.root, "去射箭"))
		freeze(main.world)
		check(main.run.run_id == state.run_id and main.run.challenge == state.challenge and main.run.active.to_dict() == state.active, "continue keeps run/contracts/active energy")

func tutorial() -> void:
	await click(caption(main.root, "教程"))
	var lesson: TutorialController = main.tutorial
	freeze(lesson.world)
	draw(lesson.world, Vector2(1, -0.138).normalized())
	tick(lesson.world, 260)
	check(lesson.step == TutorialController.Step.UPGRADE and lesson.run.gold == 24, "tutorial real bullseye reaches upgrade")
	await click(lesson.page.hud.skills_button)
	for extent: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(extent)
		await create_timer(0.1).timeout
		await capture("tutorial-shop-%d" % extent.x)
		var back: Button = caption(lesson.page, "返回靶场")
		check(back.get_global_rect().end.y + 8 <= lesson.page.coach.position.y, "tutorial return hitbox clears coaching footer")
		check(lesson.page.hud.phase_card.get_global_rect().end.y <= lesson.page.coach.position.y, "tutorial shop panel clears coaching footer")
	await click(lesson.page.hud.content.find_child("damage", true, false))
	await click(caption(lesson.page, "返回靶场"))
	draw(lesson.world, Vector2(1, -0.138).normalized())
	tick(lesson.world, 260)
	check(lesson.run.phase == RunModel.Phase.CHOICE, "tutorial demonstration reaches reward")
	await click(lesson.page.hud.encounter_panel.choice_buttons[0])
	await capture("tutorial-complete")
	await click(lesson.page.leave_button)
	check(main.session.profile.tutorial_completed and main.session.profile.total_score == 0 and main.session.run == null, "tutorial completion carries no practice rewards")

func play_run(index: int) -> void:
	await click(caption(main.root, "去射箭"))
	freeze(main.world)
	main.run.rng.seed = 9100 + index
	check(main.run.gold == 0 and main.run.skill_levels.is_empty() and main.run.active.energy == 0, "new adventure resets local progression")
	var starting: int = main.run.shots_left
	var resumed: bool = false
	for turn: int in range(70):
		if main.run.is_finished(): break
		if main.run.phase == RunModel.Phase.SUPPLY:
			await capture("supply-%d" % index)
			await click(named("SupplyBuy"))
			continue
		if main.run.phase == RunModel.Phase.CHOICE:
			await capture("reward-%d" % index)
			await click(main.hud.encounter_panel.choice_buttons[-1])
			continue
		if main.run.gold >= main.run.skill_price(SkillCatalog.find("damage")) and int(main.run.skill_levels.get("damage", 0)) < 2:
			await click(main.hud.skills_button)
			await click(named("damage"))
			await capture("upgrade-%d" % index)
			await click(caption(main.root, "返回靶场"))
		tick(main.world, 120)
		# Settling the preceding flight can open a reward or exhaust the bag.
		if main.run.phase != RunModel.Phase.PLAYING: continue
		if main.world.can_activate_skill():
			await click(main.hud.active_button)
			casts += 1
		var sequence: int = main.run.shot_sequence
		draw(main.world, aim(main.world))
		check(main.run.shot_sequence == sequence + 1, "mouse draw consumes exactly one charge")
		if index == 0 and not resumed:
			var flight: int = main.world.arrows.size()
			await reload_disk()
			check(main.world.arrows.size() == flight and flight > 0, "in-flight arrows survive disk continue")
			resumed = true
		tick(main.world, 1500)
		await process_frame
	check(main.run.is_finished(), "natural exhaustion terminates adventure")
	check(main.run.gold == 0 and not main.session.has_active_run(), "finish clears run currency and active state")
	check(main.session.last_run_summary.gold_spent <= main.session.last_run_summary.gold_earned, "all purchases paid from real rewards")
	report.append({"run": index + 1, "initial_draws": starting, "draws": main.run.shot_sequence, "kills": main.run.defeated_count, "score": main.run.defeat_score, "gold_earned": main.run.gold_earned, "gold_spent": main.run.gold_spent, "level": main.session.profile.level, "contracts": main.run.challenge.selection})
	await capture("result-%d" % index)
	await reload_disk()
	check(main.router.continue_button.disabled, "finished adventure cannot be revived")
	await click(caption(main.root, "开始游戏"))
	await click(caption(main.root, "天赋 ·"))
	var before: int = int(main.session.profile.talents.get("quiver_root", 0))
	var buy: Button = named("PurchaseTalent")
	if buy != null and not buy.disabled:
		await click(buy)
		check(int(main.session.profile.talents.get("quiver_root", 0)) == before + 1, "earned points buy next-run talent")
	await capture("talent-%d" % index)
	await click(caption(main.root, "返回"))

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "journey-test"
	main.saves = AuditedStore.new("user://tests/journey-natural.json", [])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await tutorial()
	await reload_disk()
	await click(caption(main.root, "开始游戏"))
	await click(caption(main.root, "主动技能 ·"))
	await click(named("sunshot"))
	check(main.session.profile.equipped_active == "sunshot" and main.session.profile.talent_points == 0, "free first active skill equips before departure")
	await click(caption(main.root, "返回天赋树"))
	await click(caption(main.root, "返回"))
	await click(named("OpenContracts"))
	await click(named("Preset_hard"))
	await click(named("Preset_normal"))
	await capture("contracts")
	await click(named("ContractsBack"))
	for index: int in range(4): await play_run(index)
	check(casts > 0, "earned shooting energy actually activates skill")
	check(main.session.profile.leaderboard.entries.size() == 3, "four finished adventures retain only top three")
	check(AuditedStore.rejected == 0, "every automatic save in the journey is accepted")
	await click(caption(main.root, "排行榜"))
	await capture("ranking")
	var file := FileAccess.open("res://artifacts/t09a-journey.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"runs": report, "casts": casts, "assertions": assertions, "failures": failures}, "\t"))
	file.close()
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("JOURNEY RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
