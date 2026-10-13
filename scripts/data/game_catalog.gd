class_name GameCatalog
extends RefCounted

const BASE_BOW: BowStats = preload("res://data/base_bow.tres")
const TARGETS: Array[TargetData] = [
	preload("res://data/targets/standard.tres"),
	preload("res://data/targets/armored.tres"),
	preload("res://data/targets/moving.tres"),
]
const UPGRADE_PATHS: Array[String] = [
	"res://data/upgrades/power.tres", "res://data/upgrades/focus.tres",
	"res://data/upgrades/haste.tres", "res://data/upgrades/velocity.tres",
	"res://data/upgrades/volley.tres", "res://data/upgrades/pierce.tres",
	"res://data/upgrades/heavy.tres", "res://data/upgrades/critical.tres",
	"res://data/upgrades/lucky.tres", "res://data/upgrades/wind.tres",
	"res://data/upgrades/bounty.tres", "res://data/upgrades/giant.tres",
]
static var _cached_upgrades: Array[UpgradeData] = []

static func upgrades() -> Array[UpgradeData]:
	if _cached_upgrades.is_empty():
		for path: String in UPGRADE_PATHS:
			_cached_upgrades.append(load(path) as UpgradeData)
	return _cached_upgrades

static func find_upgrade(id: StringName) -> UpgradeData:
	for upgrade: UpgradeData in upgrades():
		if upgrade.id == id:
			return upgrade
	return null
