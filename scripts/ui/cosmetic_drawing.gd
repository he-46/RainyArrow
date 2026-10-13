class_name CosmeticDrawing
extends RefCounted
## Shared pixel shapes for preview and gameplay. Sizes never modify collision data.

static func archer(canvas: CanvasItem, skin: CosmeticData, origin: Vector2) -> void:
	canvas.draw_rect(Rect2(origin + Vector2(0, 19), Vector2(17, 31)), skin.primary)
	canvas.draw_rect(Rect2(origin + Vector2(1, 46), Vector2(5, 14)), Color("172d34"))
	canvas.draw_rect(Rect2(origin + Vector2(13, 46), Vector2(5, 14)), Color("172d34"))
	canvas.draw_rect(Rect2(origin + Vector2(0, 2), Vector2(17, 18)), skin.secondary)
	canvas.draw_rect(Rect2(origin + Vector2(7, 5), Vector2(11, 11)), Color("dab38a"))
	canvas.draw_rect(Rect2(origin + Vector2(-1, 0), Vector2(21, 5)), skin.accent)
	canvas.draw_rect(Rect2(origin + Vector2(14, 20), Vector2(13, 5)), Color("dab38a"))
	if skin.style > 0:
		canvas.draw_rect(Rect2(origin + Vector2(0, 39), Vector2(17, 3)), skin.accent)
		canvas.draw_rect(Rect2(origin + Vector2(2, 18), Vector2(3, 18)), skin.accent)
	if skin.style == 2:
		canvas.draw_rect(Rect2(origin + Vector2(-4, 23), Vector2(4, 23)), skin.secondary)

static func bow(canvas: CanvasItem, skin: CosmeticData, center: Vector2, direction: Vector2, pull: float) -> void:
	var normal: Vector2 = direction.orthogonal()
	var top: Vector2 = center - normal * 19
	var bottom: Vector2 = center + normal * 19
	var grip: Vector2 = center + direction * 7
	canvas.draw_line(top, grip - normal * 8, skin.primary, 3)
	canvas.draw_line(grip - normal * 8, grip + normal * 8, skin.primary, 3)
	canvas.draw_line(grip + normal * 8, bottom, skin.primary, 3)
	var string_center: Vector2 = center - direction * (pull * 23)
	canvas.draw_line(top, string_center, skin.secondary, 1)
	canvas.draw_line(string_center, bottom, skin.secondary, 1)
	if skin.style > 0:
		canvas.draw_line(grip - normal * 4, grip + normal * 4, skin.accent, 4)
		canvas.draw_line(top - normal * 2, top + direction * 3, skin.accent, 2)
		canvas.draw_line(bottom + normal * 2, bottom + direction * 3, skin.accent, 2)

static func arrow(canvas: CanvasItem, skin: CosmeticData, origin: Vector2, size: float, child: bool = false, radius: float = 2.0) -> void:
	canvas.draw_line(origin + Vector2(-16, 0) * size, origin, skin.primary, size)
	var head: Color = skin.accent
	if child: head = Color("b8e395") if skin.style == 0 else skin.accent.lerp(skin.secondary, 0.45)
	canvas.draw_circle(origin, radius, head)
	canvas.draw_line(origin + Vector2(-13, 0) * size, origin + Vector2(-17, -3) * size, skin.secondary, 2 * size)
	if skin.style > 0:
		canvas.draw_line(origin + Vector2(-13, 0) * size, origin + Vector2(-17, 3) * size, skin.secondary, 2 * size)
