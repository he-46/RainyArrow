class_name TraitUpgradeData
extends Resource
## Deltas are applied once to the original rules, never to previously derived values.

@export var max_level: int = 3
@export var cost: int = 240
@export var cost_growth: float = 1.8
@export var additions: Dictionary = {}
@export var divisors: Dictionary = {}

func price(rank: int) -> int:
	return mini(1000000000, ceili(cost * pow(cost_growth, clampi(rank, 0, max_level))))

func apply(rules: EncounterRules, base: EncounterRules, rank: int) -> void:
	rank = clampi(rank, 0, max_level)
	for field: String in additions: rules.set(field, base.get(field) + additions[field] * rank)
	for field: String in divisors: rules.set(field, base.get(field) / (1.0 + divisors[field] * rank))
