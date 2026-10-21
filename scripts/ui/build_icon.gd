class_name BuildIcon
extends Control
## Shared 24-unit pixel symbols. Composite marks describe artifact links.
const ARTIFACTS: Dictionary = {
	"piercing_split": ["penetration", "quantity"], "ricochet_haste": ["ricochet", "speed"],
	"swarm_precision": ["quantity", "critical"], "unified_arrow": ["damage", "quantity"],
	"critical_forging": ["critical", "penetration"], "critical_ricochet": ["critical", "ricochet"],
	"piercing_edge": ["penetration", "damage"], "armor_surplus": ["armor", "damage"],
	"echo_strike": ["ricochet", "damage"], "wall_forging": ["ricochet", "penetration"],
	"charged_breach": ["quiver", "penetration"], "bullseye_wave": ["target", "size"],
	"critical_flow": ["critical", "damage"], "broad_precision": ["size", "target"],
	"branch_harvest": ["quantity", "coin"], "branch_ricochet": ["quantity", "ricochet"],
	"slender_gale": ["size", "speed"], "heavy_draw": ["damage", "quiver"],
}
const CONTRACTS: Dictionary = {"health": "health", "armor": "armor", "boss": "boss", "quiver": "quiver", "supply": "supply", "prices": "coin", "slots": "slots", "bullseye": "target"}
const ARTIFACT_COPY: Dictionary = {
	"piercing_split": "穿出靶子后分裂子箭", "ricochet_haste": "反弹后提高速度",
	"swarm_precision": "箭数越多，暴击率越高", "unified_arrow": "全部箭合一，换取伤害与大小",
	"critical_forging": "失去暴击率，将其转为穿甲", "critical_ricochet": "失去额外暴伤，将其转为弹射",
	"piercing_edge": "穿出靶子后叠加伤害", "armor_surplus": "多余穿甲转为伤害加成",
	"echo_strike": "反弹强化下一次命中", "wall_forging": "反弹后叠加穿甲",
	"charged_breach": "拉力越满，额外穿甲越高", "bullseye_wave": "命中靶心触发范围回响",
	"critical_flow": "暴击后叠加伤害", "broad_precision": "箭体越大，靶心增伤越高",
	"branch_harvest": "子箭击倒获得额外金币", "branch_ricochet": "子箭获得额外反弹次数",
	"slender_gale": "缩小箭体，换取初速", "heavy_draw": "延长装填，换取伤害",
}
const EFFECTS: Dictionary = {"initial_shots": "quiver", "kill_refund": "supply", "crit_refund": "critical", "crit_chance": "critical", "crit_per_arrow": "quantity", "gold_multiplier": "coin", "combo_gold": "combo", "combo_cap": "combo", "bullseye_gold": "target", "damage": "damage", "damage_bonus": "damage", "armor_penetration": "penetration", "damage_per_penetration": "penetration", "target_count": "quantity", "target_scale": "size", "bounces": "ricochet", "crit_multiplier": "critical"}
var symbol: String = "damage"
var secondary: String = ""
var ink := Color("edc879")
var tier: int = -1

static func add_to(parent: Node, id: String, at: Vector2, extent: float = 32, tint: Color = Color("edc879")) -> BuildIcon:
	var icon := BuildIcon.new()
	icon.name = "BuildIcon"
	icon.symbol = id
	icon.position = at
	icon.size = Vector2.ONE * extent
	icon.ink = tint
	parent.add_child(icon)
	return icon

static func artifact(parent: Node, id: String, at: Vector2, extent: float, tint: Color) -> BuildIcon:
	var reward: EncounterData = EncounterCatalog.find(id)
	var key: String = reward.upgrade_trait if reward != null and not reward.upgrade_trait.is_empty() else id
	var ordinary: Dictionary = {"windfall": "coin", "rainfall": "quantity", "second_wind": "quiver", "steady_power": "damage", "tempered_tip": "penetration", "quick_nock": "damage"}
	var pair: Array = ARTIFACTS.get(key, [ordinary.get(key, "experience"), ""])
	var icon: BuildIcon = add_to(parent, pair[0], at, extent, tint)
	icon.secondary = pair[1]
	return icon

