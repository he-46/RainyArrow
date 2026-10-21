class_name TargetArt
extends RefCounted
## All bright surfaces derive from real hit volumes. Supports remain dark scenery.
const INK := Color("182c30")
const STEEL := Color("647c80")
const EDGE := Color("adc0ac")

static func body_rect(target: ArcheryTarget) -> Rect2:
	var size: Vector2 = (target.collider.shape as RectangleShape2D).size
	return Rect2(-size * 0.5, size)

static func weak_rect(target: ArcheryTarget) -> Rect2:
	var body: Rect2 = body_rect(target)
	var half: float = target.definition.radius * 0.26 * float(target.difficulty_parameters.get("bullseye_scale", 1.0))
	if target is ArcheryBoss and target.combat_schema == 1:
		half = float(target.parameters["weak_half_height"])
		body = body.grow_side(SIDE_LEFT, 2).grow_side(SIDE_RIGHT, 2)
	return Rect2(body.position.x, -half, body.size.x, half * 2)

static func shield_rect(boss: ArcheryBoss) -> Rect2:
	var size := Vector2(float(boss.parameters["shield_width"]), float(boss.parameters["shield_height"]))
	return Rect2(boss.shield_position - boss.position - size * 0.5, size)

static func _bolt(canvas: CanvasItem, at: Vector2, bright: Color = EDGE) -> void:
	canvas.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), INK)
	canvas.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), bright)

static func _crack(canvas: CanvasItem, points: PackedVector2Array) -> void:
	canvas.draw_polyline(points, Color("9c906b"), 2, false)
	canvas.draw_polyline(points, INK, 1, false)
	canvas.draw_line(points[1], points[1] + Vector2(3, -2), INK, 1, false)

static func ordinary(canvas: CanvasItem, target: ArcheryTarget) -> void:
	var r: float = target.definition.radius
	var foot: float = (308.0 - target.position.y) / target.scale.y
	canvas.draw_rect(Rect2(-2, r, 4, maxf(0, foot - r)), Color("2e4342"))
	canvas.draw_line(Vector2(-1, r), Vector2(-1, foot), Color("3d524b"), 1, false)
	canvas.draw_rect(Rect2(-7, foot, 14, 2), Color("43594b"))
	if target.definition.movement > 0:
		canvas.draw_rect(Rect2(-3, r + 2, 6, 4), Color("49635c"))
	if target.hp <= 0: return
	var body: Rect2 = body_rect(target)
	var iron: bool = target.definition.armor > 0
	var tint: Color = (STEEL if iron else Color("a2784d")).lerp(Color("fff1c2"), target.flash * 0.65)
	canvas.draw_rect(body, INK)
	canvas.draw_rect(body.grow(-1), tint)
	# Separate vertical boards, end grain and small knots.
	for x: int in [-4, 1, 4]:
		canvas.draw_line(Vector2(x, -r + 3), Vector2(x, r - 3), tint.darkened(0.24), 1, false)
	for i: int in range(6):
		var x: int = -5 + (i * 5) % 10
		var y: float = -r + 6 + i * (r * 2 - 12) / 6
		canvas.draw_rect(Rect2(x, y, 2, 3), tint.lightened(0.15) if i % 2 == 0 else tint.darkened(0.3))
	var binding: Color = Color("849ba0") if target.armor > 0 else Color("c5ae7b")
	if target.definition.movement > 0: binding = Color("73a48a")
	for y: float in [-r + 1, r - 5]:
		canvas.draw_rect(Rect2(-6, y, 12, 4), binding.darkened(0.2))
		canvas.draw_line(Vector2(-6, y), Vector2(5, y), binding, 1, false)
		if target.armor > 0:
			_bolt(canvas, Vector2(-4, y + 2))
			_bolt(canvas, Vector2(4, y + 2))
	# Straw/paint rings do not extend beyond the 14-unit contact body.
	canvas.draw_rect(Rect2(-6, -r * 0.61, 12, r * 1.22), Color("bfa77d") if not iron else Color("839696"))
	canvas.draw_rect(Rect2(-5, -r * 0.48, 10, r * 0.96), Color("e0c593") if not iron else Color("b7bba4"))
	var weak: Rect2 = weak_rect(target)
	canvas.draw_rect(weak, Color("cc6247").lerp(Color("ffe0a0"), target.flash * 0.4))
	canvas.draw_rect(Rect2(-5, -minf(1, weak.size.y * 0.2), 10, minf(2, weak.size.y * 0.4)), Color("ffe4a2"))
	if target.definition.movement > 0:
		canvas.draw_polyline(PackedVector2Array([Vector2(-3, -r + 10), Vector2(0, -r + 7), Vector2(3, -r + 10)]), Color("9bc8a0"), 1, false)
	var health: float = target.hp / target.max_hp
	if health <= 0.7:
		_crack(canvas, PackedVector2Array([Vector2(-5, -r + 6), Vector2(-2, -r + 10), Vector2(-4, -r + 14)]))
	if health <= 0.35:
		_crack(canvas, PackedVector2Array([Vector2(4, r - 6), Vector2(1, r - 10), Vector2(3, r - 14), Vector2(1, r - 16)]))
	# UI annotations stay unscaled, as in the original target renderer.
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / target.scale)
	var width: float = 25 * sqrt(target.scale.x)
	var y: float = -r * target.scale.y - 6
	canvas.draw_rect(Rect2(-width * 0.5, y, width, 3), INK)
	canvas.draw_rect(Rect2(-width * 0.5, y, width * health, 3), Color("8dbb9c") if health > 0.35 else Color("d9a465"))
	if target.armor > 0:
		canvas.draw_string(ThemeDB.fallback_font, Vector2(7 * target.scale.x + 3, -r * target.scale.y + 10), "A %d" % target.armor, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("9fc7db"))

