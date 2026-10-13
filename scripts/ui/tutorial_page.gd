class_name TutorialPage
extends Control
## Coaching overlay; combat cards are the same widgets used by the real game.

signal action(id: String, value: Variant)
var hud: GameHUD
var coach: Panel
var title: Label
var copy: Label
var status: Label
var pause_button: Button
var restart_button: Button
var leave_button: Button
var complete_panel: Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud = GameHUD.new()
	hud.supply_enabled = false
	add_child(hud)
	hud.action.connect(func(id: String, value: Variant) -> void: action.emit(id, value))
	coach = GameUI.panel(self, Rect2(350, 110, 890, 132))
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = GameUI.label(coach, "", 23, GameUI.GOLD)
	title.position = Vector2(18, 8)
	copy = GameUI.label(coach, "", 16)
	copy.position = Vector2(18, 44)
	copy.size = Vector2(660, 58)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status = GameUI.label(coach, "练习次数不限 · 收益仅在教程内", 13, GameUI.MUTED)
	status.position = Vector2(18, 108)
	pause_button = GameUI.button(coach, "暂停练习", func() -> void: action.emit("pause", null))
	pause_button.position = Vector2(704, 5)
	pause_button.size = Vector2(168, 36)
	restart_button = GameUI.button(coach, "重新练习", func() -> void: action.emit("restart", null))
	restart_button.position = Vector2(704, 47)
	restart_button.size = Vector2(168, 36)
	leave_button = GameUI.button(coach, "跳过 / 返回", func() -> void: action.emit("leave", null))
	leave_button.position = Vector2(704, 89)
	leave_button.size = Vector2(168, 36)
	complete_panel = GameUI.panel(self, Rect2(230, 252, 820, 352))
	var heading: Label = GameUI.label(complete_panel, "弓手，准备出发。", 34, GameUI.GOLD)
	heading.position = Vector2(32, 22)
	var summary: Label = GameUI.label(complete_panel, "拉弓、靶心、升级、奇遇：你已经完成练习。\n击倒靶子才会获得金币和经验；每 10 次击倒选一次奇遇。\n金币仅供本局使用，等级和天赋会留到下一次冒险。\n\n教程完成已保存，可随时重玩。", 19)
	summary.position = Vector2(32, 90)
	var back: Button = GameUI.button(complete_panel, "结束练习，返回", func() -> void: action.emit("leave", null))
	back.position = Vector2(32, 280)
	back.size = Vector2(756, 46)
	complete_panel.hide()

func refresh(run: RunModel, profile: PlayerProfile, step: int, paused_by_user: bool, muted: bool, message: String) -> void:
	hud.refresh(run, profile, muted, "")
	hud.pause_button.text = "继续" if paused_by_user else "暂停"
	hud.skills_button.disabled = step != 2 or paused_by_user
	hud.encounters_button.disabled = true
	hud.shots_label.text = "练习次数不限"
	hud.hint_label.text = "练习局 · 金币、经验、天赋和奇遇只在本教程内结算    Esc 暂停 / 取消拉弓    M 静音"
	var titles: Array[String] = ["01 / 04   拉开弓弦", "02 / 04   瞄准靶心", "03 / 04   花金币升级", "04 / 04   选择你的奇遇", "练习完成"]
	var instructions: Array[String] = [
		"按住左侧弓附近，向左后方拖动，再松开鼠标射出一箭。\n向下拖可以抬高弹道；拉得越远，初速度越快。",
		"让箭头击中练习靶的红色中心，并击倒它。\n击中只扣血，击倒才获得金币与经验；失误可以继续练习。",
		"点击左上角「技能」，用刚获得的金币购买任意一项升级。\n升级从下一次拉弓生效；购买后点击「返回靶场」。",
		"练习局已补齐到下次奇遇前，再击倒一次练习靶。\n每 10 次击倒出现三选一；选一项后完成练习。",
		"教程完成记录已保存；你可以返回或重新练习。",
	]
	title.text = ("练习已暂停 · " if paused_by_user else "") + titles[step]
	copy.text = message if not message.is_empty() else instructions[step]
	pause_button.text = "继续练习" if paused_by_user else "暂停练习"
	var modal: bool = run.phase in [RunModel.Phase.SHOP, RunModel.Phase.CHOICE]
	coach.position = Vector2(24, 604) if modal else Vector2(350, 110)
	coach.size = Vector2(1232, 112) if modal else Vector2(890, 132)
	copy.size = Vector2(990, 52) if modal else Vector2(660, 58)
	status.visible = not modal
	pause_button.visible = not modal
	restart_button.position.y = 5 if modal else 47
	leave_button.position.y = 55 if modal else 89
	for child: Node in coach.get_children():
		if child is Button: child.position.x = 1046 if modal else 704
	complete_panel.visible = step == 4
