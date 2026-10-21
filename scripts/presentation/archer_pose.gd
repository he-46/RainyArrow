class_name ArcherPose
extends RefCounted
## Pure presentation state. Local origin is (79, 221); feet stay on y=60.
## The grip (25, 17) maps exactly to ArcheryWorld.BOW, including while recoiling.
const GRIP := Vector2(25, 17)
var state: String = "idle"
var direction := Vector2.RIGHT
var tension: float = 0.0
var recoil: float = 0.0
var body_shift := Vector2.ZERO
var cloak_swing: float = 0.0
var draw_hand := Vector2.ZERO
var draw_elbow := Vector2.ZERO
var bow_elbow := Vector2.ZERO
var loaded: bool = true

static func string_anchor(center: Vector2, aim: Vector2, tension_value: float) -> Vector2:
	return center - aim * (4.0 + clampf(tension_value, 0, 1) * 19.0)

static func sample(aim: Vector2, pulling: bool = false, amount: float = 0.0, reload_left: float = 0.0, reload_duration: float = 0.65, kick: float = 0.0, cast_left: float = 0.0, time: float = 0.0) -> ArcherPose:
	var pose := ArcherPose.new()
	pose.direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	pose.tension = clampf(amount, 0, 1) if pulling else 0.0
	pose.recoil = clampf(kick, 0, 1) if not pulling else 0.0
	pose.loaded = reload_left <= 0.0 and (pulling or kick <= 0.0)
	pose.body_shift = Vector2(round(-pose.tension * 2 - pose.recoil * 2), round(sin(time * 2.4) * 0.6))
	pose.cloak_swing = round(sin(time * 2.1) * 1.5 - pose.tension * 2 - pose.recoil * 6)
	pose.bow_elbow = Vector2(17, 23) + pose.body_shift
	pose.draw_hand = string_anchor(GRIP, pose.direction, pose.tension)
	pose.draw_elbow = Vector2(2, 31) + pose.body_shift
	if pulling:
		pose.state = "hold" if pose.tension >= 0.98 else "draw"
		pose.draw_elbow = pose.draw_hand + Vector2(-9, 6 - pose.tension * 9)
	elif kick > 0.0:
		pose.state = "release"
		pose.draw_hand = Vector2(1, 15) + Vector2(-5, -3) * pose.recoil
		pose.draw_elbow = Vector2(-7, 25)
	elif cast_left > 0.0:
		pose.state = "cast"
		pose.draw_hand = Vector2(-3, 5)
		pose.draw_elbow = Vector2(-9, 20)
	elif reload_left > 0.0:
		pose.state = "reload"
		var progress: float = 1.0 - clampf(reload_left / maxf(reload_duration, 0.001), 0, 1)
		# Reach into the quiver, then carry the new arrow back to the string.
		pose.draw_hand = Vector2(-7, 8).lerp(string_anchor(GRIP, pose.direction, 0), smoothstep(0.3, 1.0, progress))
		pose.draw_elbow = Vector2(-10, 26).lerp(Vector2(6, 29), progress)
	return pose
