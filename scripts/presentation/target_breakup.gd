class_name TargetBreakup
extends Node2D
## Disposable visual debris: no collisions, hit groups, rewards, or combat RNG.
const DURATION: float = 0.42
const MAX_ACTIVE: int = 12
var age: float = 0.0
var pieces: Array[Dictionary] = []
var cleared: bool = false

static func spawn_from(target: ArcheryTarget, is_clear: bool = false) -> TargetBreakup:
	if not target.is_inside_tree(): return null
	if target.get_parent() is ArcheryWorld and target.get_parent().reduced_effects: return null
	var existing: Array[Node] = []
	for child: Node in target.get_parent().get_children():
		if child is TargetBreakup: existing.append(child)
	if existing.size() >= MAX_ACTIVE:
		var oldest: Node = existing[0]
		target.get_parent().remove_child(oldest)
		oldest.queue_free()
	var effect := TargetBreakup.new()
	effect.position = target.position
	effect.cleared = is_clear
	var body: Rect2 = TargetArt.body_rect(target)
	var steel: bool = target is ArcheryBoss or target.definition.armor > 0
	for row: int in range(4):
		for col: int in range(2):
			var size: Vector2 = body.size * target.scale / Vector2(2, 4)
			var origin: Vector2 = body.position * target.scale + size * Vector2(col, row)
			var direction: float = -1.0 if col == 0 else 1.0
			var velocity := Vector2(direction * (18 + row * 7), -38 + row * 14)
			if target is ArcheryBoss: velocity *= 2.0
			if is_clear: velocity = Vector2(direction * 12, 15 + row * 8)
			var color := Color("7f999b") if steel else Color("b18a56")
			if target is ArcheryBoss and row in [1, 2]: color = Color("c9af70")
			effect.pieces.append({"origin": origin, "size": size - Vector2.ONE, "velocity": velocity, "spin": direction * (0.7 + row * 0.25), "color": Color("526562") if is_clear else color})
	target.get_parent().add_child(effect)
	return effect

func _process(delta: float) -> void:
	age += delta
	if age >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var opacity: float = 1.0 - clampf(age / DURATION, 0, 1)
	for piece: Dictionary in pieces:
		var position_now: Vector2 = piece.origin + piece.velocity * age + Vector2(0, 100 * age * age)
		var color: Color = piece.color
		color.a = opacity * (0.65 if cleared else 1.0)
		var size: Vector2 = piece.size
		draw_set_transform((position_now + size * 0.5).round(), piece.spin * age)
		var half: Vector2 = size * 0.5
		var notch: float = minf(2, size.x * 0.25)
		draw_colored_polygon(PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x - notch, -half.y), Vector2(half.x, -half.y * 0.3), Vector2(half.x - notch, half.y * 0.4), half, Vector2(-half.x + notch, half.y), Vector2(-half.x, half.y * 0.4)]), color)
		var detail: Color = color.darkened(0.3)
		detail.a = color.a
		draw_line(-half + Vector2(2, 1), Vector2(-half.x + 2, half.y - 2), detail, 1, false)
		draw_set_transform(Vector2.ZERO)
