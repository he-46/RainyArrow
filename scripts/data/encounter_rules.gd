class_name EncounterRules
extends Resource

@export_range(1, 100) var kills_per_reward: int = 10
@export var split_children: int = 2
@export var split_damage: float = 0.5
@export var split_degrees: float = 12.0
@export var bounce_multiplier: float = 1.25
@export var projectile_speed_limit: float = 2000.0
@export var crit_per_extra_arrow: float = 0.02
@export var unity_damage_exponent: float = 1.0
@export var unity_size_exponent: float = 0.5
@export var crit_per_penetration: float = 0.02
@export var extra_crit_per_bounce: float = 0.20
@export var penetration_damage: float = 0.15
@export var penetration_limit: int = 5
@export var excess_damage: float = 0.02
@export var excess_limit: float = 1.0
@export var echo_damage: float = 0.5
@export var bounce_penetration: int = 3
@export var bounce_penetration_limit: int = 5
@export var charged_penetration: int = 8
@export var bullseye_radius: float = 140.0
@export var bullseye_damage: float = 0.4
@export var bullseye_targets: int = 6
@export var critical_damage: float = 0.12
@export var critical_limit: int = 5
@export var size_bullseye: float = 0.15
@export var size_bullseye_limit: float = 0.75
@export var child_gold_bonus: float = 0.5
@export var child_bounces: int = 2
@export var slender_size_factor: float = 0.7
@export var slender_speed_factor: float = 1.25
@export var heavy_damage_factor: float = 1.4
@export var heavy_reload_factor: float = 1.35
