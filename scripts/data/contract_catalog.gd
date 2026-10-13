class_name ContractCatalog
extends RefCounted
## Version 1 is immutable: saved challenges keep their rules across future catalogs.
const VERSION: int = 1
const ALL: Array[Dictionary] = [
	{"id": "health", "title": "坚固靶材", "scope": "普通靶", "options": ["生命 ×1.25", "生命 ×1.5"]},
	{"id": "armor", "title": "铁甲加固", "scope": "普通靶", "options": ["额外护甲 +2", "额外护甲 +4"]},
	{"id": "boss", "title": "狂暴巨靶", "scope": "Boss", "options": ["生命 ×1.5", "生命 ×2"]},
	{"id": "quiver", "title": "箭袋紧缩", "scope": "全局", "options": ["初始拉弓 -2 次", "初始拉弓 -4 次"]},
	{"id": "supply", "title": "补给短缺", "scope": "全局", "options": ["每段仅 1 次购买补给", "无法购买补给"]},
	{"id": "prices", "title": "物资昂贵", "scope": "全局", "options": ["技能与神器强化价格 ×1.25", "技能与神器强化价格 ×1.5"]},
	{"id": "slots", "title": "轻装出征", "scope": "全局", "options": ["神器仅 5 格", "神器仅 4 格"]},
	{"id": "bullseye", "title": "狭小靶心", "scope": "普通靶", "options": ["靶心高度 ×0.75", "靶心高度 ×0.5"]},
]
const PRESETS: Dictionary = {
	"normal": {},
	"hard": {"health": 2, "boss": 1},
	"hell": {"health": 2, "armor": 2, "boss": 2, "quiver": 1, "supply": 1, "slots": 1},
}

static func find(id: String) -> Dictionary:
	for item: Dictionary in ALL:
		if item.id == id: return item
	return {}

static func valid_selection(value: Variant) -> bool:
	if not value is Dictionary or value.size() > ALL.size(): return false
	for id: Variant in value:
		if not id is String or find(id).is_empty(): return false
		if not (value[id] is int or value[id] is float) or not is_finite(float(value[id])) or float(value[id]) not in [1.0, 2.0]: return false
	return true

static func normalize(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item: Dictionary in ALL:
		if value.has(item.id): result[item.id] = int(value[item.id])
	return result

static func preset(id: String) -> Dictionary:
	return PRESETS.get(id, {}).duplicate()

static func parameters(selection: Dictionary) -> Dictionary:
	var ordinary: int = int(selection.get("health", 0)) + int(selection.get("armor", 0)) + int(selection.get("bullseye", 0))
	var global: int = int(selection.get("quiver", 0)) + int(selection.get("supply", 0)) + int(selection.get("prices", 0)) + int(selection.get("slots", 0))
	var boss: int = int(selection.get("boss", 0))
	return {"target_health": 1.0 + 0.25 * int(selection.get("health", 0)), "target_armor": 2 * int(selection.get("armor", 0)),
		"boss_health": 1.0 + 0.5 * boss, "draw_penalty": 2 * int(selection.get("quiver", 0)),
		"supply_limit": 2 - int(selection.get("supply", 0)), "price_multiplier": 1.0 + 0.25 * int(selection.get("prices", 0)),
		"artifact_slots": 6 - int(selection.get("slots", 0)), "bullseye_scale": 1.0 - 0.25 * int(selection.get("bullseye", 0)),
		"target_score": 1.0 + ordinary * 0.1, "boss_score": 1.0 + boss * 0.15, "stage_bonus": global * 0.1}

static func snapshot(selection: Dictionary) -> Dictionary:
	var picked: Dictionary = normalize(selection)
	var risk: int = 0
	for rank: int in picked.values(): risk += rank
	return {"version": VERSION, "selection": picked, "parameters": parameters(picked), "risk": risk}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Legacy fixed difficulty run/record.
	if value.size() != 4 or value.get("version") != VERSION or not valid_selection(value.get("selection")): return false
	var expected: Dictionary = snapshot(value.selection)
	if not (value.get("risk") is int or value.get("risk") is float) or value.risk != expected.risk or not value.get("parameters") is Dictionary or value.parameters.size() != expected.parameters.size(): return false
	for key: String in expected.parameters:
		var number: Variant = value.parameters.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number) - float(expected.parameters[key])) > 1.0e-12: return false
	return true

static func title(challenge: Dictionary) -> String:
	return "契约 %d" % int(challenge.risk) if not challenge.is_empty() else "旧版难度"

static func description(challenge: Dictionary) -> String:
	if challenge.is_empty(): return "旧版固定难度 · 沿用原生命、成长与得分倍率"
	var lines: Array[String] = ["挑战等级 %d" % int(challenge.risk)]
	for item: Dictionary in ALL:
		var rank: int = int(challenge.selection.get(item.id, 0))
		if rank > 0: lines.append("%s %s：%s" % [item.title, "I" if rank == 1 else "II", item.options[rank - 1]])
	if challenge.selection.is_empty(): lines.append("无额外限制")
	var p: Dictionary = challenge.parameters
	lines.append("普通靶得分 ×%.2f · Boss 得分 ×%.2f" % [p.target_score, p.boss_score])
	lines.append("击败 Boss 时，另得本轮普通靶与 Boss 基础分的 %.0f%%；未击败不发放" % (p.stage_bonus * 100))
	return "\n".join(lines)
