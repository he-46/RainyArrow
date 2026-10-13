class_name EncounterData
extends Resource
## Independent run rewards; trait keys are interpreted by RunModel.

var upgrade_trait: String = ""
var upgrade_rank: int = 0

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var group: String = ""
@export var is_trait: bool = false
@export var has_debuff: bool = false
@export var additions: Dictionary = {}
@export var damage_bonus: float = 0.0
@export var trait_key: String = ""
@export var requires_trait: String = ""
@export_range(0, 100) var draws: int = 0
@export var color: Color = Color("8ebaa1")

func candidate_group() -> String:
	return id if group.is_empty() else group

func category_label() -> String:
	match group:
		"gold": return "金币"
		"arrows": return "箭数"
		"draws": return "补给"
		"damage": return "伤害"
		"damage_percent": return "增伤"
		"penetration": return "穿甲"
		"reload": return "装填"
	return "构筑"
