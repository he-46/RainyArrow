class_name Leaderboard
extends RefCounted
## Only the best three completed runs, in stable score order. No global run history.

const LIMIT: int = 3
var _entries: Array[Dictionary] = []
var entries: Array[Dictionary]:
	get: return _entries.duplicate(true)

static func valid_entry(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not ContractCatalog.valid_snapshot(value.get("challenge", {})): return false
	if not value.get("run_id") is String or value["run_id"].is_empty() or value["run_id"].length() > 128: return false
	if not value.get("mode_id") is String or DifficultyCatalog.find(value["mode_id"]) == null: return false
	if not (value.get("score") is int or value.get("score") is float) or not is_finite(float(value["score"])) or float(value["score"]) <= 0: return false
	for key: String in ["ended_at", "defeated_count", "bosses_defeated"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)) or float(number) < 0 or float(number) > 1.0e12: return false
	return value["ended_at"] > 0 and value.get("reason") in ["exhausted", "completed", "abandoned"]

func rank_of(run_id: String) -> int:
	for index: int in range(_entries.size()):
		if _entries[index]["run_id"] == run_id: return index + 1
	return 0

func submit(record: Dictionary) -> int:
	if not valid_entry(record): return 0
	var existing: int = rank_of(record["run_id"])
	if existing > 0: return existing
	# Strictly greater goes first; equal scores retain completion order even if the clock changes.
	var index: int = 0
	while index < _entries.size() and float(_entries[index]["score"]) >= float(record["score"]): index += 1
	if index >= LIMIT: return 0
	_entries.insert(index, {"run_id": str(record["run_id"]), "mode_id": str(record["mode_id"]), "score": float(record["score"]),
		"ended_at": int(record["ended_at"]), "reason": str(record["reason"]),
		"defeated_count": int(record["defeated_count"]), "bosses_defeated": int(record["bosses_defeated"])})
	if not record.get("challenge", {}).is_empty(): _entries[index]["challenge"] = ContractCatalog.snapshot(record["challenge"].selection)
	if _entries.size() > LIMIT: _entries.resize(LIMIT)
	return index + 1

static func from_array(value: Variant) -> Leaderboard:
	var result := Leaderboard.new()
	# SaveStore rejects malformed current files; this boundary also stays bounded for direct callers.
	if not value is Array or value.size() > LIMIT: return result
	for entry: Variant in value:
		if valid_entry(entry): result.submit(entry)
	return result
