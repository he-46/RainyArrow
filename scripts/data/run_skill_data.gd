class_name RunSkillData
extends Resource
## Run-only skills. Additive effects are applied before quantity's damage multiplier.

@export var id: StringName
@export var title: String
@export var description: String
@export var additions: Dictionary = {}
@export var damage_factor: float = 1.0
@export var cost: int = 12
@export var cost_growth: float = 1.5
@export var max_level: int = 6
@export var mastery_description: String = ""
@export var mastery_cost: int = 150
@export var mastery_cost_growth: float = 1.18
@export var mastery_max_level: int = 100
@export var mastery_decay: float = 0.12
@export var mastery_additions: Dictionary = {}
@export var mastery_flat_additions: Dictionary = {}
@export var mastery_damage_bonus: float = 0.0
@export var quantity_relief_ranks: int = 6
@export var quantity_relief: float = 0.02
@export var quantity_factor_limit: float = 0.98

func price(rank: int) -> int:
	return ceili(cost * pow(cost_growth, rank))

func mastery_price(rank: int) -> int:
	return ceili(minf(1000000000.0, mastery_cost * pow(mastery_cost_growth, clampi(rank, 0, mastery_max_level))))

func mastery_weight(rank: int) -> float:
	var total: float = 0.0
	for index: int in range(clampi(rank, 0, mastery_max_level)):
		total += 1.0 / (1.0 + mastery_decay * index)
	return total

func comparison(before: BowStats, after: BowStats) -> String:
	match id:
		&"quantity":
			var result: String = "箭数 %d → %d · 单箭 %.1f → %.1f" % [before.arrow_count, after.arrow_count, before.damage, after.damage]
			if not is_equal_approx(before.crit_chance, after.crit_chance): result += "\n联动暴击 %.0f%% → %.0f%%" % [before.crit_chance * 100, after.crit_chance * 100]
			return result
		&"critical": return "暴击 %.0f%% → %.0f%% · 倍率 %.2f → %.2f" % [before.crit_chance * 100, after.crit_chance * 100, before.crit_multiplier, after.crit_multiplier]
		&"damage": return "单箭伤害 %.1f → %.1f" % [before.damage, after.damage]
		&"penetration": return "穿甲 %d → %d" % [before.armor_penetration, after.armor_penetration]
		&"ricochet": return "反弹次数 %d → %d" % [before.bounces, after.bounces]
		&"size": return "碰撞半径 %.1f → %.1f" % [before.collision_radius(), after.collision_radius()]
	return ""
