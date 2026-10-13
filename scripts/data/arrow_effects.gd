class_name ArrowEffects
extends RefCounted
## Values copied at launch. Active projectiles never read newly selected traits.

var split_count: int = 0
var split_damage: float = 0.5
var split_degrees: float = 12.0
var bounce_multiplier: float = 1.0
var speed_limit: float = 2000.0
var penetration_damage: float = 0.0
var penetration_limit: int = 0
var excess_damage: float = 0.0
var excess_limit: float = 0.0
var echo_damage: float = 0.0
var bounce_penetration: int = 0
var bounce_penetration_limit: int = 0
var charged_penetration: int = 0
var bullseye_radius: float = 0.0
var bullseye_damage: float = 0.0
var bullseye_targets: int = 0
var critical_damage: float = 0.0
var critical_limit: int = 0
var size_bullseye: float = 0.0
var size_bullseye_limit: float = 0.0
var child_gold_bonus: float = 0.0
var child_bounces: int = 0

func to_dict() -> Dictionary:
	return {"split_count": split_count, "split_damage": split_damage, "split_degrees": split_degrees,
		"bounce_multiplier": bounce_multiplier, "speed_limit": speed_limit,
		"penetration_damage": penetration_damage, "penetration_limit": penetration_limit,
		"excess_damage": excess_damage, "excess_limit": excess_limit, "echo_damage": echo_damage,
		"bounce_penetration": bounce_penetration, "bounce_penetration_limit": bounce_penetration_limit,
		"charged_penetration": charged_penetration, "bullseye_radius": bullseye_radius,
		"bullseye_damage": bullseye_damage, "bullseye_targets": bullseye_targets,
		"critical_damage": critical_damage, "critical_limit": critical_limit,
		"size_bullseye": size_bullseye, "size_bullseye_limit": size_bullseye_limit,
		"child_gold_bonus": child_gold_bonus, "child_bounces": child_bounces}

static func from_dict(data: Dictionary) -> ArrowEffects:
	var result := ArrowEffects.new()
	for key: String in result.to_dict():
		if data.has(key): result.set(key, data[key])
	return result
