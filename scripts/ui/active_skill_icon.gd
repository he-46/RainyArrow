class_name ActiveSkillIcon
extends Control
## Three small, code-drawn pixel emblems; UI-only, no combat state mutation.
var skill: String = ""
var available: bool = false
var reduced_effects: bool = false
var charge_ready: bool = false
var charge_context: String = ""
var pulse_left: float = 0.0
var remaining: int = 0
var segments: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_charge(context: String, charged: bool, draws_left: int, total: int) -> void:
	if context != charge_context:
		charge_context = context
		charge_ready = false
		pulse_left = 0.0
	if charged and not charge_ready and not reduced_effects: pulse_left = 0.45
	if reduced_effects or not charged: pulse_left = 0.0
	if charge_ready != charged or remaining != draws_left or segments != total: queue_redraw()
	charge_ready = charged
	remaining = draws_left
	segments = total

func _process(delta: float) -> void:
	if pulse_left <= 0 or get_tree().paused or not is_visible_in_tree(): return
	pulse_left = maxf(0, pulse_left - delta)
	queue_redraw()

func configure(id: String, ready_to_cast: bool) -> void:
	if skill == id and available == ready_to_cast: return
	skill = id
	available = ready_to_cast
	queue_redraw()

func _draw() -> void:
	var ink := Color("edc879") if available else Color("8da99d")
	draw_rect(Rect2(1, 1, 46, 46), Color("132a30"))
	draw_rect(Rect2(1, 1, 46, 46), ink.darkened(0.45), false, 1)
	if pulse_left > 0 and not reduced_effects:
		var pulse := Color("ffe5a0")
		pulse.a = pulse_left / 0.45
		draw_rect(Rect2(0, 0, 48, 48), pulse, false, 2)
	match skill:
		"sunshot":
			for i: int in range(8):
				var dir := Vector2.RIGHT.rotated(i * PI / 4)
				draw_line((Vector2(24, 24) + dir * 11).round(), (Vector2(24, 24) + dir * 16).round(), ink, 2)
			draw_line(Vector2(13, 35), Vector2(34, 14), ink, 3)
			draw_polyline(PackedVector2Array([Vector2(23, 14), Vector2(34, 14), Vector2(34, 25)]), ink, 3)
		"quickdraw":
			for y: int in [17, 30]:
				draw_line(Vector2(10, y), Vector2(35, y), ink, 2)
				draw_polyline(PackedVector2Array([Vector2(28, y - 6), Vector2(35, y), Vector2(28, y + 6)]), ink, 2)
			draw_line(Vector2(10, 9), Vector2(19, 9), ink.darkened(0.3), 2)
		"hunters_mark":
			draw_rect(Rect2(15, 15, 18, 18), ink, false, 2)
			draw_rect(Rect2(21, 21, 6, 6), ink)
			for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(Vector2(24, 24) + dir * 12, Vector2(24, 24) + dir * 18, ink, 2)
		_:
			draw_rect(Rect2(16, 22, 16, 13), ink, false, 2)
			draw_rect(Rect2(20, 14, 8, 9), ink, false, 2)
	if remaining > 0:
		for i: int in range(segments):
			var width: float = 38.0 / maxi(1, segments)
			draw_rect(Rect2(5 + i * width, 41, width - 3, 3), Color("8fd9ba") if i < remaining else Color("374d4d"))
