class_name TalentCatalog
extends RefCounted

const TREE_NAMES: Array[String] = ["箭袋 · 绵延", "金币 · 丰收", "锋芒 · 破阵", "靶场 · 万象"]
const RULES: TalentRules = preload("res://data/talent_rules.tres")
static var ALL: Array[TalentData] = _load_all()

static func _load_all() -> Array[TalentData]:
	var nodes: Array[TalentData] = []
	for prefix: String in ["quiver", "economy", "damage", "field"]:
		for suffix: String in ["root", "left", "right", "master_left", "master_right", "advanced_left", "advanced_right", "capstone_left", "capstone_right"]:
			nodes.append(load("res://data/talents/%s_%s.tres" % [prefix, suffix]) as TalentData)
	return nodes

static func find(id: String) -> TalentData:
	for node: TalentData in ALL:
		if node.id == id: return node
	return null

static func lock_reason(ranks: Dictionary, points: int, id: String) -> String:
	var node: TalentData = find(id)
	if node == null: return "未知天赋"
	var rank: int = int(ranks.get(id, 0))
	if rank >= node.max_rank: return "已满级"
	if not node.parent.is_empty() and int(ranks.get(node.parent, 0)) < node.required_rank:
		return "需要 %s %d 级" % [find(node.parent).title, node.required_rank]
	if not node.exclusive_group.is_empty():
		for other: TalentData in ALL:
			if other.id != id and other.exclusive_group == node.exclusive_group and int(ranks.get(other.id, 0)) > 0:
				return "已选择另一专精"
	if points < node.price(rank): return "天赋点不足"
	return ""

static func valid_ranks(source: Dictionary) -> Dictionary:
	var ranks: Dictionary = {}
	for node: TalentData in ALL:
		var rank: int = clampi(int(source.get(node.id, 0)), 0, node.max_rank)
		if rank > 0 and lock_reason(ranks, 100000, node.id).is_empty():
			ranks[node.id] = rank
	return ranks

static func effects(ranks: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var valid: Dictionary = valid_ranks(ranks)
	for node: TalentData in ALL:
		for key: String in node.effects:
			result[key] = float(result.get(key, 0.0)) + float(node.effects[key]) * int(valid.get(node.id, 0))
	return result
