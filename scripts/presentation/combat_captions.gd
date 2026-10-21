class_name CombatCaptions
extends RefCounted
const LIMIT: int = 24

static func append(labels: Array[Dictionary], record: Dictionary) -> void:
	if labels.size() >= LIMIT:
		var removable: int = -1
		for i: int in range(labels.size()):
			if not labels[i].get("important", false):
				removable = i
				break
		if removable < 0 and not record.get("important", false): return
		labels.remove_at(maxi(0, removable))
	labels.append(record)

static func hit(labels: Array[Dictionary], key: String, at: Vector2, damage: float, tags: Array[String], important: bool) -> void:
	for label: Dictionary in labels:
		if label.get("key", "") != key: continue
		label.damage += damage
		label.count += 1
		label.life = 1.0
		label.important = label.important or important
		for tag: String in tags:
			if not label.tags.has(tag): label.tags.append(tag)
		_refresh(label)
		return
	# Keep consecutive volleys on separate rows; area and shield lanes stay distinct.
	var group: String = key.substr(key.find(":") + 1)
	for label: Dictionary in labels:
		if label.get("group", "") == group:
			at.y = minf(at.y, label.position.y - 16.0)
	var record: Dictionary = {"key": key, "group": group, "position": at, "damage": damage, "count": 1, "tags": tags.duplicate(), "important": important, "life": 1.0}
	_refresh(record)
	append(labels, record)

static func _refresh(record: Dictionary) -> void:
	var count: String = " ×%d" % record.count if record.count > 1 else ""
	record.text = "-%d%s %s" % [roundi(record.damage), count, " ".join(record.tags)]
	if record.count > 1: record.text = "合计 -%d · %d击 %s" % [roundi(record.damage), record.count, " ".join(record.tags)]
	if record.tags.has("护板阻挡") or record.tags.has("护板贯穿"): record.text = " ".join(record.tags) + count
	record.color = Color("ffdc83") if record.tags.has("暴击") else (Color("a4e2c0") if record.tags.has("靶心") else Color("c8e3ca"))
	record.font_size = 12 if record.tags.has("暴击") else 10
