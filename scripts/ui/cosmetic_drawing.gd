class_name CosmeticDrawing
extends RefCounted
## Shared code-drawn pixel art. Palette and poses never alter combat geometry.

static func _shape(canvas: CanvasItem, origin: Vector2, points: Array, color: Color) -> void:
	var vertices := PackedVector2Array()
	for point: Vector2 in points: vertices.append((origin + point).round())
	canvas.draw_colored_polygon(vertices, color)

static func _limb(canvas: CanvasItem, origin: Vector2, shoulder: Vector2, elbow: Vector2, hand: Vector2, cloth: Color, leather: Color) -> void:
	var outline := Color("14282d")
	canvas.draw_line((origin + shoulder).round(), (origin + elbow).round(), outline, 7, false)
	canvas.draw_line((origin + elbow).round(), (origin + hand).round(), outline, 6, false)
	canvas.draw_line((origin + shoulder).round(), (origin + elbow).round(), cloth, 5, false)
	canvas.draw_line((origin + elbow).round(), (origin + hand).round(), leather, 4, false)
	canvas.draw_rect(Rect2((origin + hand - Vector2(2, 2)).round(), Vector2(4, 4)), Color("d8b287"))

static func archer(canvas: CanvasItem, skin: CosmeticData, origin: Vector2, pose: ArcherPose = null) -> void:
	if pose == null: pose = ArcherPose.sample(Vector2.RIGHT)
	var dark := Color("14282d")
	var leather := Color("775b41")
	var light_leather := Color("ac8356")
	var body: Vector2 = origin + pose.body_shift
	# Short split cloak sits behind the quiver and leaves both boots readable.
	_shape(canvas, body, [Vector2(3, 17), Vector2(13, 22), Vector2(11, 43), Vector2(-2 + pose.cloak_swing, 50), Vector2(-3 + pose.cloak_swing, 45), Vector2(-12 + pose.cloak_swing, 47), Vector2(-7, 28)], dark)
	_shape(canvas, body, [Vector2(2, 18), Vector2(10, 24), Vector2(7, 42), Vector2(-2 + pose.cloak_swing, 46), Vector2(-8 + pose.cloak_swing, 43), Vector2(-4, 28)], skin.secondary)
	canvas.draw_line(body + Vector2(0, 26), body + Vector2(-4 + pose.cloak_swing, 42), skin.primary.darkened(0.15), 2, false)
	if skin.style == 2: canvas.draw_line(body + Vector2(-7 + pose.cloak_swing, 43), body + Vector2(-2 + pose.cloak_swing, 46), skin.accent, 2, false)
	# Back quiver and three distinct feather tips.
	_shape(canvas, body, [Vector2(-8, 15), Vector2(-1, 17), Vector2(-3, 38), Vector2(-10, 36)], dark)
	_shape(canvas, body, [Vector2(-7, 17), Vector2(-2, 18), Vector2(-4, 35), Vector2(-8, 34)], leather)
	canvas.draw_line(body + Vector2(-8, 17), body + Vector2(-1, 19), light_leather, 2, false)
	for i: int in range(3):
		var tip := Vector2(-10 + i * 3, 5 + i % 2 * 2)
		canvas.draw_line(body + tip, body + tip + Vector2(3, 17), Color("b5a579"), 1, false)
		canvas.draw_line(body + tip, body + tip + Vector2(2, 4), skin.accent.lightened(0.12), 2, false)
	# Feet are fixed at the platform, independent of breathing and recoil.
	_shape(canvas, origin, [Vector2(2, 38), Vector2(10, 39), Vector2(7, 55), Vector2(0, 55)], dark)
	_shape(canvas, origin, [Vector2(11, 39), Vector2(18, 39), Vector2(20, 55), Vector2(13, 55)], dark)
	canvas.draw_line(origin + Vector2(5, 44), origin + Vector2(3, 53), Color("3d4b44"), 4, false)
	canvas.draw_line(origin + Vector2(15, 44), origin + Vector2(17, 53), Color("3d4b44"), 4, false)
	canvas.draw_rect(Rect2(origin + Vector2(-1, 53), Vector2(9, 7)), dark)
	canvas.draw_rect(Rect2(origin + Vector2(13, 53), Vector2(11, 7)), dark)
	canvas.draw_rect(Rect2(origin + Vector2(0, 54), Vector2(7, 4)), leather)
	canvas.draw_rect(Rect2(origin + Vector2(14, 54), Vector2(9, 4)), leather)
	canvas.draw_line(origin + Vector2(0, 55), origin + Vector2(6, 55), light_leather, 1)
	canvas.draw_line(origin + Vector2(15, 55), origin + Vector2(21, 55), light_leather, 1)
	# Tunic, layered leather shoulder, diagonal quiver strap, belt and pouch.
	_shape(canvas, body, [Vector2(2, 18), Vector2(13, 17), Vector2(18, 23), Vector2(18, 38), Vector2(21, 44), Vector2(10, 46), Vector2(8, 42), Vector2(-1, 44), Vector2(1, 27)], dark)
	_shape(canvas, body, [Vector2(3, 20), Vector2(12, 19), Vector2(16, 24), Vector2(15, 36), Vector2(18, 42), Vector2(10, 43), Vector2(8, 39), Vector2(1, 42), Vector2(3, 28)], skin.primary)
	canvas.draw_rect(Rect2(body + Vector2(11, 25), Vector2(3, 11)), skin.primary.darkened(0.2))
	canvas.draw_line(body + Vector2(1, 21), body + Vector2(14, 35), leather, 3, false)
	canvas.draw_line(body + Vector2(2, 20), body + Vector2(15, 34), light_leather, 1, false)
	canvas.draw_rect(Rect2(body + Vector2(1, 35), Vector2(16, 3)), leather)
	canvas.draw_rect(Rect2(body + Vector2(9, 35), Vector2(3, 3)), skin.accent.lightened(0.2))
	canvas.draw_rect(Rect2(body + Vector2(1, 36), Vector2(5, 7)), dark)
	canvas.draw_rect(Rect2(body + Vector2(2, 37), Vector2(4, 5)), light_leather)
	if skin.style > 0: canvas.draw_line(body + Vector2(11, 42), body + Vector2(17, 41), skin.accent, 2)
	# Hood with projecting brim, lit cheek, eye and scarf silhouette.
	_shape(canvas, body, [Vector2(-2, 3), Vector2(3, -2), Vector2(12, -2), Vector2(18, 3), Vector2(20, 9), Vector2(16, 12), Vector2(14, 19), Vector2(1, 21), Vector2(-3, 14)], dark)
	_shape(canvas, body, [Vector2(0, 4), Vector2(4, 0), Vector2(11, 0), Vector2(16, 4), Vector2(17, 8), Vector2(12, 10), Vector2(12, 17), Vector2(2, 18), Vector2(-1, 13)], skin.secondary)
	_shape(canvas, body, [Vector2(2, 4), Vector2(5, 1), Vector2(11, 1), Vector2(15, 5), Vector2(5, 5), Vector2(2, 13)], skin.primary)
	canvas.draw_rect(Rect2(body + Vector2(9, 7), Vector2(8, 8)), Color("bd9066"))
	canvas.draw_rect(Rect2(body + Vector2(12, 8), Vector2(6, 5)), Color("dfb98c"))
	canvas.draw_rect(Rect2(body + Vector2(15, 8), Vector2(2, 2)), dark)
	canvas.draw_rect(Rect2(body + Vector2(7, 5), Vector2(12, 2)), skin.accent)
	canvas.draw_rect(Rect2(body + Vector2(7, 14), Vector2(9, 5)), skin.primary.darkened(0.18))
	canvas.draw_line(body + Vector2(5, 20), body + Vector2(14, 18), skin.accent, 2, false)
	# Both hands follow the same grip/string anchors used by the bow renderer.
	_limb(canvas, origin, Vector2(12, 23) + pose.body_shift, pose.bow_elbow, ArcherPose.GRIP, skin.primary, leather)
	_limb(canvas, origin, Vector2(4, 23) + pose.body_shift, pose.draw_elbow, pose.draw_hand, skin.primary.darkened(0.1), leather)
	if pose.state == "cast":
		canvas.draw_rect(Rect2((origin + pose.draw_hand + Vector2(-1, -4)).round(), Vector2(2, 3)), skin.accent.lightened(0.3))

