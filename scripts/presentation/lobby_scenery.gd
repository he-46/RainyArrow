class_name LobbyScenery
extends Control
## Cached, deterministic scenery. These props never instantiate gameplay objects.
var scene: String = "home"
var loadout: Dictionary = {}
var reduced: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var life := LobbyLife.new()
	life.name = "LobbyLife"
	life.scene = scene
	life.loadout = loadout.duplicate()
	life.reduced = reduced
	add_child(life)

func _disc(at: Vector2, radius: Vector2, color: Color) -> void:
	for y: int in range(-int(radius.y), int(radius.y) + 1, 2):
		var width: int = int(sqrt(maxf(0, 1 - pow(y / radius.y, 2))) * radius.x)
		draw_rect(Rect2(at.x - width, at.y + y, width * 2, 2), color)

func _pine(x: float, foot: float, height: float, color: Color) -> void:
	draw_rect(Rect2(x - 1, foot - height, 3, height), color)
	for tier: int in range(4):
		for row: int in range(0, 22, 3):
			var w: float = 2 + row * 0.5 + tier * 2
			draw_rect(Rect2(x - w, foot - height + tier * 12 + row, w * 2, 3), color)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
	for y: int in range(0, 360, 2):
		draw_rect(Rect2(0, y, 640, 2), Color("101e30").lerp(Color("2d4849"), minf(1, y / 265.0)))
	for i: int in range(45):
		draw_rect(Rect2(24 + i * 137 % 600, 24 + i * 43 % 106, 1, 1), Color("617783"))
	var moon := Vector2(510, 70) if scene == "home" else Vector2(410, 106)
	for i: int in range(4, 0, -1):
		_disc(moon, Vector2(26 + i * 8, 25 + i * 7), Color("203542").lerp(Color("405653"), (4 - i) / 5.0))
	_disc(moon, Vector2(27, 26), Color("cdd2aa"))
	_disc(moon + Vector2(-3, -2), Vector2(23, 22), Color("dedcba"))
	for r: Rect2 in [Rect2(-14, -10, 9, 3), Rect2(8, -4, 6, 5), Rect2(-3, 12, 11, 3)]:
		draw_rect(Rect2(moon + r.position, r.size), Color("aebd9c"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 158), Vector2(92, 103), Vector2(179, 142), Vector2(267, 92), Vector2(356, 139), Vector2(438, 108), Vector2(537, 148), Vector2(640, 100), Vector2(640, 360), Vector2(0, 360)]), Color("243b47"))
	for i: int in range(38): _pine(i * 19 - 6, 212, 38 + i * 31 % 65, Color("29464a") if i % 3 == 0 else Color("233c43"))
	for i: int in range(9):
		draw_rect(Rect2(240 + i * 47 % 300, 155 + i * 5, 75 + i * 19 % 110, 2), Color(0.55, 0.66, 0.63, 0.04))
	for i: int in range(7): _pine(20 + i * 101, 231, 72 + i * 11 % 50, Color("193137"))
	draw_rect(Rect2(0, 209, 640, 151), Color("152e31"))
	for i: int in range(74):
		draw_rect(Rect2(i * 43 % 640, 211 + i * 17 % 130, 4 + i % 7, 2), Color("29433d"))
	if scene == "home": _home()
	else: _camp()
	# Side trunks frame the illustration, staying outside the interactive controls.
	for x: int in [4, 628]:
		draw_rect(Rect2(x, 0, 9, 310), Color("10282e"))
		draw_line(Vector2(x + 3, 56), Vector2(x + (58 if x == 4 else -58), 8), Color("10282e"), 7)
	draw_set_transform(Vector2.ZERO)

func _home() -> void:
	# A moonlit ledge above the record board; no illustration behind the title.
	draw_colored_polygon(PackedVector2Array([Vector2(353, 201), Vector2(402, 186), Vector2(469, 188), Vector2(492, 203), Vector2(353, 217)]), Color("3f514a"))
	draw_rect(Rect2(393, 187, 82, 4), Color("8b9872"))
	for i: int in range(8): draw_rect(Rect2(396 + i * 10, 190, 8, 3 + i % 3), Color("586e50"))
	for i: int in range(5):
		draw_rect(Rect2(388 + i * 19, 198 + i % 2 * 5, 15, 2), Color("6c7b61"))
	# Darken the reading zone in stepped bands; art remains on the right.
	for i: int in range(24):
		draw_rect(Rect2(i * 14, 0, 14, 360), Color(0.035, 0.085, 0.11, maxf(0, 0.96 - i * 0.04)))

