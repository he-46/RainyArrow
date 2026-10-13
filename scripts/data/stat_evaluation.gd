class_name StatEvaluation
extends RefCounted

var mastery_ranks: Dictionary = {}
## Derived values for combat and explanations; never persisted as source attributes.

var raw: BowStats
var linked: BowStats
var converted: BowStats
var effective: BowStats
var source_arrows: int = 1
var crit_source: float = 0.0
var extra_crit_source: float = 0.0
var converted_penetration: int = 0
var converted_bounces: int = 0
var talent_damage_bonuses: Dictionary = {}
