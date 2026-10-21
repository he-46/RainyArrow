class_name ForestBackdrop
extends Node2D
## Static pixel scenery cached by CanvasItem. A private seed never touches combat RNG.

var palette_rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = -5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	palette_rng.seed = 41723
	_sky()
	_distant_forest()
	_midground()
	_ground()
	_platform()

func _sky() -> void:
	for y: int in range(0, 310, 2):
		var shade: Color = Color("101e30").lerp(Color("34494a"), float(y) / 380.0)
		draw_rect(Rect2(0, y, 640, 2), shade)
	for i: int in range(48):
		var p := Vector2(palette_rng.randi_range(12, 628), palette_rng.randi_range(52, 149))
		draw_rect(Rect2(p, Vector2(1, 1)), Color("738486") if i % 4 == 0 else Color("455967"))
	# Stepped halos remain muted enough for the target and arrow silhouettes.
	for i: int in range(4, 0, -1):
		_disc(Vector2(477, 89), 25 + i * 7, 22 + i * 6, Color("1c3040").lerp(Color("344747"), float(5 - i) / 5.0))
	_disc(Vector2(477, 89), 25, 24, Color("a7b8a4"))
	_disc(Vector2(475, 87), 22, 21, Color("d4d4ad"))
	for crater: Rect2 in [Rect2(463, 75, 7, 3), Rect2(482, 80, 9, 4), Rect2(471, 98, 11, 3), Rect2(489, 92, 4, 5)]:
		draw_rect(crater, Color("b7c2a0"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 185), Vector2(75, 115), Vector2(135, 158), Vector2(209, 107), Vector2(278, 157), Vector2(363, 122), Vector2(444, 164), Vector2(545, 129), Vector2(640, 160), Vector2(640, 290), Vector2(0, 290)]), Color("273d48"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 217), Vector2(111, 162), Vector2(184, 201), Vector2(304, 151), Vector2(415, 201), Vector2(510, 165), Vector2(640, 220), Vector2(640, 310), Vector2(0, 310)]), Color("29414a"))

func _disc(center: Vector2, rx: int, ry: int, color: Color) -> void:
	for y: int in range(-ry, ry + 1, 2):
		var width: int = int(sqrt(maxf(0.0, 1.0 - pow(float(y) / ry, 2))) * rx)
		draw_rect(Rect2(center.x - width, center.y + y, width * 2, 2), color)

func _distant_forest() -> void:
	for i: int in range(42):
		var x: int = i * 17 + palette_rng.randi_range(-4, 4)
		var height: int = palette_rng.randi_range(28, 66)
		var foot: int = 218 + palette_rng.randi_range(-14, 8)
		var color := Color("223b42") if i % 2 == 0 else Color("253e45")
		draw_rect(Rect2(x - 1, foot - height, 2, height), color)
		for tier: int in range(4):
			var top: int = foot - height + tier * 9
			for row: int in range(0, 20, 3):
				var half_width: int = 2 + row / 2 + tier
				draw_rect(Rect2(x - half_width, top + row, half_width * 2, 3), color)
	# Broken horizontal mist bands, never a bright overlay over colliders.
	for i: int in range(9):
		var y: int = 196 + i * 7
		var width: int = palette_rng.randi_range(120, 310)
		draw_rect(Rect2(palette_rng.randi_range(130, 420), y, width, 2), Color(0.42, 0.53, 0.53, 0.045))

func _tree(x: int, foot: int, height: int, width: int, trunk: Color, leaves: Color) -> void:
	var top: int = foot - height
	for y: int in range(top, foot, 4):
		var lean: int = int(sin(float(y - top) / height * 2.2) * width * 0.45)
		draw_rect(Rect2(x + lean, y, width, 4), trunk)
		draw_rect(Rect2(x + lean, y, 2, 4), trunk.lightened(0.025))
	for side: int in [-1, 1]:
		var branch_start := Vector2(x + width * 0.5, top + height * 0.43)
		var branch_end: Vector2 = branch_start + Vector2(side * (width + 22), -18)
		draw_line(branch_start, branch_end, trunk, maxf(2, width * 0.28), false)
	for i: int in range(6):
		var center := Vector2(x + palette_rng.randi_range(-22, 24), top + palette_rng.randi_range(-10, 28))
		var rx: int = palette_rng.randi_range(24, 42)
		var ry: int = palette_rng.randi_range(10, 20)
		_disc(center.round(), rx, ry, leaves.lightened((i % 3) * 0.012))
		for speck: int in range(7):
			var p: Vector2 = center + Vector2(palette_rng.randi_range(-rx + 7, rx - 7), palette_rng.randi_range(-ry / 2, ry / 2))
			draw_rect(Rect2(p.round(), Vector2(3, 1)), leaves.lightened(0.035))
	for i: int in range(4):
		draw_rect(Rect2(x + i % maxi(2, width), foot - 13 - i * 17, 2, 6), trunk.darkened(0.08))