static func bow(canvas: CanvasItem, skin: CosmeticData, center: Vector2, direction: Vector2, pull: float, recoil: float = 0.0) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var tension: float = clampf(pull, 0, 1)
	var flex: float = tension * 6 + sin(recoil * PI * 3) * recoil * 2
	var top: Vector2 = center - normal * 19 - direction * (4 + flex)
	var bottom: Vector2 = center + normal * 19 - direction * (4 + flex)
	var points := PackedVector2Array([top, center - normal * 12 + direction * (3 - tension * 2), center - normal * 4, center + normal * 4, center + normal * 12 + direction * (3 - tension * 2), bottom])
	for i: int in range(points.size()): points[i] = points[i].round()
	canvas.draw_polyline(points, Color("192a2d"), 5, false)
	canvas.draw_polyline(points, skin.primary, 3, false)
	var string_center: Vector2 = ArcherPose.string_anchor(center, direction, tension)
	canvas.draw_line(top.round(), string_center.round(), skin.secondary, 1, false)
	canvas.draw_line(string_center.round(), bottom.round(), skin.secondary, 1, false)
	canvas.draw_line(center - normal * 3, center + normal * 3, Color("72553e"), 4, false)
	canvas.draw_line(center - normal, center + normal, skin.accent, 2, false)
	if skin.style > 0:
		canvas.draw_line(top - normal * 2, top + direction * 3, skin.accent, 2, false)
		canvas.draw_line(bottom + normal * 2, bottom + direction * 3, skin.accent, 2, false)

