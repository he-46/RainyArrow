extends SceneTree
## Run with: godot --headless --path . --script res://tests/test_runner.gd

var failures: int = 0
var assertions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	_test_combat()
	preload("res://tests/test_sweep_culling.gd").new(check).run_all()
	await preload("res://tests/test_balance_pacing.gd").new(check).run_all(self)
	await preload("res://tests/test_boss_resilience.gd").new(check).run_all(self)
	await preload("res://tests/test_damage_pacing.gd").new(check).run_all(self)
	_test_economy_and_tree()
	_test_progression()
	_test_save()
	preload("res://tests/test_session.gd").new(check).run_all()
	await _test_fast_arrow()
	await _test_scene()
	await preload("res://tests/test_continuous.gd").new(check).run_all(self)
	await preload("res://tests/test_skills.gd").new(check).run_all(self)
	await preload("res://tests/test_talents.gd").new(check).run_all(self)
	await preload("res://tests/test_encounters.gd").new(check).run_all(self)
	await preload("res://tests/test_traits.gd").new(check).run_all(self)
	await preload("res://tests/test_conversions.gd").new(check).run_all(self)
	await preload("res://tests/test_settings.gd").new(check).run_all(self)
	await preload("res://tests/test_music.gd").new(check).run_all(self)
	await preload("res://tests/test_active_skills.gd").new(check).run_all(self)
	await preload("res://tests/test_visual_v01.gd").new(check).run_all(self)
	await preload("res://tests/test_visual_v02.gd").new(check).run_all(self)
	await preload("res://tests/test_visual_v03.gd").new(check).run_all(self)
	await preload("res://tests/test_visual_v04.gd").new(check).run_all(self)
	await preload("res://tests/test_tutorial.gd").new(check).run_all(self)
	await preload("res://tests/test_cosmetics.gd").new(check).run_all(self)
	await preload("res://tests/test_boss.gd").new(check).run_all(self)
	await preload("res://tests/test_boss_combat.gd").new(check).run_all(self)
	await preload("res://tests/test_boss_rewards.gd").new(check).run_all(self)
	await preload("res://tests/test_encounter_expansion.gd").new(check).run_all(self)
	await preload("res://tests/test_penetration_traits.gd").new(check).run_all(self)
	await preload("res://tests/test_precision_traits.gd").new(check).run_all(self)
	await preload("res://tests/test_branch_traits.gd").new(check).run_all(self)
	await preload("res://tests/test_mastery.gd").new(check).run_all(self)
	await preload("res://tests/test_trait_upgrades.gd").new(check).run_all(self)
	await preload("res://tests/test_supplies.gd").new(check).run_all(self)
	await preload("res://tests/test_difficulty.gd").new(check).run_all(self)
	await preload("res://tests/test_leaderboard.gd").new(check).run_all(self)
	await preload("res://tests/test_talent_expansion.gd").new(check).run_all(self)
	await preload("res://tests/test_backpack.gd").new(check).run_all(self)
	await preload("res://tests/test_contracts.gd").new(check).run_all(self)
	# Give the audio mix thread time to release stopped playback objects.
	await create_timer(0.1).timeout
	print("TEST RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _test_combat() -> void:
	var bow: BowStats = GameCatalog.BASE_BOW.duplicate() as BowStats
	bow.damage = 1000.0
	var hit: Dictionary = CombatMath.resolve_hit(bow, 1.0, true, 10.0, 0.99)
	check(is_equal_approx(float(hit["effective"]), 10.0), "Overkill cannot inflate effective damage")
	check(not hit.has("score"), "Nonlethal hit does not carry score reward")
	check(not hit.has("gold_value"), "Damage math cannot mint hit currency")
	bow.damage = 20
	bow.crit_chance = 1
	var critical: Dictionary = CombatMath.resolve_hit(bow, 1, false, 100, 0.99)
	check(float(critical["effective"]) == 40, "Critical damage uses configured multiplier")
	var velocity: Vector2 = Vector2(300, -100)
	var total: Vector2 = Vector2.ZERO
	for index: int in range(120):
		total += CombatMath.displacement(velocity, 230, 1.0 / 120.0)
		velocity.y += 230.0 / 120.0
	check(total.distance_to(CombatMath.displacement(Vector2(300, -100), 230, 1)) < 0.01, "Preview matches integrated trajectory")

func _test_economy_and_tree() -> void:
	var run := RunModel.new()
	var power: RunSkillData = SkillCatalog.find(&"damage")
	check(not run.buy(power), "Cannot buy while playing")
	run.open_skills()
	run.gold = 10000
	check(SkillCatalog.ALL.size() == 6, "Exactly six skill branches")
	for skill: RunSkillData in SkillCatalog.ALL:
		check(run.can_buy(skill), "Every branch is initially available: " + String(skill.id))
		var before_gold: int = run.gold
		var preview: Dictionary = run.preview_skill(skill).to_dict()
		check(run.buy(skill) and run.gold == before_gold - skill.cost, "Purchase charges exactly once: " + String(skill.id))
		check(run.stats.to_dict() == preview, "Preview matches effective attributes: " + String(skill.id))
	var damage: float = run.stats.damage
	run.rebuild_stats()
	check(run.stats.damage == damage and GameCatalog.BASE_BOW.damage == 24, "Rebuild is stable and shared base immutable")
	check(is_equal_approx(run.stats.damage, 32 * 0.85) and run.stats.arrow_count == 2, "Quantity penalty applies after additive damage")
	check(run.stats.crit_chance > 0.1 and run.stats.crit_multiplier > 2, "Critical skill increases chance and multiplier together")
	run.gold = 0
	check(not run.buy(power), "Insufficient coins cannot buy")
	var fractional := RunModel.new()
	for index: int in range(10): fractional.record_defeat(str(index), 0, 0.25)
	check(fractional.gold == 2 and is_equal_approx(fractional.gold_fraction, 0.5), "Fractional kill currency accumulates")

func _test_progression() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait: run.seen_encounters.append(reward.id)
	for index: int in range(60):
		session.record_defeat(str(index), 40, 8)
	check(run.phase == RunModel.Phase.PLAYING and run.defeated_count == 60 and run.pending_encounters == 6, "Continuous play queues encounters without old shop or level limits")
	run.settle_volley()
	while run.pending_encounters > 0:
		run.choices.assign(["windfall", "rainfall", "second_wind"])
		run.choose_encounter("windfall", run.encounter_offer_id)
	check(session.profile.level > 5 and run.score == 2400, "Defeat score feeds permanent XP beyond five stages")
	check(run.open_skills(), "Skills open on demand")
	var shots: int = run.shots_left
	var points: float = run.defeat_score
	run.close_skills()
	check(run.shots_left == shots and run.defeat_score == points, "Closing skills preserves ammo and score")
	run.shots_left = 0
	session.defeat_recorded.connect(func(_id: String) -> void: run.restore_shots(1))
	session.record_defeat("last-shot", 40, 8)
	run.settle_volley()
	check(not run.is_finished() and run.shots_left == 1, "Final-arrow reward hook refunds draw before exhaustion")
	run.consume_shot()
	run.settle_volley()
	check(run.phase == RunModel.Phase.SUPPLY, "Affordable final draw offers finite supply before ending")
	run.decline_supply(run.supply_offer_id)
	check(run.is_finished() and run.gold == 0, "Exhaustion ends continuous run and discards coins")
	check(session.last_run_summary["ending_level"] == session.profile.level, "Summary captures permanent level growth")
	check(not run.consume_shot() and run.restore_shots(1) == 0, "Ended run cannot fire or be resurrected by refund")

func _test_save() -> void:
	var path: String = "user://automated_save_test.json"
	var store: SaveStore = SaveStore.new(path)
	var session: GameSession = GameSession.new()
	session.start_run()
	session.run.gold = 37
	session.world_snapshot = {"clock": 1.25, "targets": [{"hp": 7.0}]}
	check(store.write(session.to_dict()), "Write save")
	session.run.gold = 50
	check(store.write(session.to_dict()), "Write save with backup")
	check(int(store.read()["run"]["gold"]) == 50, "Load latest save")
	var corrupt: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	check(int(store.read()["run"]["gold"]) == 37, "Corrupt primary falls back to previous good backup")
	var unknown: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	unknown.store_string('{"version":999,"payload":{"run":{}}}')
	unknown.close()
	check(int(store.read()["run"]["gold"]) == 37, "Unsupported version cannot masquerade as current schema")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func _test_fast_arrow() -> void:
	var field: Node2D = Node2D.new()
	root.add_child(field)
	var target: ArcheryTarget = ArcheryTarget.new()
	target.configure(GameCatalog.TARGETS[0], Vector2(180, 100), 1, 0)
	field.add_child(target)
	var second: ArcheryTarget = ArcheryTarget.new()
	second.configure(GameCatalog.TARGETS[0], Vector2(220, 100), 1, 1)
	field.add_child(second)
	await physics_frame
	await physics_frame
	var bow: BowStats = GameCatalog.BASE_BOW.duplicate() as BowStats
	bow.gravity = 0
	bow.armor_penetration = 1
	bow.crit_chance = 0
	var arrow: Arrow = Arrow.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	arrow.setup(Vector2(100, 100), Vector2(20000, 0), bow, 1.0, random)
	field.add_child(arrow)
	for index: int in range(4):
		await physics_frame
	check(target.hp < target.max_hp, "Swept collision hits thin target at extreme speed")
	check(second.hp < second.max_hp, "Piercing processes second contact in same step")
	check(is_equal_approx(target.hp, target.max_hp - bow.damage), "Piercing cannot hit same target twice")
	field.queue_free()
	await process_frame

func _test_scene() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	root.add_child(main)
	check(main.router.route == "home" and main.world == null and main.run == null, "Home creates no combat model or world")
	check(main.router.continue_button.disabled, "Continue is disabled without active adventure")
	main.saves.write_blocked = true
	main._save_checkpoint()
	check(not main.save_notice.is_empty(), "Rejected checkpoint exposes the save failure")
	main.saves.write_blocked = false
	main._save_checkpoint()
	check(main.save_notice.is_empty(), "Successful checkpoint clears an earlier failure notice")
	main._on_action("start", null)
	check(main.router.route == "hub" and main.world == null, "Start enters hub without consuming an adventure")
	for destination: String in ["talents", "cosmetics"]:
		main._on_action(destination, null)
		check(main.router.route == destination and main.world == null, "Hub feature has independent page: " + destination)
		main._on_action("back", null)
		check(main.router.route == "hub", "Hub feature returns to hub")
	main._on_action("home", null)
	for destination: String in ["settings", "tutorial"]:
		main._on_action(destination, null)
		check(main.router.route == destination, "Home feature has independent page: " + destination)
		main._on_action("back", null)
		check(main.router.route == "home", "Home feature returns to home")
	main._on_action("start", null)
	main._on_action("range", null)
	await physics_frame
	await physics_frame
	check(main.world.targets.size() == 3, "Main scene composes first stage targets")
	# Fire a real volley on a known ballistic trajectory toward the nearest target.
	main.run.stats.crit_chance = 0
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(208, 476)
	root.push_input(motion, true)
	await process_frame
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	check(main.world.dragging, "Mouse press near bow begins drag through viewport input")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(80, 493.65)
	root.push_input(motion, true)
	await process_frame
	await process_frame
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = motion.position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	check(main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1, "Live volley spends exactly one draw")
	check(not main.world.arrows.is_empty(), "Navigation test begins with a live projectile")
	var live_world: ArcheryWorld = main.world
	var live_target: ArcheryTarget = main.world.targets[0]
	var live_arrow: Arrow = main.world.arrows[0]
	var paused_position: Vector2 = live_arrow.position
	var run_id: String = main.run.run_id
	main._on_action("hub", null)
	check(paused and main.run.suspended and not main.world.visible, "Hub pauses and hides the live world")
	for index: int in range(5):
		await physics_frame
	check(live_arrow.position == paused_position, "In-flight arrow does not advance in hub")
	main._on_action("home", null)
	check(not main.router.continue_button.disabled, "Home offers Continue for paused adventure")
	main.router.continue_button.pressed.emit()
	check(main.router.route == "hub" and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1, "Continue enters hub without refunding draw")
	main._on_action("range", null)
	check(main.world == live_world and main.world.targets[0] == live_target, "Resuming reuses exact world and targets")
	check(main.run.run_id == run_id and main.world.arrows[0] == live_arrow and not paused, "Resume retains run and in-flight projectile")
	for index: int in range(160):
		await physics_frame
	check(main.world.targets[0].hp < main.world.targets[0].max_hp and main.run.score == 0 and main.session.profile.total_score == 0 and main.run.gold == 0, "Nonlethal live hit damages target without score, XP or coins")
	check(main.world.arrows.is_empty(), "Arrow lifecycle clears finished projectiles")
	check(main.world.is_settled(), "Volley checkpoint waits for all projectiles")
	check(not main.saves.read().is_empty(), "Live settled volley creates a restorable save")
	var saved_hp: float = live_target.hp
	var saved_gold: int = main.run.gold
	for index: int in range(3):
		main._on_action("hub", null)
		main._on_action("talents", null)
		main._on_action("back", null)
		main._on_action("range", null)
	check(main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1 and main.run.gold == saved_gold and live_target.hp == saved_hp, "Repeated navigation does not refill, reward or heal")
	check(main.router.get_child_count() == 0, "Range retains no hidden page instances")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(int(payload["run"]["shots_left"]) == RunModel.CURRENT_INITIAL_SHOTS - 1 and bool(payload["in_lobby"]), "Hub persists suspended run with spent draw")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	check(main.world == null and main.session.world_snapshot == payload["world"], "Uninstantiated save keeps target checkpoint on home")
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	check(main.run.run_id == run_id and main.world.targets[0].hp == saved_hp and main.run.gold == saved_gold, "Lazy Continue restores target health and currency from checkpoint")
	# Manual skills preserve the continuous field and spent ammunition.
	var same_world: ArcheryWorld = main.world
	main._on_action("skills", null)
	check(main.hud.overlay.visible, "Manual skills panel opens")
	main._on_action("pause", null)
	main._on_action("back", null)
	check(main.run.phase == RunModel.Phase.SHOP and main.hud.overlay.visible and paused, "Pause resumes the same skills phase")
	main._continue()
	check(main.run.phase == RunModel.Phase.PLAYING and main.world == same_world and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS - 1, "Closing skills keeps continuous targets and ammo")
	check(main.session.profile.total_score == 0, "Hit-score is never promoted to permanent XP")
	main.session.profile.record_defeat(250.0)
	main._on_action("home", null)
	main._on_action("start", null)
	var dialog: ConfirmationDialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	check(dialog != null and main.session.has_active_run(), "Start requests confirmation before replacing adventure")
	dialog.canceled.emit()
	check(main.session.has_active_run() and main.run.run_id == run_id, "Cancel replacement preserves active adventure")
	main._start_to_hub()
	check(main.world == null and not main.session.has_active_run() and main.run.gold == 0, "Confirmed replacement ends old adventure before entering hub")
	main._on_action("range", null)
	check(main.session.profile.level == 3 and main.session.profile.talent_points == 2, "UI new-game action retains permanent progression")
	check(main.run.gold == 0 and main.run.shots_left == RunModel.CURRENT_INITIAL_SHOTS and main.run.skill_levels.is_empty(), "UI new-game action resets only local growth")
	var final_run_id: String = main.run.run_id
	main.run.shots_left = 0
	main.run.settle_volley()
	main._on_action("pause", null)
	main._on_action("back", null)
	check(main.run.run_id == final_run_id and main.run.is_finished() and main.hud.overlay.visible, "Leaving pause on result screen does not silently create new run")
	main._on_action("hub", null)
	main._on_action("home", null)
	check(main.router.continue_button.disabled, "Finished adventure cannot be continued from home")
	main.queue_free()
	await process_frame



