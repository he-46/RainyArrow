extends RefCounted
## Differential coverage for the broad phase against the unchanged exact solver.
var assertion: Callable
func _init(check: Callable) -> void: assertion = check
func run_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70718
	for magnitude: float in [0.01, 1.0, 1000.0]:
		var equal: bool = true
		for sample: int in range(2500):
			var origin := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100)) * magnitude
			var movement := Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200)) * magnitude
			var rect := Rect2(Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50)) * magnitude, Vector2(rng.randf_range(1, 60), rng.randf_range(1, 60)) * magnitude)
			var radius: float = rng.randf_range(0.1, 20) * magnitude
			if sample % 11 == 0: movement = Vector2.ZERO
			if sample % 13 == 0: movement.x = 0
			if sample % 17 == 0: movement.y = 0
			if sample % 19 == 0: origin = rect.position - Vector2(radius, 0)
			if SweepMath.circle_rect(origin, movement, radius, rect) != SweepMath._circle_rect_exact(origin, movement, radius, rect):
				equal = false
				push_error("Culling mismatch: start=%s step=%s radius=%s rect=%s" % [origin, movement, radius, rect])
				break
		assertion.call(equal, "V07: broad phase equals exact contact fraction/normal across 2500 cases at scale " + str(magnitude))
	var box := Rect2(10, 10, 10, 10)
	assertion.call(SweepMath.circle_rect(Vector2(0, 9), Vector2(10, 0), 1, box).fraction == 1.0, "V07: endpoint tangency is retained")
	assertion.call(SweepMath.circle_rect(Vector2(9, 9), Vector2.ZERO, 1, box).is_empty(), "V07: expanded rectangle corner does not become a false hit")
	assertion.call(not SweepMath.circle_rect(Vector2(15, 15), Vector2.ZERO, 1, box).is_empty(), "V07: stationary overlap is retained")
