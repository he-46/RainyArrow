class_name EncounterPanel
extends Control

signal action(id: String, value: Variant)
var choice_buttons: Array[Button] = []
var history_scroll: ScrollContainer

func configure(run: RunModel, choosing: bool) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.055, 0.07, 0.87)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel: Panel = GameUI.panel(self, Rect2(116, 124, 1048, 474) if choosing else Rect2(116, 62, 1048, 596))
	if choosing: _choices(panel, run)
	else: _history(panel, run)

func _choices(panel: Panel, run: RunModel) -> void:
	var source: Dictionary = run.reward_source()
	var boss_reward: bool = source["kind"] == "boss"
	var count: int = run.choices.size()
	var heading: String = "Boss 战利品" if boss_reward else "林间奇遇"
	var instruction: String = "三选一" if count == 3 else ("%d 项可选" % count if count > 0 else "普通增益已满")
	_text(panel, heading + "  /  " + instruction, Vector2(32, 24), 30, GameUI.GOLD)
	var caption: String = "击倒 %d 个靶子  ·  待领取 %d 次  ·  选择一项后继续" % [run.defeated_count, run.pending_encounters]
	if boss_reward:
		for record: Dictionary in run.boss_reward_log:
			if record["round"] == source["round"]:
				caption = "第 %d 次 Boss 已击败 · 已得 %s 分 / %d 金币 / 拉弓 +%d · 再选一项增益" % [record["round"], GameUI.score_text(record["score"]), record["gold"], record["draws"]]
	if count == 0: caption = "已得收益保留 · 确认后继续当前靶场"
	_text(panel, caption, Vector2(34, 73), 17, GameUI.MUTED)
	var offer_token: int = run.encounter_offer_id
	for index: int in range(run.choices.size()):
		var reward: EncounterData = EncounterCatalog.find(run.choices[index])
		var x: float = (panel.size.x - (count * 316 + (count - 1) * 16)) * 0.5 + index * 332
		var card: Panel = GameUI.panel(panel, Rect2(x, 124, 316, 238))
		card.add_theme_stylebox_override("panel", GameUI.box(Color("1e3439"), reward.color))
		_text(card, "Boss · 免费强化" if not reward.upgrade_trait.is_empty() else ("神器 · 含代价" if reward.has_debuff else ("神器 · 本局唯一" if reward.is_trait else "普通 · %s · 无负面" % reward.category_label())), Vector2(20, 15), 14, reward.color)
		BuildIcon.artifact(card, reward.id, Vector2(20, 45), 32, reward.color)
		_text(card, reward.title, Vector2(64, 46), 22, GameUI.CREAM)
		var description := Label.new()
		description.name = "Description"
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 17)
		description.position = Vector2(20, 93)
		description.size = Vector2(276, 75)
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.text = run.encounter_description(reward)
		card.add_child(description)
		var comparison := Label.new()
		comparison.name = "Comparison"
		comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		comparison.add_theme_font_size_override("font_size", 13 if not reward.upgrade_trait.is_empty() else 14)
		comparison.add_theme_color_override("font_color", reward.color)
		comparison.position = Vector2(20, 178)
		comparison.size = Vector2(276, 56)
		comparison.mouse_filter = Control.MOUSE_FILTER_IGNORE
		comparison.text = run.encounter_comparison(reward).replace(" · ", "\n") if not reward.upgrade_trait.is_empty() else run.encounter_comparison(reward)
		comparison.tooltip_text = comparison.text
		card.add_child(comparison)
		var button: Button = _button(panel, ("免费强化  " if not reward.upgrade_trait.is_empty() else "选择  ") + reward.title.replace(" · 强化", ""), Rect2(x, 366, 316, 52), func() -> void: _request_pick(panel, run, reward.id, offer_token))
		if reward.is_trait and run.backpack_full(): button.text = "替换神器  " + reward.title
		button.name = reward.id.replace("/", "_")
		button.disabled = not run.encounter_has_gain(reward)
		GameUI.card_state(button, false, not button.disabled, reward.color)
		if button.disabled: button.text = "已达上限  " + reward.title
		choice_buttons.append(button)
	if count == 0:
		_text(panel, "普通增益已达到上限，保留当前构筑。", Vector2(40, 174), 24, GameUI.CREAM)
		_text(panel, "已获得的 Boss 补给和收益会保留。" if boss_reward else "无需改变构筑，确认后继续射箭。", Vector2(40, 220), 18, GameUI.MUTED)
	if run.can_skip_encounter():
		_text(panel, "背包已满 · 可替换、选择普通增益，或放弃本次奖励" if run.backpack_full() and not boss_reward else "安全普通增益已满 · 可保持构筑继续", Vector2(34, 436), 14, GameUI.MUTED)
		_button(panel, "保持构筑 · 继续射箭", Rect2(704, 428, 312, 36), func() -> void: action.emit("encounter_skip", offer_token))
	else:
		_text(panel, "战斗已暂停 · 在场箭矢保留发射时属性 · 退出后继续同一组选项", Vector2(34, 436), 14, GameUI.MUTED)

