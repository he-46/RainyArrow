class_name GameUI
extends RefCounted

const CREAM: Color = Color("eee5cc")
const MUTED: Color = Color("9caea7")
const GOLD: Color = Color("edc879")

static func score_text(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func make_theme() -> Theme:
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color("71837e"))
	theme.set_stylebox("normal", "Button", box(Color("263b3e"), Color("4b625a")))
	theme.set_stylebox("hover", "Button", box(Color("354c48"), GOLD))
	theme.set_stylebox("pressed", "Button", box(Color("44594b"), GOLD))
	theme.set_stylebox("disabled", "Button", box(Color("172a32"), Color("2a3c40")))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD))
	return theme

static func box(background: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func panel(parent: Node, rect: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", box(Color("142832"), Color("43584f")))
	parent.add_child(panel)
	return panel

static func label(parent: Node, text: String, font_size: int = 18, color: Color = CREAM) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


