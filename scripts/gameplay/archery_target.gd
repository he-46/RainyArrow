class_name ArcheryTarget
extends Area2D

const RULES: FieldRules = preload("res://data/field_rules.tres")

var difficulty_parameters: Dictionary = {}
var definition: TargetData
var hp: float
var max_hp: float
var anchor: Vector2
var motion_phase: float = 0.0
var respawn_left: float = 0.0
var flash: float = 0.0
var slot: int = 0
var generation: int = 0
var spawn_difficulty: int = 0
var armor: int = 0
var reward_score: float = 0.0
var reward_gold: float = 0.0
var collider: CollisionShape2D

func _ready() -> void:
	add_to_group("archery_targets")

func configure(data: TargetData, origin: Vector2, stage: int, index: int, mode: Dictionary = {}) -> void:
	difficulty_parameters = mode.duplicate()
	definition = data
	anchor = origin
	position = origin
	slot = index
	motion_phase = float(index) * 1.6
	collision_layer = 2
	collision_mask = 0
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(14.0, definition.radius * 2.0)
	collider = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	spawn(data, 0, false)
	# Only legacy snapshots use this old stage health multiplier.
	max_hp *= 1.0 + float(stage - 1) * 0.13
	hp = max_hp

func spawn(data: TargetData, difficulty: int, next_life: bool = true) -> void:
	definition = data
	if next_life:
		generation += 1
	var values: Dictionary = RULES.target_values(data, difficulty, difficulty_parameters)
	max_hp = values["max_hp"]
	armor = values["armor"]
	reward_score = values["reward_score"]
	reward_gold = values["reward_gold"]
	spawn_difficulty = values["spawn_difficulty"]
	hp = max_hp
	respawn_left = 0.0
	collision_layer = 2
	(collider.shape as RectangleShape2D).size = Vector2(14.0, data.radius * 2.0)
	queue_redraw()

func defeat_id() -> String:
	return "slot%d-life%d" % [slot, generation]

func tick(delta: float, clock: float) -> void:
	flash = maxf(flash - delta * 5.0, 0.0)
	position = anchor + Vector2(0.0, sin(clock * 1.6 + motion_phase) * definition.movement)
	position.y = clampf(position.y, 56.0 + definition.radius * scale.y, 306.0 - definition.radius * scale.y)
	if respawn_left > 0.0:
		respawn_left = maxf(0.0, respawn_left - delta)
	queue_redraw()

func receive_hit(stats: BowStats, pull: float, point: Vector2, roll: float) -> Dictionary:
	if hp <= 0.0:
		return {}
	var bullseye: bool = is_bullseye(point)
	var result: Dictionary = CombatMath.resolve_hit(stats, pull, bullseye, hp, roll, armor)
	return apply_hit(result)

func is_bullseye(point: Vector2) -> bool:
	return absf(point.y - global_position.y) <= definition.radius * 0.26 * global_scale.y * float(difficulty_parameters.get("bullseye_scale", 1.0))

func receive_area(damage: float, penetration: int, _shot_id: int = 0) -> Dictionary:
	if hp <= 0.0: return {}
	var shot := BowStats.new()
	shot.damage = damage
	shot.crit_chance = 0.0
	shot.armor_penetration = penetration
	var hit: Dictionary = CombatMath.resolve_hit(shot, 1.0, false, hp, 1.0, armor)
	hit["pierced"] = false
	hit["can_split"] = false
	hit["damage_kind"] = "area"
	return apply_hit(hit)

func apply_hit(result: Dictionary) -> Dictionary:
	hp = maxf(hp - float(result["effective"]), 0.0)
	result["broken"] = hp <= 0.0
	result["event_id"] = defeat_id()
	result["reward_score"] = reward_score if hp <= 0.0 else 0.0
	result["reward_gold"] = reward_gold if hp <= 0.0 else 0.0
	flash = 1.0
	if hp <= 0.0:
		TargetBreakup.spawn_from(self)
		respawn_left = RULES.respawn_seconds
		set_deferred("collision_layer", 0)
	queue_redraw()
	return result

func collision_volumes() -> Array[Dictionary]:
	var half: Vector2 = (collider.shape as RectangleShape2D).size * scale * 0.5
	return [{"slot": slot, "part": "body", "rect": Rect2(position - half, half * 2)}]

func contact_armor(_point: Vector2, _part: String) -> int:
	return armor

func receive_contact(stats: BowStats, pull: float, point: Vector2, roll: float, _part: String, _shot_id: int = 0) -> Dictionary:
	return receive_hit(stats, pull, point, roll)

func snapshot() -> Dictionary:
	return {
		"anchor": [anchor.x, anchor.y], "target_scale": scale.x,
		"hp": hp, "respawn_left": respawn_left, "max_hp": max_hp,
		"kind": String(definition.id), "generation": generation, "armor": armor,
		"spawn_difficulty": spawn_difficulty, "reward_score": reward_score, "reward_gold": reward_gold,
	}

func restore(data: Dictionary) -> void:
	var origin: Array = data.get("anchor", [anchor.x, anchor.y])
	anchor = Vector2(origin[0], origin[1])
	scale = Vector2.ONE * clampf(float(data.get("target_scale", scale.x)), 1.0, 3.0)
	for kind: TargetData in GameCatalog.TARGETS:
		if String(kind.id) == str(data.get("kind", "")):
			definition = kind
	(collider.shape as RectangleShape2D).size = Vector2(14.0, definition.radius * 2.0)
	max_hp = maxf(1.0, float(data.get("max_hp", max_hp)))
	generation = maxi(0, int(data.get("generation", 0)))
	armor = maxi(0, int(data.get("armor", 0)))
	spawn_difficulty = maxi(0, int(data.get("spawn_difficulty", 0)))
	reward_score = maxf(0.0, float(data.get("reward_score", definition.defeat_score)))
	reward_gold = maxf(0.0, float(data.get("reward_gold", definition.break_gold)))
	hp = clampf(float(data.get("hp", max_hp)), 0.0, max_hp)
	respawn_left = clampf(float(data.get("respawn_left", 0.0)), 0.0, RULES.respawn_seconds)
	if hp <= 0.0:
		collision_layer = 0

func _draw() -> void:
	if definition == null or collider == null: return
	TargetArt.ordinary(self, self)
