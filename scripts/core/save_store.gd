class_name SaveStore
extends RefCounted
## Versioned profile+run transaction, legacy import and previous-good recovery.

const VERSION: int = 22
const DEFAULT_PATH: String = "user://save.json"
var path: String
var last_error: String = ""
var migration_notice: String = ""
var write_blocked: bool = false
var legacy_paths: Array[String] = []

func _init(save_path: String = DEFAULT_PATH, old_paths: Array[String] = []) -> void:
	path = save_path
	legacy_paths = old_paths.duplicate()

static func default_legacy_paths() -> Array[String]:
	return [OS.get_data_dir().path_join("Godot/app_userdata/弦金 · Bow & Gold/bow_and_gold_v1.json")]

func write(payload: Dictionary) -> bool:
	last_error = ""
	if write_blocked:
		last_error = "发现较新版本存档，当前版本不会覆盖它。"
		return false
	if not _valid_payload(payload):
		last_error = "存档结构无效，未写入。"
		return false
	if int(payload["profile"].get("leaderboard_schema", 0)) != 1 or (payload["run"] != null and int(payload["run"].get("ranking_schema", 0)) != 1):
		last_error = "排行榜状态缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("challenge_schema", 0)) != 1:
		last_error = "挑战契约快照缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("mode_schema", 0)) != 1:
		last_error = "难度快照缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("economy_schema", 0)) != 1:
		last_error = "补给与消费账本缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("backpack_schema", 0)) != 1:
		last_error = "神器背包状态缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("trait_schema", 0)) != 1:
		last_error = "特性强化状态缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("mastery_schema", 0)) != 1:
		last_error = "技能精通状态缺失，未写入。"
		return false
	for arrow: Dictionary in payload["world"].get("arrows", []):
		if not _valid_arrow_combat(arrow, true):
			last_error = "箭矢特性状态缺失或无效，未写入。"
			return false
	if payload["run"] != null and int(payload["run"].get("boss_schema", 0)) != 1:
		last_error = "局内 Boss 状态缺失，未写入。"
		return false
	if payload["run"] != null and int(payload["run"].get("boss_reward_schema", 0)) != 1:
		last_error = "Boss 奖励队列缺失，未写入。"
		return false
	if payload["run"] != null and not payload["run"].get("offer_exhausted") is bool: return false
	if payload["world"].get("boss") is Dictionary and not payload["world"]["boss"].has("combat_schema"):
		last_error = "Boss 战斗部件状态缺失，未写入。"
		return false
	if payload["world"].get("boss") is Dictionary and int(payload["world"]["boss"].get("health_revision", 0)) != 2: return false
	var existing: Dictionary = _read_envelope(path)
	if int(existing.get("version", 0)) > VERSION:
		write_blocked = true
		last_error = "发现较新版本存档，当前版本不会覆盖它。"
		return false
	if FileAccess.file_exists(path):
		var backup_path: String = path + ".bak"
		if not _valid_envelope(existing):
			# Keep damaged/legacy bytes rather than overwriting a valid recovery backup.
			backup_path = path + ".preserved-" + str(Time.get_ticks_usec())
		var backup_error: Error = DirAccess.copy_absolute(path, backup_path)
		if backup_error != OK:
			last_error = "无法备份原存档，未覆盖。"
			return false
	var envelope: Dictionary = {"version": VERSION, "payload": payload}
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档：%s" % error_string(FileAccess.get_open_error())
		return false
	# Converted damage can have more significant digits than JSON's default output.
	file.store_string(JSON.stringify(envelope, "", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = "存档写入失败：%s" % error_string(write_error)
		return false
	# Godot replaces an existing destination file. Do not delete the old save first.
	var rename_error: Error = DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK:
		last_error = "无法完成存档：%s" % error_string(rename_error)
		return false
	return true

func read() -> Dictionary:
	last_error = ""
	migration_notice = ""
	write_blocked = false
	var primary: Dictionary = _read_envelope(path)
	if int(primary.get("version", 0)) > VERSION:
		write_blocked = true
		last_error = "发现较新版本存档，当前版本不会覆盖它。"
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		var envelope: Dictionary = _read_envelope(candidate)
		if _valid_envelope(envelope):
			if candidate != path and not write_blocked:
				last_error = "主存档不可用，已恢复临时文件。" if candidate.ends_with(".tmp") else "主存档不可用，已恢复备份。"
			if int(envelope["version"]) < VERSION:
				return _migrate_previous(candidate, envelope["payload"], int(envelope["version"]))
			return envelope["payload"]
	if write_blocked:
		return {}
	# Prefer current-version backups to importing an older prototype.
	if _valid_legacy(primary):
		return _migrate_legacy(path, primary["payload"])
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp"):
		last_error = "当前存档及恢复文件无法读取；原文件将保留。"
		return {}
	for old_path: String in legacy_paths:
		for candidate: String in [old_path, old_path + ".bak"]:
			var envelope: Dictionary = _read_envelope(candidate)
			if _valid_legacy(envelope):
				return _migrate_legacy(candidate, envelope["payload"])
			if FileAccess.file_exists(candidate):
				last_error = "旧版存档无法读取，原文件已保留，未导入。"
	return {}

func _migrate_legacy(source: String, payload: Dictionary) -> Dictionary:
	var archive: String = path + ".legacy-v1"
	if not FileAccess.file_exists(archive):
		var error: Error = DirAccess.copy_absolute(source, archive)
		if error != OK:
			last_error = "无法备份旧版存档，未执行迁移。"
			return {}
	var session: GameSession = GameSession.from_legacy(payload)
	session.migration["source_path"] = source
	var migrated: Dictionary = session.to_dict()
	write(migrated)
	migration_notice = "旧存档已保留：转入连续靶场，保留剩余次数与构筑；旧命中积分不兑换经验。"
	return migrated

func _migrate_previous(source: String, payload: Dictionary, version: int) -> Dictionary:
	var archive: String = path + ".legacy-v%d" % version
	if not FileAccess.file_exists(archive):
		if DirAccess.copy_absolute(source, archive) != OK:
			last_error = "无法备份旧版存档，未执行迁移。"
			return {}
	var legacy: Dictionary = payload.duplicate(true)
	if version < 20:
		# Never infer past scores from old summaries, even if an old file has extra fields.
		legacy["profile"].erase("leaderboard_schema")
		legacy["profile"].erase("leaderboard")
		if legacy.get("run") is Dictionary:
			for key: String in ["ranking_schema", "ranking_processed", "rank_at_finish", "ended_at"]: legacy["run"].erase(key)
		for key: String in ["ranking_processed", "rank_at_finish", "ended_at"]: legacy.get("last_run_summary", {}).erase(key)
	if legacy.get("run") is Dictionary and version < 21:
		for key: String in ["backpack_schema", "artifact_capacity", "artifact_revision", "discarded_artifacts"]: legacy["run"].erase(key)
	if legacy.get("run") is Dictionary:
		for key: String in ["challenge_schema", "challenge", "contract_stage_base_score", "contract_stage_bonus_earned"]: legacy["run"].erase(key)
	var session: GameSession = GameSession.from_dict(legacy)
	session.migration["source_version"] = version
	session.migration["legacy_progress"] = "continuous_converted"
	var migrated: Dictionary = session.to_dict()
	if not write_blocked:
		write(migrated)
	migration_notice = "存档已备份升级：保留构筑、固定选项和在途箭；新奇遇用于后续选择，历史胜利不补发奖励。"
	if version < 10: migration_notice += "旧 Boss 血量按剩余比例扩大三倍，旧静态战保留原机制。"
	if version == 11: migration_notice = "存档已备份升级：快手搭箭改为箭势渐盛，每层伤害 +5%；已选层数沿用，固定选项、在途箭与当前装填保持。"
	if version == 15: migration_notice = "存档已备份升级：六类精通从零开始，原基础等级、固定选项、在途母子箭与当前装填保持。"
	if version == 18: migration_notice = "存档已备份升级：原冒险按普通模式继续，已有靶子、Boss、收益与在途箭不追溯放大；新局可选难度。"
	if version == 19: migration_notice = "存档已备份升级：本地前三榜从空榜开始，旧终局不补录；当前冒险结束后可入榜，难度和收益保持。"
	if version == 17: migration_notice = "存档已备份升级：当前段补给额度从零购买开始，原构筑、奖励、在途箭与装填保持；已结束的单局不复活。"
	if version == 16: migration_notice = "存档已备份升级：已选特性强化从零开始，精通、固定奖励、在途母子箭与装填保持。"
	if version == 20: migration_notice = "存档已备份升级：特性转入神器背包，保留强化、排行榜与在途箭；旧局超出六件时保留额外槽位，新局使用六格。"
	if version == 21: migration_notice = "存档已备份升级：当前冒险沿用原难度、背包与排行榜；新冒险可自选挑战契约。"
	return migrated

func _read_envelope(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or not _is_number(parsed.get("version")):
		return {}
	return parsed

func _valid_envelope(envelope: Dictionary) -> bool:
	if int(envelope.get("version", -1)) not in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, VERSION] or not _valid_payload(envelope.get("payload")): return false
	if int(envelope["version"]) >= 22 and envelope["payload"]["run"] != null and int(envelope["payload"]["run"].get("challenge_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 21 and envelope["payload"]["run"] != null and int(envelope["payload"]["run"].get("backpack_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 20:
		if int(envelope["payload"]["profile"].get("leaderboard_schema", 0)) != 1: return false
		if envelope["payload"]["run"] != null and int(envelope["payload"]["run"].get("ranking_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 13:
		for arrow: Dictionary in envelope["payload"]["world"].get("arrows", []):
			if not _valid_arrow_combat(arrow, int(envelope["version"]) >= 15): return false
			if int(envelope["version"]) == 14 and int(arrow["combat_schema"]) < 2: return false
	var run: Variant = envelope["payload"]["run"]
	if int(envelope["version"]) >= 19 and run != null and int(run.get("mode_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 18 and run != null and int(run.get("economy_schema", 0)) != 1: return false
	if int(envelope["version"]) < 18 and run != null and int(run.get("phase", 0)) > RunModel.Phase.LOST: return false
	if int(envelope["version"]) >= 17 and run != null and int(run.get("trait_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 16 and run != null and int(run.get("mastery_schema", 0)) != 1: return false
	if int(envelope["version"]) >= 11 and run != null and not run.get("offer_exhausted") is bool: return false
	if int(envelope["version"]) >= 8 and run != null and int(run.get("boss_schema", 0)) != 1: return false
	var boss: Variant = envelope["payload"]["world"].get("boss")
	if int(envelope["version"]) >= 10:
		if run != null and int(run.get("boss_reward_schema", 0)) != 1: return false
		if boss != null and int(boss.get("health_revision", 0)) != 2: return false
	return int(envelope["version"]) < 9 or boss == null or boss.has("combat_schema")

func _valid_legacy(envelope: Dictionary) -> bool:
	if int(envelope.get("version", -1)) != 1 or not envelope.get("payload") is Dictionary:
		return false
	var payload: Dictionary = envelope["payload"]
	return payload.get("run") is Dictionary and _valid_run(payload["run"]) and _valid_world(payload.get("world", {}))

func _valid_payload(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if not data.get("profile") is Dictionary or not data.has("run") or not data.get("world") is Dictionary:
		return false
	if not data.get("in_lobby") is bool:
		return false
	for key: String in ["last_run_summary", "migration"]:
		if not data.get(key, {}) is Dictionary:
			return false
	var profile: Dictionary = data["profile"]
	if not _valid_leaderboard(profile) or not _valid_ranking(data): return false
	for key: String in ["total_score", "total_defeats"]:
		if not _is_number(profile.get(key)):
			return false
	for key: String in ["talents", "talent_spending"]:
		if not _number_map(profile.get(key, {})):
			return false
	for key: String in ["settings", "equipped_cosmetics"]:
		if not profile.get(key, {}) is Dictionary:
			return false
	if not _string_array(profile.get("unlocked_cosmetics", [])):
		return false
	if not _valid_world(data["world"]): return false
	if data["run"] == null: return data["world"].get("boss") == null
	if not data["run"] is Dictionary or not _valid_run(data["run"]): return false
	if int(data["run"].get("phase", 0)) == RunModel.Phase.SUPPLY:
		if not data["world"].get("arrows", []).is_empty() or not data["world"].get("pending_volleys", {}).is_empty() or bool(data["world"].get("waiting_for_settle", false)): return false
	if bool(data["run"].get("boss_active", false)):
		var boss: Variant = data["world"].get("boss")
		if not boss is Dictionary or int(boss["round_number"]) != int(data["run"]["boss_round"]) or not data["world"].get("targets", []).is_empty(): return false
		if data["run"].get("credited_defeats", {}).has("boss%d" % int(boss["round_number"])) and float(boss["hp"]) != 0: return false
	elif data["world"].get("boss") != null: return false
	return true

func _valid_leaderboard(profile: Dictionary) -> bool:
	if not _integer_range(profile.get("leaderboard_schema", 0), 0, 1): return false
	if int(profile.get("leaderboard_schema", 0)) == 0: return true
	var entries: Variant = profile.get("leaderboard")
	if not entries is Array or entries.size() > Leaderboard.LIMIT: return false
	var ids: Dictionary = {}
	var previous: float = INF
	for entry: Variant in entries:
		if not Leaderboard.valid_entry(entry) or ids.has(entry["run_id"]) or float(entry["score"]) > previous: return false
		ids[entry["run_id"]] = true
		previous = float(entry["score"])
	return true

func _valid_ranking(data: Dictionary) -> bool:
	var run: Variant = data["run"]
	if run == null: return true
	if not run is Dictionary or not _integer_range(run.get("ranking_schema", 0), 0, 1): return false
	if int(run.get("ranking_schema", 0)) == 0: return true
	if not run.get("ranking_processed") is bool or not _integer_range(run.get("rank_at_finish"), 0, 3) or not _integer_range(run.get("ended_at"), 0, 1000000000000): return false
	var terminal: bool = int(run.get("phase", -1)) in [RunModel.Phase.WON, RunModel.Phase.LOST]
	if not terminal:
		if run["ranking_processed"] or int(run["rank_at_finish"]) != 0 or int(run["ended_at"]) != 0: return false
	elif not run["ranking_processed"]: return false
	if int(run["rank_at_finish"]) > 0 and (float(run.get("defeat_score", 0)) <= 0 or int(run["ended_at"]) <= 0): return false
	var entries: Array = data["profile"].get("leaderboard", []) if int(data["profile"].get("leaderboard_schema", 0)) == 1 else []
	var rank: int = 0
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		if entry["run_id"] != run.get("run_id"): continue
		rank = index + 1
		if entry.get("challenge", {}) != run.get("challenge", {}): return false
		if not terminal or int(run["rank_at_finish"]) != rank: return false
		for pair: Array in [["score", "defeat_score"], ["mode_id", "mode_id"], ["ended_at", "ended_at"], ["reason", "finished_reason"], ["defeated_count", "defeated_count"], ["bosses_defeated", "bosses_defeated"]]:
			if entry[pair[0]] != run.get(pair[1]): return false
	if int(run["rank_at_finish"]) != rank: return false
	var summary: Dictionary = data.get("last_run_summary", {})
	if terminal and int(run["ended_at"]) > 0 and summary.get("run_id") != run.get("run_id"): return false
	if terminal and summary.get("run_id") == run.get("run_id") and (int(run["ended_at"]) > 0 or summary.has("ranking_processed")):
		if summary.get("challenge", {}) != run.get("challenge", {}): return false
		for key: String in ["ranking_processed", "rank_at_finish", "ended_at", "mode_id", "defeat_score"]:
			if summary.get(key) != run.get(key): return false
	return true

func _valid_world(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var world: Dictionary = value
	if not _is_number(world.get("projectile_schema", 0)) or float(world.get("projectile_schema", 0)) not in [0.0, 1.0]: return false
	var modern: bool = int(world.get("projectile_schema", 0)) == 1
	var ledger: Variant = world.get("projectile_ledger", {})
	if not ledger is Dictionary: return false
	var sources: Dictionary = {}
	var live_children: Dictionary = {}
	if not world.get("pending_volleys", {}) is Dictionary: return false
	if modern:
		for key: Variant in ledger:
			if not key is String or not world.get("pending_volleys", {}).has(key) or not ledger[key] is Dictionary: return false
			# Pre-v5 arrows lack shot metadata and are grouped under reserved shot 0.
			var source_limit: int = 1000000 if key == "0" else 96
			if not _integer_range(ledger[key].get("next_source"), 1, source_limit) or not _integer_range(ledger[key].get("children"), 0, 64): return false
			if int(ledger[key]["next_source"]) <= int(ledger[key]["children"]): return false
	for key: Variant in world.get("pending_volleys", {}):
		if not key is String or not key.is_valid_int() or int(key) < 0: return false
		if modern and not ledger.has(key): return false
		var hits: Variant = world["pending_volleys"][key]
		if not hits is Array: return false
		for hit: Variant in hits:
			if not hit is Dictionary: return false
			for field: String in ["effective", "reward_score", "reward_gold"]:
				if not _is_number(hit.get(field)) or float(hit[field]) < 0: return false
			for field: String in ["hit_id", "event_id"]:
				if not hit.get(field) is String: return false
			for field: String in ["broken", "bullseye", "critical"]:
				if not hit.get(field) is bool: return false
			if not hit.get("is_boss", false) is bool: return false
			if hit.has("boss_part") and (not bool(hit.get("is_boss", false)) or hit["boss_part"] not in ["body", "weak", "shield"]): return false
			if hit.get("boss_part", "") == "shield" and (float(hit["effective"]) != 0 or hit["broken"] or hit["critical"] or hit["bullseye"] or float(hit["reward_score"]) != 0 or float(hit["reward_gold"]) != 0): return false
			if hit.has("damage_kind"):
				if hit["damage_kind"] != "area" or hit["critical"] or hit["bullseye"] or float(hit["effective"]) <= 0.0 or hit.get("boss_part", "") == "shield": return false
				if not str(hit["hit_id"]).contains(":area:") or not str(hit["hit_id"]).ends_with(":" + str(hit["event_id"])): return false
			if hit.has("child_gold_bonus") or hit.has("parent_source_id"):
				if not _is_number(hit.get("child_gold_bonus")) or float(hit["child_gold_bonus"]) <= 0 or float(hit["child_gold_bonus"]) > 2: return false
				if not hit["broken"] or float(hit["effective"]) <= 0 or hit.get("boss_part", "") == "shield": return false
				var parts: PackedStringArray = str(hit["hit_id"]).split(":")
				if parts.size() < 3 or parts[0] != key or not parts[1].is_valid_int(): return false
				var source: int = int(parts[1])
				if not _integer_range(hit.get("parent_source_id"), 0, source - 1) or not ledger.has(key) or source >= int(ledger[key]["next_source"]): return false
	if not _is_number(world.get("reload_left", 0)) or not _vector(world.get("direction", [1, 0])):
		return false
	if not world.get("waiting_for_settle", false) is bool or not world.get("arrows", []) is Array:
		return false
	for arrow: Variant in world.get("arrows", []):
		if not arrow is Dictionary or not _vector(arrow.get("position")) or not _vector(arrow.get("velocity")):
			return false
		if not arrow.get("stats") is Dictionary or not arrow.get("hit_slots") is Array:
			return false
		if arrow.has("combat_schema") and not _valid_arrow_combat(arrow): return false
		for key: String in ["shot_id", "source_id"]:
			if not _is_number(arrow.get(key, 0)) or float(arrow.get(key, 0)) < 0: return false
		if modern:
			if not _integer_range(arrow.get("shot_id"), 0, 1000000000): return false
			var shot: String = str(int(arrow["shot_id"]))
			if not _integer_range(arrow.get("source_id"), 0, 999999 if shot == "0" else 95): return false
			var source: int = int(arrow["source_id"])
			var identity: String = "%s:%d" % [shot, source]
			if sources.has(identity) or not ledger.has(shot) or source >= int(ledger[shot]["next_source"]): return false
			sources[identity] = true
			if not _integer_range(arrow.get("parent_source_id"), -1, source - 1) or not arrow.get("split_spent") is bool: return false
			if not _valid_effects(arrow.get("effects")): return false
			if not arrow.get("split_pending") is bool or not arrow.get("split_exit_rect") is Array or arrow["split_exit_rect"].size() != 4: return false
			for component: Variant in arrow["split_exit_rect"]:
				if not _is_number(component): return false
			if arrow["split_pending"] and (not arrow["split_spent"] or int(arrow["effects"]["split_count"]) == 0 or float(arrow["split_exit_rect"][2]) <= 0 or float(arrow["split_exit_rect"][3]) <= 0): return false
			if int(arrow["parent_source_id"]) >= 0:
				if int(arrow["effects"]["split_count"]) != 0 or not arrow["split_spent"] or arrow["split_pending"]: return false
				live_children[shot] = int(live_children.get(shot, 0)) + 1
		for key: String in BowStats.FIELDS:
			if not _is_number(arrow["stats"].get(key)): return false
		if float(arrow["stats"]["arrow_size"]) < 0.5 or float(arrow["stats"]["arrow_size"]) > 6.0:
			return false
		for key: String in ["pull", "elapsed", "remaining_bounces"]:
			if not _is_number(arrow.get(key)) or float(arrow[key]) < 0: return false
		for slot: Variant in arrow["hit_slots"]:
			if not _is_number(slot) or float(slot) != floorf(float(slot)): return false
	for shot: String in live_children:
		if int(live_children[shot]) > int(ledger[shot]["children"]): return false
	if not _is_number(world.get("clock", 0.0)) or not world.get("targets", []) is Array:
		return false
	for target: Variant in world.get("targets", []):
		if not target is Dictionary or not _is_number(target.get("hp", 0.0)) or not _is_number(target.get("respawn_left", 0.0)):
			return false
		for key: String in ["max_hp", "generation", "armor", "spawn_difficulty", "reward_score", "reward_gold"]:
			if not _is_number(target.get(key, 0)):
				return false
		if not target.get("kind", "") is String:
			return false
		if not _vector(target.get("anchor", [0, 0])) or not _is_number(target.get("target_scale", 1)): return false
	if not _integer_range(world.get("field_generation", 0), 0, 1000000000): return false
	var boss: Variant = world.get("boss")
	if boss != null:
		if not boss is Dictionary or not _integer_range(boss.get("round_number"), 1, 10000000): return false
		if boss.get("kind") != "mechanical_boss" or not _vector(boss.get("anchor")): return false
		if boss.has("health_revision") and not _integer_range(boss["health_revision"], 2, 2): return false
		for key: String in ["hp", "max_hp", "armor", "reward_score", "reward_gold", "respawn_left", "target_scale"]:
			if not _is_number(boss.get(key)) or float(boss[key]) < 0: return false
		if float(boss["max_hp"]) <= 0 or float(boss["hp"]) > float(boss["max_hp"]) or float(boss["target_scale"]) != 1: return false
		if boss.has("combat_schema") and not _valid_boss_combat(boss): return false
	return true

func _valid_boss_combat(boss: Dictionary) -> bool:
	if not _integer_range(boss.get("combat_schema"), 0, 1) or not _integer_range(boss.get("battle_phase"), 1, 2): return false
	if not _is_number(boss.get("phase_clock")) or float(boss["phase_clock"]) < 0 or float(boss["phase_clock"]) > 1.0e9: return false
	if not _vector(boss.get("body_position")) or not _vector(boss.get("shield_position")): return false
	var params: Variant = boss.get("combat_parameters")
	if not _number_map(params): return false
	var limits: Dictionary = {"body_width": [16, 64], "body_radius": [24, 70],
		"phase_health_ratio": [0.1, 0.9], "weak_multiplier": [1, 4], "weak_half_height": [2, 24],
		"weak_armor_reduction": [0, 100], "shield_width": [4, 20], "shield_height": [12, 60], "shield_gap": [4, 40],
		"shield_armor_bonus": [0, 100], "body_amplitude": [0, 24], "body_frequency": [0.1, 5],
		"shield_amplitude": [0, 48], "shield_frequency": [0.1, 5]}
	for key: String in limits:
		if not params.has(key) or float(params[key]) < limits[key][0] or float(params[key]) > limits[key][1]: return false
	if int(boss["combat_schema"]) == 0:
		return int(boss["battle_phase"]) == 1 and float(boss["phase_clock"]) == 0 and boss["body_position"] == boss["anchor"]
	if int(boss["battle_phase"]) == 1 and float(boss["phase_clock"]) != 0: return false
	if float(boss["hp"]) > 0:
		if (int(boss["battle_phase"]) == 2) != (float(boss["hp"]) <= float(boss["max_hp"]) * float(params["phase_health_ratio"])): return false
	# Reconstruct the collider poses; forged offsets must not silently move on resume.
	var moving: bool = int(boss["battle_phase"]) == 2
	var origin := Vector2(boss["anchor"][0], boss["anchor"][1])
	var body := origin + Vector2(0, sin(float(boss["phase_clock"]) * float(params["body_frequency"])) * float(params["body_amplitude"]) if moving else 0.0)
	var shield := body + Vector2(-float(params["body_width"]) * 0.5 - float(params["shield_width"]) * 0.5 - float(params["shield_gap"]), sin(float(boss["phase_clock"]) * float(params["shield_frequency"])) * float(params["shield_amplitude"]) if moving else 0.0)
	return body.distance_to(Vector2(boss["body_position"][0], boss["body_position"][1])) < 0.0001 and shield.distance_to(Vector2(boss["shield_position"][0], boss["shield_position"][1])) < 0.0001

func _valid_effects(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _integer_range(value.get("split_count"), 0, 2): return false
	for key: String in ["split_damage", "split_degrees", "bounce_multiplier", "speed_limit"]:
		if not _is_number(value.get(key)): return false
	return float(value["split_damage"]) > 0 and float(value["split_damage"]) <= 1 and float(value["split_degrees"]) >= 0 and float(value["split_degrees"]) <= 45 and float(value["bounce_multiplier"]) >= 1 and float(value["bounce_multiplier"]) <= 2 and float(value["speed_limit"]) >= 200 and float(value["speed_limit"]) <= 5000

func _valid_arrow_combat(arrow: Dictionary, require_current: bool = false) -> bool:
	if not _integer_range(arrow.get("combat_schema"), 3 if require_current else 1, 3): return false
	var params: Variant = arrow.get("effects")
	if not params is Dictionary: return false
	for key: String in ["penetration_damage", "excess_damage", "excess_limit", "echo_damage"]:
		if not _is_number(params.get(key)) or float(params[key]) < 0 or float(params[key]) > 2: return false
	for key: String in ["penetration_limit", "bounce_penetration_limit"]:
		if not _integer_range(params.get(key), 0, 32): return false
	if not _integer_range(params.get("bounce_penetration"), 0, 100): return false
	if not _integer_range(arrow.get("penetration_stacks"), 0, int(params["penetration_limit"])) or not _integer_range(arrow.get("bounce_stacks"), 0, int(params["bounce_penetration_limit"])): return false
	if not arrow.get("echo_ready") is bool or (arrow["echo_ready"] and float(params["echo_damage"]) == 0): return false
	if not arrow.get("penetration_exits") is Array or not arrow.get("hit_slots") is Array: return false
	if arrow["penetration_exits"].size() + int(arrow["penetration_stacks"]) > int(params["penetration_limit"]): return false
	var slots: Dictionary = {}
	for entry: Variant in arrow["penetration_exits"]:
		if not entry is Dictionary or not _integer_range(entry.get("slot"), -3, 1000000) or not arrow["hit_slots"].has(entry["slot"]) or slots.has(entry["slot"]) or int(entry["slot"]) == -2: return false
		slots[entry["slot"]] = true
		if not entry.get("rect") is Array or entry["rect"].size() != 4: return false
		for component: Variant in entry["rect"]:
			if not _is_number(component) or absf(float(component)) > 10000: return false
		if float(entry["rect"][2]) <= 0 or float(entry["rect"][3]) <= 0: return false
	if int(arrow["combat_schema"]) == 1: return true
	if not _integer_range(params.get("charged_penetration"), 0, 100) or not _integer_range(params.get("bullseye_targets"), 0, 16) or not _integer_range(params.get("critical_limit"), 0, 32): return false
	for key: String in ["bullseye_damage", "critical_damage", "size_bullseye", "size_bullseye_limit"]:
		if not _is_number(params.get(key)) or float(params[key]) < 0.0 or float(params[key]) > 2.0: return false
	if not _is_number(params.get("bullseye_radius")) or float(params["bullseye_radius"]) < 0.0 or float(params["bullseye_radius"]) > 640.0: return false
	if not _integer_range(arrow.get("critical_stacks"), 0, int(params["critical_limit"])): return false
	if not arrow.get("area_slots") is Array or arrow["area_slots"].size() > 16: return false
	var affected: Dictionary = {}
	for slot: Variant in arrow["area_slots"]:
		if not _integer_range(slot, -1, 1000000) or affected.has(int(slot)): return false
		affected[int(slot)] = true
	if not affected.is_empty() and (float(params["bullseye_damage"]) == 0.0 or int(params["bullseye_targets"]) == 0 or float(params["bullseye_radius"]) == 0.0): return false
	if affected.has(-1) and (not arrow["hit_slots"].has(-1) or not arrow["hit_slots"].has(-3)): return false
	if int(arrow["combat_schema"]) >= 3:
		if not _integer_range(params.get("child_bounces"), 0, 32): return false
		if not _is_number(params.get("child_gold_bonus")) or float(params["child_gold_bonus"]) < 0 or float(params["child_gold_bonus"]) > 2: return false
		if not _integer_range(arrow.get("remaining_bounces"), 0, 32): return false
	return true

func _integer_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

func _valid_run(data: Dictionary) -> bool:
	if not _valid_challenge(data) or not _valid_backpack(data) or not _valid_mode(data) or not _valid_economy(data) or not _valid_trait_levels(data) or not _valid_mastery(data): return false
	if not data.get("offer_exhausted", false) is bool: return false
	var exhausted: bool = bool(data.get("offer_exhausted", false))
	if not _integer_range(data.get("boss_reward_schema", 0), 0, 1): return false
	if int(data.get("boss_reward_schema", 0)) == 1 and not _valid_reward_queue(data): return false
	if not _integer_range(data.get("boss_schema", 0), 0, 1): return false
	if int(data.get("boss_schema", 0)) == 1:
		if not _integer_range(data.get("boss_round"), 0, 10000000) or not _integer_range(data.get("bosses_defeated"), 0, int(data["boss_round"])): return false
		if not data.get("boss_active") is bool: return false
		if not _integer_range(data.get("boss_next_defeats"), 100, 1000000100) or int(data["boss_next_defeats"]) != (int(data["boss_round"]) + 1) * RunModel.BOSS_RULES.kills_per_boss: return false
		if data["boss_active"] and int(data["boss_round"]) <= 0: return false
	for key: String in ["encounter_schema", "encounter_rewards_generated", "encounter_offer_id", "pending_encounters", "defeated_count", "phase"]:
		if not _is_number(data.get(key, 0)): return false
	if float(data.get("encounter_schema", 0)) not in [0.0, 1.0]: return false
	if not _number_map(data.get("encounter_picks", {})): return false
	if int(data.get("encounter_schema", 0)) == 1:
		for key: String in ["encounter_rewards_generated", "encounter_offer_id", "pending_encounters"]:
			var number: float = float(data.get(key, 0))
			if number < 0 or number != floorf(number): return false
		var earned: int = int(data.get("encounter_rewards_generated", 0))
		if earned != int(data.get("defeated_count", 0)) / EncounterCatalog.RULES.kills_per_reward: return false
		var picks: Dictionary = data.get("encounter_picks", {})
		var picked_count: int = data.get("discarded_artifacts", {}).size() if int(data.get("backpack_schema", 0)) == 1 else 0
		for id: Variant in picks:
			if not id is String or EncounterCatalog.find(id) == null or float(picks[id]) < 1 or float(picks[id]) != floorf(float(picks[id])): return false
			if EncounterCatalog.find(id).is_trait and (int(picks[id]) != 1 or not _string_array(data.get("seen_encounters", [])) or not data.get("seen_encounters", []).has(id)): return false
			picked_count += int(picks[id])
		var boss_rewards: int = data.get("boss_reward_log", []).size() if int(data.get("boss_reward_schema", 0)) == 1 else 0
		if picked_count + int(data.get("pending_encounters", 0)) > earned + boss_rewards or int(data.get("encounter_offer_id", 0)) > earned + boss_rewards: return false
		var offered: Variant = data.get("choices", [])
		if not _string_array(offered): return false
		if int(data.get("phase", 0)) == RunModel.Phase.CHOICE:
			if int(data.get("pending_encounters", 0)) <= 0 or offered.size() > 3 or (offered.is_empty() and not exhausted) or int(data.get("encounter_offer_id", 0)) <= 0: return false
		elif not offered.is_empty(): return false
		var groups: Dictionary = {}
		var safe: bool = false
		for id: String in offered:
			var reward: EncounterData = EncounterCatalog.find(id)
			if reward == null or groups.has(reward.candidate_group()): return false
			var is_boss: bool = int(data.get("boss_reward_schema", 0)) == 1 and not data["reward_queue"].is_empty() and data["reward_queue"][0]["kind"] == "boss"
			if is_boss and (reward.is_trait or reward.has_debuff): return false
			if not reward.upgrade_trait.is_empty():
				if not is_boss or int(data.get("trait_schema", 0)) != 1 or not picks.has(reward.upgrade_trait) or reward.upgrade_rank != int(data["trait_levels"].get(reward.upgrade_trait, 0)) + 1: return false
				if not RunModel.from_dict(data).trait_has_gain(reward.upgrade_trait): return false
			if reward.is_trait and (not _string_array(data.get("seen_encounters", [])) or not data.get("seen_encounters", []).has(id) or picks.has(id) or data.get("discarded_artifacts", {}).has(id)): return false
			groups[reward.candidate_group()] = true
			if not reward.is_trait and not reward.has_debuff: safe = true
		if not offered.is_empty() and not safe: return false
	for key: String in ["shot_sequence", "last_settled_shot", "combo"]:
		if not _is_number(data.get(key, 0)): return false
	for key: String in ["phase", "stage", "shots_left", "gold", "gold_fraction", "score", "prototype_total_score", "lifetime_score", "initial_shots", "defeated_count", "defeat_score", "difficulty_step", "pending_encounters", "starting_level", "gold_earned"]:
		if not _is_number(data.get(key, 0)):
			return false
	for key: String in ["skill_levels", "legacy_skill_levels", "purchases", "talent_snapshot"]:
		if not _number_map(data.get(key, {})):
			return false
	if not data.get("credited_defeats", {}) is Dictionary:
		return false
	for key: String in ["encounters", "blessings", "choices", "seen_encounters"]:
		if not _string_array(data.get(key, [])):
			return false
	if exhausted:
		if int(data.get("phase", 0)) != RunModel.Phase.CHOICE or not data.get("choices", []).is_empty(): return false
		var model: RunModel = RunModel.from_dict(data)
		for reward: EncounterData in EncounterCatalog.ALL:
			if not reward.is_trait and not reward.has_debuff and model.encounter_has_gain(reward): return false
		if model.reward_source()["kind"] == "boss":
			for id: String in TraitUpgradeCatalog.ALL:
				if model.trait_has_gain(id): return false
	return true

func _valid_challenge(data: Dictionary) -> bool:
	if not _integer_range(data.get("challenge_schema", 0), 0, 1): return false
	if not ContractCatalog.valid_snapshot(data.get("challenge", {})): return false
	if int(data.get("challenge_schema", 0)) == 0: return data.get("challenge", {}).is_empty()
	if not data.has("challenge"): return false
	for field: String in ["contract_stage_base_score", "contract_stage_bonus_earned"]:
		if not _is_number(data.get(field)) or float(data[field]) < 0 or float(data[field]) > 1.0e18: return false
	if data.challenge.is_empty(): return data.contract_stage_base_score == 0 and data.contract_stage_bonus_earned == 0
	var p: Dictionary = data.challenge.parameters
	if float(data.contract_stage_base_score) > float(data.get("defeat_score", 0)) + 0.000001: return false
	if float(p.stage_bonus) == 0 and float(data.contract_stage_bonus_earned) != 0: return false
	if data.get("mode_parameters") != {"target_health": p.target_health, "boss_health": p.boss_health, "score": 1.0, "health_growth": 0.06}: return false
	if data.get("artifact_capacity") != p.artifact_slots or not data.get("supply_parameters") is Dictionary or data.supply_parameters.get("limit") != p.supply_limit: return false
	if not data.get("boss_reward_log") is Array: return false
	var total: float = 0.0
	for record: Variant in data.boss_reward_log:
		if not record is Dictionary or not _is_number(record.get("contract_bonus")) or not _is_number(record.get("score")): return false
		if float(record.contract_bonus) < 0 or float(record.contract_bonus) > float(record.score): return false
		total += float(record.contract_bonus)
	return is_equal_approx(total, float(data.contract_stage_bonus_earned)) and float(data.contract_stage_bonus_earned) <= float(data.get("defeat_score", 0))

func _valid_mode(data: Dictionary) -> bool:
	if not _integer_range(data.get("mode_schema", 0), 0, 1): return false
	if int(data.get("mode_schema", 0)) == 0: return true
	if not data.get("mode_id") is String or DifficultyCatalog.find(data["mode_id"]) == null: return false
	var params: Variant = data.get("mode_parameters")
	if not params is Dictionary or params.size() != 4: return false
	for key: String in ["target_health", "boss_health", "score", "health_growth"]:
		if not _is_number(params.get(key)): return false
		if key == "health_growth":
			if float(params[key]) < 0 or float(params[key]) > 1: return false
		elif float(params[key]) < 1 or float(params[key]) > 10: return false
	return true

func _valid_economy(data: Dictionary) -> bool:
	if not _integer_range(data.get("economy_schema", 0), 0, 1): return false
	if int(data.get("economy_schema", 0)) == 0: return _integer_range(data.get("phase", 0), 0, RunModel.Phase.LOST)
	if not _integer_range(data.get("phase"), 0, RunModel.Phase.SUPPLY): return false
	var params: Variant = data.get("supply_parameters")
	if not params is Dictionary or params.size() != 4: return false
	if not _integer_range(params.get("limit"), 0 if not data.get("challenge", {}).is_empty() else 1, 10) or not _integer_range(params.get("draws"), 1, 10) or not _integer_range(params.get("first_cost"), 1, 1000000000): return false
	if not _is_number(params.get("growth")) or float(params["growth"]) < 1.01 or float(params["growth"]) > 10: return false
	if not _integer_range(data.get("supply_segment"), 0, 10000000) or int(data["supply_segment"]) != int(data.get("bosses_defeated", 0)): return false
	if not _integer_range(data.get("supply_total_bought"), 0, (int(data["supply_segment"]) + 1) * int(params["limit"])): return false
	if not _integer_range(data.get("supply_segment_bought"), 0, mini(int(params["limit"]), int(data["supply_total_bought"]))): return false
	if int(data["supply_total_bought"]) - int(data["supply_segment_bought"]) > int(data["supply_segment"]) * int(params["limit"]): return false
	if not _integer_range(data.get("supply_offer_id"), 0, int(data["supply_total_bought"]) + 1): return false
	if not _integer_range(data.get("gold"), 0, 1000000000) or not _integer_range(data.get("shots_left"), 0, 100000): return false
	if not _integer_range(data.get("gold_spent"), 0, 9007199254740991) or not data.get("gold_spending") is Dictionary: return false
	var spending: Dictionary = data["gold_spending"]
	if spending.size() != 5: return false
	var total: int = 0
	for key: String in ["basic", "mastery", "traits", "supplies", "legacy"]:
		if not _integer_range(spending.get(key), 0, 9007199254740991): return false
		total += int(spending[key])
	if total != int(data["gold_spent"]): return false
	var purchased: int = int(data["supply_total_bought"])
	var expected: int = 0
	# At the price cap the remaining sum is linear, even for very long saves.
	for index: int in range(purchased):
		var price: int = SupplyRules.price(params, index)
		if price == 1000000000:
			expected += price * (purchased - index)
			break
		expected += price
	if int(spending["supplies"]) != expected: return false
	if int(data["phase"]) == RunModel.Phase.SUPPLY:
		if int(data["shots_left"]) != 0 or int(data.get("pending_encounters", 0)) != 0 or int(data["supply_offer_id"]) <= 0 or not str(data.get("finished_reason", "")).is_empty(): return false
		if int(data["supply_segment_bought"]) >= int(params["limit"]) or int(data["gold"]) < SupplyRules.price(params, purchased): return false
	return true

func _valid_backpack(data: Dictionary) -> bool:
	if not data.get("discarded_artifacts", {}) is Dictionary: return false
	if not _integer_range(data.get("backpack_schema", 0), 0, 1): return false
	if int(data.get("backpack_schema", 0)) == 0: return true
	if not _integer_range(data.get("artifact_capacity"), 4 if not data.get("challenge", {}).is_empty() else RunModel.ARTIFACT_SLOTS, TraitUpgradeCatalog.ALL.size()) or not _integer_range(data.get("artifact_revision"), 0, 9007199254740991): return false
	if not data.get("discarded_artifacts") is Dictionary or not data.get("encounter_picks") is Dictionary or not _string_array(data.get("seen_encounters")): return false
	var active: int = 0
	for id: Variant in data["encounter_picks"]:
		if not id is String: return false
		var reward: EncounterData = EncounterCatalog.find(id)
		if reward != null and reward.is_trait: active += 1
	if active > int(data["artifact_capacity"]): return false
	for id: Variant in data["discarded_artifacts"]:
		if not id is String or TraitUpgradeCatalog.find(id) == null or data["encounter_picks"].has(id) or not data["seen_encounters"].has(id): return false
		if not _integer_range(data["discarded_artifacts"][id], 0, TraitUpgradeCatalog.find(id).max_level): return false
	return true

func _valid_trait_levels(data: Dictionary) -> bool:
	if not _integer_range(data.get("trait_schema", 0), 0, 1): return false
	if int(data.get("trait_schema", 0)) == 0: return true
	if not data.get("trait_levels") is Dictionary or not data.get("encounter_picks") is Dictionary: return false
	for id: Variant in data["trait_levels"]:
		if not id is String or TraitUpgradeCatalog.find(id) == null: return false
		if not _integer_range(data["trait_levels"][id], 1, TraitUpgradeCatalog.find(id).max_level) or data["encounter_picks"].get(id, 0) != 1: return false
	return true

func _valid_mastery(data: Dictionary) -> bool:
	if not _integer_range(data.get("mastery_schema", 0), 0, 1): return false
	if int(data.get("mastery_schema", 0)) == 0: return true
	if not _integer_range(data.get("skill_schema"), 2, 2) or not data.get("mastery_levels") is Dictionary or not _string_array(data.get("mastery_unlocks")): return false
	var seen: Dictionary = {}
	for id: String in data["mastery_unlocks"]:
		if SkillCatalog.find(StringName(id)) == null or seen.has(id) or not data["mastery_levels"].has(id): return false
		seen[id] = true
	for id: Variant in data["mastery_levels"]:
		if not id is String: return false
		var skill: RunSkillData = SkillCatalog.find(StringName(id))
		if skill == null or not _integer_range(data["mastery_levels"][id], 1, skill.mastery_max_level) or not seen.has(id): return false
	if not data.get("skill_levels") is Dictionary: return false
	for id: Variant in data["skill_levels"]:
		if not id is String: return false
		var skill: RunSkillData = SkillCatalog.find(StringName(id))
		if skill == null or not _integer_range(data["skill_levels"][id], 0, skill.max_level): return false
	return true

func _valid_reward_queue(data: Dictionary) -> bool:
	if not data.get("credited_defeats", {}) is Dictionary or not _number_map(data.get("encounter_picks", {})): return false
	var queue: Variant = data.get("reward_queue")
	var log: Variant = data.get("boss_reward_log")
	if not queue is Array or not log is Array or not _integer_range(data.get("pending_encounters"), 0, 1000000) or queue.size() != int(data["pending_encounters"]): return false
	if not _integer_range(data.get("bosses_defeated"), log.size(), 10000000): return false
	var records: Dictionary = {}
	var previous: int = 0
	var granted: Dictionary = {}
	var granted_ranks: Dictionary = {}
	for record: Variant in log:
		if not record is Dictionary or not _integer_range(record.get("round"), previous + 1, int(data.get("boss_round", 0))): return false
		previous = int(record["round"])
		if not data.get("credited_defeats", {}).get("boss%d" % previous, false): return false
		for key: String in ["score", "gold"]:
			if not _is_number(record.get(key)) or float(record[key]) < 0: return false
		if not _integer_range(record.get("draws"), 0, 6) or not record.get("choice") is String: return false
		if not record["choice"].is_empty() and record["choice"] != RunModel.NO_GAIN:
			var reward: EncounterData = EncounterCatalog.find(record["choice"])
			if reward == null or reward.is_trait or reward.has_debuff: return false
			if not reward.upgrade_trait.is_empty():
				if int(data.get("trait_schema", 0)) != 1 or maxi(int(data.get("trait_levels", {}).get(reward.upgrade_trait, 0)), int(data.get("discarded_artifacts", {}).get(reward.upgrade_trait, 0))) < reward.upgrade_rank or granted.has(record["choice"]): return false
				if reward.upgrade_rank <= int(granted_ranks.get(reward.upgrade_trait, 0)): return false
				granted_ranks[reward.upgrade_trait] = reward.upgrade_rank
				granted[record["choice"]] = true
			elif int(data.get("encounter_picks", {}).get(record["choice"], 0)) <= 0: return false
		records[previous] = record
	var queued: Dictionary = {}
	for source: Variant in queue:
		if not source is Dictionary or source.get("kind") not in ["ordinary", "boss"] or not _integer_range(source.get("round"), 0, int(data.get("boss_round", 0))): return false
		if source["kind"] == "ordinary":
			if int(source["round"]) != 0: return false
		else:
			var number: int = int(source["round"])
			if not records.has(number) or queued.has(number) or not records[number]["choice"].is_empty(): return false
			queued[number] = true
	if int(data.get("phase", 0)) not in [RunModel.Phase.WON, RunModel.Phase.LOST]:
		for number: int in records:
			if records[number]["choice"].is_empty() and not queued.has(number): return false
	return true

func _number_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for entry: Variant in value.values():
		if not _is_number(entry):
			return false
	return true

func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _is_number(value[0]) and _is_number(value[1])

func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String:
			return false
	return true

func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

