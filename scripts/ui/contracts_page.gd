class_name ContractsPage
extends Control

signal action(id: String, value: Variant)

func configure(selection: Dictionary, profile: PlayerProfile, locked_run: RunModel = null) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var locked: bool = locked_run != null
	var legacy: bool = locked and locked_run.challenge.is_empty()
	var challenge: Dictionary = locked_run.challenge if locked else ContractCatalog.snapshot(selection)
	var picks: Dictionary = challenge.get("selection", {})
	var p: Dictionary = challenge.get("parameters", ContractCatalog.parameters({}))
	var title: Label = GameUI.label(self, "挑战契约  /  %s" % ("本局已锁定" if locked else "选择你要面对的挑战"), 28, GameUI.GOLD)
	title.position = Vector2(40, 32)
	for index: int in range(3):
		var id: String = ["normal", "hard", "hell"][index]
		var preset: Button = GameUI.button(self, DifficultyCatalog.title(id) + "预设", func() -> void: action.emit("contract_preset", id))
		preset.name = "Preset_" + id
		preset.position = Vector2(800 + index * 146, 30)
		preset.size = Vector2(136, 42)
		preset.disabled = locked
	for index: int in range(ContractCatalog.ALL.size()):
		var item: Dictionary = ContractCatalog.ALL[index]
		var rank: int = int(picks.get(item.id, 0))
		var card: Panel = GameUI.panel(self, Rect2(40 + (index % 2) * 404, 102 + (index / 2) * 130, 392, 120))
		card.name = "Contract_" + item.id
		var heading: Label = GameUI.label(card, item.title + "  ·  " + item.scope, 20, GameUI.GOLD if rank > 0 else GameUI.CREAM)
		heading.position = Vector2(14, 8)
		var detail: Label = GameUI.label(card, item.options[rank - 1] if rank > 0 else ("旧版冒险沿用原难度" if legacy else ("本局未启用" if locked else "未启用 · 点击 I / II 查看并选择")), 14, GameUI.MUTED)
		detail.position = Vector2(14, 40)
		for level: int in range(3):
			var text: String = ["关闭", "I · 挑战 +1", "II · 挑战 +2"][level]
			var button: Button = GameUI.button(card, ("✓ " if level == rank else "") + text, func() -> void: action.emit("contract_select", {"id": item.id, "rank": level}))
			button.name = item.id + "_" + str(level)
			button.position = Vector2(14 + level * 122, 74)
			button.custom_minimum_size = Vector2(0, 32)
			button.size = Vector2(114, 32)
			button.add_theme_font_size_override("font_size", 14)
			button.disabled = locked
			button.tooltip_text = item.options[level - 1] if level > 0 else "关闭此词条"
	var summary: Panel = GameUI.panel(self, Rect2(860, 102, 380, 510))
	var caption: Label = GameUI.label(summary, (DifficultyCatalog.title(locked_run.mode_id) + " · 旧版冒险") if legacy else "挑战等级  %d" % int(challenge.risk), 27, GameUI.GOLD)
	caption.position = Vector2(20, 18)
	var initial: int = RunModel.INITIAL_SHOTS + int(TalentCatalog.effects(profile.talents).get("initial_shots", 0)) - int(p.draw_penalty)
	if locked: initial = locked_run.initial_shots
	var stats: String = "开局拉弓 %d 次 · 神器 %d 格\n每段可买补给 %d 次\n技能 / 神器价格 ×%.2f\n普通靶血量 ×%.2f · 护甲 +%d\nBoss 血量 ×%.2f\n普通靶靶心高度 ×%.2f" % [initial, int(p.artifact_slots), int(p.supply_limit), p.price_multiplier, p.target_health, int(p.target_armor), p.boss_health, p.bullseye_scale]
	if legacy:
		var old: Dictionary = locked_run.mode_parameters
		stats = "此存档继续沿用原有难度与构筑。\n\n普通靶血量 ×%.2f\nBoss 血量 ×%.2f · 得分 ×%.2f\n每击倒一次，新靶基础血量 +%.0f%%\n初始拉弓 %d 次 · 神器 %d 格\n\n本局结束后，新冒险可自由搭配契约。" % [old.target_health, old.boss_health, old.score, old.health_growth * 100, initial, locked_run.artifact_capacity]
	var body: Label = GameUI.label(summary, stats, 16)
	body.position = Vector2(20, 72)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size = Vector2(340, 360 if legacy else 190)
	var rewards: Label = GameUI.label(summary, "得分与经验\n普通靶 ×%.2f · Boss ×%.2f\n击败 Boss 后，另得该轮\n普通靶与 Boss 基础分的 %.0f%%。\n未击败 Boss，不发阶段额外分。\n\n金币收益保持原规则。\n同类只选一档，组合可能更难。" % [p.target_score, p.boss_score, p.stage_bonus * 100], 15, GameUI.MUTED)
	rewards.position = Vector2(20, 278)
	rewards.visible = not legacy
	var back: Button = GameUI.button(self, "返回大厅", func() -> void: action.emit("hub", null))
	back.name = "ContractsBack"
	back.position = Vector2(40, 638)
	back.size = Vector2(220, 48)
	var note: Label = GameUI.label(self, "当前冒险保持原契约；新冒险才能修改。" if locked else "开局后锁定 · 预设可继续修改 · 零词条也可正常开始", 16, GameUI.MUTED)
	note.position = Vector2(282, 651)
	var start: Button = GameUI.button(self, "继续射箭" if locked else "按此契约出征", func() -> void: action.emit("range", null))
	start.name = "ContractsStart"
	start.position = Vector2(960, 638)
	start.size = Vector2(280, 48)