static func talent(parent: Node, node: TalentData, at: Vector2) -> BuildIcon:
	var key: String = str(node.effects.keys()[0]) if not node.effects.is_empty() else ""
	var icon: BuildIcon = add_to(parent, EFFECTS.get(key, "experience"), at, 24)
	icon.tier = node.tier
	return icon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / 24.0)
	draw_rect(Rect2(0, 0, 24, 24), Color("142a32"))
	draw_rect(Rect2(0, 0, 24, 24), ink.darkened(0.65), false, 1)
	_glyph(symbol, ink)
	if not secondary.is_empty():
		draw_set_transform(size * 0.5, 0, size / 24.0 * 0.58)
		draw_rect(Rect2(0, 0, 24, 24), Color("142a32"))
		_glyph(secondary, Color("8fd9ba"))
	if tier >= 0:
		draw_set_transform(Vector2.ZERO, 0, size / 24.0)
		for i: int in range(tier + 1): draw_rect(Rect2(3 + i * 4, 22, 2, 2), ink)
	draw_set_transform(Vector2.ZERO)

func _line(points: Array, color: Color, width: float = 2) -> void:
	var p := PackedVector2Array()
	for at: Vector2 in points: p.append(at)
	draw_polyline(p, color, width, false)

func _arrow(x: float, top: float, bottom: float, color: Color) -> void:
	_line([Vector2(x, bottom), Vector2(x, top)], color)
	_line([Vector2(x - 3, top + 4), Vector2(x, top), Vector2(x + 3, top + 4)], color)

func _glyph(id: String, color: Color) -> void:
	match id:
		"quantity":
			for x: int in [6, 12, 18]: _arrow(x, 5 if x == 12 else 8, 20, color)
		"damage", "penetration":
			if id == "penetration": draw_rect(Rect2(5, 9, 14, 7), color.darkened(0.45))
			_line([Vector2(5, 20), Vector2(19, 5), Vector2(12, 7)], color)
			_line([Vector2(19, 5), Vector2(18, 12)], color)
		"critical":
			_line([Vector2(12, 3), Vector2(14, 9), Vector2(21, 7), Vector2(17, 13), Vector2(20, 19), Vector2(13, 17), Vector2(8, 21), Vector2(8, 14), Vector2(3, 10), Vector2(9, 9), Vector2(12, 3)], color, 1)
			_line([Vector2(13, 8), Vector2(10, 14), Vector2(14, 13)], color)
		"ricochet":
			_line([Vector2(3, 5), Vector2(20, 5)], color.darkened(0.3))
			_line([Vector2(5, 20), Vector2(12, 7), Vector2(19, 20), Vector2(19, 14)], color)
		"coin":
			draw_rect(Rect2(6, 4, 12, 16), color, false, 2)
			draw_rect(Rect2(4, 7, 16, 10), color, false, 2)
			draw_line(Vector2(12, 8), Vector2(12, 16), color, 2)
		"quiver", "supply":
			draw_rect(Rect2(7, 10, 11, 11), color, false, 2)
			for x: int in [9, 15]: _arrow(x, 3, 11, color)
			if id == "supply": _line([Vector2(3, 15), Vector2(3, 21), Vector2(7, 21)], Color("8fd9ba"))
		"size", "target":
			draw_rect(Rect2(5, 5, 14, 14), color, false, 2)
			if id == "target":
				draw_rect(Rect2(9, 9, 6, 6), color, false, 2)
			else:
				_line([Vector2(9, 15), Vector2(15, 9), Vector2(10, 9)], color)
				_line([Vector2(15, 9), Vector2(15, 14)], color)
		"armor", "boss":
			_line([Vector2(4, 5), Vector2(20, 5), Vector2(19, 15), Vector2(12, 21), Vector2(5, 15), Vector2(4, 5)], color)
			if id == "boss": _line([Vector2(6, 5), Vector2(4, 2), Vector2(12, 5), Vector2(20, 2), Vector2(18, 5)], color)
			draw_line(Vector2(12, 8), Vector2(12, 16), color)
		"energy": _line([Vector2(14, 3), Vector2(6, 13), Vector2(12, 13), Vector2(10, 21), Vector2(19, 10), Vector2(13, 10)], color)
		"speed", "combo":
			for x: int in [5, 12]: _line([Vector2(x, 6), Vector2(x + 6, 12), Vector2(x, 18)], color)
		"slots":
			for x: int in [5, 13]:
				for y: int in [5, 13]: draw_rect(Rect2(x, y, 6, 6), color, false, 1)
		"health": _line([Vector2(9, 3), Vector2(15, 3), Vector2(15, 9), Vector2(21, 9), Vector2(21, 15), Vector2(15, 15), Vector2(15, 21), Vector2(9, 21), Vector2(9, 15), Vector2(3, 15), Vector2(3, 9), Vector2(9, 9), Vector2(9, 3)], color, 1)
		_: _line([Vector2(12, 3), Vector2(20, 12), Vector2(12, 21), Vector2(4, 12), Vector2(12, 3)], color)
