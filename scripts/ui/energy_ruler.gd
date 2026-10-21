class_name EnergyRuler
extends Control
var cost: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_cost(value: int) -> void:
	if cost == value: return
	cost = value
	queue_redraw()

func _draw() -> void:
	for i: int in range(1, 10):
		var x: float = round(size.x * i / 10.0)
		draw_line(Vector2(x, 3), Vector2(x, 10), Color("172a2e"), 1)
	if cost > 0:
		var x: float = round(size.x * cost / 100.0)
		draw_line(Vector2(x, 0), Vector2(x, 12), Color("edc879"), 2)
		draw_line(Vector2(x - 3, 0), Vector2(x + 3, 0), Color("edc879"), 1)
