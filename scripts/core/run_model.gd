class_name RunModel
extends RefCounted
## Owns authoritative game state. World/UI may request changes, never award currency themselves.

signal changed
signal stage_finished

# WON retains its number for old saves; CHOICE now holds an earned encounter offer.
enum Phase { PLAYING, SHOP, CHOICE, WON, LOST, SUPPLY }
const LEGACY_LAST_STAGE: int = 5
const INITIAL_SHOTS: int = 10
const BOSS_RULES: BossRules = preload("res://data/boss_rules.tres")

var _mode_id: String = "normal"
var _mode_parameters: Dictionary
var mode_id: String:
	get: return _mode_id
var mode_parameters: Dictionary:
	get: return _mode_parameters.duplicate()
var _challenge: Dictionary = {}
var challenge: Dictionary:
	get: return _challenge.duplicate(true)
var contract_stage_base_score: float = 0.0
var contract_stage_bonus_earned: float = 0.0
var phase: Phase = Phase.PLAYING
var stage: int = 1 # Legacy field layout only; continuous difficulty uses defeated_count.
var shots_left: int = INITIAL_SHOTS
var gold: int = 0
var gold_fraction: float = 0.0
const SUPPLY_RULES: SupplyRules = preload("res://data/supply_rules.tres")
var supply_parameters: Dictionary = SUPPLY_RULES.parameters()
var supply_total_bought: int = 0
var supply_segment_bought: int = 0
var supply_segment: int = 0 # Number of Boss victories when this allowance began.
var supply_offer_id: int = 0
var gold_spent: int = 0
var gold_spending: Dictionary = {"basic": 0, "mastery": 0, "traits": 0, "supplies": 0, "legacy": 0}
var score: float = 0.0
var prototype_total_score: float = 0.0
var skill_levels: Dictionary = {}
var trait_levels: Dictionary = {}
const ARTIFACT_SLOTS: int = 6
var artifact_capacity: int = ARTIFACT_SLOTS
var discarded_artifacts: Dictionary = {} # Final ranks retained only for reward history.
var artifact_revision: int = 0
var trait_shop_open: bool = false # Transient UI permission, never restored from disk.
var mastery_levels: Dictionary = {}
var mastery_unlocks: Array[String] = []
var legacy_skill_levels: Dictionary = {}
var encounters: Array[String] = []
var choices: Array[String] = []
var stats: BowStats
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var run_id: String
var ruleset: String = "continuous_v1"
var initial_shots: int = INITIAL_SHOTS
var talent_snapshot: Dictionary = {}
var talent_effects: Dictionary = {}
var shot_sequence: int = 0
var last_settled_shot: int = -1
var combo: int = 0
var defeated_count: int = 0
var defeat_score: float = 0.0
var difficulty_step: int = 0
var credited_defeats: Dictionary = {}
var seen_encounters: Array[String] = []
var pending_encounters: int = 0
var encounter_picks: Dictionary = {}
var encounter_rewards_generated: int = 0
var encounter_offer_id: int = 0
var suspended: bool = false
var finished_reason: String = ""
var ranking_processed: bool = false
var rank_at_finish: int = 0
var ended_at: int = 0
var starting_level: int = 1
var gold_earned: float = 0.0
var boss_round: int = 0
var bosses_defeated: int = 0
var boss_next_defeats: int = 100
var boss_active: bool = false
var reward_queue: Array[Dictionary] = []
var boss_reward_log: Array[Dictionary] = []
var offer_exhausted: bool = false
const NO_GAIN: String = "_no_gain"

func _sync_reward_queue() -> void:
	# Legacy saves/test fixtures have only the ordinary pending count.
	while reward_queue.size() < pending_encounters:
		reward_queue.append({"kind": "ordinary", "round": 0})

func reward_source() -> Dictionary:
	_sync_reward_queue()
	return reward_queue[0] if not reward_queue.is_empty() else {"kind": "ordinary", "round": 0}

func boss_reward_totals() -> Dictionary:
	var totals: Dictionary = {"score": 0.0, "gold": 0.0, "draws": 0}
	for record: Dictionary in boss_reward_log:
		for key: String in totals: totals[key] += record[key]
	return totals

func _init(mode: String = "normal", contracts: Variant = null) -> void:
	var config: DifficultyData = DifficultyCatalog.find(mode)
	if config == null: config = DifficultyCatalog.find("normal")
	_mode_id = config.id
	_mode_parameters = config.parameters()
	if ContractCatalog.valid_selection(contracts):
		_challenge = ContractCatalog.snapshot(contracts)
		var p: Dictionary = _challenge.parameters
		_mode_parameters = {"target_health": p.target_health, "boss_health": p.boss_health, "score": 1.0, "health_growth": 0.06}
		supply_parameters["limit"] = int(p.supply_limit)
		artifact_capacity = int(p.artifact_slots)
		initial_shots = INITIAL_SHOTS - int(p.draw_penalty)
		shots_left = initial_shots
	rng.randomize()
	run_id = "%x-%x" % [rng.randi(), rng.randi()]
	rebuild_stats()

func contract_value(key: String, fallback: float) -> float:
	return float(_challenge.parameters.get(key, fallback)) if not _challenge.is_empty() else fallback

func field_parameters() -> Dictionary:
	var result: Dictionary = mode_parameters
	result["target_armor"] = int(contract_value("target_armor", 0))
	result["bullseye_scale"] = contract_value("bullseye_scale", 1)
	return result

func difficulty_title() -> String:
	return ContractCatalog.title(_challenge) if not _challenge.is_empty() else DifficultyCatalog.title(mode_id)

func trait_price(id: String, rank: int) -> int:
	var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
	return contract_price(config.price(rank)) if config != null else 1000000000

func contract_price(base: int) -> int:
	return mini(1000000000, ceili(base * contract_value("price_multiplier", 1)))

func is_finished() -> bool:
	return phase == Phase.WON or phase == Phase.LOST

func boss_due() -> bool:
	return not boss_active and not is_finished() and defeated_count >= boss_next_defeats

func begin_boss() -> bool:
	if suspended or phase != Phase.PLAYING or pending_encounters > 0 or not boss_due(): return false
	boss_round += 1
	boss_next_defeats += BOSS_RULES.kills_per_boss
	boss_active = true
	return true

func record_boss_defeat(event_id: String, points: float, coins: float) -> bool:
	if suspended or phase != Phase.PLAYING or not boss_active or event_id != "boss%d" % boss_round or credited_defeats.has(event_id): return false
	if not is_finite(points) or points < 0 or not is_finite(coins) or coins < 0: return false
	credited_defeats[event_id] = true
	bosses_defeated += 1
	supply_segment = bosses_defeated
	supply_segment_bought = 0
	var contract_bonus: float = 0.0
	if not _challenge.is_empty():
		contract_bonus = (contract_stage_base_score + points) * contract_value("stage_bonus", 0)
		points = points * contract_value("boss_score", 1) + contract_bonus
		contract_stage_base_score = 0.0
		contract_stage_bonus_earned += contract_bonus
	defeat_score += points
	score = defeat_score
	var reward: float = coins * stats.gold_multiplier
	gold_earned += reward
	gold_fraction += reward
	var whole: int = floori(gold_fraction)
	gold = mini(1000000000, gold + whole)
	gold_fraction -= whole
	_sync_reward_queue()
	var draws: int = restore_shots(BOSS_RULES.draw_reward(boss_round))
	boss_reward_log.append({"round": boss_round, "score": points, "gold": reward, "draws": draws, "choice": ""})
	if not _challenge.is_empty(): boss_reward_log.back()["contract_bonus"] = contract_bonus
	reward_queue.append({"kind": "boss", "round": boss_round})
	pending_encounters += 1
	return true

func record_defeat(event_id: String, points: float, coins: float = 0.0) -> bool:
	if suspended or phase != Phase.PLAYING or boss_active or event_id.is_empty() or credited_defeats.has(event_id):
		return false
	if not is_finite(points) or points < 0.0 or not is_finite(coins) or coins < 0.0:
		return false
	credited_defeats[event_id] = true
	defeated_count += 1
	if not _challenge.is_empty():
		contract_stage_base_score += points
		points *= contract_value("target_score", 1)
	defeat_score += points
	score = defeat_score
	var reward: float = coins * stats.gold_multiplier
	gold_earned += reward
	gold_fraction += reward
	var whole: int = floori(gold_fraction)
	gold = mini(1000000000, gold + whole)
	gold_fraction -= whole
	difficulty_step = defeated_count
	var entitlement: int = defeated_count / EncounterCatalog.RULES.kills_per_reward
	if entitlement > encounter_rewards_generated:
		_sync_reward_queue()
		for index: int in range(entitlement - encounter_rewards_generated):
			reward_queue.append({"kind": "ordinary", "round": 0})
		pending_encounters += entitlement - encounter_rewards_generated
		encounter_rewards_generated = entitlement
	return true

