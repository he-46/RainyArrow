class_name DifficultyCatalog
extends RefCounted

const ALL: Array[DifficultyData] = [preload("res://data/difficulties/normal.tres"), preload("res://data/difficulties/hard.tres"), preload("res://data/difficulties/hell.tres")]

static func find(id: String) -> DifficultyData:
	for mode: DifficultyData in ALL:
		if mode.id == id: return mode
	return null

static func title(id: String) -> String:
	var mode: DifficultyData = find(id)
	return mode.title if mode != null else "普通"
