class_name TalentPage
extends Control

signal action(id: String, value: Variant)
signal selection_changed(id: String)
var profile: PlayerProfile
var selected: String = "quiver_root"
var detail: Panel
var nodes: Dictionary = {}
var tree_scroll: ScrollContainer

func configure(player: PlayerProfile, selection: String, scroll_position: int = -1) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile = player
	selected = selection if TalentCatalog.find(selection) != null else "quiver_root"
	_text(self, "永久天赋  /  四条成长之路", Vector2(32, 30), 30, GameUI.GOLD)
	_text(self, "Lv.%02d   ·   可用天赋点 %d" % [profile.level, profile.talent_points], Vector2(34, 82), 22)
	_button(self, "主动技能 →", Rect2(590, 38, 218, 44), func() -> void: action.emit("active_skills", null))
	_text(self, "%d 个节点 · 向下滚动查看进阶与终极。早期分支可兼得，同树专精二选一；改动从下一局生效。" % TalentCatalog.ALL.size(), Vector2(34, 121), 16, GameUI.MUTED)
	var reset: Button = _button(self, "免费重置 · 返还 %d 点" % (profile.earned_talent_points - profile.talent_points), Rect2(825, 38, 250, 44), func() -> void: action.emit("talent_reset", null))
	reset.disabled = profile.talents.is_empty() and profile.active_unlocks.is_empty()
	reset.tooltip_text = "返还所有天赋及主动技能解锁点数，并可重新选择免费技能；本局快照不受影响。"
	_button(self, "返回", Rect2(1090, 38, 158, 44), func() -> void: action.emit("back", null))
	tree_scroll = ScrollContainer.new()
	tree_scroll.name = "TalentScroll"
	tree_scroll.position = Vector2(28, 162)
	tree_scroll.size = Vector2(1224, 358)
	tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tree_scroll.follow_focus = true
	add_child(tree_scroll)
	var forest := Control.new()
	forest.custom_minimum_size = Vector2(1200, 588)
	tree_scroll.add_child(forest)
	for tree: int in range(4):
		var panel: Panel = GameUI.panel(forest, Rect2(tree * 302, 0, 286, 584))
		BuildIcon.add_to(panel, ["quiver", "coin", "penetration", "target"][tree], Vector2(14, 10), 32)
		_text(panel, TalentCatalog.TREE_NAMES[tree], Vector2(56, 15), 20, GameUI.GOLD)
		# Actual parent links keep the new tiers readable and reflect the purchase rules.
		for node: TalentData in TalentCatalog.ALL:
			if node.tree != tree: continue
			var pos: Vector2 = _node_position(node)
			var width: float = 222.0 if node.tier == 0 else 126.0
			if not node.parent.is_empty():
				var parent_node: TalentData = TalentCatalog.find(node.parent)
				var start: Vector2 = _node_position(parent_node) + Vector2(111 if parent_node.tier == 0 else 63, 86)
				var end: Vector2 = pos + Vector2(width * 0.5, 0)
				var line := Line2D.new()
				line.width = 3.0 if int(profile.talents.get(node.id, 0)) > 0 else 2.0
				line.default_color = Color("78b99d") if int(profile.talents.get(node.id, 0)) > 0 else (Color("b59f69") if TalentCatalog.lock_reason(profile.talents, profile.talent_points, node.id).is_empty() else Color("3b5154"))
				line.points = PackedVector2Array([start, Vector2(start.x, end.y - 20), Vector2(end.x, end.y - 20), end])
				panel.add_child(line)
			var rank: int = int(profile.talents.get(node.id, 0))
			var reason: String = _lock_reason(node.id)
			var status: String = "满级" if rank == node.max_rank else ("可学" if reason.is_empty() else "%d 点" % node.price(rank))
			if reason == "已选择另一专精": status = "互斥"
			elif reason.begins_with("需要"): status = "待解锁"
			var button: Button = _button(panel, "\n%s\n%d/%d · %s" % [node.title, rank, node.max_rank, status], Rect2(pos, Vector2(width, 86)), func() -> void: _select(node.id))
			button.add_theme_font_size_override("font_size", 14)
			BuildIcon.talent(button, node, Vector2(width * 0.5 - 12, 5))
			button.tooltip_text = node.description + ("\n" + reason if not reason.is_empty() else "")
			nodes[node.id] = button
	_select(selected)
	if scroll_position >= 0: tree_scroll.set_deferred("scroll_vertical", scroll_position)
	else: tree_scroll.ensure_control_visible.call_deferred(nodes[selected])

