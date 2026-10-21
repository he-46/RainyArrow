class_name GameSession
extends RefCounted
## Coordinates profile/run transitions and atomic checkpoints without owning a scene tree.

signal defeat_recorded(event_id: String)

var profile: PlayerProfile = PlayerProfile.new()
var run: RunModel
var in_lobby: bool = true
var world_snapshot: Dictionary = {}
var last_run_summary: Dictionary = {}
var migration: Dictionary = {}
var _checkpoint: Dictionary = {}
var _record_scores: bool = true

func _init(record_scores: bool = true) -> void:
	_record_scores = record_scores

func has_active_run() -> bool:
	return run != null and not run.is_finished()

func start_run(replace_existing: bool = false, mode_id: String = "normal", contracts: Variant = null) -> RunModel:
	if (contracts != null and not ContractCatalog.valid_selection(contracts)) or DifficultyCatalog.find(mode_id) == null: return null
	if has_active_run() and not replace_existing:
		return null
	if has_active_run():
		end_run("abandoned")
	_detach_run()
	run = RunModel.new(mode_id, contracts)
	run.active.id = profile.equipped_active
	run.starting_level = profile.level
	run.talent_snapshot = profile.talents.duplicate(true)
	run.rebuild_stats()
	run.initial_shots = maxi(1, run.initial_shots + int(run.talent_effects.get("initial_shots", 0)))
	run.shots_left = run.initial_shots
	run.stage_finished.connect(_on_stage_finished)
	world_snapshot = {}
	in_lobby = false
	_checkpoint = to_dict()
	return run

func resume_run() -> RunModel:
	if not has_active_run():
		return null
	in_lobby = false
	run.suspended = false
	_update_checkpoint_location()
	return run

func return_to_lobby() -> void:
	in_lobby = true
	if run != null:
		run.suspended = true
	_update_checkpoint_location()

func end_run(reason: String = "exhausted") -> bool:
	if run == null or not run.finished_reason.is_empty():
		return false
	if not run.ranking_processed:
		run.ranking_processed = true
		run.ended_at = int(Time.get_unix_time_from_system())
		if _record_scores:
			run.rank_at_finish = profile.leaderboard.submit({"run_id": run.run_id, "score": run.defeat_score,
				"challenge": run.challenge, "mode_id": run.mode_id, "ended_at": run.ended_at, "reason": reason,
				"defeated_count": run.defeated_count, "bosses_defeated": run.bosses_defeated})
	last_run_summary = {
		"ranking_processed": run.ranking_processed, "rank_at_finish": run.rank_at_finish, "ended_at": run.ended_at,
		"challenge": run.challenge, "contract_stage_bonus_earned": run.contract_stage_bonus_earned, "run_id": run.run_id, "mode_id": run.mode_id, "reason": reason, "defeated_count": run.defeated_count,
		"defeat_score": run.defeat_score, "prototype_total_score": run.prototype_total_score,
		"gold_discarded": run.gold,
		"gold_spent": run.gold_spent, "gold_spending": run.gold_spending.duplicate(),
		"supply_total_bought": run.supply_total_bought,
		"gold_earned": run.gold_earned, "starting_level": run.starting_level,
		"bosses_defeated": run.bosses_defeated,
		"boss_reward_log": run.boss_reward_log.duplicate(true), "boss_reward_totals": run.boss_reward_totals(),
		"ending_level": profile.level, "talent_points_earned": profile.level - run.starting_level,
	}
	run.finished_reason = reason
	if not run.is_finished():
		run.phase = RunModel.Phase.LOST
	run.gold = 0
	run.gold_fraction = 0.0
	run.choices.clear()
	run.pending_encounters = 0
	run.reward_queue.clear()
	run.offer_exhausted = false
	return_to_lobby()
	# Ending is terminal, so an older playable checkpoint must never revive the run.
	_checkpoint = to_dict()
	run.changed.emit()
	return true

