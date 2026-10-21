extends "res://tests/test_journey_window.gd"
## Accelerated shop fixture: displayed price, click debit, mastery and disk Continue.
func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"): quit(1); return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "economy-window-test"
	main._new_run()
	freeze(main.world)
	main.run.gold = 5000 # Explicit shop QA fixture, not a progression measurement.
	main.saves = SaveStore.new("user://tests/economy-window.json", [])
	await click(main.hud.skills_button)
	var skill := SkillCatalog.find("damage")
	var prices: Array[int] = [12,18,27,39,52,67,82,99,117,137]
	for rank: int in range(10):
		var button: Button = named("damage")
		check(button.get_node("CardDescription").text.contains("满级共 +80") and button.get_node("CardState").text.contains(str(prices[rank])), "current curve and exact price visible")
		var wallet: int = main.run.gold
		var preview: float = main.run.preview_skill(skill).damage
		await click(button)
		check(main.run.gold == wallet - prices[rank] and is_equal_approx(main.run.stats.damage, preview), "native purchase debit and preview match")
		if rank == 0: await capture("b3-first-damage")
	check(main.run.stats.damage == 104 and main.run.skill_price(skill) == 206, "full rank damage and mastery entry")
	var card: Button = named("damage")
	for name: String in ["CardTitle", "CardState", "CardDescription", "CardComparison"]:
		check(Rect2(Vector2.ZERO, card.size).encloses(card.get_node(name).get_rect()), "mastery label fits card " + name)
	await capture("b3-damage-mastery")
	var wallet: int = main.run.gold
	await click(card)
	check(main.run.gold == wallet - 206 and main.run.mastery_levels.damage == 1 and is_equal_approx(main.run.stats.damage, 119.48), "mastery buys actual original benefit at new entry price")
	await reload_disk()
	check(main.run.balance_revision == 3 and main.run.mastery_levels.damage == 1 and main.run.skill_price(skill) == 244, "disk Continue preserves new rule and next mastery price")
	await capture("b3-continued-shop")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("ECONOMY WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