func rebuild_stats() -> void:
	talent_effects = TalentCatalog.effects(talent_snapshot)
	stats = calculate_stats(skill_levels)

func calculate_stats(levels: Dictionary) -> BowStats:
	return _effective_stats(calculate_raw_stats(levels, encounter_picks), encounter_picks)

func _effective_stats(raw: BowStats, picks: Dictionary) -> BowStats:
	return _evaluate_raw(raw, picks).effective

func evaluate_stats(levels: Dictionary, picks: Dictionary, masteries: Variant = null, upgrades: Variant = null) -> StatEvaluation:
	var evaluation: StatEvaluation = _evaluate_raw(calculate_raw_stats(levels, picks, masteries, upgrades), picks, upgrades)
	evaluation.mastery_ranks = (mastery_levels if masteries == null else masteries).duplicate()
	return evaluation

func _evaluate_raw(raw: BowStats, picks: Dictionary, upgrades: Variant = null) -> StatEvaluation:
	var result := StatEvaluation.new()
	var rules: EncounterRules = trait_rules(picks, upgrades)
	result.raw = raw
	result.linked = raw.duplicate() as BowStats
	result.source_arrows = clampi(raw.arrow_count, 1, 32)
	# A single directed pipeline: sources -> linkage -> conversions -> final caps.
	if int(picks.get("swarm_precision", 0)) > 0:
		result.linked.crit_chance += (result.source_arrows - 1) * rules.crit_per_extra_arrow
	result.linked.crit_chance += minf(TalentCatalog.RULES.arrow_crit_bonus_cap, (result.source_arrows - 1) * float(talent_effects.get("crit_per_arrow", 0.0)))
	result.crit_source = clampf(result.linked.crit_chance, 0.0, 1.0)
	result.extra_crit_source = clampf(result.linked.crit_multiplier, 1.0, 10.0) - 1.0
	result.converted = result.linked.duplicate() as BowStats
	if int(picks.get("unified_arrow", 0)) > 0:
		result.converted.arrow_count = 1
		result.converted.damage *= pow(result.source_arrows, rules.unity_damage_exponent)
		result.converted.arrow_size *= pow(result.source_arrows, rules.unity_size_exponent)
	if int(picks.get("critical_forging", 0)) > 0:
		result.converted_penetration = _conversion_units(result.crit_source, rules.crit_per_penetration)
		result.converted.armor_penetration += result.converted_penetration
		result.converted.crit_chance = 0.0
	if int(picks.get("critical_ricochet", 0)) > 0:
		result.converted_bounces = _conversion_units(result.extra_crit_source, rules.extra_crit_per_bounce)
		result.converted.bounces += result.converted_bounces
		result.converted.crit_multiplier = 1.0
	# Derive damage once after conversions, so forging and unified arrows keep their meaning.
	result.talent_damage_bonuses = {
		"透甲锋芒": minf(TalentCatalog.RULES.penetration_damage_bonus_cap, clampi(result.converted.armor_penetration, 0, 1000000) * float(talent_effects.get("damage_per_penetration", 0.0))),
		"万箭回响": minf(TalentCatalog.RULES.arrow_damage_bonus_cap, (result.source_arrows - 1) * float(talent_effects.get("damage_per_arrow", 0.0))),
		"巨矢会心": minf(TalentCatalog.RULES.size_damage_bonus_cap, maxf(0.0, clampf(result.converted.arrow_size, 0.5, 6.0) - 1.0) * float(talent_effects.get("damage_per_size", 0.0))),
	}
	var talent_damage: float = 0.0
	for bonus: float in result.talent_damage_bonuses.values(): talent_damage += bonus
	result.converted.damage *= 1.0 + talent_damage
	result.effective = result.converted.duplicate() as BowStats
	result.effective.clamp_values()
	return result

static func _conversion_units(value: float, step: float) -> int:
	# Stabilize decimal thresholds such as (2.2 - 1.0) / 0.2 without rounding remainders up.
	return floori(value / step + 0.000000001) if step > 0 else 0

func calculate_raw_stats(levels: Dictionary, picks: Dictionary, masteries: Variant = null, upgrades: Variant = null) -> BowStats:
	var result: BowStats = GameCatalog.BASE_BOW.duplicate() as BowStats
	for field: String in ["damage", "armor_penetration", "gold_multiplier", "arrow_count", "arrow_size", "crit_chance", "crit_multiplier", "launch_speed", "bounces"]:
		result.set(field, result.get(field) + float(talent_effects.get(field, 0.0)))
	# Old saved bonuses are isolated from the six purchasable branches.
	for key: Variant in legacy_skill_levels:
		_apply_legacy(result, GameCatalog.find_upgrade(StringName(key)), int(legacy_skill_levels[key]))
	for id: String in encounters:
		_apply_legacy(result, GameCatalog.find_upgrade(StringName(id)), 1)
	var damage_bonus: float = float(talent_effects.get("damage_bonus", 0.0))
	for reward: EncounterData in EncounterCatalog.ALL:
		var count: int = int(picks.get(reward.id, 0))
		damage_bonus += reward.damage_bonus * count
		for field: String in reward.additions:
			result.set(field, result.get(field) + reward.additions[field] * count)
	var damage_factor: float = 1.0
	var ranks: Dictionary = mastery_levels if masteries == null else masteries
	for skill: RunSkillData in SkillCatalog.ALL:
		var rank: int = clampi(int(levels.get(String(skill.id), 0)), 0, skill.max_level)
		for field: String in skill.additions:
			result.set(field, result.get(field) + skill.additions[field] * rank)
		var mastery: int = clampi(int(ranks.get(String(skill.id), 0)), 0, skill.mastery_max_level)
		var weight: float = skill.mastery_weight(mastery)
		var factor: float = skill.damage_factor
		if skill.id == &"quantity":
			factor = minf(skill.quantity_factor_limit, factor + skill.quantity_relief * skill.mastery_weight(mini(mastery, skill.quantity_relief_ranks)))
			var extra: int = maxi(0, mastery - skill.quantity_relief_ranks)
			result.arrow_count += extra
			damage_bonus += skill.mastery_damage_bonus * 0.5 * skill.mastery_weight(mini(mastery, skill.quantity_relief_ranks))
			damage_bonus += skill.mastery_damage_bonus * skill.mastery_weight(extra)
		else:
			damage_bonus += skill.mastery_damage_bonus * weight
		for field: String in skill.mastery_additions:
			var addition: float = float(skill.mastery_additions[field]) * weight
			if field in ["arrow_count", "armor_penetration", "bounces"]: addition = floorf(addition + 0.000000001)
			result.set(field, result.get(field) + addition)
		for field: String in skill.mastery_flat_additions:
			result.set(field, result.get(field) + skill.mastery_flat_additions[field] * mastery)
		damage_factor *= pow(factor, rank)
	# Gold efficiency linkage uses the same capped multiplier as actual currency awards.
	damage_bonus += (clampf(result.gold_multiplier, 1.0, 4.0) - 1.0) * float(talent_effects.get("damage_per_gold", 0.0))
	result.damage *= damage_factor * (1.0 + damage_bonus)
	var rules: EncounterRules = trait_rules(picks, upgrades)
	if int(picks.get("slender_gale", 0)) > 0:
		result.arrow_size *= rules.slender_size_factor
		result.launch_speed *= rules.slender_speed_factor
	if int(picks.get("heavy_draw", 0)) > 0:
		result.damage *= rules.heavy_damage_factor
		result.reload_seconds *= rules.heavy_reload_factor
	return result

