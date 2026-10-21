extends SceneTree
## Deterministic real-projectile balance experiments; no injected rewards or talent points.
var rows: Array[Dictionary] = []
var variant: String = "baseline"
var trials: int = 3
var runs: int = 8
var max_draws: int = 260
var report_name: String = ""

func _initialize() -> void: simulate.call_deferred()

func tick(w: ArcheryWorld, steps: int) -> void:
	for i: int in range(steps):
		if w.run.phase != RunModel.Phase.PLAYING: break
		for arrow: Arrow in w.arrows.duplicate():
			arrow.set_physics_process(false)
			arrow._physics_process(1.0 / 120)
		w._physics_process(1.0 / 120)

func aim(w: ArcheryWorld) -> Vector2:
	var target: ArcheryTarget = w.boss
	if target == null:
		for candidate: ArcheryTarget in w.targets:
			if candidate.hp > 0 and (target == null or candidate.position.x < target.position.x): target = candidate
	if target == null: return Vector2.RIGHT
	var speed: float = w.run.stats.launch_speed
	var g: float = w.run.stats.gravity
	var x: float = target.position.x - ArcheryWorld.BOW.x - 7 * target.scale.x
	var angle: float = 0
	for i: int in range(5):
		var t: float = x / (speed * cos(angle))
		var y: float = target.anchor.y + sin((w.clock + t) * 1.6 + target.motion_phase) * target.definition.movement - ArcheryWorld.BOW.y
		if target is ArcheryBoss: y = target.position.y - ArcheryWorld.BOW.y
		var d: float = pow(speed, 4) - g * (g * x * x - 2 * y * speed * speed)
		angle = atan((-speed * speed + sqrt(maxf(0, d))) / (g * x))
	return Vector2.RIGHT.rotated(clampf(angle, -1.1, 0.4))

func buy(run: RunModel, route: String) -> void:
	var order: Array[String]
	if route == "damage": order.assign(["damage", "damage", "penetration", "damage", "quantity", "damage", "critical", "penetration"])
	elif route == "quantity": order.assign(["quantity", "damage", "penetration", "quantity", "damage", "critical", "ricochet", "damage"])
	else: order.assign(["penetration", "damage", "quantity", "penetration", "damage", "ricochet", "damage", "critical"])
	var purchased: int = 0
	for rank: int in run.skill_levels.values(): purchased += rank
	for rank: int in run.mastery_levels.values(): purchased += rank
	run.open_skills()
	for attempt: int in range(12):
		var skill: RunSkillData = SkillCatalog.find(order[purchased % order.size()])
		if not run.buy(skill): break
		purchased += 1
	run.close_skills()

func choose(run: RunModel) -> void:
	var priorities: Array[String] = ["piercing_split", "charged_breach", "second_wind", "bullseye_wave", "armor_surplus", "piercing_edge", "heavy_draw", "steady_power", "rainfall", "tempered_tip", "windfall", "quick_nock"]
	for id: String in priorities:
		if run.choices.has(id) and (not EncounterCatalog.find(id).is_trait or not run.backpack_full()):
			if run.choose_encounter(id, run.encounter_offer_id): return
	if run.can_skip_encounter(): run.skip_encounter(run.encounter_offer_id); return
	for id: String in run.choices.duplicate():
		if run.choose_encounter(id, run.encounter_offer_id): return

func talents(session: GameSession, route: String) -> void:
	var order: Array[String] = ["quiver_root", "damage_root", "quiver_left", "damage_left", "quiver_master_left", "quiver_advanced_left", "quiver_capstone_left", "damage_master_left", "damage_advanced_left", "damage_capstone_left", "economy_root"]
	if route == "penetration": order.assign(["damage_root", "damage_right", "quiver_root", "quiver_left", "quiver_master_left", "quiver_advanced_left", "damage_master_right", "damage_advanced_right", "quiver_capstone_left", "damage_capstone_right", "economy_root"])
	for id: String in order:
		while session.purchase_talent(id): pass

