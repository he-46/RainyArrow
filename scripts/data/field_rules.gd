class_name FieldRules
extends Resource
## Values are sampled once when a target spawns, never applied to existing targets.

@export var health_growth: float = 0.06
@export var reward_growth: float = 0.08
@export var defeats_per_armor: int = 5
@export var respawn_seconds: float = 1.4

func target_values(definition: TargetData, defeats: int, mode: Dictionary = {}) -> Dictionary:
	var step: int = clampi(defeats, 0, 1000000)
	var health_factor: float = 1.0 + step * float(mode.get("health_growth", health_growth))
	var armor_growth: int = floori(float(step) / maxi(1, defeats_per_armor))
	if int(mode.get("growth_revision", 0)) == 1:
		# Revision 1 stays immutable for saved adventures. The initial HP slope
		# remains 6% of base, then marginal growth decreases instead of compounding.
		health_factor = pow(1.0 + step * 0.075, 0.8)
		armor_growth = floori(pow(float(step) / 5.0, 0.8))
	return {
		"max_hp": definition.durability * health_factor * float(mode.get("target_health", 1.0)),
		"armor": definition.armor + int(mode.get("target_armor", 0)) + armor_growth,
		"reward_score": roundf(definition.defeat_score * (1.0 + step * reward_growth)) * float(mode.get("score", 1.0)),
		"reward_gold": roundf(definition.break_gold * (1.0 + step * reward_growth)),
		"spawn_difficulty": step,
	}