func _midground() -> void:
	for spec: Vector3 in [Vector3(-12, 160, 12), Vector3(80, 115, 7), Vector3(184, 169, 8), Vector3(274, 120, 6), Vector3(387, 164, 8), Vector3(549, 111, 7), Vector3(617, 179, 13)]:
		_tree(int(spec.x), 302, int(spec.y), int(spec.z), Color("20363a"), Color("233b3e"))
	# Near trees frame the sides; the shooting corridor remains open.
	_tree(-14, 313, 240, 21, Color("152a30"), Color("182e34"))
	_tree(629, 313, 225, 18, Color("142a2f"), Color("183037"))
	for i: int in range(40):
		var x: int = i * 17 + palette_rng.randi_range(-6, 6)
		var y: int = 289 + palette_rng.randi_range(0, 15)
		_disc(Vector2(x, y), palette_rng.randi_range(10, 25), palette_rng.randi_range(3, 8), Color("2c4540"))
	# A quiet moonlit clearing behind the target stands.
	for i: int in range(8):
		draw_rect(Rect2(222 + i * 21, 294 + i % 3 * 3, 91, 1), Color("344c45"))

func _ground() -> void:
	draw_rect(Rect2(0, 308, 640, 52), Color("243b37"))
	draw_rect(Rect2(0, 308, 640, 2), Color("65816a"))
	draw_rect(Rect2(0, 311, 640, 5), Color("3a5342"))
	draw_colored_polygon(PackedVector2Array([Vector2(128, 314), Vector2(469, 314), Vector2(627, 360), Vector2(34, 360)]), Color("354239"))
	for i: int in range(200):
		var p := Vector2(palette_rng.randi_range(0, 639), palette_rng.randi_range(314, 359))
		var color: Color = [Color("3e4d3e"), Color("2b3933"), Color("4c5c45"), Color("506049")][i % 4]
		draw_rect(Rect2(p, Vector2(palette_rng.randi_range(2, 7), 1 + i % 2)), color)
	for i: int in range(90):
		var x: int = i * 7 + palette_rng.randi_range(-3, 3)
		var height: int = palette_rng.randi_range(2, 6)
		draw_rect(Rect2(x, 308 - height, 1, height), Color("587553"))
		if i % 3 == 0: draw_line(Vector2(x, 307), Vector2(x - 3, 303), Color("587553"), 1, false)
	for p: Vector2 in [Vector2(21, 316), Vector2(190, 330), Vector2(454, 334), Vector2(610, 320)]:
		draw_rect(Rect2(p, Vector2(15, 5)), Color("1c302e"))
		draw_rect(Rect2(p + Vector2(2, -2), Vector2(11, 4)), Color("536156"))
		draw_rect(Rect2(p + Vector2(3, -2), Vector2(7, 1)), Color("75806a"))

func _platform() -> void:
	draw_rect(Rect2(59, 307, 85, 3), Color("162b2c"))
	draw_rect(Rect2(64, 284, 73, 24), Color("354b48"))
	for row: int in range(3):
		for col: int in range(4):
			var x: int = 65 + col * 18
			var y: int = 285 + row * 7
			draw_rect(Rect2(x, y, 17, 6), Color("4a5d52") if (col + row) % 3 == 0 else Color("40534d"))
			draw_rect(Rect2(x + 2, y, 11, 1), Color("56695a"))
	draw_rect(Rect2(61, 281, 79, 4), Color("64785e"))
	draw_rect(Rect2(61, 281, 79, 1), Color("92a079"))
	for i: int in range(12):
		draw_rect(Rect2(64 + i * 6, 281, 4, 2 + i % 3), Color("718450"))
	# An arrow rack outside the player's silhouette.
	draw_rect(Rect2(29, 278, 18, 27), Color("3e4034"))
	draw_rect(Rect2(27, 279, 22, 3), Color("7a6b45"))
	for i: int in range(4):
		var x: int = 31 + i * 4
		draw_line(Vector2(x, 285), Vector2(x - 4, 259 - i % 2 * 4), Color("9a8c61"), 1, false)
		draw_line(Vector2(x - 5, 260 - i % 2 * 4), Vector2(x - 2, 265 - i % 2 * 4), Color("879783"), 2, false)
