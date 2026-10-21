extends "res://tests/simulate_progression.gd"
## Compare queue waiting with buying affordable alternatives; no injected currency.
var policy: String = "strict"
var economy_revision: int = 2
var blocked: int = 0
var alternatives: int = 0
var purchases: Array[Dictionary] = []

func simulate() -> void:
	variant = "current"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--policy="): policy = arg.trim_prefix("--policy=")
		if arg.begins_with("--economy-revision="): economy_revision = int(arg.trim_prefix("--economy-revision="))
	report_name = "t09b3-r%d-%s" % [economy_revision, policy]
	await super.simulate()

func configure_experiment(run: RunModel) -> void:
	run.balance_revision = economy_revision
	run.rebuild_stats()
	blocked = 0
	alternatives = 0
	purchases.clear()

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
		if not run.can_buy(skill):
			var fallback: RunSkillData
			for offset: int in range(1, order.size()):
				var candidate := SkillCatalog.find(order[(purchased + offset) % order.size()])
				if run.can_buy(candidate): fallback = candidate; break
			if attempt == 0:
				blocked += 1
				if fallback != null: alternatives += 1
			if policy == "flexible" and fallback != null: skill = fallback
			else: break
		var price: int = run.skill_price(skill)
		if not run.buy(skill): break
		purchases.append({"draw": run.shot_sequence, "id": String(skill.id), "cost": price, "damage": run.stats.damage, "arrows": run.stats.arrow_count, "penetration": run.stats.armor_penetration})
		purchased += 1
	run.close_skills()

func decorate_result(result: Dictionary, run: RunModel) -> void:
	result["blocked_draws"] = blocked
	result["affordable_alternative_draws"] = alternatives
	result["wallet"] = run.gold
	result["recovered_draws"] = run.shots_left + run.shot_sequence - run.initial_shots
	result["purchases"] = purchases.duplicate(true)
