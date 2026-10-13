class_name FieldRules
extends Resource
## Values are sampled once when a target spawns, never applied to existing targets.

@export var health_growth: float = 0.06
@export var reward_growth: float = 0.08
@export var defeats_per_armor: int = 5
@export var respawn_seconds: float = 1.4

func target_values(definition: TargetData, defeats: int, mode: Dictionary = {}) -> Dictionary:
	var step: int = clampi(defeats, 0, 1000000)
	return {
		"max_hp": definition.durability * (1.0 + step * float(mode.get("health_growth", health_growth))) * float(mode.get("target_health", 1.0)),
		"armor": definition.armor + int(mode.get("target_armor", 0)) + floori(float(step) / maxi(1, defeats_per_armor)),
		"reward_score": roundf(definition.defeat_score * (1.0 + step * reward_growth)) * float(mode.get("score", 1.0)),
		"reward_gold": roundf(definition.break_gold * (1.0 + step * reward_growth)),
		"spawn_difficulty": step,
	}