static func boss(canvas: CanvasItem, target: ArcheryBoss) -> void:
	var body: Rect2 = body_rect(target)
	var half: float = body.size.x * 0.5
	var r: float = body.size.y * 0.5
	var foot: float = 306 - target.position.y
	# Two telescoping supports meet a grounded pedestal. No bright false hit zone.
	for x: float in [-half + 7, half - 11]:
		canvas.draw_rect(Rect2(x, r, 4, maxf(0, foot - r)), Color("364b49"))
		canvas.draw_line(Vector2(x + 1, r), Vector2(x + 1, foot), Color("53635a"), 1, false)
	canvas.draw_rect(Rect2(-half - 6, foot, body.size.x + 12, 4), Color("3d5247"))
	canvas.draw_line(Vector2(-half - 6, foot), Vector2(half + 5, foot), Color("6b7d62"), 1, false)
	if target.hp <= 0: return
	var active: bool = target.combat_schema == 1 and target.battle_phase == 2
	var tint: Color = STEEL.lerp(Color("ffebbd"), target.flash * 0.65)
	var trim: Color = Color("b88757") if active else Color("8c9d89")
	canvas.draw_rect(body, INK)
	canvas.draw_rect(body.grow(-1), tint)
	canvas.draw_rect(body.grow(-4), Color("2c444d"))
	# Chamfered plate faces, diagonal braces and inset bolt heads.
	for side: int in [-1, 1]:
		var top: float = -r + 6 if side < 0 else 18
		var height: float = r - 24
		var panel := Rect2(-half + 6, top, body.size.x - 12, height)
		canvas.draw_rect(panel, Color("435e65").lerp(Color("e9d7ac"), target.flash * 0.4))
		canvas.draw_line(panel.position, Vector2(panel.end.x, panel.position.y), trim, 2, false)
		canvas.draw_line(panel.position + Vector2(2, 5), panel.end - Vector2(2, 5), Color("536e72"), 3, false)
		canvas.draw_line(Vector2(panel.end.x - 2, panel.position.y + 5), Vector2(panel.position.x + 2, panel.end.y - 5), Color("344d54"), 2, false)
		for x: float in [-half + 3, half - 4]:
			_bolt(canvas, Vector2(x, top + 2), trim.lightened(0.18))
			_bolt(canvas, Vector2(x, top + height - 3), trim)
		for index: int in range(3):
			var y: float = top + 10 + index * 7
			canvas.draw_rect(Rect2(-5, y, 10, 2), Color("e59957") if active else Color("88aaa4"))
	# Gold band equals the entire real weak volume, including its two-unit lip.
	var weak: Rect2 = weak_rect(target)
	canvas.draw_rect(weak, Color("b77844") if active else Color("b5985b"))
	canvas.draw_rect(weak.grow(-1), Color("e1bd70").lerp(Color("ffeac0"), target.flash * 0.5))
	var pulse: float = 0.12 * (0.5 + 0.5 * sin(target.phase_clock * 5)) if active else 0
	canvas.draw_rect(Rect2(-10, -weak.size.y * 0.3, 20, weak.size.y * 0.6), Color("f2dfa0").lightened(pulse))
	canvas.draw_rect(Rect2(-4, -weak.size.y * 0.22, 8, weak.size.y * 0.44), Color("fff3ca"))
	for x: float in [weak.position.x + 2, weak.end.x - 4]:
		canvas.draw_rect(Rect2(x, -3, 2, 6), Color("a27b45"))
	if target.hp / target.max_hp <= 0.5:
		_crack(canvas, PackedVector2Array([Vector2(-half + 6, -r + 9), Vector2(-half + 13, -r + 17), Vector2(-half + 10, -r + 24), Vector2(-half + 16, -r + 30)]))
	if target.hp / target.max_hp <= 0.25:
		_crack(canvas, PackedVector2Array([Vector2(half - 5, r - 7), Vector2(half - 13, r - 17), Vector2(half - 9, r - 25)]))
	if target.combat_schema == 1:
		canvas.draw_string(ThemeDB.fallback_font, Vector2(half + 7, 4), "核心 ×%.2f" % float(target.parameters["weak_multiplier"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ffdc83"))
	if active: _shield(canvas, target)

static func _shield(canvas: CanvasItem, target: ArcheryBoss) -> void:
	var rect: Rect2 = shield_rect(target)
	var center: Vector2 = rect.get_center()
	canvas.draw_line(Vector2(-body_rect(target).size.x * 0.5, center.y), center, Color("33484c"), 2, false)
	canvas.draw_rect(rect, INK)
	canvas.draw_rect(rect.grow(-1), Color("8aa5aa").lerp(Color("fff2ce"), target.shield_flash * 0.8))
	canvas.draw_rect(rect.grow(-3), Color("405c69"))
	for y: float in [rect.position.y + 4, center.y, rect.end.y - 5]:
		canvas.draw_line(Vector2(rect.position.x + 1, y), Vector2(rect.end.x - 2, y), Color("c49e62"), 2, false)
		_bolt(canvas, Vector2(center.x, y), Color("e0cd92"))
	canvas.draw_string(ThemeDB.fallback_font, Vector2(rect.position.x - 24, rect.position.y - 6), "护板 A %d" % target.shield_armor(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("9fc7db"))
