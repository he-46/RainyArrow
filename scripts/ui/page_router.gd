class_name PageRouter
extends Control
## Owns one non-combat page at a time; navigation never constructs a world.

signal action(id: String, value: Variant)
var route: String = "home"
var return_route: String = "home"
var settings_return_route: String = "home"
var page: Control
var continue_button: Button
var selected_mode: String = "normal"
var selected_contracts: Dictionary = {}
var selected_talent: String = "quiver_root"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_page(destination: String, session: GameSession, notice: String = "") -> void:
	if destination == "leaderboard": return_route = "hub"
	if destination == "settings" and route != "settings": settings_return_route = route
	if destination in ["settings", "tutorial", "talents", "cosmetics", "pause"]:
		if route in ["home", "hub", "range"]:
			return_route = route
	route = destination
	if page != null:
		remove_child(page)
		page.queue_free()
		page = null
	continue_button = null
	visible = destination != "range"
	if not visible:
		return
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	page.add_child(MenuBackdrop.new())
	match destination:
		"contracts":
			var contracts_page := ContractsPage.new()
			page.add_child(contracts_page)
			contracts_page.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
			contracts_page.configure(selected_contracts, session.profile, session.run if session.has_active_run() else null)
		"leaderboard":
			_text("射箭记录", Vector2(52, 48), 28, GameUI.GOLD)
			_button("返回大厅", Rect2(1100, 48, 128, 44), "hub")
			_ranking(session.profile, Rect2(260, 190, 760, 300))
		"home": _home(session)
		"hub": _hub(session)
		"tutorial": pass # TutorialController owns the disposable field and page.
		"cosmetics":
			var cosmetics_page := CosmeticsPage.new()
			page.add_child(cosmetics_page)
			cosmetics_page.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
			cosmetics_page.configure(session.profile)
		"settings":
			var settings_page := SettingsPage.new()
			page.add_child(settings_page)
			settings_page.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
			settings_page.configure(session.profile.settings)
		"talents":
			var tree := TalentPage.new()
			page.add_child(tree)
			tree.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
			tree.selection_changed.connect(func(id: String) -> void: selected_talent = id)
			tree.configure(session.profile, selected_talent)
		_: _feature(destination, session)
	if not notice.is_empty():
		var status: Label = _text(notice, Vector2(48, 672), 13, GameUI.GOLD)
		status.size.x = 1180
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func back_destination() -> String:
	return settings_return_route if route == "settings" else return_route

func sync_settings(options: Dictionary) -> void:
	if route != "settings" or page == null: return
	for child: Node in page.get_children():
		if child is SettingsPage: child.sync(options)

func _home(session: GameSession) -> void:
	_text("暮 林 · 弓 手 的 旅 途", Vector2(80, 76), 15, GameUI.MUTED)
	_text("箭如雨下", Vector2(72, 119), 76, GameUI.GOLD)
	_text("拉开弓弦，让每一箭生出新的可能。", Vector2(82, 228), 20)
	_button("开始游戏   →", Rect2(82, 312, 330, 56), "start")
	continue_button = _button("继续游戏", Rect2(82, 382, 330, 56), "resume_hub")
	continue_button.disabled = not session.has_active_run()
	continue_button.tooltip_text = "继续未结束的靶场" if session.has_active_run() else "尚无进行中的冒险，先开始游戏"
	_button("设置", Rect2(82, 452, 158, 48), "settings")
	_button("教程 · 重玩" if session.profile.tutorial_completed else "教程", Rect2(254, 452, 158, 48), "tutorial")
	_text("已有冒险等待继续" if session.has_active_run() else "暂无可继续的冒险", Vector2(84, 522), 14, GameUI.MUTED)
	_text("像素弓箭 · 随机构筑 · 永久成长", Vector2(82, 651), 14, GameUI.MUTED)
	_button("退出", Rect2(1124, 642, 108, 42), "quit")
	_ranking(session.profile, Rect2(560, 304, 668, 300))

func _ranking(profile: PlayerProfile, rect: Rect2) -> void:
	var panel := LeaderboardPanel.new()
	panel.position = rect.position
	panel.size = rect.size
	page.add_child(panel)
	panel.configure(profile.leaderboard)