func record_defeat(event_id: String, points: float, coins: float = 0.0) -> bool:
	var previous: float = run.defeat_score if run != null else 0.0
	if in_lobby or not has_active_run() or not run.record_defeat(event_id, points, coins):
		return false
	profile.record_defeat(run.defeat_score - previous)
	# Talent hooks may refund a draw here, before the world checks exhaustion.
	defeat_recorded.emit(event_id)
	run.changed.emit()
	return true

func capture_checkpoint(world: Dictionary) -> void:
	# Caller captures between physics steps, including all live arrows and target state.
	world_snapshot = world.duplicate(true)
	_checkpoint = to_dict()

func record_boss_defeat(event_id: String, points: float, coins: float) -> bool:
	var previous: float = run.defeat_score if run != null else 0.0
	if in_lobby or not has_active_run() or not run.record_boss_defeat(event_id, points, coins): return false
	profile.record_score(run.defeat_score - previous)
	defeat_recorded.emit(event_id)
	run.changed.emit()
	return true

func purchase_talent(id: String) -> bool:
	var node: TalentData = TalentCatalog.find(id)
	return in_lobby and node != null and profile.invest_talent(id, node.price(int(profile.talents.get(id, 0))))

func reset_talents() -> int:
	return profile.reset_talents() if in_lobby else 0

func unlock_active(id: String) -> bool:
	return in_lobby and profile.unlock_active(id)

func equip_active(id: String) -> bool:
	return in_lobby and not has_active_run() and profile.equip_active(id)

func settle_shot(shot_id: int, hits: Array) -> bool:
	if in_lobby or not has_active_run() or run.phase != RunModel.Phase.PLAYING or shot_id <= run.last_settled_shot or shot_id > run.shot_sequence:
		return false
	run.last_settled_shot = shot_id
	var unique: Dictionary = {}
	var effective: Array[Dictionary] = []
	for hit: Dictionary in hits:
		var key: String = str(hit.get("hit_id", ""))
		if key.is_empty() or unique.has(key) or float(hit.get("effective", 0.0)) <= 0.0: continue
		unique[key] = true
		effective.append(hit)
	run.combo = 0 if effective.is_empty() else run.combo + 1
	var energy_hit: bool = false
	var energy_bullseye: bool = false
	for hit: Dictionary in effective:
		if not bool(hit.get("energy_eligible", false)): continue
		energy_hit = true
		energy_bullseye = energy_bullseye or bool(hit.get("bullseye", false))
	run.active.gain((4 if energy_hit else 0) + (2 if energy_bullseye else 0))
	var refunded: int = 0
	for hit: Dictionary in effective:
		var killed: bool = false
		if bool(hit.get("broken", false)):
			var bonus: float = 1.0 + float(run.talent_effects.get("combo_gold", 0.0)) * mini(maxi(run.combo - 1, 0), TalentCatalog.RULES.combo_bonus_cap + int(run.talent_effects.get("combo_cap", 0)))
			if bool(hit.get("bullseye", false)): bonus *= 1.0 + float(run.talent_effects.get("bullseye_gold", 0.0))
			if int(hit.get("parent_source_id", -1)) >= 0: bonus *= 1.0 + float(hit.get("child_gold_bonus", 0.0))
			if bool(hit.get("is_boss", false)):
				killed = record_boss_defeat(str(hit["event_id"]), float(hit["reward_score"]), float(hit["reward_gold"]) * bonus)
			else:
				killed = record_defeat(str(hit["event_id"]), float(hit["reward_score"]), float(hit["reward_gold"]) * bonus)
		for chance: float in [float(run.talent_effects.get("kill_refund", 0.0)) if killed else 0.0, float(run.talent_effects.get("crit_refund", 0.0)) if bool(hit.get("critical", false)) else 0.0]:
			if refunded < TalentCatalog.RULES.max_refunds_per_draw and chance > 0.0 and run.rng.randf() < chance:
				refunded += run.restore_shots(1)
	# Finish every hit/refund in this draw before pausing for an earned encounter.
	run.offer_encounter()
	run.changed.emit()
	return true

