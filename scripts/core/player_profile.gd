class_name PlayerProfile
extends RefCounted
## Permanent state only. Currency, skill levels and encounter choices never belong here.

signal changed

const RULES: ProgressionRules = preload("res://data/progression.tres")
const DEFAULT_COSMETICS: Array[String] = ["bow_default", "arrow_default", "archer_default"]

var total_score: float = 0.0
var total_defeats: int = 0
var level: int = 1
var earned_talent_points: int = 0
var talents: Dictionary = {}
var talent_spending: Dictionary = {}
var unlocked_cosmetics: Array[String] = DEFAULT_COSMETICS.duplicate()
var equipped_cosmetics: Dictionary = {"bow": "bow_default", "arrow": "arrow_default", "archer": "archer_default"}
var tutorial_completed: bool = false
var leaderboard: Leaderboard = Leaderboard.new()
var settings: Dictionary = {
	"muted": false, "master_volume": 1.0, "music_volume": 0.7,
	"sfx_volume": 1.0, "fullscreen": false, "screen_shake": true, "trajectory_guide": true,
}

var talent_points: int:
	get:
		var spent: int = 0
		for cost: Variant in talent_spending.values():
			spent += int(cost)
		return maxi(0, earned_talent_points - spent)

func record_defeat(points: float) -> void:
	if not is_finite(points) or points < 0.0:
		return
	total_defeats += 1
	record_score(points)

func record_score(points: float) -> void:
	if not is_finite(points) or points < 0.0: return
	total_score = minf(total_score + points, 1.0e12)
	level = RULES.level_for_score(total_score)
	grant_talent_points()
	refresh_cosmetics()
	changed.emit()

func grant_talent_points() -> int:
	# Entitlement is derived from level, so retries and loading cannot duplicate grants.
	var delta: int = maxi(0, level - 1 - earned_talent_points)
	earned_talent_points += delta
	return delta

func invest_talent(id: String, cost: int) -> bool:
	var node: TalentData = TalentCatalog.find(id)
	if node == null or not TalentCatalog.lock_reason(talents, talent_points, id).is_empty():
		return false
	if cost != node.price(int(talents.get(id, 0))):
		return false
	talents[id] = int(talents.get(id, 0)) + 1
	talent_spending[id] = int(talent_spending.get(id, 0)) + cost
	changed.emit()
	return true

func reset_talents() -> int:
	var refund: int = earned_talent_points - talent_points
	talents.clear()
	talent_spending.clear()
	changed.emit()
	return refund

func to_dict() -> Dictionary:
	return {
		"leaderboard_schema": 1, "leaderboard": leaderboard.entries,
		"total_score": total_score, "total_defeats": total_defeats,
		"talents": talents.duplicate(true), "talent_spending": talent_spending.duplicate(true),
		"unlocked_cosmetics": unlocked_cosmetics.duplicate(),
		"equipped_cosmetics": equipped_cosmetics.duplicate(true),
		"settings": settings.duplicate(true), "tutorial_completed": tutorial_completed,
	}

func set_setting(key: String, value: Variant) -> bool:
	if not settings.has(key): return false
	if settings[key] is bool:
		if not value is bool: return false
	else:
		if not (value is float or value is int) or not is_finite(float(value)): return false
		value = clampf(float(value), 0.0, 1.0)
	settings[key] = value
	changed.emit()
	return true

func refresh_cosmetics() -> void:
	# Entitlements come from permanent progress, never a supplied list of unlock IDs.
	unlocked_cosmetics.clear()
	for skin: CosmeticData in CosmeticCatalog.ALL:
		if skin.eligible(level, total_defeats): unlocked_cosmetics.append(skin.id)
	for slot: String in CosmeticCatalog.SLOTS:
		var skin: CosmeticData = CosmeticCatalog.find(str(equipped_cosmetics.get(slot, "")))
		if skin == null or skin.slot != slot or not unlocked_cosmetics.has(skin.id):
			equipped_cosmetics[slot] = slot + "_default"

func equip_cosmetic(id: String) -> bool:
	refresh_cosmetics()
	var skin: CosmeticData = CosmeticCatalog.find(id)
	if skin == null or not unlocked_cosmetics.has(id) or equipped_cosmetics[skin.slot] == id: return false
	equipped_cosmetics[skin.slot] = id
	changed.emit()
	return true

static func from_dict(data: Dictionary) -> PlayerProfile:
	var result: PlayerProfile = PlayerProfile.new()
	if int(data.get("leaderboard_schema", 0)) == 1:
		result.leaderboard = Leaderboard.from_array(data.get("leaderboard", []))
	var points: float = float(data.get("total_score", 0.0))
	result.total_score = clampf(points, 0.0, 1.0e12) if is_finite(points) else 0.0
	result.total_defeats = maxi(0, int(data.get("total_defeats", 0)))
	result.level = RULES.level_for_score(result.total_score)
	result.earned_talent_points = result.level - 1
	# Restore the spending ledger; do not replay purchases or level-up events.
	var levels: Dictionary = data.get("talents", {})
	var spending: Dictionary = data.get("talent_spending", {})
	for node: TalentData in TalentCatalog.ALL:
		var key: String = node.id
		var cost: int = int(spending.get(key, 0))
		var rank: int = clampi(int(levels.get(key, 0)), 0, node.max_rank)
		if rank > 0 and cost >= rank and cost <= result.talent_points and TalentCatalog.lock_reason(result.talents, 100000, key).is_empty():
			result.talents[key] = rank
			result.talent_spending[key] = cost
	result.refresh_cosmetics()
	var equipped: Dictionary = data.get("equipped_cosmetics", {})
	for slot: String in ["bow", "arrow", "archer"]:
		var id: String = str(equipped.get(slot, result.equipped_cosmetics[slot]))
		var skin: CosmeticData = CosmeticCatalog.find(id)
		if skin != null and skin.slot == slot and result.unlocked_cosmetics.has(id):
			result.equipped_cosmetics[slot] = id
	result.tutorial_completed = bool(data.get("tutorial_completed", false))
	var options: Dictionary = data.get("settings", {})
	for key: String in result.settings:
		if result.settings[key] is bool:
			if options.get(key) is bool:
				result.settings[key] = options[key]
		elif options.get(key) is float or options.get(key) is int:
			var volume: float = float(options[key])
			if is_finite(volume):
				result.settings[key] = clampf(volume, 0.0, 1.0)
	return result
