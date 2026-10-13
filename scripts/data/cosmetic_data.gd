class_name CosmeticData
extends Resource
## Visual data only; no combat fields belong here.

@export var id: String
@export var slot: String
@export var title: String
@export var required_level: int = 1
@export var required_defeats: int = 0
@export var primary: Color
@export var secondary: Color
@export var accent: Color
@export var style: int = 0

func eligible(level: int, defeats: int) -> bool:
	return level >= required_level and defeats >= required_defeats

func condition() -> String:
	if required_defeats > 0: return "累计击倒 %d 次" % required_defeats
	if required_level > 1: return "永久等级 Lv.%d" % required_level
	return "初始拥有"