func _node_position(node: TalentData) -> Vector2:
	return Vector2(32, 60) if node.tier == 0 else Vector2(12 + node.side * 136, 60 + node.tier * 108)

func _lock_reason(id: String) -> String:
	var node: TalentData = TalentCatalog.find(id)
	# Surface an already-chosen specialization even before the opposite parent is learned.
	if not node.exclusive_group.is_empty() and int(profile.talents.get(id, 0)) == 0:
		for other: TalentData in TalentCatalog.ALL:
			if other.id != id and other.exclusive_group == node.exclusive_group and int(profile.talents.get(other.id, 0)) > 0:
				return "已选择另一专精"
	return TalentCatalog.lock_reason(profile.talents, profile.talent_points, id)

func _select(id: String) -> void:
	selected = id
	selection_changed.emit(id)
	for key: String in nodes:
		var rank: int = int(profile.talents.get(key, 0))
		var available: bool = _lock_reason(key).is_empty()
		var border: Color = GameUI.GOLD if key == id or available else (Color("78b99d") if rank > 0 else Color("56605c"))
		var color: Color = GameUI.CREAM if available or rank > 0 else GameUI.MUTED
		GameUI.card_state(nodes[key], key == id, available or rank > 0, border)
		nodes[key].add_theme_color_override("font_color", color)
		var icon: BuildIcon = nodes[key].get_node("BuildIcon")
		icon.ink = GameUI.GOLD if key == id else (Color("8fd9ba") if rank > 0 else color)
		icon.queue_redraw()
	if detail != null:
		remove_child(detail)
		detail.queue_free()
	detail = GameUI.panel(self, Rect2(28, 540, 1224, 132))
	var node: TalentData = TalentCatalog.find(id)
	var rank: int = int(profile.talents.get(id, 0))
	_text(detail, "%s  ·  %d / %d" % [node.title, rank, node.max_rank], Vector2(20, 12), 22, GameUI.GOLD)
	var description: Label = GameUI.label(detail, node.description, 16)
	description.name = "TalentDescription"
	description.position = Vector2(20, 44)
	description.size = Vector2(962, 44)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reason: String = _lock_reason(id)
	var hint: String = "可学习 · 消耗 %d 点" % node.price(rank) if reason.is_empty() else reason
	if node.tree == 0: hint += "   /   击倒与暴击回复合计每次拉弓最多 1 次"
	elif node.tree == 1: hint += "   /   整次拉弓落空中断连击；仅击倒获得金币"
	if node.tier >= 2: hint += "   /   免费重置可重新选择专精"
	var requirement: Label = GameUI.label(detail, hint, 14, GameUI.MUTED)
	requirement.position = Vector2(20, 92)
	requirement.size = Vector2(962, 32)
	requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buy: Button = _button(detail, "学习 · %d 点" % node.price(rank) if rank < node.max_rank else "已满级", Rect2(1012, 43, 190, 48), func() -> void: action.emit("talent_buy", selected))
	buy.name = "PurchaseTalent"
	buy.disabled = not reason.is_empty()

func _text(parent: Node, value: String, at: Vector2, font_size: int, color: Color = GameUI.CREAM) -> void:
	GameUI.label(parent, value, font_size, color).position = at

func _button(parent: Node, value: String, rect: Rect2, callback: Callable) -> Button:
	var button: Button = GameUI.button(parent, value, callback)
	button.position = rect.position
	button.size = rect.size
	return button