func projectile_effects(upgrades: Variant = null) -> ArrowEffects:
	var effects := ArrowEffects.new()
	var rules: EncounterRules = trait_rules(encounter_picks, upgrades)
	if int(encounter_picks.get("piercing_split", 0)) > 0:
		effects.split_count = rules.split_children
		effects.split_damage = rules.split_damage
		effects.split_degrees = rules.split_degrees
	if int(encounter_picks.get("ricochet_haste", 0)) > 0: effects.bounce_multiplier = rules.bounce_multiplier
	effects.speed_limit = rules.projectile_speed_limit
	if int(encounter_picks.get("piercing_edge", 0)) > 0:
		effects.penetration_damage = rules.penetration_damage
		effects.penetration_limit = rules.penetration_limit
	if int(encounter_picks.get("armor_surplus", 0)) > 0:
		effects.excess_damage = rules.excess_damage
		effects.excess_limit = rules.excess_limit
	if int(encounter_picks.get("echo_strike", 0)) > 0: effects.echo_damage = rules.echo_damage
	if int(encounter_picks.get("wall_forging", 0)) > 0:
		effects.bounce_penetration = rules.bounce_penetration
		effects.bounce_penetration_limit = rules.bounce_penetration_limit
	if int(encounter_picks.get("charged_breach", 0)) > 0: effects.charged_penetration = rules.charged_penetration
	if int(encounter_picks.get("bullseye_wave", 0)) > 0:
		effects.bullseye_radius = rules.bullseye_radius
		effects.bullseye_damage = rules.bullseye_damage
		effects.bullseye_targets = rules.bullseye_targets
	if int(encounter_picks.get("critical_flow", 0)) > 0:
		effects.critical_damage = rules.critical_damage
		effects.critical_limit = rules.critical_limit
	if int(encounter_picks.get("broad_precision", 0)) > 0:
		effects.size_bullseye = rules.size_bullseye
		effects.size_bullseye_limit = rules.size_bullseye_limit
	if int(encounter_picks.get("branch_harvest", 0)) > 0: effects.child_gold_bonus = rules.child_gold_bonus
	if int(encounter_picks.get("branch_ricochet", 0)) > 0: effects.child_bounces = rules.child_bounces
	return effects

func trait_rules(picks: Dictionary, upgrades: Variant = null) -> EncounterRules:
	return TraitUpgradeCatalog.derive(picks, trait_levels if upgrades == null else upgrades)

func trait_rank(id: String) -> int:
	return int(trait_levels.get(id, 0))

func preview_trait(id: String) -> StatEvaluation:
	var levels: Dictionary = trait_levels.duplicate()
	levels[id] = trait_rank(id) + 1
	return evaluate_stats(skill_levels, encounter_picks, null, levels)

func trait_has_gain(id: String) -> bool:
	var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
	if config == null or int(encounter_picks.get(id, 0)) != 1 or trait_rank(id) >= config.max_level: return false
	var before: BowStats = evaluate_stats(skill_levels, encounter_picks).effective
	var after: BowStats = preview_trait(id).effective
	if id in ["swarm_precision", "unified_arrow", "critical_forging", "critical_ricochet", "slender_gale", "heavy_draw"]: return _has_stat_gain(before, after)
	var rules: EncounterRules = trait_rules(encounter_picks)
	var levels: Dictionary = trait_levels.duplicate()
	levels[id] = trait_rank(id) + 1
	var next: EncounterRules = trait_rules(encounter_picks, levels)
	var charged: bool = encounter_picks.has("charged_breach") and rules.charged_penetration > 0
	var can_bounce: bool = before.bounces > 0 or (encounter_picks.has("piercing_split") and encounter_picks.has("branch_ricochet") and (before.armor_penetration > 0 or charged))
	var can_pierce: bool = before.armor_penetration > 0 or charged or (can_bounce and encounter_picks.has("wall_forging"))
	match id:
		"piercing_split", "piercing_edge", "armor_surplus": return can_pierce
		"ricochet_haste", "echo_strike": return can_bounce
		"wall_forging": return can_bounce and before.armor_penetration < 1000000
		"charged_breach": return before.armor_penetration < 1000000
		"critical_flow": return before.crit_chance > 0
		"broad_precision": return minf(maxf(before.arrow_size - 1, 0) * next.size_bullseye, next.size_bullseye_limit) > minf(maxf(before.arrow_size - 1, 0) * rules.size_bullseye, rules.size_bullseye_limit) + 0.000000001
		"branch_harvest": return encounter_picks.has("piercing_split") and can_pierce
		"branch_ricochet": return encounter_picks.has("piercing_split") and can_pierce and before.bounces + rules.child_bounces < 32
	return true

func can_buy_trait(id: String, expected_rank: int) -> bool:
	var permission: bool = phase == Phase.SHOP or (phase == Phase.PLAYING and trait_shop_open and pending_encounters == 0)
	return not suspended and permission and expected_rank == trait_rank(id) and trait_has_gain(id) and gold >= trait_price(id, expected_rank)

func buy_trait(id: String, expected_rank: int) -> bool:
	if not can_buy_trait(id, expected_rank): return false
	_spend_gold(trait_price(id, expected_rank), "traits")
	trait_levels[id] = expected_rank + 1
	artifact_revision += 1
	rebuild_stats()
	changed.emit()
	return true

func artifact_ids() -> Array[String]:
	var result: Array[String] = []
	for reward: EncounterData in EncounterCatalog.ALL:
		if reward.is_trait and int(encounter_picks.get(reward.id, 0)) > 0: result.append(reward.id)
	return result

func backpack_full() -> bool:
	return artifact_ids().size() >= artifact_capacity

func artifact_removal_blocker(id: String) -> String:
	if not artifact_ids().has(id): return "神器已不在背包中"
	for owned: String in artifact_ids():
		var reward: EncounterData = EncounterCatalog.find(owned)
		if reward.requires_trait == id: return "请先丢弃依赖它的「%s」" % reward.title
	return ""

func can_discard_artifact(id: String, revision: int) -> bool:
	return not suspended and phase == Phase.PLAYING and pending_encounters == 0 and trait_shop_open and revision == artifact_revision and artifact_removal_blocker(id).is_empty()

func _remove_artifact(id: String) -> void:
	discarded_artifacts[id] = trait_rank(id)
	encounter_picks.erase(id)
	trait_levels.erase(id)
	artifact_revision += 1

func discard_artifact(id: String, revision: int) -> bool:
	if not can_discard_artifact(id, revision): return false
	_remove_artifact(id)
	rebuild_stats()
	changed.emit()
	return true

func can_replace_artifact(incoming: String, outgoing: String, offer_id: int, revision: int) -> bool:
	if suspended or phase != Phase.CHOICE or pending_encounters <= 0 or offer_id != encounter_offer_id or revision != artifact_revision: return false
	if reward_source()["kind"] != "ordinary" or not backpack_full() or not choices.has(incoming) or not artifact_removal_blocker(outgoing).is_empty(): return false
	var reward: EncounterData = EncounterCatalog.find(incoming)
	return reward != null and reward.is_trait and not encounter_picks.has(incoming) and not discarded_artifacts.has(incoming) and reward.requires_trait != outgoing and encounter_has_gain(reward)

func preview_artifact_change(outgoing: String, incoming: String = "") -> BowStats:
	var picks: Dictionary = encounter_picks.duplicate()
	picks.erase(outgoing)
	if not incoming.is_empty(): picks[incoming] = 1
	return evaluate_stats(skill_levels, picks).effective

func trait_parameters(id: String, next_rank: bool = false) -> String:
	var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
	if config == null: return ""
	var old: EncounterRules = trait_rules(encounter_picks)
	var levels: Dictionary = trait_levels.duplicate()
	if next_rank: levels[id] = trait_rank(id) + 1
	var newer: EncounterRules = trait_rules(encounter_picks, levels)
	var lines: Array[String] = []
	for field: String in config.additions.keys() + config.divisors.keys():
		var text: String = TraitUpgradeCatalog.LABELS[field] + " " + TraitUpgradeCatalog.value_text(field, old.get(field))
		if next_rank: text += " → " + TraitUpgradeCatalog.value_text(field, newer.get(field))
		lines.append(text)
	return " · ".join(lines)

func trait_comparison(id: String) -> String:
	var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
	if config == null: return "未获得此特性"
	if trait_rank(id) >= config.max_level: return "强化满阶 · 当前效果保留"
	if not trait_has_gain(id): return "当前构筑无额外收益 · 不可强化"
	if id in ["swarm_precision", "unified_arrow", "critical_forging", "critical_ricochet", "slender_gale", "heavy_draw"]:
		var a: BowStats = evaluate_stats(skill_levels, encounter_picks).effective
		var b: BowStats = preview_trait(id).effective
		var items: Array[String] = []
		for field: String in ["damage", "armor_penetration", "bounces", "crit_chance", "arrow_size", "launch_speed", "reload_seconds"]:
			if a.get(field) == b.get(field): continue
			var labels: Dictionary = {"damage": "伤害", "armor_penetration": "穿甲", "bounces": "反弹", "crit_chance": "暴击率", "arrow_size": "尺寸", "launch_speed": "初速", "reload_seconds": "装填秒数"}
			if field == "crit_chance": items.append("暴击率 %.1f%%→%.1f%%" % [a.crit_chance * 100, b.crit_chance * 100])
			else: items.append("%s %.2f→%.2f" % [labels[field], a.get(field), b.get(field)])
		return " · ".join(items)
	return trait_parameters(id, true)

