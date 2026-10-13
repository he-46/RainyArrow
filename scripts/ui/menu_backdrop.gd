class_name MenuBackdrop
extends Control
## Deterministic pixel scenery; no gameplay objects or random-state consumption.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("0d2029"))
	draw_rect(Rect2(740, 72, 144, 144), Color("b9be94"))
	draw_rect(Rect2(716, 96, 192, 96), Color("b9be94"))
	for depth: int in range(3):
		var shade: Color = [Color("18343a"), Color("1c4142"), Color("102c32")][depth]
		for index: int in range(9):
			var x: float = index * 167 + depth * 53 - 90
			var y: float = 145 + depth * 105 + (index % 3) * 29
			draw_rect(Rect2(x + 54, y, 16 + depth * 4, 720 - y), shade)
			for tier: int in range(5):
				draw_rect(Rect2(x + 45 - tier * 12, y + tier * 35, 36 + tier * 24, 44), shade)
	# Fine arrows falling across the distant forest.
	for index: int in range(12):
		var tip := Vector2(580 + (index * 137) % 670, 220 + (index * 83) % 350)
		draw_line(tip - Vector2(28, 56), tip, Color("577368"), 2)
		draw_line(tip - Vector2(9, 7), tip, Color("819486"), 2)
		draw_line(tip + Vector2(0, -12), tip, Color("819486"), 2)
	draw_rect(Rect2(0, 625, 1280, 95), Color("0b1c23"))
	for index: int in range(32):
		draw_rect(Rect2(index * 43, 619 - (index % 3) * 4, 24, 8), Color("26433e"))
