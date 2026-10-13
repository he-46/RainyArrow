class_name SkillCatalog
extends RefCounted

const ALL: Array[RunSkillData] = [
	preload("res://data/skills/quantity.tres"), preload("res://data/skills/critical.tres"),
	preload("res://data/skills/damage.tres"), preload("res://data/skills/penetration.tres"),
	preload("res://data/skills/ricochet.tres"), preload("res://data/skills/size.tres"),
]

static func find(id: StringName) -> RunSkillData:
	for skill: RunSkillData in ALL:
		if skill.id == id: return skill
	return null
