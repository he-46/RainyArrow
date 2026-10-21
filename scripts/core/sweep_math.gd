class_name SweepMath
extends RefCounted
## Continuous collision for a circular arrowhead against axis-aligned rectangular targets.

static func circle_rect(start: Vector2, step: Vector2, radius: float, rect: Rect2) -> Dictionary:
	# Reject only separated swept bounds. Border contacts and rounded-corner tests
	# still use the exact solver; the margin is conservative for float rounding.
	var end: Vector2 = start + step
	var coordinate_scale: float = maxf(maxf(start.abs().x, start.abs().y), maxf(end.abs().x, end.abs().y))
	coordinate_scale = maxf(coordinate_scale, maxf(rect.position.abs().x, rect.position.abs().y))
	coordinate_scale = maxf(coordinate_scale, maxf(rect.end.abs().x, rect.end.abs().y))
	var padding: float = radius + maxf(0.0001, coordinate_scale * 0.000001)
	if maxf(start.x, end.x) + padding < rect.position.x or minf(start.x, end.x) - padding > rect.end.x or maxf(start.y, end.y) + padding < rect.position.y or minf(start.y, end.y) - padding > rect.end.y:
		return {}
	return _circle_rect_exact(start, step, radius, rect)

static func _circle_rect_exact(start: Vector2, step: Vector2, radius: float, rect: Rect2) -> Dictionary:
	var nearest := start.clamp(rect.position, rect.end)
	if start.distance_squared_to(nearest) <= radius * radius:
		return {"fraction": 0.0, "normal": -step.normalized()}
	var best: Dictionary = {}
	for axis: int in range(2):
		if absf(step[axis]) < 0.0000001: continue
		var other: int = 1 - axis
		var sign_value: float = -1.0 if step[axis] > 0.0 else 1.0
		var edge: float = rect.position[axis] - radius if sign_value < 0 else rect.end[axis] + radius
		var fraction: float = (edge - start[axis]) / step[axis]
		var cross_position: float = start[other] + step[other] * fraction
		if fraction >= 0.0 and fraction <= 1.0 and cross_position >= rect.position[other] and cross_position <= rect.end[other]:
			var normal := Vector2.ZERO
			normal[axis] = sign_value
			best = _earlier(best, fraction, normal)
	# Rounded corners avoid the false hits produced by a simple expanded AABB.
	var length_squared: float = step.length_squared()
	if length_squared > 0.0000001:
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var offset: Vector2 = start - corner
			var b: float = offset.dot(step)
			var discriminant: float = b * b - length_squared * (offset.length_squared() - radius * radius)
			if discriminant < 0.0: continue
			var fraction: float = (-b - sqrt(discriminant)) / length_squared
			if fraction >= 0.0 and fraction <= 1.0:
				best = _earlier(best, fraction, (start + step * fraction - corner).normalized())
	return best

static func boundary(start: Vector2, step: Vector2, allowed: Rect2) -> Dictionary:
	var best: Dictionary = {}
	for axis: int in range(2):
		if absf(step[axis]) < 0.0000001: continue
		var edge: float = allowed.end[axis] if step[axis] > 0 else allowed.position[axis]
		var fraction: float = (edge - start[axis]) / step[axis]
		if fraction < -0.000001 or fraction > 1.0: continue
		var normal := Vector2.ZERO
		normal[axis] = -1.0 if step[axis] > 0 else 1.0
		if not best.is_empty() and absf(float(best["fraction"]) - fraction) < 0.000001:
			best["normal"] += normal
		else:
			best = _earlier(best, maxf(0.0, fraction), normal)
	return best

static func _earlier(best: Dictionary, fraction: float, normal: Vector2) -> Dictionary:
	if best.is_empty() or fraction < float(best["fraction"]):
		return {"fraction": fraction, "normal": normal}
	return best
