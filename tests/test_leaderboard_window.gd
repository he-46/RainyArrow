extends SceneTree

var main: Node
var bosses: RefCounted
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("T14-B WINDOW: " + message)

func freeze() -> void:
	main.world.set_physics_process(false)
	main.world.set_process(false)
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)

func button(parent: Node, caption: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and child.text == caption: return child
		var found: Button = button(child, caption)
		if found != null: return found
	return null

func click(control: Button) -> void:
	check(control != null and not control.disabled, "real button available")
	if control == null: return
	var viewport: Viewport = control.get_viewport()
	var point: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = point
	release.button_index = MOUSE_BUTTON_LEFT
	viewport.push_input(release, true)
	await process_frame
	await process_frame

func capture(name: String) -> void:
	if main.world != null: main.world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if main.router.route in ["home", "leaderboard"]:
		var panel: LeaderboardPanel = main.router.page.get_node("LeaderboardPanel") as LeaderboardPanel
		check(panel.get_global_rect().end.x <= 1228 and panel.get_global_rect().end.y <= 620, "ranking stays within page " + name)
		for index: int in range(1, 4):
			var row: Panel = panel.get_node("Rank%d" % index) as Panel
			check(row.position.y + row.size.y < panel.size.y and row.size.x > 500, "ranking row fits " + name + "/" + str(index))
	check(root.get_texture().get_image().save_png("res://artifacts/t14b-" + name + ".png") == OK, "capture " + name)

func small(name: String) -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	await create_timer(0.1).timeout
	await capture(name)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.1).timeout

