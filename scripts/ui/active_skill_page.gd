class_name ActiveSkillPage
extends Control

signal action(id: String, value: Variant)

func configure(session: GameSession) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var profile: PlayerProfile = session.profile
	var heading: Label = GameUI.label(self, "永久天赋  /  主动技能", 30, GameUI.GOLD)
	heading.position = Vector2(32, 30)
	var back: Button = GameUI.button(self, "返回天赋树", func() -> void: action.emit("talents", null))
	back.position = Vector2(1030, 38)
	back.size = Vector2(218, 44)
	var info: Label = GameUI.label(self, "可用天赋点 %d  ·  首个免费选择，其余各 %d 点  ·  同时装备 1 个" % [profile.talent_points, ActiveAbility.UNLOCK_COST], 20)
	info.position = Vector2(34, 93)
	var hint: Label = GameUI.label(self, "技能随箭矢属性成长；天赋重置返还解锁花费，并可重选免费技能。", 16, GameUI.MUTED)
	hint.position = Vector2(34, 132)
	var index: int = 0
	for id: String in ActiveAbility.ALL:
		var data: Dictionary = ActiveAbility.ALL[id]
		var owned: bool = profile.active_unlocks.has(id)
		var equipped: bool = profile.equipped_active == id
		var card: Panel = GameUI.panel(self, Rect2(32 + index * 410, 192, 396, 350))
		var title: Label = GameUI.label(card, data.title, 28, GameUI.GOLD)
		title.position = Vector2(84, 25)
		var icon := ActiveSkillIcon.new()
		icon.position = Vector2(24, 22)
		icon.configure(id, equipped)
		card.add_child(icon)
		if equipped: card.add_theme_stylebox_override("panel", GameUI.box(Color("233a38"), GameUI.GOLD))
		var cost: Label = GameUI.label(card, "能量 %d  /  %s" % [data.cost, "已装备" if equipped else ("已解锁" if owned else "待解锁")], 18, Color("8fd9ba"))
		cost.position = Vector2(52, 77)
		BuildIcon.add_to(card, "energy", Vector2(24, 78), 20, Color("8fd9ba"))
		var description: Label = GameUI.label(card, data.description, 18)
		description.name = "SkillDescription"
		description.position = Vector2(24, 124)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size = Vector2(348, 118)
		description.set_deferred("size", Vector2(348, 118))
		var price: int = 0 if profile.active_unlocks.is_empty() else ActiveAbility.UNLOCK_COST
		var caption: String = ("已装备" if equipped else "装备技能") if owned else ("免费选择" if price == 0 else "解锁 · %d 天赋点" % price)
		var button: Button = GameUI.button(card, caption, func() -> void: action.emit("active_equip" if owned else "active_unlock", id))
		button.name = id
		button.position = Vector2(24, 275)
		button.size = Vector2(348, 48)
		button.disabled = (equipped or session.has_active_run()) if owned else profile.talent_points < price
		GameUI.card_state(button, equipped, not button.disabled)
		if owned and session.has_active_run(): button.tooltip_text = "本局技能已锁定，结束冒险后可更换。"
		index += 1
	var rule: Label = GameUI.label(self, "每次拉弓 +8 能量，整轮命中 +4，命中靶心再 +2，上限 100。\n等待不恢复能量；分裂、范围伤害和战技强化伤害不额外回能。战斗中按 Q 或点击技能施放。", 17, GameUI.MUTED)
	rule.position = Vector2(34, 577)
	var lock_text: String = "出战时锁定技能，开局能量归零。大厅可自由换装。"
	if session.has_active_run():
		var current: String = str(ActiveAbility.ALL[session.run.active.id].title) if ActiveAbility.ALL.has(session.run.active.id) else "未装备（新局生效）"
		lock_text = "本局已锁定：%s。现在解锁或重置，只影响下一局。" % current
	var lock_hint: Label = GameUI.label(self, lock_text, 17, GameUI.GOLD)
	lock_hint.position = Vector2(34, 650)
