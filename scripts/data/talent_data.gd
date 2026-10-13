class_name TalentData
extends Resource

@export var id: String = ""
@export var tree: int = 0
@export var title: String = ""
@export_multiline var description: String = ""
@export var parent: String = ""
@export var required_rank: int = 1
@export var max_rank: int = 1
@export var base_cost: int = 1
@export var cost_step: int = 1
@export var tier: int = 0
@export var side: int = 0
@export var exclusive_group: String = ""
@export var effects: Dictionary = {}

func price(rank: int) -> int:
	return base_cost + rank * cost_step
