class_name GameHUD
extends Control

signal action(id: String, value: Variant)
const GOLD = GameUI.GOLD
const MUTED = GameUI.MUTED
var overlay: ColorRect
var content: VBoxContainer
var phase_card: Panel
var stage_label: Label
var gold_label: Label
var shots_label: Label
var score_label: Label
var stats_label: Label
var hint_label: Label
var progress: ProgressBar
var debug_label: Label
var mute_button: Button
var pause_button: Button
var skills_button: Button
var encounters_button: Button
var encounter_panel: EncounterPanel
var encounter_log_open: bool = false
var supply_enabled: bool = true # Unlimited practice hides the formal supply economy.
var mode_label: Label
var boss_hint: Label
var boss_panel: Panel
var boss_title: Label
var boss_health: ProgressBar

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header: Panel = GameUI.panel(self, Rect2(24, 20, 1232, 76))
	var logo: Label = GameUI.label(header, "箭如雨下", 23, GOLD)
	logo.position = Vector2(20, 6)
	var caption: Label = GameUI.label(header, "A R R O W S  L I K E  R A I N", 11, MUTED)
	caption.position = Vector2(21, 44)
	stage_label = GameUI.label(header, "", 18)
	stage_label.position = Vector2(205, 10)
	score_label = GameUI.label(header, "", 14, MUTED)
	score_label.position = Vector2(205, 39)
	progress = ProgressBar.new()
	progress.position = Vector2(415, 29)
	progress.size = Vector2(220, 12)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", GameUI.box(Color("10252c"), Color("263d40")))
	progress.add_theme_stylebox_override("fill", GameUI.box(Color("c9ab68"), Color("c9ab68")))
	header.add_child(progress)
	shots_label = GameUI.label(header, "", 18)
	shots_label.position = Vector2(668, 22)
	gold_label = GameUI.label(header, "", 20, GOLD)
	gold_label.position = Vector2(833, 20)
	mute_button = GameUI.button(header, "声音 开", func() -> void: action.emit("mute", null))
	mute_button.position = Vector2(995, 18)
	mute_button.size = Vector2(94, 38)
	pause_button = GameUI.button(header, "暂停", func() -> void: action.emit("pause", null))
	pause_button.position = Vector2(1101, 18)
	pause_button.size = Vector2(108, 38)
	var footer: Panel = GameUI.panel(self, Rect2(24, 638, 1232, 62))
	stats_label = GameUI.label(footer, "", 16)
	stats_label.position = Vector2(16, 7)
	hint_label = GameUI.label(footer, "", 13, MUTED)
	hint_label.position = Vector2(16, 34)
	var instruction: Label = GameUI.label(self, "按住弓附近，向后拖拽\n松手射箭 · 向下拖可抬高弹道", 16, Color("b3c4b6"))
	instruction.position = Vector2(40, 338)
	instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_label = GameUI.label(self, "暮 林 · 连 续 靶 场", 13, MUTED)
	mode_label.position = Vector2(43, 122)
	debug_label = GameUI.label(self, "", 14, GOLD)
	skills_button = GameUI.button(self, "技能", func() -> void: action.emit("skills", null))
	skills_button.position = Vector2(40, 157)
	skills_button.size = Vector2(108, 42)
	encounters_button = GameUI.button(self, "神器背包", func() -> void: action.emit("encounters", null))
	encounters_button.position = Vector2(160, 157)
	encounters_button.size = Vector2(160, 42)
	debug_label.position = Vector2(35, 213)
	debug_label.visible = false
	boss_hint = GameUI.label(self, "", 14, GOLD)
	boss_hint.position = Vector2(40, 226)
	boss_panel = GameUI.panel(self, Rect2(400, 116, 620, 72))
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_title = GameUI.label(boss_panel, "", 18, GOLD)
	boss_title.position = Vector2(16, 8)
	boss_health = ProgressBar.new()
	boss_health.position = Vector2(16, 40)
	boss_health.size = Vector2(588, 16)
	boss_health.show_percentage = false
	boss_health.add_theme_stylebox_override("background", GameUI.box(Color("10252c"), Color("263d40")))
	boss_health.add_theme_stylebox_override("fill", GameUI.box(Color("bc7048"), Color("bc7048")))
	boss_panel.add_child(boss_health)
	boss_panel.hide()
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.055, 0.07, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	phase_card = GameUI.panel(overlay, Rect2(250, 106, 780, 516))
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	phase_card.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	overlay.visible = false

func _clear_content() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

