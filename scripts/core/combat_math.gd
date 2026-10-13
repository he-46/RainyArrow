class_name CombatMath
extends RefCounted
## Pure functions: shared by the live shot, aiming preview and automated tests.

static func displacement(velocity: Vector2, gravity: float, delta: float) -> Vector2:
	return velocity * delta + Vector2(0.0, 0.5 * gravity * delta * delta)

static func launch_velocity(direction: Vector2, pull: float, stats: BowStats) -> Vector2:
	return direction.normalized() * stats.launch_speed * lerpf(0.42, 1.0, clampf(pull, 0.0, 1.0))

static func resolve_hit(stats: BowStats, pull: float, bullseye: bool, remaining_hp: float, roll: float, armor: int = 0) -> Dictionary:
	var critical: bool = roll < stats.crit_chance
	var raw: float = stats.damage * lerpf(0.7, 1.0, clampf(pull, 0.0, 1.0))
	if critical:
		raw *= stats.crit_multiplier
	var unblocked_armor: int = maxi(armor - stats.armor_penetration, 0)
	var effective: float = minf(maxf(1.0, raw - unblocked_armor), maxf(remaining_hp, 0.0))
	return {
		"raw": raw, "effective": effective, "critical": critical,
		"bullseye": bullseye,
		"pierced": stats.armor_penetration > armor, "armor_blocked": unblocked_armor,
	}
