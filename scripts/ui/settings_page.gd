class_name SettingsPage
extends Control

signal action(id: String, value: Variant)
var sliders: Dictionary = {}
var toggles: Dictionary = {}
var percentages: Dictionary = {}

func configure(options: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: Panel = GameUI.panel(self, Rect2(210, 64, 860, 578))
	var title: Label = GameUI.label(panel, "设置", 36, GameUI.GOLD)
	title.position = Vector2(36, 22)
	var note: Label = GameUI.label(panel, "调整后立即生效，并自动保存", 16, GameUI.MUTED)
	note.position = Vector2(36, 78)
	var labels: Dictionary = {"master_volume": "总音量", "sfx_volume": "音效音量", "music_volume": "音乐音量"}
	var row: int = 0
	for key: String in labels:
		var y: float = 128 + row * 64
		var caption: Label = GameUI.label(panel, labels[key], 19)
		caption.position = Vector2(36, y)
		var slider := HSlider.new()
		slider.name = key
		slider.position = Vector2(208, y + 2)
		slider.size = Vector2(470, 28)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = float(options[key])
		panel.add_child(slider)
		sliders[key] = slider
		var amount: Label = GameUI.label(panel, "", 18, GameUI.GOLD)
		amount.position = Vector2(720, y)
		percentages[key] = amount
		slider.value_changed.connect(func(value: float) -> void:
			amount.text = "%d%%" % roundi(value * 100)
			action.emit("setting", {"key": key, "value": value}))
		row += 1
	var music_note: Label = GameUI.label(panel, "音乐：暂无曲目，音量设置会保留", 14, GameUI.MUTED)
	music_note.position = Vector2(208, 290)
	var toggle_labels: Dictionary = {"muted": "静音（M）", "fullscreen": "全屏", "screen_shake": "命中震屏", "trajectory_guide": "瞄准轨迹"}
	row = 0
	for key: String in toggle_labels:
		var toggle := CheckButton.new()
		toggle.name = key
		toggle.text = toggle_labels[key]
		toggle.position = Vector2(36 + (row % 2) * 410, 334 + (row / 2) * 66)
		toggle.size = Vector2(375, 48)
		panel.add_child(toggle)
		toggles[key] = toggle
		toggle.toggled.connect(func(value: bool) -> void: action.emit("setting", {"key": key, "value": value}))
		row += 1
	var test: Button = GameUI.button(panel, "试听音效", func() -> void: action.emit("sound_preview", null))
	test.position = Vector2(36, 500)
	test.size = Vector2(180, 46)
	var back: Button = GameUI.button(panel, "返回", func() -> void: action.emit("back", null))
	back.position = Vector2(242, 500)
	back.size = Vector2(582, 46)
	sync(options)

func sync(options: Dictionary) -> void:
	for key: String in sliders:
		(sliders[key] as HSlider).set_value_no_signal(float(options[key]))
		(percentages[key] as Label).text = "%d%%" % roundi(float(options[key]) * 100)
	for key: String in toggles:
		(toggles[key] as CheckButton).set_pressed_no_signal(bool(options[key]))
