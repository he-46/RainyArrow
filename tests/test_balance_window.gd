extends "res://tests/test_journey_window.gd"
## Resumes a checkpoint earned by the real-projectile progression simulation.

func aim(w: ArcheryWorld) -> Vector2:
	if w.boss == null: return super.aim(w)
	var x: float = w.boss.position.x - ArcheryWorld.BOW.x - 25
	var y: float = w.boss.position.y - ArcheryWorld.BOW.y
	var v: float = w.run.stats.launch_speed
	var g: float = w.run.stats.gravity
	var d: float = pow(v, 4) - g * (g * x * x - 2 * y * v * v)
	return Vector2.RIGHT.rotated(atan((-v * v + sqrt(maxf(0, d))) / (g * x)))

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	var saved: Dictionary = SaveStore.new("res://artifacts/t09b-earned-boss.json", []).read()
	var resilient: bool = OS.get_cmdline_user_args().has("--resilient")
	# Controlled new-rule comparison; the actual old save stays on revision 1.
	if resilient and not saved.is_empty():
		saved.run.balance_revision = 2
		saved.world.boss["impact_revision"] = 1
		saved.world.boss["volley_pressure"] = {}
	check(not saved.is_empty(), "earned Boss checkpoint readable")
	if saved.is_empty(): quit(1); return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "balance-window-test"
	await click(caption(main.root, "开始游戏"))
	await click(named("OpenContracts"))
	await capture("b-contracts-16")
	await click(named("quiver_2"))
	await click(named("ContractsStart"))
	freeze(main.world)
	check(main.run.shots_left == 12 and main.run.balance_revision == 3, "contract reduces new baseline to twelve")
	await capture("b-new-run")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main.saves = SaveStore.new("user://tests/balance-earned.json", [])
	main._navigate("home")
	await click(main.router.continue_button)
	await click(caption(main.root, "去射箭"))
	freeze(main.world)
	check(main.run.defeated_count >= 100 and main.world.targets.is_empty() and main.world.boss.hp == 2880, "earned hundredth defeat enters unchanged full-health Boss")
	await capture("b-earned-boss")
	var start: int = main.run.shot_sequence
	var phase_two_seen: bool = false
	for attempt: int in range(30):
		if main.run.is_finished() or main.run.bosses_defeated > 0: break
		if main.run.phase == RunModel.Phase.SUPPLY:
			await click(named("SupplyBuy"))
			continue
		tick(main.world, 120)
		if main.world.can_activate_skill(): await click(main.hud.active_button)
		draw(main.world, aim(main.world))
		for frame: int in range(1500):
			tick(main.world, 1)
			if resilient and not phase_two_seen and main.world.boss != null and main.world.boss.hp > 0 and main.world.boss.battle_phase == 2:
				phase_two_seen = true
				main._refresh()
				check(main.hud.boss_hint.text.contains("韧甲") and main.hud.boss_hint.tooltip_text.contains("等待不会重置") and main.hud.boss_hint.mouse_filter == Control.MOUSE_FILTER_PASS, "Boss explains resilience and allows tooltip hover")
				await capture("b2-resilient-phase-two")
				var hp_before: float = main.world.boss.hp
				var pressure: Dictionary = main.world.boss.volley_pressure.duplicate()
				await reload_disk()
				check(is_equal_approx(main.world.boss.hp, hp_before) and main.world.boss.volley_pressure == pressure, "native in-flight continue preserves resilience and phase two")
			if main.run.phase != RunModel.Phase.PLAYING: break
		await process_frame
	check(main.run.bosses_defeated == 1 and main.run.phase == RunModel.Phase.CHOICE, "earned build beats Boss with real mouse volleys")
	if resilient: check(phase_two_seen and main.run.shot_sequence - start >= 2, "earned resilient Boss exposes a second-phase shooting window")
	await capture("b-earned-victory")
	if main.run.phase == RunModel.Phase.CHOICE:
		var old_gold: int = main.run.gold
		var old_score: float = main.run.defeat_score
		await reload_disk()
		check(main.run.gold == old_gold and main.run.defeat_score == old_score and main.run.phase == RunModel.Phase.CHOICE, "victory checkpoint preserves reward without duplicate credit")
		var pick: int = main.run.choices.find("second_wind")
		await click(main.hud.encounter_panel.choice_buttons[pick if pick >= 0 else main.run.choices.size() - 1])
		tick(main.world, 1)
		check(main.world.boss == null and not main.world.targets.is_empty(), "victory choice returns to ordinary range")
		await capture("b-after-boss")
	print("BALANCE WINDOW BOSS DRAWS: ", main.run.shot_sequence - start)
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("BALANCE WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
