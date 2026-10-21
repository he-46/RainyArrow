class_name Arrow
extends Node2D
var cosmetic: CosmeticData = CosmeticCatalog.default_for("arrow")
## Sweeps arrowhead volume, resolving ordered contacts and unused step time.

signal struck(target: ArcheryTarget, point: Vector2, hit: Dictionary)
signal bounced(point: Vector2, normal: Vector2)
signal expired(arrow: Arrow)
signal split_requested(arrow: Arrow)
signal area_requested(arrow: Arrow, primary: ArcheryTarget, point: Vector2, damage: float, penetration: int)

const FIELD := Rect2(8, 54, 624, 254)
const MAX_CONTACTS: int = 64
const MAX_LIFETIME: float = 12.0
var velocity: Vector2
var stats: BowStats
var pull: float = 1.0
var rng: RandomNumberGenerator
var elapsed: float = 0.0
var hit_slots: Array[int] = []
var remaining_bounces: int = 0
var done: bool = false
var trail: Array[Vector2] = []
var shot_id: int = 0
var source_id: int = 0
var parent_source_id: int = -1
var effects: ArrowEffects = ArrowEffects.new()
var split_spent: bool = false
var split_pending: bool = false
var split_exit_rect: Rect2 = Rect2()
var penetration_stacks: int = 0
var bounce_stacks: int = 0
var echo_ready: bool = false
var critical_stacks: int = 0
var area_slots: Array[int] = []
var active_effect: String = ""
var active_target: String = ""
# Each overlapping volume has its own captured exit, independent of respawns.
var penetration_exits: Array[Dictionary] = []

