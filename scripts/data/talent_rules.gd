class_name TalentRules
extends Resource

@export_range(0, 10) var max_refunds_per_draw: int = 1
@export_range(0, 20) var combo_bonus_cap: int = 5
@export_range(0.0, 1.0) var arrow_crit_bonus_cap: float = 0.10
@export_range(0.0, 1.0) var penetration_damage_bonus_cap: float = 0.30
@export_range(0.0, 1.0) var arrow_damage_bonus_cap: float = 0.28
@export_range(0.0, 1.0) var size_damage_bonus_cap: float = 0.30
