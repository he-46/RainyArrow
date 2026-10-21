class_name ActiveAbility
extends RefCounted
## Per-run loadout and draw-count effects. Energy has no clock-based source.

const UNLOCK_COST: int = 2
const MAX_ENERGY: int = 100
const ALL: Dictionary = {
	"sunshot": {"title": "贯日一箭", "cost": 60, "draws": 1, "description": "下一次拉弓：本轮箭伤害 ×2，额外穿甲 +12。\n适合破甲与 Boss 爆发。"},
	"quickdraw": {"title": "疾风连弦", "cost": 40, "draws": 2, "description": "立即完成装填，接下来两次拉弓后无需装填。\n仍消耗箭袋次数，适合连续出手。"},
	"hunters_mark": {"title": "猎手印记", "cost": 50, "draws": 3, "description": "标记瞄准方向上的目标，接下来三轮箭对其伤害 ×1.6。\n目标被击倒时结束，不转移到新靶。"},
}
var id: String = ""
var energy: int = 0
var remaining: int = 0
var target_id: String = ""
var cooldown: float = 0.0

func can_cast() -> bool:
	return ALL.has(id) and energy >= int(ALL[id].cost) and remaining == 0 and cooldown <= 0.0

func cast(mark: String = "") -> bool:
	if not can_cast() or (id == "hunters_mark" and mark.is_empty()): return false
	energy -= int(ALL[id].cost)
	remaining = int(ALL[id].draws)
	target_id = mark if id == "hunters_mark" else ""
	cooldown = 0.25
	return true

func gain(amount: int) -> void:
	if ALL.has(id): energy = clampi(energy + maxi(0, amount), 0, MAX_ENERGY)

func take_shot() -> Dictionary:
	if remaining <= 0: return {}
	remaining -= 1
	var effect: Dictionary = {"id": id, "target": target_id}
	if remaining == 0: target_id = ""
	return effect

func status() -> String:
	if id.is_empty(): return "前往大厅 → 天赋 → 主动技能，免费选择首个技能"
	if remaining > 0: return "已发动 · 剩余 %d 次拉弓" % remaining
	return "Q 施放 · 消耗 %d 能量 · 射箭回能，等待不回能" % int(ALL[id].cost)

func to_dict() -> Dictionary:
	return {"id": id, "energy": energy, "remaining": remaining, "target_id": target_id, "cooldown": cooldown}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or not data.get("id") is String: return false
	if data.id != "" and not ALL.has(data.id): return false
	for key: String in ["energy", "remaining", "cooldown"]:
		if not (data.get(key) is int or data.get(key) is float) or not is_finite(float(data[key])): return false
	if data.energy != int(data.energy) or data.energy < 0 or data.energy > MAX_ENERGY: return false
	if data.remaining != int(data.remaining) or data.remaining < 0 or data.remaining > (int(ALL[data.id].draws) if ALL.has(data.id) else 0): return false
	if data.cooldown < 0 or data.cooldown > 0.25 or not data.get("target_id") is String: return false
	if data.id == "" and (data.energy != 0 or data.cooldown != 0): return false
	if data.id == "hunters_mark" and data.remaining > 0: return not data.target_id.is_empty() and data.target_id.length() < 80
	return data.target_id.is_empty()

static func from_dict(data: Dictionary) -> ActiveAbility:
	var result := ActiveAbility.new()
	if not valid(data): return result
	result.id = data.id
	result.energy = int(data.energy)
	result.remaining = int(data.remaining)
	result.target_id = data.target_id
	result.cooldown = float(data.cooldown)
	return result
