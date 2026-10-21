class_name ArcheryBoss
extends ArcheryTarget
## An ordinary swept target interface with a separate identity and reward ledger.

signal phase_changed(number: int)

var round_number: int = 1
var rules: BossRules
var combat_schema: int = 1 # 0 preserves an already-started v8 static fight.
var battle_phase: int = 1
var phase_clock: float = 0.0
var parameters: Dictionary = {}
var shield_position: Vector2
var shield_flash: float = 0.0
var impact_revision: int = 0
var volley_pressure: Dictionary = {}
const BURST_RATIO: float = 0.2

func configure_boss(config: BossRules, number: int, mode: Dictionary = {}) -> void:
	rules = config
	round_number = number
	parameters = config.combat_parameters()
	impact_revision = int(mode.get("boss_impact_revision", 0))
	volley_pressure.clear()
	var data := TargetData.new()
	data.id = &"mechanical_boss"
	data.title = rules.title
	data.radius = rules.radius
	data.movement = 0.0
	configure(data, Vector2(470, 205), 1, -1, mode)
	var sampled: Dictionary = rules.values(number, mode)
	max_hp = sampled["max_hp"]
	hp = max_hp
	armor = sampled["armor"]
	reward_score = sampled["reward_score"]
	reward_gold = sampled["reward_gold"]
	(collider.shape as RectangleShape2D).size = Vector2(rules.width, rules.radius * 2.0)
	_sync_pose()

func defeat_id() -> String:
	return "boss%d" % round_number

func receive_hit(stats: BowStats, strength: float, point: Vector2, roll: float) -> Dictionary:
	return receive_contact(stats, strength, point, roll, "body")

func receive_contact(stats: BowStats, strength: float, point: Vector2, roll: float, part: String, shot_id: int = 0) -> Dictionary:
	if hp <= 0: return {}
	if combat_schema == 0:
		var old: Dictionary = super.receive_hit(stats, strength, point, roll)
		old["is_boss"] = true
		return old
	if part == "shield":
		shield_flash = 1.0
		queue_redraw()
		return {"raw": 0.0, "effective": 0.0, "critical": false, "bullseye": false,
			"pierced": stats.armor_penetration > shield_armor(), "broken": false,
			"armor_blocked": maxi(0, shield_armor() - stats.armor_penetration),
			"event_id": defeat_id() + ":shield", "reward_score": 0.0, "reward_gold": 0.0,
			"is_boss": true, "boss_part": "shield", "can_split": false}
	# Large arrowheads do not enlarge the gold weak spot's center test.
	var weak: bool = is_bullseye(point)
	var shot: BowStats = stats.duplicate() as BowStats
	if weak: shot.damage *= float(parameters["weak_multiplier"])
	var hit_armor: int = maxi(0, armor - int(parameters["weak_armor_reduction"])) if weak else armor
	var hit: Dictionary = CombatMath.resolve_hit(shot, strength, weak, INF, roll, hit_armor)
	_apply_resilience(hit, shot_id)
	hp = maxf(0.0, hp - float(hit["effective"]))
	hit["broken"] = hp <= 0
	hit["event_id"] = defeat_id()
	hit["reward_score"] = reward_score if hp <= 0 else 0.0
	hit["reward_gold"] = reward_gold if hp <= 0 else 0.0
	hit["is_boss"] = true
	hit["boss_part"] = "weak" if weak else "body"
	hit["excluded_slots"] = [-1, -3] # Body and weak point share one HP hit per arrow.
	flash = 1.0
	if hp <= 0:
		TargetBreakup.spawn_from(self)
		respawn_left = RULES.respawn_seconds
		set_deferred("collision_layer", 0)
	else: refresh_phase()
	queue_redraw()
	return hit

func is_bullseye(point: Vector2) -> bool:
	if combat_schema == 0: return super.is_bullseye(point)
	return absf(point.y - global_position.y) <= float(parameters["weak_half_height"]) * global_scale.y

func receive_area(damage: float, penetration: int, shot_id: int = 0) -> Dictionary:
	if hp <= 0: return {}
	var shot := BowStats.new()
	shot.damage = damage
	shot.crit_chance = 0.0
	shot.armor_penetration = penetration
	var hit: Dictionary = CombatMath.resolve_hit(shot, 1.0, false, INF, 1.0, armor)
	_apply_resilience(hit, shot_id)
	hit["pierced"] = false
	hit["can_split"] = false
	hit["damage_kind"] = "area"
	hit = apply_hit(hit)
	if hit.is_empty(): return hit
	hit["is_boss"] = true
	hit["boss_part"] = "body"
	hit["excluded_slots"] = [-1, -3]
	refresh_phase()
	return hit

func _apply_resilience(hit: Dictionary, shot_id: int) -> void:
	var incoming: float = float(hit["effective"])
	if impact_revision == 1:
		var key: String = str(shot_id)
		var previous: float = float(volley_pressure.get(key, 0.0))
		hit["effective"] = BossRules.resilient_damage(previous, incoming, max_hp * BURST_RATIO)
		volley_pressure[key] = previous + incoming
		hit["resisted"] = maxf(0.0, incoming - float(hit["effective"]))
	hit["effective"] = minf(hp, float(hit["effective"]))

