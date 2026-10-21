class_name BossRules
extends Resource
## Boss values are sampled on entry, independently of ordinary target growth.

@export var kills_per_boss: int = 100
@export var title: String = "铁弦巨靶"
@export var health: float = 2880.0
@export var health_growth: float = 0.6
@export var armor: int = 20
@export var armor_growth: int = 6
@export var score: float = 1200.0
@export var gold: float = 240.0
@export var reward_growth: float = 0.5
@export var width: float = 46.0
@export var radius: float = 62.0
@export var phase_health_ratio: float = 0.5
@export var weak_multiplier: float = 1.75
@export var weak_half_height: float = 12.0
@export var weak_armor_reduction: float = 12.0
@export var shield_width: float = 12.0
@export var shield_height: float = 46.0
@export var shield_gap: float = 23.0
@export var shield_armor_bonus: float = 8.0
@export var body_amplitude: float = 24.0
@export var body_frequency: float = 1.7
@export var shield_amplitude: float = 48.0
@export var shield_frequency: float = 2.3
@export var victory_draws: int = 3
@export var draws_growth_rounds: int = 2
@export var victory_draws_cap: int = 6

func draw_reward(round_number: int) -> int:
	return mini(victory_draws_cap, victory_draws + maxi(0, round_number - 1) / maxi(1, draws_growth_rounds))

func combat_parameters() -> Dictionary:
	return {"body_width": width, "body_radius": radius,
		"phase_health_ratio": phase_health_ratio, "weak_multiplier": weak_multiplier,
		"weak_half_height": weak_half_height, "weak_armor_reduction": weak_armor_reduction,
		"shield_width": shield_width, "shield_height": shield_height, "shield_gap": shield_gap,
		"shield_armor_bonus": shield_armor_bonus, "body_amplitude": body_amplitude,
		"body_frequency": body_frequency, "shield_amplitude": shield_amplitude, "shield_frequency": shield_frequency}

func values(round_number: int, mode: Dictionary = {}) -> Dictionary:
	var step: int = maxi(0, round_number - 1)
	return {
		"max_hp": roundf(health * (1.0 + step * health_growth)) * float(mode.get("boss_health", 1.0)),
		"armor": armor + step * armor_growth,
		"reward_score": roundf(score * (1.0 + step * reward_growth)) * float(mode.get("score", 1.0)),
		"reward_gold": roundf(gold * (1.0 + step * reward_growth)),
	}

static func resilient_damage(previous: float, incoming: float, threshold: float) -> float:
	# Linear up to T, then T * (1 + ln(D/T)) per entire draw. Incremental form
	# preserves small late contacts and does not favor a large number of arrows.
	var normal: float = minf(incoming, maxf(0.0, threshold - previous))
	var excess: float = maxf(0.0, incoming - normal)
	return normal + threshold * log(1.0 + excess / maxf(threshold, previous))