func _coin_label(value: int) -> String:
	if value >= 100000000: return "%.2f亿" % (value / 100000000.0)
	if value >= 10000: return "%.1f万" % (value / 10000.0)
	return str(value)

func refresh(run: RunModel, profile: PlayerProfile, muted: bool, save_notice: String) -> void:
	mode_label.text = "暮 林 · 连 续 靶 场 · %s" % run.difficulty_title()
	mode_label.tooltip_text = ContractCatalog.description(run.challenge)
	mode_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stage_label.text = "击倒 %d  ·  Lv.%d" % [run.defeated_count, profile.level]
	var floor_score: float = PlayerProfile.RULES.threshold(profile.level)
	var next_score: float = PlayerProfile.RULES.threshold(profile.level + 1)
	score_label.text = "经验 %s / %s" % [GameUI.score_text(profile.total_score - floor_score), GameUI.score_text(next_score - floor_score)]
	progress.max_value = next_score - floor_score
	progress.value = profile.total_score - floor_score
	if profile.level >= PlayerProfile.RULES.max_level:
		score_label.text = "等级已满"
		progress.value = progress.max_value
	shots_label.text = "剩余拉弓  %02d" % run.shots_left
	gold_label.text = "金币  %s" % _coin_label(run.gold)
	var stats: BowStats = run.stats
	stats_label.text = "单箭 %.1f  /  箭数 %d  /  暴击 %.0f%% ×%.2f  /  穿甲 %d  /  反弹 %d  /  尺寸 ×%.2f  /  得分 %s" % [stats.damage, stats.arrow_count, stats.crit_chance * 100, stats.crit_multiplier, stats.armor_penetration, stats.bounces, stats.arrow_size, GameUI.score_text(run.defeat_score)]
	hint_label.text = "连中 %d 次 · 齐射结束结算收益 · 整次落空中断连击    ESC 暂停 / 取消拉弓    F3 数值面板    M 静音" % run.combo
	if run.shots_left == 0 and not run.is_finished():
		hint_label.text = "最后一轮箭矢正在结算……"
	if run.phase == RunModel.Phase.SUPPLY:
		hint_label.text = "本轮结算完成 · 购买补给继续，或结束本局。"
	if not save_notice.is_empty():
		hint_label.text = save_notice
	mute_button.text = "声音 关" if muted else "声音 开"
	encounters_button.text = "奇遇 · 待选 %d" % run.pending_encounters if run.pending_encounters > 0 else "背包 · %d/%d" % [run.artifact_ids().size(), run.artifact_capacity]
	_show_phase(run, profile)

func update_availability(run: RunModel, _settled: bool) -> void:
	skills_button.disabled = run.phase != RunModel.Phase.PLAYING
	encounters_button.disabled = run.phase != RunModel.Phase.PLAYING
	encounters_button.tooltip_text = "查看、强化或丢弃神器；每累计 %d 次击倒获得一次选择" % EncounterCatalog.RULES.kills_per_reward
	skills_button.tooltip_text = "暂停战斗并升级；在场箭矢保留发射时属性"

func update_boss(run: RunModel, world: ArcheryWorld) -> void:
	boss_panel.visible = run.boss_active and world.boss != null and run.phase == RunModel.Phase.PLAYING and not encounter_log_open
	if run.boss_active:
		boss_hint.text = "BOSS 第 %d 次 · 击败后重新补靶" % run.boss_round
	elif run.boss_due():
		boss_hint.text = "BOSS 将至 · 等待箭矢与奇遇结算"
	else:
		boss_hint.text = "下次 BOSS · 击倒 %d / %d" % [run.defeated_count, run.boss_next_defeats]
		boss_hint.text += "\n已击败 Boss %d 次 · 胜利补给与增益见背包记录" % run.bosses_defeated
	if world.boss != null:
		var mode: String = "旧版静态" if world.boss.combat_schema == 0 else "阶段 %d" % world.boss.battle_phase
		boss_title.text = "%s · %s · 第 %d 次   HP %d / %d   甲 %d" % [RunModel.BOSS_RULES.title, mode, run.boss_round, ceili(world.boss.hp), ceili(world.boss.max_hp), world.boss.armor]
		if world.boss.combat_schema == 1:
			boss_hint.text += "\n金色弱点 ×%.2f · 甲 %d" % [float(world.boss.parameters["weak_multiplier"]), maxi(0, world.boss.armor - int(world.boss.parameters["weak_armor_reduction"]))]
			if world.boss.battle_phase == 2: boss_hint.text += "\n护板甲 %d · 穿甲更高才能穿过" % world.boss.shield_armor()
		boss_health.max_value = world.boss.max_hp
		boss_health.value = world.boss.hp

