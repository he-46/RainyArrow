class_name BowStats
extends Resource
## Immutable base configuration. RunModel always duplicates it before applying upgrades.

@export var damage: float = 24.0
@export var arrow_count: int = 1
@export var arrow_size: float = 1.0
@export var crit_chance: float = 0.1
@export var crit_multiplier: float = 2.0
@export var reload_seconds: float = 0.65
@export var launch_speed: float = 490.0
@export var gravity: float = 230.0
@export var spread_degrees: float = 6.0
@export var armor_penetration: int = 0
@export var bounces: int = 0
@export var gold_multiplier: float = 1.0

func clamp_values() -> void:
	damage = clampf(damage, 1.0, 1000000.0)
	arrow_count = clampi(arrow_count, 1, 32)
	arrow_size = clampf(arrow_size, 0.5, 6.0)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	crit_multiplier = clampf(crit_multiplier, 1.0, 10.0)
	reload_seconds = clampf(reload_seconds, 0.15, 3.0)
	launch_speed = clampf(launch_speed, 200.0, 1000.0)
	armor_penetration = clampi(armor_penetration, 0, 1000000)
	bounces = clampi(bounces, 0, 32)
	gold_multiplier = clampf(gold_multiplier, 1.0, 4.0)

const FIELDS: Array[String] = ["damage", "arrow_count", "arrow_size", "crit_chance", "crit_multiplier", "reload_seconds", "launch_speed", "gravity", "spread_degrees", "armor_penetration", "bounces", "gold_multiplier"]

func collision_radius() -> float:
	return 2.0 * arrow_size

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for field: String in FIELDS: result[field] = get(field)
	return result

static func from_dict(data: Dictionary) -> BowStats:
	var result := BowStats.new()
	for field: String in FIELDS:
		if data.has(field): result.set(field, data[field])
	return result
