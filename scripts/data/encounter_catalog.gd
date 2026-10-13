class_name EncounterCatalog
extends RefCounted

const RULES: EncounterRules = preload("res://data/encounter_rules.tres")
const CHOICE_COUNT: int = 3
const ALL: Array[EncounterData] = [
	preload("res://data/encounters/windfall.tres"),
	preload("res://data/encounters/rainfall.tres"),
	preload("res://data/encounters/second_wind.tres"),
	preload("res://data/encounters/steady_power.tres"),
	preload("res://data/encounters/tempered_tip.tres"),
	preload("res://data/encounters/quick_nock.tres"),
	preload("res://data/encounters/piercing_split.tres"),
	preload("res://data/encounters/ricochet_haste.tres"),
	preload("res://data/encounters/swarm_precision.tres"),
	preload("res://data/encounters/unified_arrow.tres"),
	preload("res://data/encounters/critical_forging.tres"),
	preload("res://data/encounters/critical_ricochet.tres"),
	preload("res://data/encounters/piercing_edge.tres"),
	preload("res://data/encounters/armor_surplus.tres"),
	preload("res://data/encounters/echo_strike.tres"),
	preload("res://data/encounters/wall_forging.tres"),
	preload("res://data/encounters/charged_breach.tres"),
	preload("res://data/encounters/bullseye_wave.tres"),
	preload("res://data/encounters/critical_flow.tres"),
	preload("res://data/encounters/broad_precision.tres"),
	preload("res://data/encounters/branch_harvest.tres"),
	preload("res://data/encounters/branch_ricochet.tres"),
	preload("res://data/encounters/slender_gale.tres"),
	preload("res://data/encounters/heavy_draw.tres"),
]

static func find(id: String) -> EncounterData:
	var upgrade: Dictionary = TraitUpgradeCatalog.decode(id)
	if not upgrade.is_empty():
		var reward: EncounterData = find(upgrade["id"]).duplicate() as EncounterData
		reward.id = id
		reward.upgrade_trait = upgrade["id"]
		reward.upgrade_rank = upgrade["rank"]
		reward.title += " · 强化"
		reward.is_trait = false
		reward.has_debuff = false
		reward.trait_key = ""
		reward.group = "upgrade:" + upgrade["id"]
		return reward
	for reward: EncounterData in ALL:
		if reward.id == id: return reward
	return null

static func draft(random: RandomNumberGenerator, seen: Array[String], pool: Array[EncounterData], eligible: Callable = Callable()) -> Array[String]:
	# Canonical ordinary rewards fill a depleted pool, with unique IDs and groups.
	var unique: Dictionary = {}
	var fallback: Array[EncounterData] = []
	for reward: EncounterData in ALL:
		if not reward.is_trait: fallback.append(reward)
	for reward: EncounterData in fallback + pool:
		if reward != null and eligible.is_valid() and not eligible.call(reward): continue
		if reward != null and not reward.id.is_empty() and not unique.has(reward.id) and not (reward.is_trait and seen.has(reward.id)):
			unique[reward.id] = reward
	var safe: Array[EncounterData] = []
	var available: Array[EncounterData] = []
	for reward: EncounterData in unique.values():
		available.append(reward)
		if not reward.is_trait and not reward.has_debuff: safe.append(reward)
	# Never offer only costly traits or index an empty/depleted pool.
	if safe.is_empty(): return []
	var selected: Array[EncounterData] = [safe[random.randi_range(0, safe.size() - 1)]]
	while selected.size() < CHOICE_COUNT:
		var remaining: Array[EncounterData] = []
		for reward: EncounterData in available:
			var allowed: bool = true
			for picked: EncounterData in selected:
				if picked.id == reward.id or picked.candidate_group() == reward.candidate_group(): allowed = false
			if allowed: remaining.append(reward)
		if remaining.is_empty(): break
		selected.append(remaining[random.randi_range(0, remaining.size() - 1)])
	# Shuffle card positions as well; reserve traits when shown, even if unchosen.
	for index: int in range(selected.size() - 1, 0, -1):
		var other: int = random.randi_range(0, index)
		var temporary: EncounterData = selected[index]
		selected[index] = selected[other]
		selected[other] = temporary
	var ids: Array[String] = []
	for reward: EncounterData in selected:
		ids.append(reward.id)
		if reward.is_trait: seen.append(reward.id)
	return ids
