class_name CosmeticCatalog
extends RefCounted

const SLOTS: Array[String] = ["bow", "arrow", "archer"]
const ALL: Array[CosmeticData] = [
	preload("res://data/cosmetics/bow_default.tres"),
	preload("res://data/cosmetics/bow_moon.tres"),
	preload("res://data/cosmetics/bow_ember.tres"),
	preload("res://data/cosmetics/arrow_default.tres"),
	preload("res://data/cosmetics/arrow_frost.tres"),
	preload("res://data/cosmetics/arrow_sun.tres"),
	preload("res://data/cosmetics/archer_default.tres"),
	preload("res://data/cosmetics/archer_crimson.tres"),
	preload("res://data/cosmetics/archer_dusk.tres"),
]

static func find(id: String) -> CosmeticData:
	for skin: CosmeticData in ALL:
		if skin.id == id: return skin
	return null

static func default_for(slot: String) -> CosmeticData:
	return find(slot + "_default")

static func equipped(loadout: Dictionary, slot: String) -> CosmeticData:
	var skin: CosmeticData = find(str(loadout.get(slot, "")))
	return skin if skin != null and skin.slot == slot else default_for(slot)