func _camp() -> void:
	_disc(Vector2(309, 210), Vector2(218, 27), Color("35453d"))
	_disc(Vector2(246, 201), Vector2(55, 16), Color("514b39"))
	# Arrow rack and a distant practice target mark the path to the range.
	for x: int in [83, 134]: draw_rect(Rect2(x, 147, 5, 60), Color("715e43"))
	for y: int in [161, 184]: draw_rect(Rect2(77, y, 66, 5), Color("a18a60"))
	for i: int in range(6):
		var x: int = 85 + i * 9
		draw_line(Vector2(x, 193), Vector2(x + 5, 135 + i % 2 * 5), Color("c1ac7a"), 1)
		draw_line(Vector2(x + 3, 139 + i % 2 * 5), Vector2(x + 7, 144 + i % 2 * 5), Color("92b9a1"), 3)
	draw_rect(Rect2(169, 133, 3, 71), Color("4b5a4b"))
	_disc(Vector2(170, 147), Vector2(14, 21), Color("8e7955"))
	_disc(Vector2(170, 147), Vector2(10, 15), Color("cfbc8a"))
	_disc(Vector2(170, 147), Vector2(5, 8), Color("b66c49"))
	# Map desk: the player's four paths are represented by four branches.
	for x: int in [315, 374]: draw_rect(Rect2(x, 174, 6, 33), Color("6f5a42"))
	draw_rect(Rect2(305, 159, 85, 21), Color("493d32"))
	draw_rect(Rect2(302, 157, 91, 6), Color("ab8656"))
	for i: int in range(3): draw_line(Vector2(310 + i * 22, 167), Vector2(324 + i * 22, 167), Color("69533c"), 1)
	draw_colored_polygon(PackedVector2Array([Vector2(315, 138), Vector2(378, 143), Vector2(373, 159), Vector2(311, 154)]), Color("c7bb8b"))
	for i: int in range(4):
		draw_line(Vector2(341, 152), Vector2(322 + i * 15, 143 + i % 2 * 3), Color("617b64"), 1)
		draw_rect(Rect2(320 + i * 15, 141 + i % 2 * 3, 3, 3), Color("9b6944"))
	draw_rect(Rect2(381, 142, 4, 14), Color("a67e49"))
	draw_rect(Rect2(380, 136, 6, 6), Color("ead193"))
	# Equipment awning, cloak stand, wooden workbench and spare bow.
	draw_colored_polygon(PackedVector2Array([Vector2(458, 111), Vector2(570, 103), Vector2(598, 134), Vector2(447, 134)]), Color("416258"))
	for i: int in range(4): draw_line(Vector2(469 + i * 25, 111 - i * 2), Vector2(461 + i * 32, 131), Color("4d6d5b"), 1)
	for i: int in range(7): draw_rect(Rect2(449 + i * 22, 132, 15, 7), Color("58735e"))
	for x: int in [454, 586]: draw_rect(Rect2(x, 133, 4, 75), Color("766548"))
	draw_rect(Rect2(480, 171, 89, 8), Color("9a794f"))
	draw_line(Vector2(486, 173), Vector2(562, 173), Color("c19a65"), 1)
	for x: int in [485, 557]: draw_rect(Rect2(x, 179, 6, 30), Color("5a4e3b"))
	draw_rect(Rect2(471, 150, 3, 57), Color("a18a60"))
	draw_colored_polygon(PackedVector2Array([Vector2(471, 148), Vector2(480, 157), Vector2(477, 187), Vector2(459, 190), Vector2(461, 158)]), CosmeticCatalog.equipped(loadout, "archer").primary)
	CosmeticDrawing.bow(self, CosmeticCatalog.equipped(loadout, "bow"), Vector2(527, 165), Vector2(0.9, -0.4), 0)
	for i: int in range(3): draw_rect(Rect2(538 + i * 5, 163, 3, 8), Color("c2aa74"))
