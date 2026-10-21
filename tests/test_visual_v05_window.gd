extends SceneTree
var main: Node
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("V05 WINDOW: " + message)

func button(id: String) -> Button:
	return main.router.page.find_child(id, true, false) as Button

func click(target: Control) -> void:
	if target == null:
		check(false, "missing pointer target")
		return
	var at: Vector2 = target.get_global_rect().get_center()
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
	check(root.get_texture().get_image().save_png("res://artifacts/v05-" + id + ".png") == OK, "capture " + id)
	var buttons: Array[Node] = main.router.page.find_children("*", "Button", true, false)
	var fitted: bool = true
	for node: Node in buttons:
		var rect: Rect2 = (node as Control).get_global_rect()
		fitted = fitted and Rect2(0, 0, 1280, 692).encloses(rect)
	check(fitted, "all page buttons fit: " + id)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v05-window-test"
	await capture("home")
	check(main.router.continue_button.disabled and main.world == null and main.run == null, "fresh home cannot resume or create gameplay")
	var board: Control = main.router.page.get_node("LeaderboardPanel")
	check(not board.get_global_rect().intersects(button("Action_quit").get_global_rect()), "record board and exit do not overlap")
	check(main.audio.music_context == "menu", "home retains moonlit music")
	await click(button("Action_start"))
	check(main.router.route == "hub" and main.run == null and main.world == null and paused, "actual start click opens camp without starting run")
	await capture("camp")
	check(main.audio.music_context == "camp", "camp uses campfire music")
	await click(button("Action_tutorial"))
	check(main.tutorial != null and main.router.route == "tutorial", "camp tutorial entry opens isolated practice")
	main._stop_tutorial()
	check(main.router.route == "hub" and main.run == null, "leaving practice returns to camp without a real adventure")
	for destination: String in ["talents", "cosmetics", "settings"]:
		await click(button("Action_" + destination))
		check(main.router.route == destination, "actual camp entry: " + destination)
		main._on_action("back", null)
		check(main.router.route == "hub", "entry returns to camp: " + destination)
	await click(button("Action_leaderboard"))
	check(main.router.route == "leaderboard", "camp ranking entry remains reachable")
	await click(button("Action_hub"))
	await click(button("Action_active_skills"))
	await click(button("sunshot"))
	check(main.session.profile.equipped_active == "sunshot", "actual free skill selection equips sunshot")
	main._on_action("back", null)
	main._on_action("back", null)
	check(main.router.route == "hub" and button("Action_active_skills").text.contains("贯日"), "skill returns through talents with new loadout in camp")
	await click(button("Mode_hard"))
	check(main.router.selected_contracts == ContractCatalog.preset("hard"), "preset pointer targets survive new layout")
	await click(button("OpenContracts"))
	check(main.router.route == "contracts", "contract editor remains reachable")
	main._on_action("hub", null)
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture("camp-small")
	await click(button("Action_range"))
	main.world.set_physics_process(false)
	main.world.set_process(false)
	check(main.router.route == "range" and main.run.active.id == "sunshot" and main.run.challenge.selection == ContractCatalog.preset("hard"), "real range button starts selected loadout and contracts")
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	main._on_action("hub", null)
	var flight: Dictionary = main.world.snapshot().duplicate(true)
	var run_id: String = main.run.run_id
	var draws: int = main.run.shots_left
	var energy: float = main.run.active.energy
	var rng_state: int = main.run.rng.state
	var life: LobbyLife = main.router.page.get_node("LobbyScenery/LobbyLife")
	var previous: float = life.clock
	await create_timer(0.3).timeout
	check(life.clock > previous and paused, "camp scenery animates while combat is paused")
	check(main.world.snapshot() == flight and main.run.rng.state == rng_state and main.run.active.energy == energy, "ambient animation cannot move arrows, draw RNG, or regenerate energy")
	check(button("Mode_normal").disabled and button("Mode_hard").disabled and button("Mode_hell").disabled, "all presets visibly locked during active adventure")
	check(main.router.page.get_node("AdventureStatus").text.contains(str(draws)) and main.router.page.get_node("ActiveLoadoutStatus").text.contains("锁定"), "camp explains real remaining draws and skill lock")
	await click(button("Action_active_skills"))
	check(button("sunshot").disabled, "active adventure keeps equipped skill locked in equipment page")
	main._on_action("back", null)
	main._on_action("back", null)
	await click(button("Mode_hell"))
	check(main.run.challenge.selection == ContractCatalog.preset("hard"), "disabled preset cannot change current run")
	await capture("camp-paused-small")
	await click(button("Action_start"))
	var dialog: ConfirmationDialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	check(dialog != null and main.run.run_id == run_id, "new adventure still requests replacement confirmation")
	if dialog != null: dialog.canceled.emit()
	await process_frame
	await click(button("Action_settings"))
	main._on_action("setting", {"key": "reduced_effects", "value": true})
	main._on_action("back", null)
	life = main.router.page.get_node("LobbyScenery/LobbyLife")
	previous = life.clock
	await create_timer(0.2).timeout
	check(life.reduced and not life.is_processing() and life.clock == previous, "reduced effects freezes ambient movement after returning from settings")
	await click(button("Action_home"))
	await capture("home-continue-small")
	check(not main.router.continue_button.disabled, "home exposes paused adventure")
	await click(main.router.continue_button)
	check(main.router.route == "hub" and main.run.shots_left == draws and main.run.run_id == run_id, "continue opens camp without spending or refunding a draw")
	await click(button("Action_range"))
	check(main.world.snapshot() == flight and main.run.active.energy == energy, "return to range preserves in-flight state and energy")
	main._on_action("hub", null)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main.session.profile.record_score(10000)
	check(main.session.profile.equip_cosmetic("archer_crimson"), "fixture equips an unlocked alternative outfit")
	main._on_action("hub", null)
	await capture("camp-equipped")
	check(main.router.page.get_node("LobbyScenery").loadout == main.session.profile.equipped_cosmetics, "scene uses the current cosmetic loadout")
	main._on_action("home", null)
	await capture("home-equipped")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await create_timer(0.1).timeout
	await capture("home-large")
	await click(main.router.continue_button)
	await capture("camp-large")
	check(main.router.route == "hub" and main.run.run_id == run_id, "large-window Continue also reaches the same adventure")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("V05 WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
