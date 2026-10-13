class_name TraitUpgradeCatalog
extends RefCounted

const ALL: Dictionary = {
	"piercing_split": preload("res://data/trait_upgrades/piercing_split.tres"),
	"ricochet_haste": preload("res://data/trait_upgrades/ricochet_haste.tres"),
	"swarm_precision": preload("res://data/trait_upgrades/swarm_precision.tres"),
	"unified_arrow": preload("res://data/trait_upgrades/unified_arrow.tres"),
	"critical_forging": preload("res://data/trait_upgrades/critical_forging.tres"),
	"critical_ricochet": preload("res://data/trait_upgrades/critical_ricochet.tres"),
	"piercing_edge": preload("res://data/trait_upgrades/piercing_edge.tres"),
	"armor_surplus": preload("res://data/trait_upgrades/armor_surplus.tres"),
	"echo_strike": preload("res://data/trait_upgrades/echo_strike.tres"),
	"wall_forging": preload("res://data/trait_upgrades/wall_forging.tres"),
	"charged_breach": preload("res://data/trait_upgrades/charged_breach.tres"),
	"bullseye_wave": preload("res://data/trait_upgrades/bullseye_wave.tres"),
	"critical_flow": preload("res://data/trait_upgrades/critical_flow.tres"),
	"broad_precision": preload("res://data/trait_upgrades/broad_precision.tres"),
	"branch_harvest": preload("res://data/trait_upgrades/branch_harvest.tres"),
	"branch_ricochet": preload("res://data/trait_upgrades/branch_ricochet.tres"),
	"slender_gale": preload("res://data/trait_upgrades/slender_gale.tres"),
	"heavy_draw": preload("res://data/trait_upgrades/heavy_draw.tres"),
}
const LABELS: Dictionary = {
	"split_damage": "子箭伤害倍率", "bounce_multiplier": "反弹速度倍率",
	"crit_per_extra_arrow": "每多一箭暴击率", "unity_damage_exponent": "归一伤害指数",
	"unity_size_exponent": "归一尺寸指数", "crit_per_penetration": "每点穿甲所需暴击率",
	"extra_crit_per_bounce": "每次反弹所需额外暴伤", "penetration_damage": "穿出每层增伤",
	"excess_damage": "多余穿甲每点增伤", "excess_limit": "多余穿甲增伤上限",
	"echo_damage": "反弹后下一击增伤", "bounce_penetration": "反弹每层穿甲",
	"charged_penetration": "满拉额外穿甲", "bullseye_radius": "回响范围",
	"bullseye_damage": "回响伤害比例", "critical_damage": "暴击后每层增伤",
	"size_bullseye": "额外尺寸增伤系数", "size_bullseye_limit": "靶心增伤上限",
	"child_gold_bonus": "子箭击倒额外金币", "child_bounces": "子箭额外反弹",
	"slender_size_factor": "尺寸来源倍率", "slender_speed_factor": "初速来源倍率",
	"heavy_damage_factor": "伤害来源倍率", "heavy_reload_factor": "装填时间倍率",
}

static func find(id: String) -> TraitUpgradeData:
	return ALL.get(id) as TraitUpgradeData

static func token(id: String, rank: int) -> String:
	return "@upgrade/%s/%d" % [id, rank]

static func decode(value: String) -> Dictionary:
	var parts: PackedStringArray = value.split("/")
	if parts.size() != 3 or parts[0] != "@upgrade" or find(parts[1]) == null or not parts[2].is_valid_int(): return {}
	var rank: int = parts[2].to_int()
	if rank < 1 or rank > find(parts[1]).max_level or token(parts[1], rank) != value: return {}
	return {"id": parts[1], "rank": rank}

static func derive(picks: Dictionary, levels: Dictionary) -> EncounterRules:
	var rules: EncounterRules = EncounterCatalog.RULES.duplicate() as EncounterRules
	for id: String in ALL:
		if int(picks.get(id, 0)) > 0: find(id).apply(rules, EncounterCatalog.RULES, int(levels.get(id, 0)))
	return rules

static func value_text(field: String, value: float) -> String:
	if field in ["charged_penetration", "bounce_penetration", "child_bounces", "bullseye_radius"]: return str(int(value))
	if field in ["crit_per_extra_arrow", "crit_per_penetration", "extra_crit_per_bounce", "penetration_damage", "excess_damage", "excess_limit", "echo_damage", "bullseye_damage", "critical_damage", "size_bullseye", "size_bullseye_limit", "child_gold_bonus"]: return "%.2f%%" % (value * 100)
	return "%.2f" % value