func _hub(session: GameSession) -> void:
	_text("箭如雨下  /  弓手营地", Vector2(52, 48), 28, GameUI.GOLD)
	_button("主页面", Rect2(1100, 48, 128, 44), "home")
	_button("设置", Rect2(948, 48, 128, 44), "settings")
	_button("教程", Rect2(796, 48, 128, 44), "tutorial")
	_button("排行榜", Rect2(644, 48, 128, 44), "leaderboard")
	var profile: PlayerProfile = session.profile
	_text("Lv.%02d     可用天赋点  %d" % [profile.level, profile.talent_points], Vector2(56, 114), 22)
	_difficulty_selector(session)
	var titles: Array[String] = ["去射箭", "天赋", "装扮"]
	var descriptions: Array[String] = ["拉弓、瞄准、松手。\n从这一箭开始你的构筑。", "四条成长之路，\n塑造自己的射箭风格。", "挑选弓、箭与行装，\n留下你的独特印记。"]
	var ids: Array[String] = ["range", "talents", "cosmetics"]
	for index: int in range(3):
		var x: float = 52 + index * 398
		var card: Panel = GameUI.panel(page, Rect2(x, 248, 380, 316))
		var number: Label = GameUI.label(card, "0%d  /  %s" % [index + 1, "靶场" if index == 0 else "营地"], 14, GameUI.MUTED)
		number.position = Vector2(24, 22)
		var title: Label = GameUI.label(card, titles[index], 36, GameUI.GOLD)
		title.position = Vector2(24, 65)
		var description: Label = GameUI.label(card, descriptions[index], 18)
		description.position = Vector2(24, 133)
		var caption: String = "继续射箭  →" if index == 0 and session.has_active_run() else ("进入靶场  →" if index == 0 else "查看  →")
		_button(caption, Rect2(x + 24, 491, 332, 48), ids[index])
	var status: String = "新旅程：进入靶场后开始本局。"
	if session.has_active_run():
		status = "冒险已暂停  ·  剩余拉弓 %d 次  ·  本局金币 %d（仅本局可用）" % [session.run.shots_left, session.run.gold]
	_text(status, Vector2(56, 600), 16, GameUI.MUTED)
	if session.has_active_run(): _button("新冒险", Rect2(1100, 590, 128, 44), "start")

func _difficulty_selector(session: GameSession) -> void:
	var active: bool = session.has_active_run()
	if active:
		selected_mode = session.run.mode_id
		selected_contracts = session.run.challenge.selection if not session.run.challenge.is_empty() else ContractCatalog.preset(selected_mode)
	var challenge: Dictionary = session.run.challenge if active else ContractCatalog.snapshot(selected_contracts)
	var caption: Label = _text("当前冒险 · %s · 已锁定" % session.run.difficulty_title() if active else "新局契约 · 挑战等级 %d" % int(challenge.risk), Vector2(56, 155), 15, GameUI.GOLD)
	caption.name = "ModeCaption"
	for index: int in range(3):
		var id: String = ["normal", "hard", "hell"][index]
		var chosen: bool = selected_contracts == ContractCatalog.preset(id)
		var button: Button = GameUI.button(page, ("✓ " if chosen else "") + DifficultyCatalog.title(id), func() -> void: action.emit("mode_select", id))
		button.name = "Mode_" + id
		button.position = Vector2(56 + index * 112, 190)
		button.size = Vector2(102, 42)
		button.disabled = active
		button.tooltip_text = "本局已锁定，新冒险可修改" if active else ContractCatalog.description(ContractCatalog.snapshot(ContractCatalog.preset(id)))
	var edit: Button = _button("查看契约" if active else "自选词条", Rect2(398, 190, 132, 42), "contracts")
	edit.name = "OpenContracts"
	var panel: Panel = GameUI.panel(page, Rect2(550, 154, 678, 88))
	var text: String = "旧版冒险保留原难度与成长，下一局可选择契约。"
	if not challenge.is_empty():
		var p: Dictionary = challenge.parameters
		text = "普通靶得分 ×%.2f · Boss ×%.2f · 击败 Boss 后另结算阶段奖励 +%.0f%%\n%d 项词条 · 金币收益不变 · 每次新冒险可重新搭配" % [p.target_score, p.boss_score, p.stage_bonus * 100, challenge.selection.size()]
	var description: Label = GameUI.label(panel, text, 14, GameUI.MUTED)
	description.position = Vector2(14, 16)
	description.name = "ModeDescription"

func _feature(destination: String, session: GameSession) -> void:
	var panel: Panel = GameUI.panel(page, Rect2(230, 100, 820, 520))
	var titles: Dictionary = {"pause": "弓弦暂歇"}
	var title: Label = GameUI.label(panel, titles.get(destination, destination), 36, GameUI.GOLD)
	title.position = Vector2(36, 28)
	var copy: Dictionary = {
		"pause": "当前靶场已暂停。\n\n返回大厅会保留本局拉弓次数、金币和靶子状态。\n正常退出会保存当前箭矢，下次继续原来的飞行。",
	}
	var body: Label = GameUI.label(panel, copy[destination], 19)
	body.position = Vector2(36, 104)
	if destination == "pause":
		_button("返回大厅", Rect2(266, 466, 240, 46), "hub")
		_button("设置", Rect2(520, 466, 240, 46), "settings")
		_button("教程", Rect2(774, 466, 240, 46), "tutorial")
	_button("继续射箭" if destination == "pause" else "返回", Rect2(266, 542, 748, 48), "back")

func _text(value: String, at: Vector2, font_size: int, color: Color = GameUI.CREAM) -> Label:
	var label: Label = GameUI.label(page, value, font_size, color)
	label.position = at
	return label

func _button(value: String, rect: Rect2, id: String) -> Button:
	var button: Button = GameUI.button(page, value, func() -> void: action.emit(id, null))
	button.position = rect.position
	button.size = rect.size
	return button
