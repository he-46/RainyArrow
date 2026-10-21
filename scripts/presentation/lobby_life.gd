class_name LobbyLife
extends Control
## Small animated layer above cached scenery; runs while the lobby pauses combat.
var scene: String = "home"
var loadout: Dictionary = {}
var reduced: bool = false
var clock: float = 0.0
var elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(not reduced)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or reduced: return
	elapsed += delta
	if elapsed < 1.0 / 12.0: return
	clock = fmod(clock + elapsed, 600.0)
	elapsed = 0
	queue_redraw()

func _draw() -> void:
	var origin := Vector2(420, 106) if scene == "home" else Vector2(205, 144)
	var zoom: float = 1.35 if scene == "home" else 1.0
	draw_set_transform(origin * 2, 0, Vector2.ONE * 2 * zoom)
	var pose := ArcherPose.sample(Vector2(1, -0.25) if scene == "home" else Vector2(0.6, 0.8), scene == "home", 0.25, 0, 0.65, 0, 0, clock)
	CosmeticDrawing.archer(self, CosmeticCatalog.equipped(loadout, "archer"), Vector2.ZERO, pose)
	CosmeticDrawing.bow(self, CosmeticCatalog.equipped(loadout, "bow"), ArcherPose.GRIP, pose.direction, pose.tension)
	if scene == "home": CosmeticDrawing.nocked_arrow(self, CosmeticCatalog.equipped(loadout, "arrow"), pose.draw_hand, pose.direction)
	draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
	if scene == "hub": _fire()
	elif not reduced:
		for i: int in range(4):
			var t: float = fmod(clock * 0.035 + i * 0.24, 1.0)
			var at := Vector2(345 + i * 51 + sin(t * TAU) * 9, 93 + t * 90).round()
			draw_rect(Rect2(at, Vector2(3, 1)), Color("78907a"))
	draw_set_transform(Vector2.ZERO)

func _fire() -> void:
	var at := Vector2(256, 198)
	for i: int in range(8):
		var p: Vector2 = at + Vector2(cos(i * TAU / 8) * 16, sin(i * TAU / 8) * 5)
		draw_rect(Rect2(p.round(), Vector2(6, 4)), Color("7c7a62"))
	draw_line(at + Vector2(-11, 3), at + Vector2(12, -1), Color("97643d"), 4)
	draw_line(at + Vector2(9, 4), at + Vector2(-8, -2), Color("634733"), 4)
	for i: int in range(5):
		var height: int = 9 + int(sin(clock * 7 + i * 1.7) * 3) + (8 if i == 2 else 0)
		draw_rect(Rect2(at.x - 8 + i * 4, at.y - height, 4, height), Color("d48c47"))
		draw_rect(Rect2(at.x - 6 + i * 3, at.y - height * 0.6, 3, height * 0.6), Color("f0c878"))
	if not reduced:
		for i: int in range(4):
			var t: float = fmod(clock * 0.25 + i * 0.25, 1)
			draw_rect(Rect2(at.x + sin(t * 5 + i) * 10, at.y - 15 - t * 25, 1, 2), Color(0.93, 0.69, 0.36, 1 - t))