func _show_phase(run: RunModel, profile: PlayerProfile) -> void:
	var history_position: int = encounter_panel.history_scroll.scroll_vertical if encounter_panel != null and encounter_panel.history_scroll != null and encounter_log_open else 0
	if encounter_panel != null:
		remove_child(encounter_panel)
		encounter_panel.queue_free()
		encounter_panel = null
	if run.phase == RunModel.Phase.CHOICE or (encounter_log_open and run.phase == RunModel.Phase.PLAYING):
		overlay.hide()
		encounter_panel = EncounterPanel.new()
		add_child(encounter_panel)
		encounter_panel.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
		encounter_panel.configure(run, run.phase == RunModel.Phase.CHOICE)
		encounter_panel.restore_scroll(history_position)
		return
	overlay.visible = run.phase != RunModel.Phase.PLAYING

	if not overlay.visible:
		return
	_clear_content()
	phase_card.position.y = 106
	phase_card.size.y = 516
	content.add_theme_constant_override("separation", 10)
	if run.phase == RunModel.Phase.SHOP:
		var has_mastery: bool = false
		for skill: RunSkillData in SkillCatalog.ALL:
			if run.skill_is_mastery(skill): has_mastery = true
		phase_card.position.y = 24
		phase_card.size.y = 672
		content.add_theme_constant_override("separation", 6)
		GameUI.label(content, "技能 · 让下一箭更强", 25, GOLD)
		GameUI.label(content, "战斗已暂停 · 在场箭矢保留原属性，新升级从下一次拉弓生效。", 14, MUTED)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		content.add_child(grid)
		for upgrade: RunSkillData in SkillCatalog.ALL:
			var mastery: bool = run.skill_is_mastery(upgrade)
			var count: int = run.skill_rank(upgrade)
			var price: int = run.skill_price(upgrade)
			var suffix: String = "%s 金" % _coin_label(price)
			if count >= run.skill_limit(upgrade):
				suffix = "精通已满" if mastery else "基础已满"
			elif not run.skill_has_gain(upgrade):
				suffix = "暂无有效收益"
			elif run.gold < price:
				suffix += " · 缺 %s" % _coin_label(price - run.gold)
			var comparison: String = run.skill_comparison(upgrade)
			var text: String = "%s%s %d/%d | %s\n%s\n%s" % [upgrade.title, " · 精通" if mastery else "", count, run.skill_limit(upgrade), suffix, upgrade.mastery_description if mastery else upgrade.description, comparison]
			var button: Button = GameUI.button(grid, text, func() -> void: action.emit("purchase", upgrade))
			button.name = String(upgrade.id)
			button.custom_minimum_size = Vector2(362, 110 if has_mastery else 98)
			button.add_theme_font_size_override("font_size", 13 if has_mastery else 14)
			button.disabled = not run.can_buy(upgrade)
			var before_lines: Array[String] = run.stat_explanations(run.evaluate_stats(run.skill_levels, run.encounter_picks))
			var after_lines: Array[String] = run.stat_explanations(run.preview_skill_evaluation(upgrade))
			button.tooltip_text = "当前\n" + "\n".join(before_lines) + "\n升级后\n" + "\n".join(after_lines) if not before_lines.is_empty() else comparison
			button.tooltip_text = "本次价格 %d 金币\n基础 %d/%d · 精通 %d/%d\n" % [price, int(run.skill_levels.get(String(upgrade.id), 0)), upgrade.max_level, int(run.mastery_levels.get(String(upgrade.id), 0)), upgrade.mastery_max_level] + button.tooltip_text
		GameUI.label(content, "基础满级或效果封顶后开放精通；收益渐缓。穿甲 > 护甲才贯穿。", 13, MUTED)
		var economy: Label = GameUI.label(content, "本局累计收入 %s 金 · 累计消费 %s 金" % [_coin_label(int(run.gold_earned)), _coin_label(run.gold_spent)], 14, MUTED)
		economy.mouse_filter = Control.MOUSE_FILTER_STOP
		economy.tooltip_text = "金币用于基础技能、精通、神器强化与拉弓补给；本局结束后清空。"
		if supply_enabled: _supply_row(run)
		GameUI.button(content, "返回靶场 →", func() -> void: action.emit("continue", null))
	elif run.phase == RunModel.Phase.SUPPLY:
		phase_card.position.y = 172
		phase_card.size.y = 376
		GameUI.label(content, "箭袋已空 · 再射一轮？", 30, GOLD)
		GameUI.label(content, "本轮箭矢与奖励已全部结算。购买补给后继续当前靶场。", 17, MUTED)
		_spacer(12)
		GameUI.label(content, "金币 %s · 累计收入 %s · 累计消费 %s" % [_coin_label(run.gold), _coin_label(int(run.gold_earned)), _coin_label(run.gold_spent)], 17)
		_supply_row(run)
		GameUI.label(content, "每段最多补给 %d 次；击败 Boss 恢复额度，价格继续递增。" % int(run.supply_parameters["limit"]), 15, MUTED)
		GameUI.label(content, "结束本局后清空剩余金币，保留等级与天赋点。", 15, MUTED)
		GameUI.button(content, "结束本局", func() -> void: action.emit("supply_end", run.supply_offer_id)).name = "SupplyEnd"
	else:
		GameUI.label(content, "箭已尽，成长留下。", 32, GOLD)
		GameUI.label(content, "%s · 本局击倒 %d 个靶子 · 得分 %s" % [run.difficulty_title(), run.defeated_count, GameUI.score_text(run.defeat_score)], 22)
		GameUI.label(content, "累计收入 %s 金 · 消费 %s 金 · 剩余金币已清空" % [_coin_label(int(run.gold_earned)), _coin_label(run.gold_spent)], 18, MUTED)
		var loot: Dictionary = run.boss_reward_totals()
		GameUI.label(content, "击败 Boss %d 次 · 战利品 %s 分 / %d 金币 / 拉弓 +%d" % [run.bosses_defeated, GameUI.score_text(loot["score"]), loot["gold"], loot["draws"]], 18, GOLD)
		if not run.challenge.is_empty():
			GameUI.label(content, "得分中已含契约阶段奖励 %s 分 · 未击败 Boss 的阶段不发放" % GameUI.score_text(run.contract_stage_bonus_earned), 14, MUTED)
		GameUI.label(content, "等级 Lv.%d → Lv.%d  ·  获得天赋点 +%d" % [run.starting_level, profile.level, profile.level - run.starting_level], 22, GOLD)
		GameUI.label(content, "可用天赋点 %d · 返回大厅学习永久天赋，让下一局更强。" % profile.talent_points, 16, MUTED)
		var ranking: String = "本局进入本地榜 · 第 %d 名" % run.rank_at_finish if run.rank_at_finish > 0 else ("本局未进入前三" if run.defeat_score > 0 else "本局零分 · 不入榜")
		if run.ended_at == 0: ranking = "旧局成绩未补录 · 新冒险结束后可入榜"
		var rank_label: Label = GameUI.label(content, ranking, 18, GOLD)
		rank_label.name = "RankingStatus"
		_spacer(12)
		GameUI.button(content, "重新开局", func() -> void: action.emit("new_run", null))
		GameUI.button(content, "返回大厅", func() -> void: action.emit("hub", null))

