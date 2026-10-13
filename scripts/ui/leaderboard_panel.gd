class_name LeaderboardPanel
extends Panel

func configure(board: Leaderboard, highlight: String = "") -> void:
	name = "LeaderboardPanel"
	add_theme_stylebox_override("panel", GameUI.box(Color("142832"), Color("43584f")))
	var title: Label = GameUI.label(self, "本地射箭榜 · 前三", 26, GameUI.GOLD)
	title.position = Vector2(20, 16)
	var note: Label = GameUI.label(self, "契约与历史记录共用 · 点击记录查看条件", 15, GameUI.MUTED)
	note.position = Vector2(20, 56)
	var entries: Array[Dictionary] = board.entries
	for index: int in range(Leaderboard.LIMIT):
		var record: Dictionary = entries[index] if index < entries.size() else {}
		var row: Panel = GameUI.panel(self, Rect2(20, 88 + index * 52, size.x - 40, 44))
		row.name = "Rank%d" % (index + 1)
		if not record.is_empty() and record["run_id"] == highlight:
			row.add_theme_stylebox_override("panel", GameUI.box(Color("263b3e"), GameUI.GOLD))
		var rank: Label = GameUI.label(row, "%02d" % (index + 1), 20, GameUI.GOLD)
		rank.position = Vector2(12, 7)
		if record.is_empty():
			var empty: Label = GameUI.label(row, "虚位以待", 18, GameUI.MUTED)
			empty.position = Vector2(62, 8)
			continue
		var mode: Label = GameUI.label(row, ContractCatalog.title(record.challenge) if not record.get("challenge", {}).is_empty() else DifficultyCatalog.title(record["mode_id"]), 18)
		mode.position = Vector2(62, 8)
		var points: Label = GameUI.label(row, GameUI.score_text(record["score"]) + " 分", 20)
		points.name = "Score"
		points.position = Vector2(138, 7)
		points.size.x = size.x - 392
		points.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var details: Label = GameUI.label(row, "击倒 %d · Boss %d" % [record["defeated_count"], record["bosses_defeated"]], 14, GameUI.MUTED)
		details.position = Vector2(size.x - 230, 11)
		details.size.x = 176
		details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _open_record(record)
		)
		row.tooltip_text = "%s · %s 分\n%s UTC · %s\n击倒 %d · 击败 Boss %d" % [ContractCatalog.title(record.challenge) if not record.get("challenge", {}).is_empty() else DifficultyCatalog.title(record["mode_id"]), GameUI.score_text(record["score"]), Time.get_datetime_string_from_unix_time(record["ended_at"], true), "主动结束" if record["reason"] == "abandoned" else "本局结束", record["defeated_count"], record["bosses_defeated"]]
	var footer: Label = GameUI.label(self, "结束后正分入榜 · 同分先取得者优先 · 仅保留三局", 14, GameUI.MUTED)
	footer.position = Vector2(20, 254)

func _open_record(record: Dictionary) -> void:
	if has_node("RecordDetails"): return
	var layer := CanvasLayer.new()
	layer.name = "RecordDetails"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.05, 0.95)
	shade.theme = GameUI.make_theme()
	layer.add_child(shade)
	var panel: Panel = GameUI.panel(shade, Rect2(260, 70, 760, 580))
	var title: Label = GameUI.label(panel, "%s 分 · 击败 Boss %d 次" % [GameUI.score_text(record.score), int(record.bosses_defeated)], 27, GameUI.GOLD)
	title.position = Vector2(28, 22)
	var description: Label = GameUI.label(panel, ContractCatalog.description(record.get("challenge", {})), 18)
	description.position = Vector2(28, 82)
	description.size = Vector2(704, 400)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if record.get("challenge", {}).is_empty(): description.text += "\n" + DifficultyCatalog.title(record.mode_id)
	var close: Button = GameUI.button(panel, "关闭", func() -> void: layer.queue_free())
	close.name = "CloseRecord"
	close.position = Vector2(28, 510)
	close.size = Vector2(704, 48)
