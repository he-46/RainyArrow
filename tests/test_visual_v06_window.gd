extends SceneTree
var main: Node
var assertions: int = 0
var failures: int = 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V06 WINDOW: " + message)

func click(control: Control) -> void:
	if control == null:
		check(false, "missing click target")
		return
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = at
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)
	await process_frame
	await process_frame

func capture(id: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/v06-" + id + ".png") == OK, "capture " + id)

func talents() -> TalentPage: return main.router.page.get_child(1) as TalentPage
func item(id: String) -> Button: return main.hud.encounter_panel.find_child(id, true, false) as Button

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v06-window-test"
	main.session.profile.record_score(1000000)
	main._navigate("talents")
	await capture("talents-roots")
	check(talents().nodes.size() == 36, "all talent nodes remain available for inspection")
	for id: String in talents().nodes:
		check(talents().nodes[id].has_node("BuildIcon"), "node has a tiered symbol: " + id)
	for id: String in ["quiver_root", "quiver_left", "quiver_left", "quiver_master_left"]: main.session.purchase_talent(id)
	main._navigate("talents")
	await process_frame
	talents().tree_scroll.scroll_vertical = 210
	talents()._select("quiver_advanced_left")
	await process_frame
	var scroll: int = talents().tree_scroll.scroll_vertical
	await click(talents().detail.get_node("PurchaseTalent"))
	check(main.session.profile.talents.get("quiver_advanced_left") == 1 and talents().tree_scroll.scroll_vertical == scroll, "real purchase preserves exact scroll offset")
	main._navigate("active_skills")
	await capture("active-skills")
	main._on_action("back", null)
	await process_frame
	await process_frame
	check(talents().selected == "quiver_advanced_left" and talents().tree_scroll.scroll_vertical == scroll, "skill roundtrip retains tree selection and position")
	talents()._select("quiver_master_right")
	check(talents().nodes.quiver_master_right.text.contains("互斥") and talents().detail.get_node("PurchaseTalent").disabled, "exclusive specialization has explicit text and blocked purchase")
	await capture("talents-specialization")
	main._navigate("hub")
	main.router.selected_contracts = {"health": 2, "armor": 1, "slots": 2, "boss": 2}
	main._navigate("contracts")
	await capture("contracts")
	for id: String in BuildIcon.CONTRACTS:
		check(main.router.page.find_child("Contract_" + id, true, false).has_node("BuildIcon"), "contract has semantic symbol: " + id)
	main._new_run("normal", null, true)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	var fixture: RefCounted = preload("res://tests/test_backpack.gd").new(check)
	fixture.equip(main.run, fixture.SIX)
	main.run.gold = 10000
	main._on_action("skills", null)
	await capture("skills")
	var first: Button = main.hud.content.get_child(2).get_node("damage")
	var before_gold: int = main.run.gold
	await click(first)
	check(main.run.gold < before_gold and main.run.skill_levels.get("damage") == 1, "structured card still buys through actual button")
	main._on_action("continue", null)
	main._on_action("encounters", null)
	await capture("backpack")
	var before: Dictionary = main.run.to_dict().duplicate(true)
	await click(item("Details_critical_forging"))
	check(main.hud.encounter_panel.has_node("ArtifactDetails"), "detail opens through reachable card button")
	await capture("artifact-details")
	check(main.run.to_dict() == before, "reading parameters and comparison cannot mutate build, wallet or RNG")
	await click(item("CloseArtifactDetails"))
	check(not main.hud.encounter_panel.has_node("ArtifactDetails"), "detail closes to same backpack")
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("backpack-small")
	await click(item("Details_unified_arrow"))
	await capture("artifact-details-small")
	await click(item("CloseArtifactDetails"))
	main._on_action("encounter_close", null)
	main._on_action("skills", null)
	await capture("skills-small")
	main._navigate("talents")
	await capture("talents-small")
	main._navigate("contracts")
	await capture("contracts-locked-small")
	# A presentation-only atlas exercises every artifact composite without granting invalid builds.
	main.hud.hide()
	main.router.hide()
	var atlas: Panel = GameUI.panel(main.root, Rect2(40, 40, 1200, 640))
	GameUI.label(atlas, "神器图鉴 · 图标与构筑联动", 28, GameUI.GOLD).position = Vector2(24, 18)
	var index: int = 0
	for id: String in TraitUpgradeCatalog.ALL:
		check(BuildIcon.ARTIFACTS.has(id) and BuildIcon.ARTIFACT_COPY.has(id), "artifact has explicit symbol and summary: " + id)
		var at := Vector2(24 + index % 3 * 390, 80 + index / 3 * 88)
		var reward: EncounterData = EncounterCatalog.find(id)
		BuildIcon.artifact(atlas, id, at, 42, reward.color)
		GameUI.label(atlas, reward.title, 20, reward.color).position = at + Vector2(56, 0)
		GameUI.label(atlas, BuildIcon.ARTIFACT_COPY[id], 14).position = at + Vector2(56, 30)
		index += 1
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout
	await capture("artifact-icons")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V06 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
