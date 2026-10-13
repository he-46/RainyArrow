extends SceneTree
## Native T11-D choices, frozen old arrows, children, premiums and Continue.

var assertions: int = 0
var failures: int = 0
var main: Node
var fixture: RefCounted
var offers: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("T11-D WINDOW: " + message)

func capture(name: String) -> void:
	if main.world != null: main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if name.contains("choices"):
		for description: Node in main.hud.encounter_panel.find_children("Description", "Label", true, false):
			var comparison := description.get_parent().get_node("Comparison") as Label
			check(description.get_rect().end.y <= comparison.position.y, "card text fits above preview: " + name)
	check(root.get_texture().get_image().save_png("res://artifacts/t11d-" + name + ".png") == OK, "capture " + name)

func new_field() -> void:
	main._new_run()
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.boss_enabled = false
	main.world.set_process_unhandled_input(false)

func prepare_offer(ids: Array[String]) -> void:
	offers.entitle(main.run)
	main.run.offer_encounter()
	main.run.choices.assign(ids)
	for id: String in ids:
		if EncounterCatalog.find(id).is_trait and not main.run.seen_encounters.has(id): main.run.seen_encounters.append(id)
	main._refresh()

func claim(id: String) -> void:
	var pick: Button
	for button: Button in main.hud.encounter_panel.choice_buttons:
		if button.name == id: pick = button
	check(pick != null and not pick.disabled, "native trait button available: " + id)
	if pick != null: pick.pressed.emit()
	check(main.run.encounter_picks.get(id, 0) == 1 and not paused, "native claim resumes field: " + id)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	fixture = preload("res://tests/test_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "branch-traits-window-test"
	new_field()
	check(not main.run.encounter_has_gain(EncounterCatalog.find("branch_harvest")) and not main.run.encounter_has_gain(EncounterCatalog.find("branch_ricochet")), "fresh run has no unusable child offers")
	var split: Array[String] = ["piercing_split"]
	fixture._equip(main.run, split)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	fixture._freeze(main.world)
	var old: Dictionary = main.world.snapshot()
	prepare_offer(["second_wind", "branch_harvest", "branch_ricochet"])
	main._save_checkpoint()
	await capture("child-choices")
	check(paused and main.hud.encounter_panel.choice_buttons.size() == 3, "child cards unlock alongside safe ordinary choice")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("child-choices-small")
	claim("branch_harvest")
	prepare_offer(["second_wind", "branch_ricochet", "steady_power"])
	claim("branch_ricochet")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	prepare_offer(["second_wind", "slender_gale", "heavy_draw"])
	await capture("cost-choices")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("cost-choices-small")
	check(EncounterCatalog.find("slender_gale").has_debuff and EncounterCatalog.find("heavy_draw").has_debuff, "tradeoff cards carry explicit cost labels and safe alternative")
	claim("slender_gale")
	prepare_offer(["second_wind", "heavy_draw", "steady_power"])
	claim("heavy_draw")
	check(main.world.snapshot() == old, "four native claims preserve preexisting projectile and reload")
	check(is_equal_approx(main.run.stats.damage, 33.6) and is_equal_approx(main.run.stats.arrow_size, 0.7) and is_equal_approx(main.run.stats.launch_speed, 612.5) and is_equal_approx(main.run.stats.reload_seconds, 0.8775), "native cost selection applies exact effective stats")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	new_field()
	var combined: Array[String] = ["piercing_split", "branch_harvest", "branch_ricochet", "bullseye_wave", "slender_gale", "heavy_draw", "ricochet_haste", "broad_precision"]
	fixture._equip(main.run, combined)
	main.run.encounter_picks["windfall"] = 2
	main.run.skill_levels = {"damage": 2, "penetration": 2, "size": 2}
	main.run.rebuild_stats()
	offers.entitle(main.run, 0)
	main.run.shots_left = 1
	for index: int in range(main.world.targets.size()):
		var target: ArcheryTarget = main.world.targets[index]
		target.anchor = Vector2([300, 390, 450][index], 150)
		target.tick(0, 0)
		target.hp = [1000, 10, 3][index]
		target.max_hp = target.hp
		target.armor = 0
	var parent: Arrow = fixture._primary(main.world, Vector2(280, 160), Vector2(500, 0))
	parent.stats.gravity = 0
	parent.stats.crit_chance = 0
	parent._physics_process(0.07)
	fixture._freeze(main.world)
	main._refresh()
	await capture("children-born")
	check(main.world.arrows.size() == 3 and main.world.arrows[1].remaining_bounces == 2 and parent.remaining_bounces == 0 and main.world.arrows[1].stats.damage == parent.stats.damage * 0.5, "real born children inherit half damage and gain two bounded reflections")
	var child: Arrow = main.world.arrows[1]
	child.position = Vector2(370, 150)
	child.velocity = Vector2(500, 0)
	child._physics_process(0.04)
	main._refresh()
	main._save_checkpoint()
	await capture("child-kills")
	check(main.world.targets[1].hp == 0 and main.world.targets[2].hp == 0 and main.run.gold == 0 and main.session.profile.total_score == 0 and main.run.shots_left == 0, "last draw child direct and area kills render but rewards wait")
	var premium_count: int = 0
	for hit: Dictionary in main.world.pending_volleys["1"]:
		if hit.has("child_gold_bonus"): premium_count += 1
	check(premium_count == 2, "both child kills have explicit frozen reward source")
	var direct_y: float = INF
	var area_y: float = INF
	for label: Dictionary in main.world.labels:
		if str(label["text"]).contains("枝丰"):
			if str(label["text"]).contains("回响"): area_y = label["position"].y
			else: direct_y = label["position"].y
	check(is_finite(direct_y) and is_finite(area_y) and area_y <= direct_y - 14.0, "nearby child direct and area reward captions occupy separate rows")
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	check(not payload.is_empty(), "native pending premium persisted on disk")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.world.boss_enabled = false
	fixture._freeze(main.world)
	check(JSON.parse_string(JSON.stringify(main.world.snapshot(), "", true, true)) == payload["world"] and main.run.rng.state == int(payload["run"]["rng_state"]), "native disk Continue keeps exact serialized family, bonus events, dead victims and RNG")
	await capture("continued-family")
	child = main.world.arrows[1]
	child.position = Vector2(629, 90)
	child.velocity = Vector2(500, 0)
	child._physics_process(0.004)
	main._refresh()
	check(child.velocity.x < 0 and child.remaining_bounces == 1 and is_equal_approx(child.velocity.length(), 625), "extra child reflection actually triggers haste and consumes one budget")
	await capture("child-bounced")
	main.run.gold = 100
	main._on_action("skills", null)
	await capture("cost-skill-preview")
	check(main.run.skill_comparison(SkillCatalog.find(&"size")).contains("靶心增伤") and paused, "future size skill preview includes both slimming and precision")
	main._on_action("continue", null)
	main.run.gold = 0
	main._on_action("encounters", null)
	await capture("history")
	var history := main.hud.encounter_panel.find_child("EncounterHistory", true, false) as ScrollContainer
	check(history != null and main.hud.encounter_log_open and paused, "child and cost explanations are in scrollable native history")
	if history == null:
		quit(1)
		return
	history.scroll_vertical = 10000
	await capture("history-bottom")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("history-small")
	main._on_action("encounter_close", null)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	for live: Arrow in main.world.arrows.duplicate(): live._finish()
	main.world._settle_shots()
	main._refresh()
	check(main.run.gold == 36 and main.session.profile.total_score == 80 and main.run.defeated_count == 102, "native settlement grants each kill8 × child1.5 × gold1.5 once, only80 score and two defeats")
	await capture("premium-settled")
	main.run.settle_volley()
	if main.run.phase == RunModel.Phase.SUPPLY:
		check(main.world.arrows.is_empty(), "child premium settles before affordable supply choice")
		main._on_action("supply_end", main.run.supply_offer_id)
	main._refresh()
	check(main.run.is_finished() and main.run.gold == 0 and main.session.last_run_summary["gold_earned"] == 36 and main.session.last_run_summary["defeat_score"] == 80, "last draw ends after premiums and result preserves earned amounts")
	await capture("result")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("result-small")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T11-D WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
