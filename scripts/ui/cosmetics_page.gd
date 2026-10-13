class_name CosmeticsPage
extends Control

signal action(id: String, value: Variant)
var equip_buttons: Dictionary = {}
var preview: CosmeticPreview

func configure(profile: PlayerProfile) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text(self, "装扮 / 弓手的行装", Vector2(48, 40), 30, GameUI.GOLD)
	_text(self, "永久等级 Lv.%d · 累计击倒 %d 次 · 解锁后免费装备" % [profile.level, profile.total_defeats], Vector2(50, 99), 18)
	var back: Button = GameUI.button(self, "返回大厅", func() -> void: action.emit("back", null))
	back.position = Vector2(1100, 44)
	back.size = Vector2(132, 44)
	var panel: Panel = GameUI.panel(self, Rect2(48, 156, 344, 456))
	_text(panel, "当前搭配", Vector2(20, 16), 23, GameUI.GOLD)
	preview = CosmeticPreview.new()
	preview.loadout = profile.equipped_cosmetics.duplicate(true)
	preview.position = Vector2(12, 62)
	preview.size = Vector2(320, 270)
	panel.add_child(preview)
	var slot_names: Dictionary = {"bow": "弓", "arrow": "箭", "archer": "角色"}
	for index: int in range(CosmeticCatalog.SLOTS.size()):
		var slot: String = CosmeticCatalog.SLOTS[index]
		_text(panel, "%s · %s" % [slot_names[slot], CosmeticCatalog.equipped(profile.equipped_cosmetics, slot).title], Vector2(20, 342 + index * 32), 17)
		var x: float = 428 + index * 276
		_text(self, slot_names[slot], Vector2(x, 161), 23, GameUI.GOLD)
		var row: int = 0
		for skin: CosmeticData in CosmeticCatalog.ALL:
			if skin.slot != slot: continue
			var card: Panel = GameUI.panel(self, Rect2(x, 203 + row * 144, 252, 132))
			var available: bool = profile.unlocked_cosmetics.has(skin.id)
			var equipped: bool = profile.equipped_cosmetics[slot] == skin.id
			if equipped: card.add_theme_stylebox_override("panel", GameUI.box(Color("263d3d"), GameUI.GOLD))
			var sample := CosmeticPreview.new()
			sample.skin = skin
			sample.position = Vector2(8, 16)
			sample.size = Vector2(64, 84)
			if not available: sample.modulate.a = 0.55
			card.add_child(sample)
			_text(card, skin.title, Vector2(84, 13), 19)
			_text(card, skin.condition(), Vector2(84, 48), 14, GameUI.MUTED)
			var button: Button = GameUI.button(card, "已装备" if equipped else ("装备" if available else "未解锁"), func() -> void: action.emit("cosmetic_equip", skin.id))
			button.name = skin.id
			button.position = Vector2(84, 82)
			button.size = Vector2(156, 42)
			button.disabled = equipped or not available
			button.tooltip_text = skin.condition() + "；只改变外观"
			equip_buttons[skin.id] = button
			row += 1
	_text(self, "只改变配色与装饰 · 不改变伤害、箭数、速度或碰撞 · 金币仅用于本局技能", Vector2(50, 649), 16, GameUI.MUTED)

func _text(parent: Node, value: String, at: Vector2, font_size: int, color: Color = GameUI.CREAM) -> void:
	var label: Label = GameUI.label(parent, value, font_size, color)
	label.position = at