func _draft_boss() -> Array[String]:
	var safe_pool: Array[EncounterData] = []
	for reward: EncounterData in EncounterCatalog.ALL:
		if not reward.is_trait and not reward.has_debuff: safe_pool.append(reward)
	var safe_seen: Array[String] = []
	var ordinary: Array[String] = EncounterCatalog.draft(rng, safe_seen, safe_pool, encounter_has_gain)
	var upgrades: Array[String] = []
	for id: String in TraitUpgradeCatalog.ALL:
		if trait_has_gain(id): upgrades.append(TraitUpgradeCatalog.token(id, trait_rank(id) + 1))
	if upgrades.is_empty(): return ordinary
	var selected: Array[String] = []
	if not ordinary.is_empty(): selected.append(ordinary.pop_front())
	while selected.size() < 3 and not upgrades.is_empty():
		var index: int = rng.randi_range(0, upgrades.size() - 1)
		selected.append(upgrades[index])
		upgrades.remove_at(index)
	while selected.size() < 3 and not ordinary.is_empty(): selected.append(ordinary.pop_front())
	for index: int in range(selected.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: String = selected[index]
		selected[index] = selected[other]
		selected[other] = swap
	return selected

func preview_encounter(reward: EncounterData) -> BowStats:
	if not reward.upgrade_trait.is_empty(): return preview_trait(reward.upgrade_trait).effective
	var picks: Dictionary = encounter_picks.duplicate()
	picks[reward.id] = int(picks.get(reward.id, 0)) + 1
	return _effective_stats(calculate_raw_stats(skill_levels, picks), picks)

func encounter_description(reward: EncounterData) -> String:
	if not reward.upgrade_trait.is_empty(): return "免费强化至 %d/%d 阶；保留原特性，仅本局生效。不会扣除金币。" % [reward.upgrade_rank, TraitUpgradeCatalog.find(reward.upgrade_trait).max_level]
	if not reward.requires_trait.is_empty() and int(encounter_picks.get(reward.requires_trait, 0)) <= 0:
		return reward.description + "\n需要先获得：" + EncounterCatalog.find(reward.requires_trait).title
	if not encounter_has_gain(reward): return reward.description + "\n已达有效上限，当前无额外收益。"
	if reward.additions.has("arrow_count") and int(encounter_picks.get("unified_arrow", 0)) > 0:
		return "原箭数 +1，主箭仍为 1；按同一规则重算归一伤害、尺寸和数量暴击联动。"
	return reward.description

func encounter_has_gain(reward: EncounterData) -> bool:
	if reward == null: return false
	if reward.is_trait and discarded_artifacts.has(reward.id): return false
	if not reward.upgrade_trait.is_empty(): return reward.upgrade_rank == trait_rank(reward.upgrade_trait) + 1 and trait_has_gain(reward.upgrade_trait)
	if not reward.requires_trait.is_empty() and int(encounter_picks.get(reward.requires_trait, 0)) <= 0: return false
	if int(encounter_picks.get(reward.id, 0)) <= 0:
		if reward.trait_key == "slender_gale": return preview_encounter(reward).launch_speed > evaluate_stats(skill_levels, encounter_picks).effective.launch_speed + 0.000000001
		if reward.trait_key == "heavy_draw": return preview_encounter(reward).damage > evaluate_stats(skill_levels, encounter_picks).effective.damage + 0.000000001
	# Traits remain build commitments: future purchases can activate their linkage.
	if reward.is_trait: return true
	if reward.draws > 0: return shots_left < 100000
	var before: BowStats = evaluate_stats(skill_levels, encounter_picks).effective
	var after: BowStats = preview_encounter(reward)
	for field: String in BowStats.FIELDS:
		if absf(float(after.get(field)) - float(before.get(field))) > 0.000000001: return true
	return false

func can_skip_encounter() -> bool:
	if phase != Phase.CHOICE or pending_encounters <= 0: return false
	if backpack_full() and reward_source()["kind"] == "ordinary": return true
	for id: String in choices:
		var reward: EncounterData = EncounterCatalog.find(id)
		if reward != null and not reward.is_trait and not reward.has_debuff and encounter_has_gain(reward): return false
	return true

func skip_encounter(offer_id: int) -> bool:
	if suspended or offer_id != encounter_offer_id or not can_skip_encounter(): return false
	_consume_reward_source(NO_GAIN)
	choices.clear()
	offer_exhausted = false
	phase = Phase.PLAYING
	if not offer_encounter(): changed.emit()
	return true

func _consume_reward_source(id: String) -> void:
	var source: Dictionary = reward_source()
	if source["kind"] == "boss":
		for record: Dictionary in boss_reward_log:
			if record["round"] == source["round"]: record["choice"] = id
	reward_queue.pop_front()
	pending_encounters -= 1

func encounter_comparison(reward: EncounterData) -> String:
	if not reward.upgrade_trait.is_empty(): return trait_comparison(reward.upgrade_trait)
	if not reward.requires_trait.is_empty() and int(encounter_picks.get(reward.requires_trait, 0)) <= 0: return "需要先获得「一箭生枝」"
	if not encounter_has_gain(reward): return "有效属性已达上限 · 本项暂无收益"
	var after: BowStats = preview_encounter(reward)
	if reward.draws > 0: return "拉弓次数  %d → %d" % [shots_left, mini(shots_left + reward.draws, 100000)]
	match reward.trait_key:
		"branch_harvest": return "子箭击倒金币 +%.0f%%\n直击 / 回响均可 · 得分不变" % (trait_rules(encounter_picks).child_gold_bonus * 100)
		"branch_ricochet": return "子箭额外反弹 +%d\n余下预算上限 32 · 母箭不加" % trait_rules(encounter_picks).child_bounces
		"slender_gale": return "尺寸 ×%.2f → ×%.2f\n初速度 %.0f → %.0f" % [stats.arrow_size, after.arrow_size, stats.launch_speed, after.launch_speed]
		"heavy_draw": return "伤害 %.1f → %.1f\n装填 %.2f → %.2f 秒" % [stats.damage, after.damage, stats.reload_seconds, after.reload_seconds]
		"charged_breach": return "半拉 +%d / 满拉 +%d 穿甲\n向下取整 · 与原穿甲相加" % [trait_rules(encounter_picks).charged_penetration / 2, trait_rules(encounter_picks).charged_penetration]
		"bullseye_wave": return "范围 %.0f · 至多 %d 靶\n实际伤害 ×%.0f%%，再减护甲" % [trait_rules(encounter_picks).bullseye_radius, trait_rules(encounter_picks).bullseye_targets, trait_rules(encounter_picks).bullseye_damage * 100]
		"critical_flow": return "暴击后伤害 +%.0f%% / 层\n上限 %d 层 · 本次不提前加成" % [trait_rules(encounter_picks).critical_damage * 100, trait_rules(encounter_picks).critical_limit]
		"broad_precision": return "当前尺寸 ×%.2f → 靶心 +%.1f%%\n不扩大中心判定区" % [stats.arrow_size, minf(maxf(stats.arrow_size - 1.0, 0.0) * trait_rules(encounter_picks).size_bullseye, trait_rules(encounter_picks).size_bullseye_limit) * 100]
		"piercing_edge": return "穿出后伤害 +%.0f%% / 层 · 上限 %d 层" % [trait_rules(encounter_picks).penetration_damage * 100, trait_rules(encounter_picks).penetration_limit]
		"armor_surplus": return "每点多余穿甲 → 本次 +%.0f%%\n增伤上限 +%.0f%%" % [trait_rules(encounter_picks).excess_damage * 100, trait_rules(encounter_picks).excess_limit * 100]
		"echo_strike": return "反弹 → 下次伤害 +%.0f%%\n命中消耗 · 连续反弹不叠加" % [trait_rules(encounter_picks).echo_damage * 100]
		"wall_forging": return "反弹 → 此箭穿甲 +%d / 层\n上限 %d 层 · 不改变面板穿甲" % [trait_rules(encounter_picks).bounce_penetration, trait_rules(encounter_picks).bounce_penetration_limit]
		"piercing_split": return "首次贯穿 → 2 支子箭 · 每支 %.0f%%" % (trait_rules(encounter_picks).split_damage * 100)
		"ricochet_haste": return "每次反弹 → 速度 ×%.2f" % trait_rules(encounter_picks).bounce_multiplier
		"swarm_precision":
			if int(encounter_picks.get("critical_forging", 0)) > 0:
				return "暴击联动继续换穿甲\n穿甲 %d → %d" % [stats.armor_penetration, after.armor_penetration]
			return "暴击率  %.0f%% → %.0f%%" % [stats.crit_chance * 100, after.crit_chance * 100]
		"unified_arrow":
			return "发射箭数 %d → 1 · 伤害 %.1f → %.1f\n尺寸 ×%.2f → ×%.2f" % [stats.arrow_count, stats.damage, after.damage, stats.arrow_size, after.arrow_size]
		"critical_forging": return "暴击 %.0f%% → 0%%\n穿甲 %d → %d" % [stats.crit_chance * 100, stats.armor_penetration, after.armor_penetration]
		"critical_ricochet": return "暴击倍率 ×%.2f → ×1\n反弹 %d → %d" % [stats.crit_multiplier, stats.bounces, after.bounces]
	if reward.additions.has("arrow_count"):
		if int(encounter_picks.get("unified_arrow", 0)) > 0:
			return "发射仍为 1 · 伤害 %.1f → %.1f\n尺寸 ×%.2f → ×%.2f · 穿甲 %d → %d" % [stats.damage, after.damage, stats.arrow_size, after.arrow_size, stats.armor_penetration, after.armor_penetration]
		if int(encounter_picks.get("critical_forging", 0)) > 0:
			return "箭数 %d → %d · 穿甲 %d → %d" % [stats.arrow_count, after.arrow_count, stats.armor_penetration, after.armor_penetration]
		return "箭数 %d → %d · 暴击 %.0f%% → %.0f%%" % [stats.arrow_count, after.arrow_count, stats.crit_chance * 100, after.crit_chance * 100]
	if reward.damage_bonus > 0:
		var bonus: float = reward.damage_bonus * int(encounter_picks.get(reward.id, 0))
		return "增伤 %.0f%% → %.0f%%\n单箭伤害 %.1f → %.1f" % [bonus * 100, (bonus + reward.damage_bonus) * 100, stats.damage, after.damage]
	if reward.additions.has("damage"):
		return "单箭伤害  %.1f → %.1f" % [stats.damage, after.damage]
	if reward.additions.has("armor_penetration"):
		return "穿甲  %d → %d" % [stats.armor_penetration, after.armor_penetration]
	if reward.additions.has("reload_seconds"):
		return "装填时间  %.2f → %.2f 秒" % [stats.reload_seconds, after.reload_seconds]
	return "金币倍率  ×%.2f → ×%.2f" % [stats.gold_multiplier, after.gold_multiplier]

func preview_skill(skill: RunSkillData) -> BowStats:
	return preview_skill_evaluation(skill).effective

func preview_skill_evaluation(skill: RunSkillData) -> StatEvaluation:
	var levels: Dictionary = skill_levels.duplicate()
	var ranks: Dictionary = mastery_levels.duplicate()
	if skill_is_mastery(skill):
		ranks[String(skill.id)] = mini(int(ranks.get(String(skill.id), 0)) + 1, skill.mastery_max_level)
	else:
		levels[String(skill.id)] = mini(int(levels.get(String(skill.id), 0)) + 1, skill.max_level)
	return evaluate_stats(levels, encounter_picks, ranks)

func _has_stat_gain(before: BowStats, after: BowStats) -> bool:
	for field: String in BowStats.FIELDS:
		var difference: float = float(after.get(field)) - float(before.get(field))
		if field in ["reload_seconds", "gravity", "spread_degrees"]: difference = -difference
		if difference > 0.000000001: return true
	return false

func skill_is_mastery(skill: RunSkillData) -> bool:
	if skill == null or SkillCatalog.find(skill.id) != skill: return false
	var key: String = String(skill.id)
	if int(skill_levels.get(key, 0)) >= skill.max_level or mastery_unlocks.has(key): return true
	var levels: Dictionary = skill_levels.duplicate()
	levels[key] = int(levels.get(key, 0)) + 1
	# An already capped basic effect unlocks mastery without charging for an empty level.
	return not _has_stat_gain(evaluate_stats(skill_levels, encounter_picks).effective, evaluate_stats(levels, encounter_picks).effective)

func skill_rank(skill: RunSkillData) -> int:
	return int(mastery_levels.get(String(skill.id), 0)) if skill_is_mastery(skill) else int(skill_levels.get(String(skill.id), 0))

func skill_limit(skill: RunSkillData) -> int:
	return skill.mastery_max_level if skill_is_mastery(skill) else skill.max_level

func skill_price(skill: RunSkillData) -> int:
	return contract_price(skill.mastery_price(skill_rank(skill)) if skill_is_mastery(skill) else skill.price(skill_rank(skill)))

func skill_has_gain(skill: RunSkillData) -> bool:
	return skill != null and SkillCatalog.find(skill.id) == skill and skill_rank(skill) < skill_limit(skill) and _has_stat_gain(evaluate_stats(skill_levels, encounter_picks).effective, preview_skill(skill))

func _mastery_comparison(before: StatEvaluation, after: StatEvaluation) -> String:
	var a: BowStats = before.effective
	var b: BowStats = after.effective
	var parts: Array[String] = []
	if a.arrow_count != b.arrow_count: parts.append("箭数 %d→%d" % [a.arrow_count, b.arrow_count])
	if a.damage != b.damage: parts.append("伤害 %.2f→%.2f" % [a.damage, b.damage])
	if a.crit_chance != b.crit_chance: parts.append("暴击 %.1f%%→%.1f%%" % [a.crit_chance * 100, b.crit_chance * 100])
	if a.crit_multiplier != b.crit_multiplier: parts.append("暴伤 %.2f→%.2f" % [a.crit_multiplier, b.crit_multiplier])
	if a.armor_penetration != b.armor_penetration: parts.append("穿甲 %d→%d" % [a.armor_penetration, b.armor_penetration])
	if a.bounces != b.bounces: parts.append("反弹 %d→%d" % [a.bounces, b.bounces])
	if a.arrow_size != b.arrow_size: parts.append("尺寸 %.2f→%.2f" % [a.arrow_size, b.arrow_size])
	if a.launch_speed != b.launch_speed: parts.append("初速 %.1f→%.1f" % [a.launch_speed, b.launch_speed])
	if int(encounter_picks.get("broad_precision", 0)) > 0:
		var rules: EncounterRules = trait_rules(encounter_picks)
		var old_bonus: float = minf(maxf(a.arrow_size - 1, 0) * rules.size_bullseye, rules.size_bullseye_limit)
		var new_bonus: float = minf(maxf(b.arrow_size - 1, 0) * rules.size_bullseye, rules.size_bullseye_limit)
		if new_bonus > old_bonus: parts.append("靶心增伤 %.1f%%→%.1f%%" % [old_bonus * 100, new_bonus * 100])
	if parts.is_empty(): return "已达有效上限 · 暂无收益"
	var lines: Array[String] = []
	for index: int in range(0, parts.size(), 2):
		lines.append(parts[index] + (" · " + parts[index + 1] if index + 1 < parts.size() else ""))
	return "\n".join(lines)

func skill_comparison(skill: RunSkillData) -> String:
	var before: StatEvaluation = evaluate_stats(skill_levels, encounter_picks)
	var after: StatEvaluation = preview_skill_evaluation(skill)
	if skill_is_mastery(skill):
		if skill_rank(skill) >= skill.mastery_max_level: return "当前效果已保留 · 精通满阶"
		return _mastery_comparison(before, after)
	if skill.id == &"size" and int(encounter_picks.get("broad_precision", 0)) > 0:
		var rules: EncounterRules = trait_rules(encounter_picks)
		return skill.comparison(stats, after.effective) + "\n靶心增伤 +%.1f%% → +%.1f%%" % [minf(maxf(stats.arrow_size - 1.0, 0.0) * rules.size_bullseye, rules.size_bullseye_limit) * 100, minf(maxf(after.effective.arrow_size - 1.0, 0.0) * rules.size_bullseye, rules.size_bullseye_limit) * 100]
	if skill.id == &"quantity":
		if int(encounter_picks.get("unified_arrow", 0)) > 0:
			return "原箭数 %d → %d · 发射 1\n伤害 %.1f → %.1f · 尺寸 %.2f → %.2f" % [before.raw.arrow_count, after.raw.arrow_count, stats.damage, after.effective.damage, stats.arrow_size, after.effective.arrow_size]
		if int(encounter_picks.get("critical_forging", 0)) > 0:
			return "箭数 %d → %d · 单箭 %.1f → %.1f\n转化穿甲 %d → %d" % [stats.arrow_count, after.effective.arrow_count, stats.damage, after.effective.damage, stats.armor_penetration, after.effective.armor_penetration]
	if skill.id == &"critical" and (int(encounter_picks.get("critical_forging", 0)) > 0 or int(encounter_picks.get("critical_ricochet", 0)) > 0):
		return "原暴击 %.0f%% → %.0f%% · 倍率 %.2f → %.2f\n穿甲 %d → %d · 反弹 %d → %d" % [before.raw.crit_chance * 100, after.raw.crit_chance * 100, before.raw.crit_multiplier, after.raw.crit_multiplier, stats.armor_penetration, after.effective.armor_penetration, stats.bounces, after.effective.bounces]
	return skill.comparison(stats, after.effective)

func stat_explanations(evaluation: StatEvaluation) -> Array[String]:
	var lines: Array[String] = []
	for skill: RunSkillData in SkillCatalog.ALL:
		var rank: int = int(evaluation.mastery_ranks.get(String(skill.id), 0))
		if rank > 0: lines.append("%s精通 %d/%d：%s" % [skill.title, rank, skill.mastery_max_level, skill.mastery_description])
	var raw: BowStats = evaluation.raw
	var effective: BowStats = evaluation.effective
	var rules: EncounterRules = trait_rules(encounter_picks)
	var percent_bonus: float = 0.0
	percent_bonus += float(talent_effects.get("damage_bonus", 0.0))
	var gold_damage: float = (clampf(raw.gold_multiplier, 1.0, 4.0) - 1.0) * float(talent_effects.get("damage_per_gold", 0.0))
	percent_bonus += gold_damage
	if gold_damage > 0:
		lines.append("财源化锋：金币效率 ×%.2f → 伤害 +%.1f%%；不按剩余金币计算" % [clampf(raw.gold_multiplier, 1.0, 4.0), gold_damage * 100])
	for title: String in evaluation.talent_damage_bonuses:
		var bonus: float = float(evaluation.talent_damage_bonuses[title])
		if bonus > 0: lines.append("%s：条件增伤 +%.1f%%，同类相加后作用于转化后的伤害" % [title, bonus * 100])
	for reward: EncounterData in EncounterCatalog.ALL:
		percent_bonus += reward.damage_bonus * int(encounter_picks.get(reward.id, 0))
	if percent_bonus > 0:
		lines.append("伤害加成：同类叠层累计 +%.0f%%，作用于基础伤害加总；单箭有效 %.1f（上限 100 万）" % [percent_bonus * 100, effective.damage])
	if int(encounter_picks.get("unified_arrow", 0)) > 0:
		lines.append("箭数：原 %d → 转化来源 %d（最多 32）→ 发射 %d" % [raw.arrow_count, evaluation.source_arrows, effective.arrow_count])
		lines.append("归一伤害：原 %.1f × %d^%.2f → 有效 %.1f（上限 100 万）" % [raw.damage, evaluation.source_arrows, rules.unity_damage_exponent, effective.damage])
		lines.append("归一尺寸：原 ×%.2f × %d^%.2f → 有效 ×%.2f（上限 6）" % [raw.arrow_size, evaluation.source_arrows, rules.unity_size_exponent, effective.arrow_size])
	if int(encounter_picks.get("swarm_precision", 0)) > 0 or int(encounter_picks.get("critical_forging", 0)) > 0 or float(talent_effects.get("crit_per_arrow", 0.0)) > 0:
		lines.append("暴击：原 %.1f%% + 箭数联动 %.1f%% → 转化来源 %.1f%%（最多 100%%）→ 有效 %.1f%%" % [raw.crit_chance * 100, (evaluation.linked.crit_chance - raw.crit_chance) * 100, evaluation.crit_source * 100, effective.crit_chance * 100])
	if int(encounter_picks.get("critical_forging", 0)) > 0:
		lines.append("穿甲：原 %d + 暴击转换 %d = 有效 %d；每 %.2f%% 换 1，不足不兑换" % [raw.armor_penetration, evaluation.converted_penetration, effective.armor_penetration, rules.crit_per_penetration * 100])
	if int(encounter_picks.get("critical_ricochet", 0)) > 0:
		lines.append("暴伤：原 ×%.2f → 额外 %.0f%%（最多 900%%）→ 有效 ×%.2f；每 %.2f%% 换 1 反弹" % [raw.crit_multiplier, evaluation.extra_crit_source * 100, effective.crit_multiplier, rules.extra_crit_per_bounce * 100])
		lines.append("反弹：原 %d + 暴伤转换 %d = 有效 %d（上限 32）" % [raw.bounces, evaluation.converted_bounces, effective.bounces])
	if int(encounter_picks.get("charged_breach", 0)) > 0:
		lines.append("蓄势穿甲：满拉额外 +%d，按本次拉力向下取整；本箭穿甲与回响共享，角色面板不改" % rules.charged_penetration)
	if int(encounter_picks.get("broad_precision", 0)) > 0:
		lines.append("广锋正中：有效尺寸 ×%.2f → 靶心 +%.1f%%；按箭头中心判定" % [effective.arrow_size, minf(maxf(effective.arrow_size - 1.0, 0.0) * rules.size_bullseye, rules.size_bullseye_limit) * 100])
	if int(encounter_picks.get("critical_flow", 0)) > 0:
		lines.append("锋锐回流：有效暴击后本箭每层 +%.0f%%，最多 %d 层；暴击转穿甲后不触发" % [rules.critical_damage * 100, rules.critical_limit])
	if int(encounter_picks.get("bullseye_wave", 0)) > 0:
		lines.append("靶心回响：范围 %.0f，最多 %d 靶，各受实际伤害 %.0f%% 再减甲；每箭每靶一次，不递归" % [rules.bullseye_radius, rules.bullseye_targets, rules.bullseye_damage * 100])
	if int(encounter_picks.get("branch_harvest", 0)) > 0:
		lines.append("枝上丰收：子箭直击或回响击倒金币 +%.0f%%，采样发射系数；基础得分/击倒仍一次" % (rules.child_gold_bonus * 100))
	if int(encounter_picks.get("branch_ricochet", 0)) > 0:
		lines.append("继枝借壁：子箭继承余下预算再加 %d 次反弹，最多 32；不加母箭，不再分裂" % rules.child_bounces)
	if int(encounter_picks.get("slender_gale", 0)) > 0:
		lines.append("瘦箭疾风：尺寸来源 ×%.2f（有效 ×%.2f，下限0.5）；速度来源 ×%.2f（有效 %.0f，上限1000）" % [rules.slender_size_factor, effective.arrow_size, rules.slender_speed_factor, effective.launch_speed])
	if int(encounter_picks.get("heavy_draw", 0)) > 0:
		lines.append("慢弦重箭：伤害来源 ×%.2f → %.1f；装填来源 ×%.2f → %.2f 秒，每次重算仅一次" % [rules.heavy_damage_factor, effective.damage, rules.heavy_reload_factor, effective.reload_seconds])
	return lines

func _apply_legacy(result: BowStats, upgrade: UpgradeData, count: int) -> void:
	if upgrade == null: return
	var field: StringName = &"armor_penetration" if upgrade.stat == &"pierce" else upgrade.stat
	result.set(field, result.get(field) + upgrade.amount * count)

func consume_shot() -> bool:
	if suspended or phase != Phase.PLAYING or shots_left <= 0:
		return false
	shots_left -= 1
	shot_sequence += 1
	changed.emit()
	return true

func restore_shots(amount: int) -> int:
	if suspended or phase != Phase.PLAYING or amount <= 0:
		return 0
	var restored: int = mini(amount, 100000 - shots_left)
	shots_left += restored
	changed.emit()
	return restored

func settle_volley() -> void:
	# World invokes this only after every projectile and synchronous reward finishes.
	if suspended or phase != Phase.PLAYING:
		return
	if offer_encounter(): return
	if shots_left <= 0 and pending_encounters == 0:
		if supply_available():
			phase = Phase.SUPPLY
			supply_offer_id += 1
			changed.emit()
		else:
			_finish_exhaustion()

func _finish_exhaustion() -> void:
	phase = Phase.LOST
	stage_finished.emit()
	changed.emit()

func _spend_gold(amount: int, category: String) -> void:
	gold -= amount
	gold_spent += amount
	gold_spending[category] = int(gold_spending[category]) + amount

func supply_price() -> int:
	return SupplyRules.price(supply_parameters, supply_total_bought)

func supply_remaining() -> int:
	return int(supply_parameters["limit"]) - supply_segment_bought

func supply_available() -> bool:
	return supply_remaining() > 0 and shots_left < 100000 and gold >= supply_price()

func supply_token() -> Dictionary:
	return {"total": supply_total_bought, "segment": supply_segment, "offer_id": supply_offer_id}

func can_buy_supply(token: Dictionary) -> bool:
	if suspended or phase not in [Phase.SHOP, Phase.SUPPLY] or pending_encounters > 0 or not supply_available(): return false
	for key: String in ["total", "segment", "offer_id"]:
		if not token.has(key) or not (token[key] is int or token[key] is float) or token[key] != supply_token()[key]: return false
	return true

func buy_supply(token: Dictionary) -> bool:
	if not can_buy_supply(token): return false
	_spend_gold(supply_price(), "supplies")
	supply_total_bought += 1
	supply_segment_bought += 1
	shots_left = mini(100000, shots_left + int(supply_parameters["draws"]))
	if phase == Phase.SUPPLY: phase = Phase.PLAYING
	changed.emit()
	return true

func decline_supply(offer_id: int) -> bool:
	if suspended or phase != Phase.SUPPLY or offer_id != supply_offer_id: return false
	_finish_exhaustion()
	return true

func offer_encounter() -> bool:
	if suspended or phase != Phase.PLAYING or pending_encounters <= 0:
		return false
	if choices.is_empty():
		var pool: Array[EncounterData] = EncounterCatalog.ALL
		if reward_source()["kind"] == "boss":
			pool = []
			for reward: EncounterData in EncounterCatalog.ALL:
				if not reward.is_trait and not reward.has_debuff: pool.append(reward)
		choices = _draft_boss() if reward_source()["kind"] == "boss" else EncounterCatalog.draft(rng, seen_encounters, pool, encounter_has_gain)
		offer_exhausted = choices.is_empty()
		encounter_offer_id += 1
	phase = Phase.CHOICE
	changed.emit()
	return true

func choose_encounter(id: String, offer_id: int, outgoing: String = "", revision: int = -1) -> bool:
	if suspended or phase != Phase.CHOICE or pending_encounters <= 0 or offer_id != encounter_offer_id or not choices.has(id):
		return false
	var reward: EncounterData = EncounterCatalog.find(id)
	if reward == null or not encounter_has_gain(reward) or (reward.is_trait and int(encounter_picks.get(id, 0)) > 0): return false
	if reward_source()["kind"] == "boss" and (reward.is_trait or reward.has_debuff): return false
	if reward.is_trait:
		if backpack_full():
			if not can_replace_artifact(id, outgoing, offer_id, revision): return false
			_remove_artifact(outgoing)
		elif not outgoing.is_empty(): return false
		artifact_revision += 1
	elif not outgoing.is_empty(): return false
	if not reward.upgrade_trait.is_empty():
		if reward_source()["kind"] != "boss": return false
		artifact_revision += 1
		trait_levels[reward.upgrade_trait] = reward.upgrade_rank
	else:
		encounter_picks[id] = int(encounter_picks.get(id, 0)) + 1
	_consume_reward_source(id)
	choices.clear()
	offer_exhausted = false
	# Immediate draw grants are applied once here; stat rebuilds never replay them.
	shots_left = mini(shots_left + reward.draws, 100000)
	rebuild_stats()
	phase = Phase.PLAYING
	if not offer_encounter(): changed.emit()
	return true

func open_skills() -> bool:
	if suspended or phase != Phase.PLAYING:
		return false
	if pending_encounters > 0:
		offer_encounter()
		return false
	phase = Phase.SHOP
	changed.emit()
	return true

func close_skills() -> void:
	if suspended or phase != Phase.SHOP:
		return
	phase = Phase.PLAYING
	changed.emit()

func can_buy(upgrade: RunSkillData) -> bool:
	if suspended or phase != Phase.SHOP or upgrade == null or SkillCatalog.find(upgrade.id) != upgrade:
		return false
	return skill_has_gain(upgrade) and gold >= skill_price(upgrade)

func buy(upgrade: RunSkillData) -> bool:
	if not can_buy(upgrade):
		return false
	var key: String = String(upgrade.id)
	var mastery: bool = skill_is_mastery(upgrade)
	var count: int = skill_rank(upgrade)
	_spend_gold(skill_price(upgrade), "mastery" if mastery else "basic")
	if mastery:
		if not mastery_unlocks.has(key): mastery_unlocks.append(key)
		mastery_levels[key] = count + 1
	else:
		skill_levels[key] = count + 1
	rebuild_stats()
	changed.emit()
	return true

func to_dict() -> Dictionary:
	_sync_reward_queue()
	return {
		"challenge_schema": 1, "challenge": challenge, "contract_stage_base_score": contract_stage_base_score, "contract_stage_bonus_earned": contract_stage_bonus_earned,
		"mode_schema": 1, "mode_id": mode_id, "mode_parameters": mode_parameters,
		"ranking_schema": 1, "ranking_processed": ranking_processed, "rank_at_finish": rank_at_finish, "ended_at": ended_at,
		"economy_schema": 1, "supply_parameters": supply_parameters.duplicate(),
		"supply_total_bought": supply_total_bought, "supply_segment_bought": supply_segment_bought,
		"supply_segment": supply_segment, "supply_offer_id": supply_offer_id,
		"gold_spent": gold_spent, "gold_spending": gold_spending.duplicate(),
		"trait_schema": 1, "trait_levels": trait_levels.duplicate(),
		"backpack_schema": 1, "artifact_capacity": artifact_capacity, "artifact_revision": artifact_revision,
		"discarded_artifacts": discarded_artifacts.duplicate(),
		"offer_exhausted": offer_exhausted,
		"boss_reward_schema": 1, "reward_queue": reward_queue.duplicate(true), "boss_reward_log": boss_reward_log.duplicate(true),
		"boss_schema": 1, "boss_round": boss_round, "bosses_defeated": bosses_defeated,
		"boss_next_defeats": boss_next_defeats, "boss_active": boss_active,
		"encounter_schema": 1, "encounter_picks": encounter_picks.duplicate(),
		"encounter_rewards_generated": encounter_rewards_generated, "encounter_offer_id": encounter_offer_id,
		"shot_sequence": shot_sequence, "last_settled_shot": last_settled_shot, "combo": combo,
		"skill_schema": 2, "legacy_skill_levels": legacy_skill_levels.duplicate(),
		"mastery_schema": 1, "mastery_levels": mastery_levels.duplicate(), "mastery_unlocks": mastery_unlocks.duplicate(),
		"starting_level": starting_level, "gold_earned": gold_earned,
		"phase": phase, "stage": stage, "shots_left": shots_left, "gold": gold,
		"gold_fraction": gold_fraction, "score": score, "prototype_total_score": prototype_total_score,
		"skill_levels": skill_levels.duplicate(), "encounters": encounters.duplicate(),
		"choices": choices.duplicate(), "rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"run_id": run_id, "ruleset": ruleset, "initial_shots": initial_shots,
		"talent_snapshot": talent_snapshot.duplicate(true), "defeated_count": defeated_count,
		"defeat_score": defeat_score, "difficulty_step": difficulty_step,
		"credited_defeats": credited_defeats.duplicate(), "seen_encounters": seen_encounters.duplicate(),
		"pending_encounters": pending_encounters, "suspended": suspended, "finished_reason": finished_reason,
	}

static func from_dict(data: Dictionary) -> RunModel:
	var result: RunModel = RunModel.new(str(data.get("mode_id", "normal")) if int(data.get("mode_schema", 0)) == 1 else "normal")
	if int(data.get("mode_schema", 0)) == 1 and data.get("mode_parameters") is Dictionary:
		for key: String in result._mode_parameters:
			result._mode_parameters[key] = float(data["mode_parameters"].get(key, result._mode_parameters[key]))
	if int(data.get("challenge_schema", 0)) == 1:
		result._challenge = ContractCatalog.snapshot(data.challenge.selection) if not data.get("challenge", {}).is_empty() else {}
		result.contract_stage_base_score = float(data.get("contract_stage_base_score", 0))
		result.contract_stage_bonus_earned = float(data.get("contract_stage_bonus_earned", 0))
	result.phase = clampi(int(data.get("phase", 0)), 0, Phase.SUPPLY) as Phase
	result.offer_exhausted = bool(data.get("offer_exhausted", false))
	result.stage = clampi(int(data.get("stage", 1)), 1, LEGACY_LAST_STAGE)
	result.initial_shots = clampi(int(data.get("initial_shots", INITIAL_SHOTS)), 1, 100000)
	result.shots_left = clampi(int(data.get("shots_left", 10)), 0, 100000)
	result.gold = clampi(int(data.get("gold", 0)), 0, 1000000000)
	result.gold_fraction = clampf(float(data.get("gold_fraction", 0.0)), 0.0, 0.999999)
	result.score = maxf(0.0, float(data.get("score", 0.0)))
	result.prototype_total_score = maxf(0.0, float(data.get("prototype_total_score", data.get("lifetime_score", 0.0))))
	var modern: bool = int(data.get("skill_schema", 0)) == 2
	var modern_encounters: bool = int(data.get("encounter_schema", 0)) == 1
	var saved: Dictionary = data.get("skill_levels", data.get("purchases", {}))
	if modern:
		for skill: RunSkillData in SkillCatalog.ALL:
			var rank: int = clampi(int(saved.get(String(skill.id), 0)), 0, skill.max_level)
			if rank > 0: result.skill_levels[String(skill.id)] = rank
	if modern and int(data.get("mastery_schema", 0)) == 1:
		for id: Variant in data.get("mastery_unlocks", []):
			if SkillCatalog.find(StringName(str(id))) != null and not result.mastery_unlocks.has(str(id)): result.mastery_unlocks.append(str(id))
		for skill: RunSkillData in SkillCatalog.ALL:
			var rank: int = clampi(int(data.get("mastery_levels", {}).get(String(skill.id), 0)), 0, skill.mastery_max_level)
			if rank > 0 and result.mastery_unlocks.has(String(skill.id)): result.mastery_levels[String(skill.id)] = rank
	var legacy: Dictionary = data.get("legacy_skill_levels", {}) if modern else saved
	for key: Variant in legacy:
		var upgrade: UpgradeData = GameCatalog.find_upgrade(StringName(key))
		if upgrade and not upgrade.random_only:
			result.legacy_skill_levels[String(key)] = clampi(int(legacy[key]), 0, upgrade.max_level)
	var old_encounters: Variant = data.get("encounters", data.get("blessings", []))
	if old_encounters is Array:
		for entry: Variant in old_encounters:
			var upgrade: UpgradeData = GameCatalog.find_upgrade(StringName(str(entry)))
			if upgrade and upgrade.random_only: result.encounters.append(str(entry))
	if modern_encounters:
		for id: Variant in data.get("choices", []):
			if EncounterCatalog.find(str(id)) != null and not result.choices.has(str(id)):
				result.choices.append(str(id))
		for reward: EncounterData in EncounterCatalog.ALL:
			# Keep ordinary stack history beyond 100k; effective stats have their own caps.
			var count: int = clampi(int(data.get("encounter_picks", {}).get(reward.id, 0)), 0, 1000000000)
			if reward.is_trait: count = mini(count, 1)
			if count > 0: result.encounter_picks[reward.id] = count
	if int(data.get("trait_schema", 0)) == 1:
		for id: String in TraitUpgradeCatalog.ALL:
			var rank: int = clampi(int(data.get("trait_levels", {}).get(id, 0)), 0, TraitUpgradeCatalog.find(id).max_level)
			if rank > 0 and result.encounter_picks.has(id): result.trait_levels[id] = rank
	if int(data.get("backpack_schema", 0)) == 1:
		result.artifact_capacity = int(data["artifact_capacity"])
		result.artifact_revision = int(data["artifact_revision"])
		for id: String in data["discarded_artifacts"]: result.discarded_artifacts[id] = int(data["discarded_artifacts"][id])
	else:
		# Legacy runs retain every owned artifact; new runs always start with six slots.
		result.artifact_capacity = maxi(ARTIFACT_SLOTS, result.artifact_ids().size())
	result.rng.seed = int(data.get("rng_seed", str(result.rng.seed)))
	result.rng.state = int(data.get("rng_state", str(result.rng.state)))
	result.run_id = str(data.get("run_id", result.run_id))
	result.ruleset = "continuous_v1"
	result.starting_level = maxi(1, int(data.get("starting_level", 1)))
	result.gold_earned = maxf(0.0, float(data.get("gold_earned", result.gold)))
	if str(data.get("ruleset", "prototype_v1")) != "continuous_v1":
		# Preserve unspent draws/build/currency; old hit scores never become kill XP.
		if result.phase in [Phase.SHOP, Phase.CHOICE]:
			result.phase = Phase.PLAYING
		result.choices.clear()
		result.score = float(data.get("defeat_score", 0.0))
	result.talent_snapshot = data.get("talent_snapshot", {}).duplicate(true)
	result.shot_sequence = maxi(0, int(data.get("shot_sequence", 0)))
	result.last_settled_shot = clampi(int(data.get("last_settled_shot", -1)), -1, result.shot_sequence)
	result.combo = maxi(0, int(data.get("combo", 0)))
	result.defeated_count = maxi(0, int(data.get("defeated_count", 0)))
	var boss_schema: bool = int(data.get("boss_schema", 0)) == 1
	# Existing kills establish a baseline; they never mint retroactive Boss fights.
	result.boss_round = maxi(0, int(data.get("boss_round", 0))) if boss_schema else result.defeated_count / BOSS_RULES.kills_per_boss
	result.bosses_defeated = clampi(int(data.get("bosses_defeated", 0)), 0, result.boss_round) if boss_schema else 0
	result.boss_next_defeats = int(data.get("boss_next_defeats", (result.boss_round + 1) * BOSS_RULES.kills_per_boss)) if boss_schema else (result.boss_round + 1) * BOSS_RULES.kills_per_boss
	result.boss_active = bool(data.get("boss_active", false)) if boss_schema else false
	result.defeat_score = maxf(0.0, float(data.get("defeat_score", 0.0)))
	result.difficulty_step = maxi(0, int(data.get("difficulty_step", result.defeated_count)))
	result.credited_defeats = data.get("credited_defeats", {}).duplicate(true)
	for id: Variant in data.get("seen_encounters", []):
		if id is String and not result.seen_encounters.has(id):
			result.seen_encounters.append(id)
	result.pending_encounters = maxi(0, int(data.get("pending_encounters", 0)))
	if int(data.get("boss_reward_schema", 0)) == 1:
		result.reward_queue.assign(data.get("reward_queue", []).duplicate(true))
		result.boss_reward_log.assign(data.get("boss_reward_log", []).duplicate(true))
	result._sync_reward_queue()
	result.encounter_rewards_generated = maxi(result.defeated_count / EncounterCatalog.RULES.kills_per_reward, int(data.get("encounter_rewards_generated", 0))) if modern_encounters else result.defeated_count / EncounterCatalog.RULES.kills_per_reward
	result.encounter_offer_id = maxi(0, int(data.get("encounter_offer_id", 0)))
	if not modern_encounters:
		# Old kills earned no modern encounters; never retroactively mint a reward.
		result.pending_encounters = 0
		result.reward_queue.clear()
		result.choices.clear()
		if result.phase == Phase.CHOICE: result.phase = Phase.PLAYING
	result.suspended = bool(data.get("suspended", false))
	result.finished_reason = str(data.get("finished_reason", ""))
	if int(data.get("ranking_schema", 0)) == 1:
		result.ranking_processed = bool(data.get("ranking_processed", false))
		result.rank_at_finish = int(data.get("rank_at_finish", 0))
		result.ended_at = int(data.get("ended_at", 0))
	else:
		# Legacy finished runs are never backfilled into the new board.
		result.ranking_processed = result.is_finished() or not result.finished_reason.is_empty()
	if int(data.get("economy_schema", 0)) == 1:
		result.supply_parameters = data["supply_parameters"].duplicate()
		for field: String in ["limit", "draws", "first_cost"]:
			result.supply_parameters[field] = int(result.supply_parameters[field])
		result.supply_parameters["growth"] = float(result.supply_parameters["growth"])
		for field: String in ["supply_total_bought", "supply_segment_bought", "supply_segment", "supply_offer_id", "gold_spent"]:
			result.set(field, int(data[field]))
		for category: String in result.gold_spending:
			result.gold_spending[category] = int(data["gold_spending"][category])
	else:
		result.supply_segment = result.bosses_defeated
		# Old ledgers have no categories; retain only reconstructable expenditure.
		var old_wallet: int = int(data.get("legacy_final_wallet", result.gold))
		result.gold_spent = maxi(0, floori(result.gold_earned) - old_wallet) if not result.is_finished() or data.has("legacy_final_wallet") else 0
		result.gold_spending["legacy"] = result.gold_spent
	if result.is_finished() and not result.finished_reason.is_empty():
		result.gold = 0
		result.gold_fraction = 0.0
	result.rebuild_stats()
	return result


