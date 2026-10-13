class_name UpgradeData
extends Resource
## All changes are recomputed from base stats; no cumulative floating-point drift.

@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var branch: String = "基础"
@export var stat: StringName
@export var amount: float
@export var cost: int = 10
@export var cost_growth: float = 1.6
@export var max_level: int = 5
@export var prerequisite: StringName = &""
@export var random_only: bool = false

func price(level: int) -> int:
	return int(ceil(float(cost) * pow(cost_growth, level)))
