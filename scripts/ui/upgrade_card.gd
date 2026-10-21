class_name UpgradeCard
extends Button
## One button owns input; child labels expose a readable hierarchy without hiding rules.
func configure(id: String, title: String, state: String, description: String, comparison: String, blocked: bool, mastery: bool) -> void:
	name = id
	text = title + " | " + state + "\n" + description + "\n" + comparison
	disabled = blocked
	custom_minimum_size = Vector2(362, 132)
	add_theme_font_size_override("font_size", 1) # Semantic text is read by accessibility; labels render it.
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
		add_theme_color_override(key, Color.TRANSPARENT)
	var accent := Color("8fd9ba") if mastery else GameUI.GOLD
	GameUI.card_state(self, false, not blocked, accent)
	BuildIcon.add_to(self, id, Vector2(12, 11), 30, GameUI.MUTED if blocked else accent)
	_line("CardTitle", title, Vector2(54, 9), Vector2(294, 24), 18, GameUI.MUTED if blocked else accent)
	_line("CardState", state, Vector2(54, 35), Vector2(294, 18), 13, GameUI.MUTED)
	_line("CardDescription", description, Vector2(14, 57), Vector2(334, 30), 13, GameUI.MUTED if blocked else GameUI.CREAM)
	_line("CardComparison", comparison, Vector2(14, 91), Vector2(334, 36), 13, GameUI.MUTED if blocked else Color("a4d9c2"))

func _line(id: String, value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> void:
	var label: Label = GameUI.label(self, value, font_size, color)
	label.name = id
	label.position = at
	label.size = extent
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