func play(session: GameSession, route: String, selection: Dictionary, seed_value: int) -> Dictionary:
	var run: RunModel = session.start_run(true, "normal", selection)
	run.rng.seed = seed_value
	if variant != "current":
		run.balance_revision = 0
		run.initial_shots -= 6
		run.shots_left -= 6
	if variant in ["draws16", "growth16"]:
		run.initial_shots += 6
		run.shots_left += 6
	if variant == "growth16": run.balance_revision = 1
	if variant == "gentle":
		run._mode_parameters["target_health"] *= 0.75
		run._mode_parameters["health_growth"] = 0.04
	configure_experiment(run)
	var w := ArcheryWorld.new()
	w.run = run
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.shot_settled.connect(session.settle_shot)
	w.build_field()
	var first_choice: int = -1
	var first_boss: int = -1
	var initial: int = run.initial_shots
	for step: int in range(max_draws * 4):
		if run.is_finished() or run.shot_sequence >= max_draws or run.bosses_defeated >= 1: break
		if run.phase == RunModel.Phase.CHOICE:
			if first_choice < 0: first_choice = run.shot_sequence
			choose(run)
			continue
		if run.phase == RunModel.Phase.SUPPLY:
			if not run.buy_supply(run.supply_token()): run.decline_supply(run.supply_offer_id)
			continue
		tick(w, 180)
		if run.phase != RunModel.Phase.PLAYING: continue
		if run.boss_active and first_boss < 0:
			first_boss = run.shot_sequence
			if variant == "current" and route == "quantity" and not FileAccess.file_exists("res://artifacts/t09b-earned-boss.json"):
				session.capture_checkpoint(w.snapshot())
				if not SaveStore.new("res://artifacts/t09b-earned-boss.json", []).write(session.save_payload()):
					push_error("Earned Boss checkpoint rejected")
		buy(run, route)
		w.direction = aim(w)
		if w.can_activate_skill(): w.activate_skill()
		w.pull = 1
		w._release()
		tick(w, 1500)
	var result: Dictionary = {"seed": seed_value, "route": route, "contracts": selection, "draws": run.shot_sequence, "initial": initial, "kills": run.defeated_count, "first_choice_draw": first_choice, "first_boss_draw": first_boss, "bosses": run.bosses_defeated, "gold": run.gold_earned, "spent": run.gold_spent, "level": session.profile.level, "score": run.defeat_score, "skills": run.skill_levels.duplicate(), "artifacts": run.artifact_ids(), "capped": not run.is_finished(), "boss_hp": w.boss.hp if w.boss != null else -1}
	decorate_result(result, run)
	session.end_run("abandoned")
	w.queue_free()
	return result

func configure_experiment(_run: RunModel) -> void: pass
func decorate_result(_result: Dictionary, _run: RunModel) -> void: pass

func simulate() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"): quit(1); return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
		if arg.begins_with("--runs="): runs = int(arg.trim_prefix("--runs="))
		if arg.begins_with("--trials="): trials = int(arg.trim_prefix("--trials="))
		if arg.begins_with("--report="): report_name = arg.trim_prefix("--report=").get_file()
	if OS.get_cmdline_user_args().has("--matrix"):
		await matrix()
		return
	for route: String in ["damage", "quantity", "penetration"]:
		for trial: int in range(trials):
			var session := GameSession.new()
			session.unlock_active("sunshot")
			for round_index: int in range(runs):
				talents(session, route)
				var row: Dictionary = play(session, route, {}, 19000 + trial * 100 + round_index)
				row["run"] = round_index + 1
				row["trial"] = trial
				rows.append(row)
				await process_frame
			print(variant, " ", route, " trial ", trial, " last kills=", rows[-1].kills, " bosses=", rows[-1].bosses, " level=", rows[-1].level)
	var file := FileAccess.open("res://artifacts/" + (report_name if not report_name.is_empty() else "t09b-" + variant) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("PROGRESSION COMPLETE: ", rows.size(), " runs")
	quit()

func matrix() -> void:
	var saved: Dictionary = SaveStore.new("res://artifacts/t09b-earned-boss.json", []).read()
	if saved.is_empty(): push_error("Run current campaign before matrix"); quit(1); return
	variant = "current"
	var selections: Dictionary = {"normal": {}, "hard": ContractCatalog.preset("hard"), "hell": ContractCatalog.preset("hell"), "economy3": {"prices": 2, "supply": 1}, "aim3": {"health": 1, "bullseye": 2}}
	for route: String in ["damage", "quantity", "penetration"]:
		for label: String in selections:
			for trial: int in range(trials):
				var session := GameSession.from_dict(saved)
				var row: Dictionary = play(session, route, selections[label], 29000 + trial)
				row["scenario"] = label
				row["trial"] = trial
				rows.append(row)
				await process_frame
			print("MATRIX ", route, " ", label, " completed")
	var file := FileAccess.open("res://artifacts/" + (report_name if not report_name.is_empty() else "t09b-matrix") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"profile": saved.profile, "runs": rows}, "\t"))
	file.close()
	print("MATRIX COMPLETE: ", rows.size(), " runs")
	quit()
