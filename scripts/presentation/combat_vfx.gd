class_name CombatVFX
extends Node2D
## Bounded presentation-only events. No timers or randomness feed back into combat.
const LIMIT: int = 64
const REDUCED_LIMIT: int = 12
var reduced: bool = false
var events: Array[Dictionary] = []

func _ready() -> void:
	z_index = 2

func configure(value: bool) -> void:
	if reduced != value:
		reduced = value
		events.clear()
		queue_redraw()

func emit_effect(kind: String, at: Vector2, direction: Vector2 = Vector2.RIGHT) -> void:
	if reduced and kind in ["wood", "iron", "sunshot", "quickdraw", "hunters_mark"]: return
	var important: bool = kind in ["critical", "bullseye", "sunshot", "quickdraw", "hunters_mark"]
	var limit: int = REDUCED_LIMIT if reduced else LIMIT
	if events.size() >= limit:
		var removable: int = -1
		for i: int in range(events.size()):
			if not events[i].important:
				removable = i
				break
		if removable < 0 and not important: return
		events.remove_at(maxi(0, removable))
	events.append({"kind": kind, "at": at, "direction": direction.normalized(), "age": 0.0, "duration": 0.18 if reduced else (0.32 if important else 0.22), "important": important})
	queue_redraw()

func _process(delta: float) -> void:
	if events.is_empty(): return
	for i: int in range(events.size() - 1, -1, -1):
		events[i].age += delta
		if events[i].age >= events[i].duration: events.remove_at(i)
	queue_redraw()

func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(a.clamp(Arrow.FIELD.position, Arrow.FIELD.end).round(), b.clamp(Arrow.FIELD.position, Arrow.FIELD.end).round(), color, width, false)

func _draw() -> void:
	for event: Dictionary in events:
		var t: float = event.age / event.duration
		var at: Vector2 = event.at
		var aim: Vector2 = event.direction
		var normal := Vector2(-aim.y, aim.x)
		var color := Color("8fd9ba")
		if event.kind in ["critical", "sunshot"]: color = Color("ffdc83")
		elif event.kind == "wood": color = Color("b99a6b")
		elif event.kind in ["iron", "bounce", "quickdraw"]: color = Color("a8dce5")
		color.a = (1 - t) * (0.7 if reduced else 1.0)
		match event.kind:
			"wood", "iron":
				for i: int in range(4):
					var dir: Vector2 = (-aim).rotated(-0.9 + i * 0.6)
					var offset: Vector2 = dir * (3 + t * 12) + Vector2(0, t * t * 5)
					_line(at + offset, at + offset + dir * (3 if event.kind == "wood" else 5), color)
			"bullseye":
				var r: float = 5 + t * (3 if reduced else 7)
				for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					_line(at + dir * r, at + dir * (r + 3), color)
			"critical":
				for i: int in range(4 if reduced else 6):
					var dir := Vector2.RIGHT.rotated(i * TAU / (4 if reduced else 6) + 0.3)
					_line(at + dir * (4 + t * 3), at + dir * (9 + t * 9), color, 1 if reduced else 2)
			"penetrate", "bounce":
				for side: int in ([0] if reduced else [-1, 1]):
					var start: Vector2 = at + normal * side * 3 + aim * t * 12
					_line(start, start + aim * (8 if reduced else 16), color)
			"sunshot":
				for side: int in [-1, 1]:
					_line(at + normal * side * (6 + t * 8) - aim * 6, at + aim * 12, color)
			"quickdraw":
				for side: int in [-1, 1]:
					_line(at - aim * (8 + t * 10) + normal * side * 15, at - aim * (3 + t * 10) + normal * side * 5, color)
			"hunters_mark":
				for side: int in [-1, 1]:
					_line(at + Vector2(side * (5 + t * 7), -5), at + Vector2(0, -12 - t * 6), color)

static func area_outline(at: Vector2, radius: float) -> Array[PackedVector2Array]:
	var points := PackedVector2Array()
	for i: int in range(49): points.append(at + Vector2.RIGHT.rotated(i * TAU / 48.0) * radius)
	var field: Rect2 = Arrow.FIELD.grow(-0.5)
	var clip := PackedVector2Array([field.position, Vector2(field.end.x, field.position.y), field.end, Vector2(field.position.x, field.end.y)])
	return Geometry2D.intersect_polyline_with_polygon(points, clip)

static func marker(canvas: CanvasItem, target: ArcheryTarget, armed: bool) -> void:
	var rect: Rect2 = TargetArt.body_rect(target)
	rect = Rect2(target.position + rect.position * target.scale, rect.size * target.scale).grow(3)
	var color := Color("b1e6b5") if armed else Color("639183")
	for x: float in [rect.position.x, rect.end.x]:
		var sign_x: float = 1 if x == rect.position.x else -1
		for y: float in [rect.position.y, rect.end.y]:
			var sign_y: float = 1 if y == rect.position.y else -1
			canvas.draw_line(Vector2(x, y), Vector2(x + sign_x * 4, y), color, 1)
			canvas.draw_line(Vector2(x, y), Vector2(x, y + sign_y * 4), color, 1)
	var symbol := Vector2(target.position.x, maxf(65, rect.position.y - 12))
	canvas.draw_polyline(PackedVector2Array([symbol + Vector2(-4, 0), symbol + Vector2(0, -4), symbol + Vector2(4, 0), symbol + Vector2(0, 4), symbol + Vector2(-4, 0)]), color, 1)
	if armed: canvas.draw_rect(Rect2(symbol - Vector2.ONE, Vector2(2, 2)), color)