func disk_restart() -> void:
	main._save_checkpoint()
	var data: Dictionary = main.saves.read()
	check(not data.is_empty() and main.save_notice.is_empty(), "native board checkpoint valid")
	var prior: Array[Dictionary] = main.session.profile.leaderboard.entries
	main.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "leaderboard-window-test"
	main.session = GameSession.from_dict(data)
	main.run = main.session.run
	if main.run != null: main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	check(main.session.profile.leaderboard.entries == prior, "fresh native scene restores same disk top3 without resubmission")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	bosses = preload("res://tests/test_boss.gd").new(check)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "leaderboard-window-test"
	check(main.session.profile.leaderboard.entries.is_empty() and main.router.route == "home", "fresh home has empty board")
	await capture("home-empty")
	await small("home-empty-small")
	var ids: Array[String] = []
	var modes: Array[String] = ["normal", "hard", "hell", "hard", "normal", "hard"]
	var scores: Array[float] = [40, 60, 80, 64.5, 40, 60]
	var ranks: Array[int] = [1, 1, 1, 2, 0, 0]
	for index: int in range(modes.size()):
		await click(button(main.router.page, "开始游戏   →"))
		var mode: Button = main.router.page.get_node("Mode_" + modes[index]) as Button
		await click(mode)
		await click(button(main.router.page, "进入靶场  →"))
		freeze()
		ids.append(main.run.run_id)
		main.world.boss_enabled = false
		main.run.shots_left = 1
		var target: ArcheryTarget = main.world.targets[0]
		if index == 3: target.spawn(target.definition, 1)
		target.anchor = Vector2(180, 238)
		target.tick(0, 0)
		for other: int in range(1, main.world.targets.size()):
			main.world.targets[other].anchor = Vector2(350 + 80 * other, 100)
			main.world.targets[other].tick(0, 0)
		check(target.reward_score == scores[index], "real generated target has mode-specific score " + str(index))
		bosses.fire(main.world, 1000, 3)
		bosses.tick(main.world, 220)
		main.run.rebuild_stats()
		main._refresh()
		main._save_checkpoint()
		check(main.run.is_finished() and main.run.rank_at_finish == ranks[index] and main.run.defeat_score == scores[index] and main.save_notice.is_empty(), "real final volley saves expected rank " + str(index))
		var status: Label = main.hud.content.get_node("RankingStatus") as Label
		check(status.text.contains("第 %d 名" % ranks[index]) if ranks[index] > 0 else status.text == "本局未进入前三", "result displays ranking decision " + str(index))
		await capture("result-%d-%s" % [index + 1, modes[index]])
		if index == 3: await small("result-half-small")
		await click(button(main.hud.content, "返回大厅"))
		await click(button(main.router.page, "排行榜"))
		check(main.router.route == "leaderboard" and paused, "hub ranking button opens paused ranking page")
		await capture("board-%d" % (index + 1))
		if index == 3: await small("board-full-small")
		await click(button(main.router.page, "返回大厅"))
		await click(button(main.router.page, "主页面"))
		check(main.session.profile.leaderboard.entries.size() == mini(index + 1, 3), "home retains only three runs " + str(index))
		if index in [0, 2, 3]: await capture("home-%d" % (index + 1))
	check(main.session.profile.leaderboard.entries.map(func(row: Dictionary) -> String: return row["run_id"]) == [ids[2], ids[3], ids[1]], "same score cannot displace earlier third and low run cannot enter")
	await disk_restart()
	await capture("home-restarted")
	await small("home-restarted-small")
	# Pause with already-settled score and a live volley must never submit.
	main._new_run("hell")
	freeze()
	main.session.record_defeat("prior-settled", 800)
	bosses.fire(main.world, 24, 3)
	var prior: Array[Dictionary] = main.session.profile.leaderboard.entries
	main._on_action("hub", null)
	await click(button(main.router.page, "排行榜"))
	check(main.session.profile.leaderboard.entries == prior and not main.run.ranking_processed and main.world.arrows.size() == 3, "looking at board pauses live arrows without ranking settled score")
	await capture("board-active-paused")
	await disk_restart()
	check(main.session.has_active_run() and main.run.mode_id == "hell" and main.run.defeat_score == 800 and main.session.profile.leaderboard.entries == prior, "active checkpoint does not rank on restart")
	await click(button(main.router.page, "继续游戏"))
	await click(button(main.router.page, "继续射箭  →"))
	freeze()
	check(main.world.arrows.size() == 3 and not main.run.ranking_processed, "Continue restores live volley without admission")
	main._on_action("hub", null)
	await click(button(main.router.page, "新冒险"))
	var dialog: ConfirmationDialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	check(main.session.profile.leaderboard.entries == prior and main.session.has_active_run(), "cancel abandon does not rank")
	await click(button(main.router.page, "新冒险"))
	dialog = main.root.get_child(main.root.get_child_count() - 1) as ConfirmationDialog
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(not main.session.has_active_run() and main.session.profile.leaderboard.entries[0]["score"] == 800 and main.session.last_run_summary["defeat_score"] == 800, "confirmed abandon ranks settled 800, not pending arrows")
	await click(button(main.router.page, "排行榜"))
	await capture("board-abandoned")
	await click(button(main.router.page, "返回大厅"))
	var board: Array[Dictionary] = main.session.profile.leaderboard.entries
	await click(button(main.router.page, "教程"))
	main.tutorial.world.set_physics_process(false)
	main.tutorial.session.record_defeat("practice-only", 999999)
	main.tutorial.session.end_run()
	check(main.tutorial.session.profile.leaderboard.entries.is_empty() and main.session.profile.leaderboard.entries == board, "actual tutorial session never ranks or alters permanent top3")
	main._stop_tutorial()
	await click(button(main.router.page, "主页面"))
	await capture("home-after-tutorial")
	main._new_run("normal")
	freeze()
	main.session.end_run()
	main._refresh()
	check(main.hud.content.get_node("RankingStatus").text == "本局零分 · 不入榜" and main.session.profile.leaderboard.entries == board, "zero-score result leaves board intact")
	await capture("result-zero")
	await disk_restart()
	check(main.session.profile.leaderboard.entries == board and not main.session.has_active_run(), "finished restart keeps top3 and never revives zero run")
	main.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("T14-B WINDOW RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