static func _head(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	# The diamond stays inside the real circular contact radius.
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(radius, 0), at + Vector2(0, -radius), at - Vector2(radius, 0), at + Vector2(0, radius)]), color)
	canvas.draw_line(at - Vector2(radius * 0.7, 0), at + Vector2(radius * 0.7, 0), color.lightened(0.18), maxf(1, radius * 0.35), false)

static func arrow(canvas: CanvasItem, skin: CosmeticData, origin: Vector2, size: float, child: bool = false, radius: float = 2.0) -> void:
	canvas.draw_line(origin + Vector2(-16, 0) * size, origin, skin.primary.darkened(0.22), maxf(1, size * 1.4), false)
	canvas.draw_line(origin + Vector2(-16, 0) * size, origin, skin.primary, maxf(1, size * 0.65), false)
	var head: Color = skin.accent
	if child: head = Color("b8e395") if skin.style == 0 else skin.accent.lerp(skin.secondary, 0.45)
	_head(canvas, origin, radius, head)
	for side: int in [-1, 1]:
		_shape(canvas, origin, [Vector2(-12, 0) * size, Vector2(-16, side * 3) * size, Vector2(-18, side * 3) * size, Vector2(-16, 0) * size], skin.secondary)
	if skin.style > 0: canvas.draw_line(origin + Vector2(-10, 0) * size, origin + Vector2(-8, 0) * size, skin.accent, maxf(1, size), false)

static func nocked_arrow(canvas: CanvasItem, skin: CosmeticData, nock: Vector2, aim: Vector2, size: float = 1.0, count: int = 1) -> void:
	# Fixed shaft length keeps the rear on the string and the full-draw tip at BOW.
	# Size changes the head to its real radius; multi-shot previews at most 3 shafts.
	var normal := Vector2(-aim.y, aim.x)
	for i: int in range(mini(count, 3)):
		var offset: Vector2 = normal * (i - (mini(count, 3) - 1) * 0.5) * 3
		var tail: Vector2 = nock + offset
		var head: Vector2 = tail + aim * 23
		canvas.draw_line(tail, head, skin.primary, maxf(1, size * 0.5), false)
		canvas.draw_line(tail + aim * 3, tail - aim * 2 + normal * 3, skin.secondary, 2, false)
		canvas.draw_line(tail + aim * 3, tail - aim * 2 - normal * 3, skin.secondary, 2, false)
		_head(canvas, head, 2 * size, skin.accent)