func _supply_row(run: RunModel) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var caption: Label = GameUI.label(row, "拉弓补给 +%d · 本段剩余 %d/%d
本局已购买 %d 次 · Boss 胜利恢复额度" % [int(run.supply_parameters["draws"]), run.supply_remaining(), int(run.supply_parameters["limit"]), run.supply_total_bought], 14, MUTED)
	if int(run.supply_parameters["limit"]) == 0: caption.text = "本局契约禁止购买拉弓补给\n击败 Boss 仍可获得胜利回复"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var token: Dictionary = run.supply_token()
	var suffix: String = "%s 金" % _coin_label(run.supply_price())
	if int(run.supply_parameters["limit"]) == 0: suffix = "契约禁止购买"
	elif run.supply_remaining() <= 0: suffix = "本段额度已用尽"
	elif run.shots_left >= 100000: suffix = "拉弓次数已达上限"
	elif run.gold < run.supply_price(): suffix += " · 缺 %s" % _coin_label(run.supply_price() - run.gold)
	var button: Button = GameUI.button(row, "购买补给 · " + suffix, func() -> void: action.emit("supply_buy", token))
	button.name = "SupplyBuy"
	button.custom_minimum_size.x = 240
	button.add_theme_font_size_override("font_size", 14)
	button.disabled = not run.can_buy_supply(token)
	button.tooltip_text = "本次 %d 金币；下次 %d 金币。每次只增加拉弓次数。" % [run.supply_price(), SupplyRules.price(run.supply_parameters, run.supply_total_bought + 1)]

func _spacer(height: float) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = height
	content.add_child(spacer)