func _history(panel: Panel, run: RunModel) -> void:
	_text(panel, "神器背包  /  %d / %d 格" % [run.artifact_ids().size(), run.artifact_capacity], Vector2(32, 24), 30, GameUI.GOLD)
	var next: int = (run.encounter_rewards_generated + 1) * EncounterCatalog.RULES.kills_per_reward
	_text(panel, "下次奇遇：击倒 %d · 当前 %d · 金币 %d · 神器可强化 3 阶" % [next, run.defeated_count, run.gold], Vector2(34, 73), 17, GameUI.MUTED)
	var scroll := ScrollContainer.new()
	history_scroll = scroll
	scroll.name = "EncounterHistory"
	scroll.position = Vector2(32, 117)
	scroll.size = Vector2(984, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	_artifact_grid(rows, run)
	if run.artifact_capacity > RunModel.ARTIFACT_SLOTS:
		_history_line(rows, "旧存档额外槽位仅保留到本局结束；新局为六格。", 15, GameUI.GOLD)
	var explanations: Array[String] = run.stat_explanations(run.evaluate_stats(run.skill_levels, run.encounter_picks))
	if not run.boss_reward_log.is_empty():
		GameUI.label(rows, "Boss 战利品记录", 18, GameUI.GOLD)
		for record: Dictionary in run.boss_reward_log:
			var reward: EncounterData = EncounterCatalog.find(record["choice"])
			var selection: String = "已跳过 · 普通增益已满" if record["choice"] == RunModel.NO_GAIN else (reward.title if reward != null else "待领取增益")
			if reward != null and not reward.upgrade_trait.is_empty(): selection = EncounterCatalog.find(reward.upgrade_trait).title + " · 免费强化至 %d 阶" % reward.upgrade_rank
			_history_line(rows, "第 %d 次 · %s 分 / %d 金币 / 拉弓 +%d · %s" % [record["round"], GameUI.score_text(record["score"]), record["gold"], record["draws"], selection], 16, GameUI.CREAM)
			if float(record.get("contract_bonus", 0)) > 0:
				_history_line(rows, "其中契约阶段奖励 %s 分" % GameUI.score_text(record.contract_bonus), 14, GameUI.MUTED)
	if not run.discarded_artifacts.is_empty():
		GameUI.label(rows, "已丢弃 · 本局不再出现", 18, GameUI.MUTED)
		for id: String in run.discarded_artifacts:
			_history_line(rows, "%s · 丢弃时强化 %d 阶" % [EncounterCatalog.find(id).title, int(run.discarded_artifacts[id])], 16, GameUI.MUTED)
	if not explanations.is_empty():
		GameUI.label(rows, "属性计算 · 原始 → 联动 → 归一 → 转穿甲 → 转反弹 → 有效", 18, GameUI.GOLD)
		var trace_rows := VBoxContainer.new()
		trace_rows.add_theme_constant_override("separation", 4)
		rows.add_child(trace_rows)
		for line: String in explanations: _history_line(trace_rows, line, 16, GameUI.CREAM)
	if run.encounter_picks.is_empty():
		GameUI.label(rows, "前路尚静，第一场奇遇等待第 %d 次击倒。" % next, 22)
		GameUI.label(rows, "每次奇遇选一项，本局持续增益可以叠加。", 17, GameUI.MUTED)
	for reward: EncounterData in EncounterCatalog.ALL:
		var count: int = int(run.encounter_picks.get(reward.id, 0))
		if count == 0 or reward.is_trait: continue
		GameUI.label(rows, "%s  ×%d  ·  %s" % [reward.title, count, "特性" if reward.is_trait else reward.category_label()], 22, reward.color)
		_history_line(rows, run.encounter_description(reward), 16, GameUI.MUTED)
	if not run.encounters.is_empty():
		GameUI.label(rows, "旧版祝福  ·  保留原有加成", 18, GameUI.MUTED)
		for id: String in run.encounters:
			var old: UpgradeData = GameCatalog.find_upgrade(StringName(id))
			if old != null: GameUI.label(rows, old.title, 17)
	_button(panel, "回到靶场  →", Rect2(704, 524, 312, 52), func() -> void: action.emit("encounter_close", null)).name = "CloseBackpack"
	_text(panel, "仅本局有效 · 丢弃不退金币、不再出现", Vector2(34, 532), 14, GameUI.MUTED)
	_text(panel, "在途箭保留原效果 · 点击卡片右上角查看详情", Vector2(34, 558), 14, GameUI.MUTED)

func _artifact_grid(parent: Control, run: RunModel, incoming: String = "", offer_id: int = -1) -> void:
	var grid := GridContainer.new()
	grid.name = "ArtifactSlots"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	var owned: Array[String] = run.artifact_ids()
	var revision: int = run.artifact_revision
	for index: int in range(run.artifact_capacity):
		var card: Panel = GameUI.panel(grid, Rect2())
		card.custom_minimum_size = Vector2(312, 178)
		card.name = "Slot%d" % index
		if index >= owned.size():
			BuildIcon.add_to(card, "slots", Vector2(14, 14), 30, Color("617770"))
			_text(card, "%02d   空槽位" % (index + 1), Vector2(56, 16), 20, GameUI.MUTED)
			_text(card, "奇遇中的神器会装备到这里", Vector2(16, 67), 16, GameUI.MUTED)
			continue
		var id: String = owned[index]
		var reward: EncounterData = EncounterCatalog.find(id)
		var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
		var rank: int = run.trait_rank(id)
		card.add_theme_stylebox_override("panel", GameUI.box(Color("1e3439"), reward.color))
		BuildIcon.artifact(card, id, Vector2(14, 12), 32, reward.color)
		_text(card, reward.title, Vector2(56, 10), 20, reward.color)
		_text(card, "强化 %d/%d%s" % [rank, config.max_level, " · 含代价" if reward.has_debuff else ""], Vector2(56, 39), 14, GameUI.GOLD if reward.has_debuff else GameUI.MUTED)
		var info: Button = _button(card, "…", Rect2(268, 10, 28, 28), func() -> void: _show_details(run, id))
		info.custom_minimum_size = Vector2(28, 28)
		info.size = Vector2(28, 28)
		info.name = "Details_" + id
		info.tooltip_text = "神器详情 · 效果、代价与下阶比较"
		_text(card, BuildIcon.ARTIFACT_COPY.get(id, reward.description), Vector2(14, 63), 14)
		var detail: Label = _text(card, run.trait_parameters(id), Vector2(14, 88), 13, GameUI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size = Vector2(282, 33)
		detail.clip_text = true
		card.tooltip_text = reward.description + "\n当前：" + run.trait_parameters(id) + "\n下一阶：" + run.trait_comparison(id)
		if not incoming.is_empty():
			var replace_button: Button = _button(card, "替换这件神器", Rect2(14, 127, 282, 40), func() -> void: _confirm_change(run, id, incoming, offer_id, revision))
			replace_button.name = "Replace_" + id
			replace_button.disabled = not run.can_replace_artifact(incoming, id, offer_id, revision)
			replace_button.tooltip_text = run.artifact_removal_blocker(id)
			if EncounterCatalog.find(incoming).requires_trait == id: replace_button.tooltip_text = "新神器需要这件神器，不能替换它"
			continue
		var upgrade: Button = _button(card, "强化 · %d 金币" % run.trait_price(id, rank), Rect2(14, 127, 202, 40), func() -> void: action.emit("trait_upgrade", {"id": id, "rank": rank}))
		upgrade.name = "Upgrade_" + id
		upgrade.add_theme_font_size_override("font_size", 15)
		upgrade.disabled = not run.can_buy_trait(id, rank)
		GameUI.card_state(upgrade, false, not upgrade.disabled, reward.color)
		if rank >= config.max_level: upgrade.text = "强化满阶"
		elif not run.trait_has_gain(id): upgrade.text = "当前无额外收益"
		elif run.gold < run.trait_price(id, rank): upgrade.text = "金币不足 · %d" % run.trait_price(id, rank)
		upgrade.tooltip_text = "下一阶：" + run.trait_comparison(id) + "\n" + run.trait_parameters(id, true)
		var discard: Button = _button(card, "丢弃", Rect2(224, 127, 72, 40), func() -> void: _confirm_change(run, id, "", -1, revision))
		discard.name = "Discard_" + id
		discard.add_theme_font_size_override("font_size", 15)
		discard.disabled = not run.can_discard_artifact(id, revision)
		discard.tooltip_text = run.artifact_removal_blocker(id) if discard.disabled else "丢弃神器及其全部强化；不退还金币"

func _show_details(run: RunModel, id: String) -> void:
	if has_node("ArtifactDetails"): return
	var shade := ColorRect.new()
	shade.name = "ArtifactDetails"
	shade.color = Color(0.02, 0.04, 0.05, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel: Panel = GameUI.panel(shade, Rect2(248, 100, 784, 520))
	var reward: EncounterData = EncounterCatalog.find(id)
	BuildIcon.artifact(panel, id, Vector2(26, 24), 44, reward.color)
	_text(panel, reward.title + " · 强化 %d/%d" % [run.trait_rank(id), TraitUpgradeCatalog.find(id).max_level], Vector2(88, 24), 27, reward.color)
	_text(panel, "含代价 · 请同时考虑损失与收益" if reward.has_debuff else "本局唯一 · 强化不会额外占用槽位", Vector2(88, 65), 16, GameUI.GOLD if reward.has_debuff else GameUI.MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 108)
	scroll.size = Vector2(728, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	_history_line(content, "核心效果", 20, GameUI.GOLD)
	_history_line(content, run.encounter_description(reward), 18, GameUI.CREAM)
	_history_line(content, "当前参数", 20, GameUI.GOLD)
	_history_line(content, run.trait_parameters(id), 17, GameUI.CREAM)
	_history_line(content, "已达最高强化阶数" if run.trait_rank(id) >= TraitUpgradeCatalog.find(id).max_level else "下一阶 · %d 金币" % run.trait_price(id, run.trait_rank(id)), 20, GameUI.GOLD)
	if run.trait_rank(id) < TraitUpgradeCatalog.find(id).max_level:
		_history_line(content, run.trait_comparison(id), 17, Color("a4d9c2"))
		_history_line(content, run.trait_parameters(id, true), 16, GameUI.MUTED)
	_history_line(content, "丢弃不退金币，本局不再出现；在途箭保留发射时的效果。", 16, GameUI.MUTED)
	var close: Button = _button(panel, "返回背包", Rect2(28, 448, 728, 48), func() -> void: shade.queue_free())
	close.name = "CloseArtifactDetails"
	close.grab_focus()

func _request_pick(panel: Panel, run: RunModel, id: String, offer_id: int) -> void:
	if not EncounterCatalog.find(id).is_trait or not run.backpack_full():
		action.emit("encounter_pick", {"id": id, "offer_id": offer_id})
		return
	for child: Node in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	panel.position = Vector2(116, 62)
	panel.size = Vector2(1048, 596)
	_text(panel, "背包已满  /  装备「%s」" % EncounterCatalog.find(id).title, Vector2(32, 24), 28, GameUI.GOLD)
	_text(panel, "选择一件替换 · 原神器与强化会丢失，不退金币 · 返回不会刷新选项", Vector2(34, 73), 16, GameUI.MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(32, 117)
	scroll.size = Vector2(984, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_artifact_grid(scroll, run, id, offer_id)
	_button(panel, "返回奇遇", Rect2(704, 524, 312, 52), func() -> void:
		for child: Node in panel.get_children():
			panel.remove_child(child)
			child.queue_free()
		panel.position = Vector2(116, 124)
		panel.size = Vector2(1048, 474)
		choice_buttons.clear()
		_choices(panel, run)
	).name = "BackToChoices"

func _confirm_change(run: RunModel, outgoing: String, incoming: String, offer_id: int, revision: int) -> void:
	var shade := ColorRect.new()
	shade.name = "ArtifactConfirmation"
	shade.color = Color(0.02, 0.04, 0.05, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var dialog: Panel = GameUI.panel(shade, Rect2(270, 168, 740, 384))
	var title: String = EncounterCatalog.find(outgoing).title
	_text(dialog, "替换神器" if not incoming.is_empty() else "丢弃神器", Vector2(28, 22), 28, GameUI.GOLD)
	var text: String = "失去「%s」及其 %d 阶强化。金币不会退还，本局不会再次出现。" % [title, run.trait_rank(outgoing)]
	if not incoming.is_empty(): text += "\n装备「%s」，从未强化状态开始。" % EncounterCatalog.find(incoming).title
	var explanation: Label = _text(dialog, text, Vector2(28, 73), 17)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.size = Vector2(684, 72)
	var before: BowStats = run.stats
	var after: BowStats = run.preview_artifact_change(outgoing, incoming)
	_text(dialog, "伤害 %.1f → %.1f     箭数 %d → %d     大小 %.2f → %.2f\n暴击 %.0f%% → %.0f%%     穿甲 %d → %d     弹射 %d → %d" % [before.damage, after.damage, before.arrow_count, after.arrow_count, before.arrow_size, after.arrow_size, before.crit_chance * 100, after.crit_chance * 100, before.armor_penetration, after.armor_penetration, before.bounces, after.bounces], Vector2(28, 164), 17)
	_text(dialog, "暴伤 ×%.2f → ×%.2f    初速 %.0f → %.0f    装填 %.2f → %.2f 秒" % [before.crit_multiplier, after.crit_multiplier, before.launch_speed, after.launch_speed, before.reload_seconds, after.reload_seconds], Vector2(28, 216), 17)
	_text(dialog, "神器的触发效果同步移除；在途箭保留发射时的效果。", Vector2(28, 259), 16, GameUI.MUTED)
	_button(dialog, "取消", Rect2(28, 300, 324, 52), func() -> void: shade.queue_free()).name = "CancelArtifact"
	_button(dialog, "确认替换" if not incoming.is_empty() else "确认丢弃", Rect2(388, 300, 324, 52), func() -> void:
		if incoming.is_empty(): action.emit("artifact_discard", {"id": outgoing, "revision": revision})
		else: action.emit("encounter_pick", {"id": incoming, "offer_id": offer_id, "outgoing": outgoing, "revision": revision})
	).name = "ConfirmArtifact"

func restore_scroll(value: int) -> void:
	if history_scroll != null: history_scroll.set_deferred("scroll_vertical", value)

func _history_line(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text = value
	parent.add_child(label)
	return label

func _text(parent: Node, value: String, at: Vector2, font_size: int, color: Color = GameUI.CREAM) -> Label:
	var label: Label = GameUI.label(parent, value, font_size, color)
	label.position = at
	return label

func _button(parent: Node, value: String, rect: Rect2, callback: Callable) -> Button:
	var button: Button = GameUI.button(parent, value, callback)
	button.position = rect.position
	button.size = rect.size
	return button