func save_payload() -> Dictionary:
	var payload: Dictionary = to_dict() if _checkpoint.is_empty() else _checkpoint.duplicate(true)
	# Settings are independent of combat. Never mix in-flight XP with an older run snapshot.
	payload["profile"]["settings"] = profile.settings.duplicate(true)
	payload["profile"]["tutorial_completed"] = profile.tutorial_completed
	# Equipment is presentation. Unlock entitlement still follows checkpointed XP/kills.
	payload["profile"]["equipped_cosmetics"] = profile.equipped_cosmetics.duplicate(true)
	return payload

func to_dict() -> Dictionary:
	return {
		"profile": profile.to_dict(), "run": run.to_dict() if run != null else null,
		"world": world_snapshot.duplicate(true), "in_lobby": in_lobby,
		"last_run_summary": last_run_summary.duplicate(true), "migration": migration.duplicate(true),
	}

static func from_dict(data: Dictionary) -> GameSession:
	var result: GameSession = GameSession.new()
	result.profile = PlayerProfile.from_dict(data.get("profile", {}))
	if data.get("run") is Dictionary:
		var saved_run: Dictionary = data["run"].duplicate(true)
		var old_summary: Dictionary = data.get("last_run_summary", {})
		if int(saved_run.get("economy_schema", 0)) == 0 and old_summary.get("run_id") == saved_run.get("run_id") and old_summary.has("gold_discarded"):
			saved_run["legacy_final_wallet"] = old_summary["gold_discarded"]
		result.run = RunModel.from_dict(saved_run)
		result.run.starting_level = int(data["run"].get("starting_level", result.profile.level))
		result.run.stage_finished.connect(result._on_stage_finished)
	result.in_lobby = bool(data.get("in_lobby", true)) or not result.has_active_run()
	if result.run != null:
		result.run.suspended = result.in_lobby
	result.world_snapshot = ArcheryWorld.upgrade_snapshot(data.get("world", {}))
	result.last_run_summary = data.get("last_run_summary", {}).duplicate(true)
	# JSON decodes every number as float. Use the same canonical v1 contract
	# types as RunModel/Leaderboard, so a completed run can be saved again.
	var summary_challenge: Variant = result.last_run_summary.get("challenge", {})
	if ContractCatalog.valid_snapshot(summary_challenge) and not summary_challenge.is_empty():
		result.last_run_summary["challenge"] = ContractCatalog.snapshot(summary_challenge.selection)
	result.migration = data.get("migration", {}).duplicate(true)
	if result.run != null and result.run.is_finished():
		result.end_run("completed" if result.run.phase == RunModel.Phase.WON else "exhausted")
	result.capture_checkpoint(result.world_snapshot)
	return result

static func from_legacy(payload: Dictionary) -> GameSession:
	var result: GameSession = GameSession.new()
	result.profile.settings["muted"] = bool(payload.get("muted", false))
	result.run = RunModel.from_dict(payload.get("run", {}))
	result.run.stage_finished.connect(result._on_stage_finished)
	result.world_snapshot = ArcheryWorld.upgrade_snapshot(payload.get("world", {}))
	result.in_lobby = true
	result.run.suspended = true
	result.migration = {"source_version": 1, "legacy_progress": "continuous_converted"}
	if result.run.is_finished():
		result.end_run("completed" if result.run.phase == RunModel.Phase.WON else "exhausted")
	result.capture_checkpoint(result.world_snapshot)
	return result

func _on_stage_finished() -> void:
	if run.is_finished():
		end_run("completed" if run.phase == RunModel.Phase.WON else "exhausted")

func _detach_run() -> void:
	if run != null and run.stage_finished.is_connected(_on_stage_finished):
		run.stage_finished.disconnect(_on_stage_finished)

func _update_checkpoint_location() -> void:
	if not _checkpoint.is_empty():
		_checkpoint["in_lobby"] = in_lobby
		if _checkpoint["run"] is Dictionary:
			_checkpoint["run"]["suspended"] = in_lobby