func contact_armor(point: Vector2, part: String) -> int:
	if combat_schema == 0: return armor
	if part == "shield": return shield_armor()
	var weak: bool = is_bullseye(point)
	return maxi(0, armor - int(parameters["weak_armor_reduction"])) if weak else armor

func shield_armor() -> int:
	return armor + int(parameters["shield_armor_bonus"])

func refresh_phase() -> void:
	if combat_schema == 1 and hp > 0 and battle_phase == 1 and hp <= max_hp * float(parameters["phase_health_ratio"]):
		battle_phase = 2
		phase_clock = 0.0
		_sync_pose()
		phase_changed.emit(2)

func tick(delta: float, _clock: float) -> void:
	flash = maxf(0.0, flash - delta * 5.0)
	shield_flash = maxf(0.0, shield_flash - delta * 5.0)
	respawn_left = maxf(0.0, respawn_left - delta)
	if combat_schema == 1 and battle_phase == 2 and hp > 0:
		phase_clock += delta
		_sync_pose()
	queue_redraw()

func _sync_pose() -> void:
	var moving: bool = combat_schema == 1 and battle_phase == 2
	position = anchor + Vector2(0, sin(phase_clock * float(parameters["body_frequency"])) * float(parameters["body_amplitude"]) if moving else 0.0)
	shield_position = position + Vector2(-float(parameters["body_width"]) * 0.5 - float(parameters["shield_width"]) * 0.5 - float(parameters["shield_gap"]), sin(phase_clock * float(parameters["shield_frequency"])) * float(parameters["shield_amplitude"]) if moving else 0.0)

func collision_volumes() -> Array[Dictionary]:
	if combat_schema == 0: return super.collision_volumes()
	var half := Vector2(float(parameters["body_width"]) * 0.5, float(parameters["body_radius"]))
	var result: Array[Dictionary] = []
	if battle_phase == 2:
		var shield_half := Vector2(float(parameters["shield_width"]), float(parameters["shield_height"])) * 0.5
		result.append({"slot": -2, "part": "shield", "rect": Rect2(shield_position - shield_half, shield_half * 2)})
	result.append({"slot": -3, "part": "weak", "rect": Rect2(position + Vector2(-half.x - 2, -float(parameters["weak_half_height"])), Vector2(half.x * 2 + 4, float(parameters["weak_half_height"]) * 2))})
	result.append({"slot": -1, "part": "body", "rect": Rect2(position - half, half * 2)})
	return result

static func upgrade_state(state: Dictionary) -> Dictionary:
	var upgraded: Dictionary = state.duplicate(true)
	if not upgraded.has("health_revision"):
		upgraded["hp"] = float(upgraded.get("hp", 0)) * 3.0
		upgraded["max_hp"] = float(upgraded.get("max_hp", 960)) * 3.0
		upgraded["health_revision"] = 2
	if upgraded.has("combat_schema"): return upgraded
	var config: BossRules = preload("res://data/boss_rules.tres")
	upgraded["combat_schema"] = 0
	upgraded["battle_phase"] = 1
	upgraded["phase_clock"] = 0.0
	upgraded["combat_parameters"] = config.combat_parameters()
	var origin: Array = upgraded.get("anchor", [470, 205])
	upgraded["body_position"] = origin.duplicate()
	upgraded["shield_position"] = [float(origin[0]) - config.width * 0.5 - config.shield_width * 0.5 - config.shield_gap, origin[1]]
	return upgraded

func snapshot() -> Dictionary:
	var state: Dictionary = super.snapshot()
	state["round_number"] = round_number
	state["health_revision"] = 2
	state["impact_revision"] = impact_revision
	state["volley_pressure"] = volley_pressure.duplicate()
	state["combat_schema"] = combat_schema
	state["battle_phase"] = battle_phase
	state["phase_clock"] = phase_clock
	state["combat_parameters"] = parameters.duplicate()
	state["body_position"] = [position.x, position.y]
	state["shield_position"] = [shield_position.x, shield_position.y]
	return state

func restore(state: Dictionary) -> void:
	var upgraded: Dictionary = upgrade_state(state)
	super.restore(upgraded)
	impact_revision = int(upgraded.get("impact_revision", 0))
	volley_pressure = upgraded.get("volley_pressure", {}).duplicate()
	combat_schema = int(upgraded["combat_schema"])
	battle_phase = int(upgraded["battle_phase"])
	phase_clock = float(upgraded["phase_clock"])
	parameters = upgraded["combat_parameters"].duplicate()
	definition.radius = float(parameters["body_radius"])
	(collider.shape as RectangleShape2D).size = Vector2(float(parameters["body_width"]), definition.radius * 2)
	var body: Array = upgraded["body_position"]
	position = Vector2(body[0], body[1])
	var shield: Array = upgraded["shield_position"]
	shield_position = Vector2(shield[0], shield[1])

func _draw() -> void:
	if rules == null or collider == null: return
	TargetArt.boss(self, self)