func setup(origin: Vector2, initial_velocity: Vector2, bow: BowStats, strength: float, random: RandomNumberGenerator) -> void:
	position = origin
	velocity = initial_velocity
	stats = bow.duplicate() as BowStats
	pull = strength
	rng = random
	remaining_bounces = stats.bounces
	rotation = velocity.angle()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if done: return
	elapsed += delta
	var remaining: float = delta
	var radius: float = stats.collision_radius()
	var allowed: Rect2 = FIELD.grow(-radius)
	position = position.clamp(allowed.position, allowed.end)
	for iteration: int in range(MAX_CONTACTS):
		if remaining <= 0.0000001: break
		var step: Vector2 = CombatMath.displacement(velocity, stats.gravity, remaining)
		var contact: Dictionary = SweepMath.boundary(position, step, allowed)
		if split_pending:
			var exit: Dictionary = SweepMath.boundary(position, step, split_exit_rect) if split_exit_rect.has_point(position) else {"fraction": 0.0}
			if not exit.is_empty() and (contact.is_empty() or float(exit["fraction"]) < float(contact["fraction"])):
				contact = exit
				contact["split_exit"] = true
		for exit_index: int in range(penetration_exits.size()):
			var rect: Rect2 = _exit_rect(penetration_exits[exit_index])
			var exit: Dictionary = SweepMath.boundary(position, step, rect) if rect.has_point(position) else {"fraction": 0.0}
			# Apply a same-edge penetration gain before spawning split children.
			if not exit.is_empty() and (contact.is_empty() or float(exit["fraction"]) <= float(contact["fraction"])):
				contact = exit
				contact["penetration_exit"] = exit_index
		for node: Node in get_tree().get_nodes_in_group("archery_targets"):
			var target := node as ArcheryTarget
			if target.get_parent() != get_parent() or target.hp <= 0.0: continue
			# Ordinary targets have one lifetime slot. Avoid allocating their volume
			# dictionaries again after this arrow has already resolved that slot.
			# Boss parts keep independent shield/core/body exclusions below.
			if not target is ArcheryBoss and hit_slots.has(target.slot): continue
			# Field targets and arrows share unrotated local coordinates, including scale=2.
			for volume: Dictionary in target.collision_volumes():
				if hit_slots.has(int(volume["slot"])): continue
				var hit: Dictionary = SweepMath.circle_rect(position, step, radius, volume["rect"])
				if not hit.is_empty() and (contact.is_empty() or float(hit["fraction"]) < float(contact["fraction"])):
					contact = hit
					contact["target"] = target
					contact["volume"] = volume
		if contact.is_empty():
			position += step
			velocity.y += stats.gravity * remaining
			remaining = 0.0
			break
		var fraction: float = float(contact["fraction"])
		var consumed: float = remaining * fraction
		position += step * fraction
		velocity.y += stats.gravity * consumed
		remaining -= consumed
		if contact.has("penetration_exit"):
			penetration_exits.remove_at(int(contact["penetration_exit"]))
			penetration_stacks = mini(penetration_stacks + 1, effects.penetration_limit)
		elif contact.has("split_exit"):
			split_pending = false
			position += velocity.normalized() * 0.0001
			split_requested.emit(self)
		elif contact.has("target"):
			var target: ArcheryTarget = contact["target"]
			var volume: Dictionary = contact["volume"]
			hit_slots.append(int(volume["slot"]))
			var part: String = str(volume["part"])
			var shot: BowStats = contact_stats(target, global_position, part)
			var result: Dictionary = target.receive_contact(shot, pull, global_position, rng.randf(), part, shot_id)
			if not result.is_empty():
				result["active_boosted"] = active_effect == "sunshot" or (active_effect == "hunters_mark" and active_target == target.defeat_id())
				if float(result["effective"]) > 0:
					result["trait_boosted"] = shot.damage > stats.damage
					echo_ready = false
					if bool(result["critical"]): critical_stacks = mini(critical_stacks + 1, effects.critical_limit)
					if bool(result["pierced"]) and penetration_stacks + penetration_exits.size() < effects.penetration_limit:
						var rect: Rect2 = (volume["rect"] as Rect2).grow(radius)
						penetration_exits.append({"slot": int(volume["slot"]), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
				for excluded: int in result.get("excluded_slots", []):
					if not hit_slots.has(excluded): hit_slots.append(excluded)
				struck.emit(target, global_position, result)
				if float(result["effective"]) > 0.0 and bool(result["bullseye"]) and effects.bullseye_damage > 0.0:
					area_requested.emit(self, target, global_position, float(result["effective"]) * effects.bullseye_damage, shot.armor_penetration)
				if bool(result["pierced"]) and bool(result.get("can_split", true)) and effects.split_count > 0 and not split_spent:
					split_spent = true
					split_pending = true
					# Capture the impacted target volume; spawn after the head leaves its far edge.
					split_exit_rect = (volume["rect"] as Rect2).grow(radius)
				if not bool(result["pierced"]):
					_finish()
					return
		else:
			if remaining_bounces <= 0:
				_finish()
				return
			remaining_bounces -= 1
			echo_ready = effects.echo_damage > 0.0
			bounce_stacks = mini(bounce_stacks + 1, effects.bounce_penetration_limit)
			var normal: Vector2 = contact["normal"]
			if normal.x != 0.0: velocity.x = -velocity.x
			if normal.y != 0.0: velocity.y = -velocity.y
			if effects.bounce_multiplier > 1.0:
				velocity = (velocity * effects.bounce_multiplier).limit_length(effects.speed_limit)
			position += normal * 0.0001
			bounced.emit(global_position, normal.normalized())
	if remaining > 0.0000001 or elapsed >= MAX_LIFETIME:
		_finish()
	rotation = velocity.angle()
	trail.push_front(position)
	if trail.size() > 10: trail.pop_back()
	# Flight changes the CanvasItem transform, not the cached arrow geometry.
	# World draws the moving trail separately; setup/equipment invalidate the body.

func snapshot() -> Dictionary:
	return {"shot_id": shot_id, "source_id": source_id, "parent_source_id": parent_source_id,
		"active_effect": active_effect, "active_target": active_target,
		"combat_schema": 3, "critical_stacks": critical_stacks, "area_slots": area_slots.duplicate(),
		"penetration_stacks": penetration_stacks, "bounce_stacks": bounce_stacks,
		"echo_ready": echo_ready, "penetration_exits": penetration_exits.duplicate(true),
		"effects": effects.to_dict(), "split_spent": split_spent, "split_pending": split_pending,
		"split_exit_rect": [split_exit_rect.position.x, split_exit_rect.position.y, split_exit_rect.size.x, split_exit_rect.size.y],
		"position": [position.x, position.y], "velocity": [velocity.x, velocity.y],
		"stats": stats.to_dict(), "pull": pull, "elapsed": elapsed,
		"hit_slots": hit_slots.duplicate(), "remaining_bounces": remaining_bounces}

func restore(data: Dictionary, random: RandomNumberGenerator) -> void:
	active_effect = str(data.get("active_effect", ""))
	active_target = str(data.get("active_target", ""))
	critical_stacks = int(data.get("critical_stacks", 0))
	area_slots.assign(data.get("area_slots", []))
	penetration_stacks = int(data.get("penetration_stacks", 0))
	bounce_stacks = int(data.get("bounce_stacks", 0))
	echo_ready = bool(data.get("echo_ready", false))
	penetration_exits.assign(data.get("penetration_exits", []).duplicate(true))
	for crossing: Dictionary in penetration_exits: crossing["slot"] = int(crossing["slot"])
	shot_id = int(data.get("shot_id", 0))
	source_id = int(data.get("source_id", 0))
	parent_source_id = int(data.get("parent_source_id", -1))
	effects = ArrowEffects.from_dict(data.get("effects", {}))
	split_spent = bool(data.get("split_spent", false))
	split_pending = bool(data.get("split_pending", false))
	var rect: Array = data.get("split_exit_rect", [0, 0, 0, 0])
	split_exit_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
	setup(Vector2(data["position"][0], data["position"][1]), Vector2(data["velocity"][0], data["velocity"][1]), BowStats.from_dict(data["stats"]), float(data["pull"]), random)
	elapsed = float(data["elapsed"])
	remaining_bounces = int(data["remaining_bounces"])
	hit_slots.assign(data["hit_slots"])

func contact_stats(target: ArcheryTarget, point: Vector2, part: String) -> BowStats:
	var shot: BowStats = stats.duplicate() as BowStats
	var charged: int = int(floorf(clampf(pull, 0.0, 1.0) * effects.charged_penetration + 1.0e-9))
	shot.armor_penetration = mini(1000000, stats.armor_penetration + bounce_stacks * effects.bounce_penetration + charged)
	if active_effect == "sunshot": shot.armor_penetration = mini(1000000, shot.armor_penetration + 12)
	if part != "shield":
		if active_effect == "sunshot": shot.damage *= 2.0
		elif active_effect == "hunters_mark" and target.defeat_id() == active_target: shot.damage *= 1.6
		var surplus: int = maxi(0, shot.armor_penetration - target.contact_armor(point, part))
		shot.damage *= (1.0 + penetration_stacks * effects.penetration_damage)
		shot.damage *= (1.0 + critical_stacks * effects.critical_damage)
		shot.damage *= (1.0 + minf(surplus * effects.excess_damage, effects.excess_limit))
		if echo_ready: shot.damage *= 1.0 + effects.echo_damage
		if target.is_bullseye(point):
			shot.damage *= 1.0 + minf(maxf(stats.arrow_size - 1.0, 0.0) * effects.size_bullseye, effects.size_bullseye_limit)
	return shot

func inherit_combat(parent: Arrow) -> void:
	active_effect = parent.active_effect
	active_target = parent.active_target
	penetration_stacks = parent.penetration_stacks
	bounce_stacks = parent.bounce_stacks
	echo_ready = parent.echo_ready
	critical_stacks = parent.critical_stacks
	area_slots.assign(parent.area_slots)
	# Unfinished crossings belong to the parent; a child never hit those volumes.
	penetration_exits.clear()

static func _exit_rect(record: Dictionary) -> Rect2:
	var rect: Array = record["rect"]
	return Rect2(rect[0], rect[1], rect[2], rect[3])

static func upgrade_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	if not result.has("combat_schema"):
		result["combat_schema"] = 1
		result["penetration_stacks"] = 0
		result["bounce_stacks"] = 0
		result["echo_ready"] = false
		result["penetration_exits"] = []
		result["effects"] = ArrowEffects.from_dict(result.get("effects", {})).to_dict()
	if int(result.get("combat_schema", 0)) == 1:
		result["combat_schema"] = 2
		result["critical_stacks"] = 0
		result["area_slots"] = []
		result["effects"] = ArrowEffects.from_dict(result.get("effects", {})).to_dict()
	if int(result.get("combat_schema", 0)) == 2:
		result["combat_schema"] = 3
		result["effects"] = ArrowEffects.from_dict(result.get("effects", {})).to_dict()
	return result

func _finish() -> void:
	if done: return
	done = true
	expired.emit(self)
	queue_free()

func _draw() -> void:
	if stats == null: return
	CosmeticDrawing.arrow(self, cosmetic, Vector2.ZERO, stats.arrow_size, parent_source_id >= 0, stats.collision_radius())
	match active_effect:
		"sunshot":
			draw_line(Vector2(-12, 0), Vector2.ZERO, Color("ffdc83"), 1)
			draw_rect(Rect2(-1, -1, 2, 2), Color("fff1bc"))
		"quickdraw":
			for y: int in [-2, 2]: draw_line(Vector2(-14, y), Vector2(-7, y), Color("a8dce5"), 1)
		"hunters_mark": draw_line(Vector2(-10, 0), Vector2(-4, 0), Color("a4e2c0"), 2)
