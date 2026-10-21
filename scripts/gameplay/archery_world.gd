class_name ArcheryWorld
extends Node2D

signal volley_settled
signal feedback(cue: String, pitch: float)
signal shot_settled(shot_id: int, hits: Array)
signal draw_released(shot_id: int)

const BOW: Vector2 = Vector2(104, 238)
const MAX_SPLIT_CHILDREN: int = 64
var run: RunModel
var targets: Array[ArcheryTarget] = []
var boss: ArcheryBoss
var boss_enabled: bool = true # Disposable practice worlds never enter a Boss fight.
var field_generation: int = 0
var arrows: Array[Arrow] = []
var labels: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var area_rings: Array[Dictionary] = []
var vfx: CombatVFX
var reduced_effects: bool = false
var clock: float = 0.0
var reload_left: float = 0.0
var dragging: bool = false
var pull: float = 0.0
var direction: Vector2 = Vector2(1, -0.2).normalized()
var recoiling: float = 0.0
var cast_pose_left: float = 0.0
var visual_reload_duration: float = 0.65
var waiting_for_settle: bool = false
var cosmetic_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var ui_blocked: bool = false
var appearance: Dictionary = {}
var trajectory_guide: bool = true
var screen_shake: bool = true
var shake_strength: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var rest_canvas: Transform2D = Transform2D.IDENTITY
var pending_volleys: Dictionary = {}
var projectile_ledger: Dictionary = {} # Per shot: next unique source and total spawned children.

func _ready() -> void:
	cosmetic_rng.randomize()
	rest_canvas = get_viewport().canvas_transform
	add_child(ForestBackdrop.new())
	vfx = CombatVFX.new()
	add_child(vfx)

func apply_settings(options: Dictionary) -> void:
	reduced_effects = bool(options.get("reduced_effects", false))
	if vfx != null: vfx.configure(reduced_effects)
	if reduced_effects:
		particles.clear()
		area_rings.clear()
		for child: Node in get_children():
			if child is TargetBreakup: child.queue_free()
	trajectory_guide = bool(options["trajectory_guide"])
	screen_shake = bool(options["screen_shake"])
	if not screen_shake: reset_shake()
	queue_redraw()

func apply_cosmetics(loadout: Dictionary) -> void:
	var updated: Dictionary = {}
	for slot: String in CosmeticCatalog.SLOTS:
		updated[slot] = CosmeticCatalog.equipped(loadout, slot).id
	appearance = updated
	for arrow: Arrow in arrows:
		arrow.cosmetic = CosmeticCatalog.equipped(appearance, "arrow")
		arrow.queue_redraw()
	queue_redraw()

func reset_shake() -> void:
	shake_strength = 0.0
	shake_offset = Vector2.ZERO
	if is_inside_tree(): get_viewport().canvas_transform = rest_canvas

func _exit_tree() -> void:
	reset_shake()

func _aim_position(viewport_position: Vector2) -> Vector2:
	# Cancel visual translation before mapping aim; physics/input never shake.
	return get_global_transform_with_canvas().affine_inverse() * (viewport_position + get_global_transform().basis_xform(shake_offset))

func _kick_shake(broken: bool) -> void:
	if screen_shake: shake_strength = maxf(shake_strength, 3.0 if broken else 1.3)

func _update_shake(delta: float) -> void:
	shake_strength = maxf(0.0, shake_strength - delta * 15.0)
	shake_offset = Vector2(sin(clock * 113.0 + 0.8), cos(clock * 137.0)) * shake_strength if screen_shake else Vector2.ZERO
	get_viewport().canvas_transform = rest_canvas.translated(get_global_transform().basis_xform(shake_offset))

func build_field(saved: Dictionary = {}) -> void:
	for arrow: Arrow in arrows:
		remove_child(arrow)
		arrow.queue_free()
	arrows.clear()
	if boss != null:
		remove_child(boss)
		boss.queue_free()
		boss = null
	for target: ArcheryTarget in targets:
		remove_child(target)
		target.queue_free()
	targets.clear()
	labels.clear()
	particles.clear()
	area_rings.clear()
	if vfx != null:
		vfx.events.clear()
		vfx.queue_redraw()
	dragging = false
	waiting_for_settle = run.shots_left <= 0 and not run.is_finished() and run.phase != RunModel.Phase.SUPPLY
	reload_left = float(saved.get("reload_left", 0.0))
	visual_reload_duration = maxf(reload_left, run.stats.reload_seconds)
	cast_pose_left = 0.0
	recoiling = 0.0
	waiting_for_settle = waiting_for_settle or bool(saved.get("waiting_for_settle", false))
	var aim: Array = saved.get("direction", [1.0, -0.2])
	direction = Vector2(aim[0], aim[1]).normalized()
	clock = float(saved.get("clock", 0.0))
	field_generation = maxi(0, int(saved.get("field_generation", 0)))
	var snapshots: Array = saved.get("targets", []) if saved.get("targets", []) is Array else []
	var count: int = snapshots.size() if not snapshots.is_empty() else 3 + int(run.talent_effects.get("target_count", 0))
	if snapshots.is_empty() and run.stage >= 3: count = maxi(4, count)
	if run.boss_active: count = 0
	var target_scale: float = 1.0 + float(run.talent_effects.get("target_scale", 0.0))
	var origins: Array[Vector2] = _origins(count, target_scale)
	if count == 4 and is_equal_approx(target_scale, 1.0) and (snapshots.is_empty() or not snapshots[0].has("anchor")):
		origins = [Vector2(316, 231), Vector2(429, 164), Vector2(541, 243), Vector2(575, 109)]
	pending_volleys = saved.get("pending_volleys", {}).duplicate(true)
	for hits: Array in pending_volleys.values():
		for hit: Dictionary in hits:
			if hit.has("parent_source_id"): hit["parent_source_id"] = int(hit["parent_source_id"])
	projectile_ledger = saved.get("projectile_ledger", {}).duplicate(true)
	for key: String in projectile_ledger:
		projectile_ledger[key]["next_source"] = int(projectile_ledger[key]["next_source"])
		projectile_ledger[key]["children"] = int(projectile_ledger[key]["children"])
	for index: int in range(origins.size()):
		var target: ArcheryTarget = ArcheryTarget.new()
		var kind: int = 0 if run.stage == 1 else (index + run.stage) % GameCatalog.TARGETS.size()
		target.configure(GameCatalog.TARGETS[kind], origins[index], run.stage, index, run.field_parameters())
		target.scale = Vector2.ONE * target_scale
		add_child(target)
		targets.append(target)
		if index < snapshots.size() and snapshots[index] is Dictionary:
			target.restore(snapshots[index])
		elif field_generation > 0:
			target.generation = field_generation
			var next_kind: int = 0 if run.difficulty_step < 5 else (index + run.difficulty_step / 5) % GameCatalog.TARGETS.size()
			target.spawn(GameCatalog.TARGETS[next_kind], run.difficulty_step, false)
		target.tick(0.0, clock)
	if run.boss_active:
		_create_boss(saved.get("boss", {}) if saved.get("boss") is Dictionary else {})
	for state: Dictionary in saved.get("arrows", []):
		var arrow := Arrow.new()
		arrow.restore(state, run.rng)
		if not state.has("source_id"): arrow.source_id = arrows.size()
		_attach_arrow(arrow)
	if not arrows.is_empty() or not pending_volleys.is_empty(): waiting_for_settle = true
	queue_redraw()

func _create_boss(state: Dictionary = {}) -> void:
	boss = ArcheryBoss.new()
	boss.configure_boss(RunModel.BOSS_RULES, run.boss_round, run.field_parameters())
	add_child(boss)
	if not state.is_empty(): boss.restore(state)
	boss.phase_changed.connect(_on_boss_phase)
	boss.tick(0.0, clock)

func _on_boss_phase(_number: int) -> void:
	add_caption({"position": Vector2(322, 114), "text": "第二阶段 · 护板启动", "life": 1.4, "color": Color("9fc7db")})
	feedback.emit("boss_phase")

func _advance_boss() -> bool:
	if not boss_enabled: return false
	# Never change colliders while a shot family or an earned choice remains unsettled.
	if not arrows.is_empty() or not pending_volleys.is_empty() or run.pending_encounters > 0 or run.phase != RunModel.Phase.PLAYING: return false
	if run.boss_active:
		if boss == null or boss.hp > 0 or not run.credited_defeats.has(boss.defeat_id()): return false
		run.boss_active = false
		var next_field: Dictionary = {"clock": clock, "direction": [direction.x, direction.y], "reload_left": reload_left, "field_generation": field_generation}
		build_field(next_field)
		add_caption({"position": Vector2(348, 138), "text": "BOSS 击败 · 靶场重新开放", "life": 2.0, "color": Color("ffdc83")})
	elif run.begin_boss():
		dragging = false
		pull = 0.0
		for target: ArcheryTarget in targets:
			field_generation = maxi(field_generation, target.generation + 1)
			if target.hp > 0: TargetBreakup.spawn_from(target, true)
			remove_child(target)
			target.queue_free()
		targets.clear()
		_create_boss()
		add_caption({"position": Vector2(348, 138), "text": "BOSS · 普通靶已清场", "life": 2.0, "color": Color("ffdc83")})
		feedback.emit("boss_entry")
	else: return false
	run.changed.emit()
	volley_settled.emit()
	return true

func _origins(count: int, target_scale: float) -> Array[Vector2]:
	if count <= 0: return []
	if count == 3 and is_equal_approx(target_scale, 1.0):
		return [Vector2(316, 231), Vector2(429, 164), Vector2(541, 243)]
	var result: Array[Vector2] = []
	var rows: int = 2 if target_scale > 1.7 else 3
	var columns: int = ceili(float(count) / rows)
	rows = ceili(float(count) / columns)
	for index: int in range(count):
		var x: float = lerpf(295.0, 588.0, float(index % columns) / maxi(columns - 1, 1))
		var y: float = lerpf(58.0 + 25.0 * target_scale, 304.0 - 25.0 * target_scale, float(index / columns) / maxi(rows - 1, 1))
		result.append(Vector2(x, y))
	return result

static func upgrade_snapshot(saved: Dictionary) -> Dictionary:
	var result: Dictionary = saved.duplicate(true)
	if result.get("boss") is Dictionary:
		result["boss"] = ArcheryBoss.upgrade_state(result["boss"])
	var old_arrows: Array = result.get("arrows", [])
	for arrow_index: int in range(old_arrows.size()):
		old_arrows[arrow_index] = Arrow.upgrade_state(old_arrows[arrow_index])
	if saved.is_empty() or saved.has("projectile_schema"): return result
	result["projectile_schema"] = 1
	var ledger: Dictionary = {}
	var pending: Dictionary = result.get("pending_volleys", {})
	for key: String in pending:
		ledger[key] = {"next_source": 1, "children": 0}
		for hit: Dictionary in pending[key]:
			var parts: PackedStringArray = str(hit.get("hit_id", "")).split(":")
			if parts.size() >= 2 and parts[1].is_valid_int():
				ledger[key]["next_source"] = maxi(int(ledger[key]["next_source"]), int(parts[1]) + 1)
	var index: int = 0
	for arrow: Dictionary in result.get("arrows", []):
		var key: String = str(int(arrow.get("shot_id", 0)))
		arrow["shot_id"] = int(key)
		if not pending.has(key): pending[key] = []
		if not ledger.has(key): ledger[key] = {"next_source": 1, "children": 0}
		arrow["source_id"] = int(arrow.get("source_id", index))
		arrow["parent_source_id"] = -1
		arrow["effects"] = ArrowEffects.new().to_dict()
		arrow["split_spent"] = false
		arrow["split_pending"] = false
		arrow["split_exit_rect"] = [0, 0, 0, 0]
		ledger[key]["next_source"] = maxi(int(ledger[key]["next_source"]), int(arrow["source_id"]) + 1)
		index += 1
	result["pending_volleys"] = pending
	result["projectile_ledger"] = ledger
	return result

func snapshot() -> Dictionary:
	var states: Array[Dictionary] = []
	for target: ArcheryTarget in targets:
		states.append(target.snapshot())
	var projectiles: Array[Dictionary] = []
	for arrow: Arrow in arrows: projectiles.append(arrow.snapshot())
	return {"boss": boss.snapshot() if boss != null else null, "field_generation": field_generation,
		"projectile_schema": 1, "projectile_ledger": projectile_ledger.duplicate(true),
		"pending_volleys": pending_volleys.duplicate(true), "clock": clock, "targets": states, "arrows": projectiles,
		"reload_left": reload_left, "waiting_for_settle": waiting_for_settle,
		"direction": [direction.x, direction.y]}

func is_settled() -> bool:
	return arrows.is_empty() and pending_volleys.is_empty() and not dragging and not waiting_for_settle

func _input(event: InputEvent) -> void:
	if dragging and event is InputEventMouseMotion:
		_update_aim(event.position)
	if dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_update_aim(event.position)
		_release()
		get_viewport().set_input_as_handled()
	if dragging and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dragging = false
		pull = 0.0
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if run == null or run.suspended or run.phase != RunModel.Phase.PLAYING or ui_blocked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_mouse: Vector2 = _aim_position(event.position)
		if (not boss_enabled or not run.boss_due()) and reload_left <= 0.0 and run.shots_left > 0 and local_mouse.distance_to(BOW) < 65.0:
			dragging = true
			_update_aim(event.position)
			feedback.emit("draw", 1.0)
			get_viewport().set_input_as_handled()

func _update_aim(viewport_position: Vector2) -> void:
	var local_mouse: Vector2 = _aim_position(viewport_position)
	var drag: Vector2 = BOW - local_mouse
	pull = clampf(drag.length() / 64.0, 0.0, 1.0)
	if drag.length() > 3.0:
		direction = Vector2.RIGHT.rotated(clampf(drag.angle(), -1.1, 0.4))

func _physics_process(delta: float) -> void:
	if run == null or run.suspended or run.phase != RunModel.Phase.PLAYING:
		return
	run.active.cooldown = maxf(0.0, run.active.cooldown - delta)
	if not run.active.target_id.is_empty() and _marked_target() == null:
		run.active.target_id = ""
		run.active.remaining = 0
		run.changed.emit()
	if run.offer_encounter():
		volley_settled.emit()
		return
	_settle_shots()
	if run.phase != RunModel.Phase.PLAYING or run.suspended: return
	_advance_boss()
	clock += delta
	reload_left = maxf(reload_left - delta, 0.0)
	for target: ArcheryTarget in targets:
		target.tick(delta, clock)
		if (not boss_enabled or not run.boss_due()) and not run.boss_active and target.hp <= 0.0 and target.respawn_left <= 0.0 and run.credited_defeats.has(target.defeat_id()):
			var kind: int = 0 if run.difficulty_step < 5 else (target.slot + run.difficulty_step / 5) % GameCatalog.TARGETS.size()
			target.spawn(GameCatalog.TARGETS[kind], run.difficulty_step)
	if boss != null: boss.tick(delta, clock)
	if (waiting_for_settle or run.shots_left <= 0) and arrows.is_empty() and pending_volleys.is_empty():
		waiting_for_settle = false
		run.settle_volley()
		volley_settled.emit()

func _settle_shots() -> void:
	var ids: Array[int] = []
	for key: String in pending_volleys: ids.append(int(key))
	ids.sort()
	for id: int in ids:
		if run.suspended or run.phase != RunModel.Phase.PLAYING: return
		for arrow: Arrow in arrows:
			if arrow.shot_id == id: return
		var hits: Array = pending_volleys[str(id)]
		pending_volleys.erase(str(id))
		projectile_ledger.erase(str(id))
		if boss != null: boss.volley_pressure.erase(str(id))
		shot_settled.emit(id, hits)

func _process(delta: float) -> void:
	for index: int in range(area_rings.size() - 1, -1, -1):
		area_rings[index]["life"] -= delta
		if area_rings[index]["life"] <= 0.0: area_rings.remove_at(index)
	_update_shake(delta)
	recoiling = maxf(recoiling - delta * 7.0, 0.0)
	cast_pose_left = maxf(cast_pose_left - delta, 0.0)
	for index: int in range(labels.size() - 1, -1, -1):
		labels[index]["life"] -= delta
		labels[index]["position"] += Vector2(0, -18) * delta
		if labels[index]["life"] <= 0.0:
			labels.remove_at(index)
	for index: int in range(particles.size() - 1, -1, -1):
		particles[index]["life"] -= delta
		particles[index]["velocity"] += Vector2(0, 140) * delta
		particles[index]["position"] += particles[index]["velocity"] * delta
		if particles[index]["life"] <= 0.0:
			particles.remove_at(index)
	queue_redraw()

func _release() -> void:
	dragging = false
	if ui_blocked or (boss_enabled and run.boss_due()) or run.phase != RunModel.Phase.PLAYING or pull < 0.12 or not run.consume_shot():
		pull = 0.0
		return
	var active_effect: Dictionary = run.active.take_shot()
	if vfx != null and not active_effect.is_empty(): vfx.emit_effect(str(active_effect.id), BOW, direction)
	for index: int in range(run.stats.arrow_count):
		var angle: float = deg_to_rad(run.stats.spread_degrees) * (float(index) - float(run.stats.arrow_count - 1) * 0.5)
		var arrow: Arrow = Arrow.new()
		arrow.setup(BOW, CombatMath.launch_velocity(direction.rotated(angle), pull, run.stats), run.stats, pull, run.rng)
		arrow.shot_id = run.shot_sequence
		arrow.source_id = index
		arrow.effects = run.projectile_effects()
		arrow.active_effect = str(active_effect.get("id", ""))
		arrow.active_target = str(active_effect.get("target", ""))
		_attach_arrow(arrow)
	reload_left = 0.0 if active_effect.get("id", "") == "quickdraw" else run.stats.reload_seconds
	visual_reload_duration = reload_left
	waiting_for_settle = true
	recoiling = 1.0
	feedback.emit("release", 0.85 + pull * 0.3)
	pull = 0.0
	draw_released.emit(run.shot_sequence)
	run.changed.emit()

func skill_target() -> ArcheryTarget:
	var best: ArcheryTarget
	var best_angle: float = 0.38
	var candidates: Array[ArcheryTarget] = targets.duplicate()
	if boss != null: candidates.append(boss)
	for target: ArcheryTarget in candidates:
		if target.hp <= 0.0: continue
		var angle: float = absf(direction.angle_to(target.position - BOW))
		if angle < best_angle:
			best_angle = angle
			best = target
	return best

func _marked_target() -> ArcheryTarget:
	if boss != null and boss.hp > 0 and boss.defeat_id() == run.active.target_id: return boss
	for target: ArcheryTarget in targets:
		if target.hp > 0 and target.defeat_id() == run.active.target_id: return target
	return null

func can_activate_skill() -> bool:
	return run != null and not run.suspended and run.phase == RunModel.Phase.PLAYING and not ui_blocked and not get_tree().paused and run.shots_left > 0 and not (boss_enabled and run.boss_due()) and run.active.can_cast() and (run.active.id != "hunters_mark" or skill_target() != null)

func activate_skill() -> bool:
	if not can_activate_skill(): return false
	var target: ArcheryTarget = skill_target() if run.active.id == "hunters_mark" else null
	if not run.active.cast(target.defeat_id() if target != null else ""): return false
	if run.active.id == "quickdraw": reload_left = 0.0
	cast_pose_left = 0.28
	if vfx != null: vfx.emit_effect(run.active.id, target.position if target != null else BOW, direction)
	add_caption({"position": BOW + Vector2(38, -25), "text": str(ActiveAbility.ALL[run.active.id].title), "life": 1.2, "color": Color("8fd9ba")})
	feedback.emit("active_skill", 1.0)
	run.changed.emit()
	queue_redraw()
	return true

func _attach_arrow(arrow: Arrow) -> void:
	arrow.cosmetic = CosmeticCatalog.equipped(appearance, "arrow")
	if not pending_volleys.has(str(arrow.shot_id)): pending_volleys[str(arrow.shot_id)] = []
	var key: String = str(arrow.shot_id)
	if not projectile_ledger.has(key): projectile_ledger[key] = {"next_source": 0, "children": 0}
	projectile_ledger[key]["next_source"] = maxi(int(projectile_ledger[key]["next_source"]), arrow.source_id + 1)
	arrow.struck.connect(_on_hit.bind(arrow))
	arrow.expired.connect(_on_arrow_expired)
	arrow.bounced.connect(_on_bounce.bind(arrow))
	arrow.split_requested.connect(_on_split)
	arrow.area_requested.connect(_on_area)
	add_child(arrow)
	arrows.append(arrow)

func _on_split(parent: Arrow) -> void:
	var ledger: Dictionary = projectile_ledger[str(parent.shot_id)]
	# Each main arrow splits once; descendants cannot split; a draw has a hard budget.
	var count: int = mini(parent.effects.split_count, MAX_SPLIT_CHILDREN - int(ledger["children"]))
	for index: int in range(count):
		var child := Arrow.new()
		var bow: BowStats = parent.stats.duplicate() as BowStats
		bow.damage *= parent.effects.split_damage
		var angle: float = deg_to_rad(parent.effects.split_degrees) * (-1.0 if index == 0 else 1.0)
		child.setup(parent.position, parent.velocity.rotated(angle), bow, parent.pull, run.rng)
		child.shot_id = parent.shot_id
		child.source_id = int(ledger["next_source"])
		child.parent_source_id = parent.source_id
		child.elapsed = parent.elapsed
		child.hit_slots.assign(parent.hit_slots)
		child.remaining_bounces = mini(32, parent.remaining_bounces + parent.effects.child_bounces)
		child.effects = ArrowEffects.from_dict(parent.effects.to_dict())
		child.inherit_combat(parent)
		child.effects.split_count = 0
		child.split_spent = true
		ledger["next_source"] = child.source_id + 1
		ledger["children"] = int(ledger["children"]) + 1
		_attach_arrow(child)
	if count > 0:
		add_caption({"position": parent.position + Vector2(-12, -24), "text": "分裂", "life": 0.65, "color": Color("b8e395")})

func _on_area(arrow: Arrow, primary: ArcheryTarget, point: Vector2, damage: float, penetration: int) -> void:
	var local: Vector2 = to_local(point)
	if not reduced_effects:
		if area_rings.size() >= 8: area_rings.pop_front()
		area_rings.append({"position": local, "radius": arrow.effects.bullseye_radius, "life": 0.45})
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("archery_targets"):
		var target := node as ArcheryTarget
		if target.get_parent() != self or target == primary or target.hp <= 0.0: continue
		if target.position.distance_to(local) > arrow.effects.bullseye_radius: continue
		if arrow.area_slots.has(target.slot): continue
		# A Boss is one life, including all body/core aliases; shield is never a victim.
		if target is ArcheryBoss and (arrow.hit_slots.has(-1) or arrow.hit_slots.has(-3)): continue
		if count >= arrow.effects.bullseye_targets or arrow.area_slots.size() >= 16: break
		var hit: Dictionary = target.receive_area(damage, penetration, arrow.shot_id)
		if hit.is_empty(): continue
		arrow.area_slots.append(target.slot)
		for excluded: int in hit.get("excluded_slots", []):
			if not arrow.hit_slots.has(excluded): arrow.hit_slots.append(excluded)
		count += 1
		# Secondary damage bypasses Arrow's crit/exit/split/area trigger pipeline.
		_on_hit(target, target.global_position, hit, arrow)

func _on_bounce(point: Vector2, normal: Vector2, arrow: Arrow = null) -> void:
	feedback.emit("ricochet", 1.0)
	if vfx != null: vfx.emit_effect("bounce", to_local(point), arrow.velocity if arrow != null else normal)

func add_caption(record: Dictionary) -> void:
	if not record.has("important"): record["important"] = true
	CombatCaptions.append(labels, record)

func _on_arrow_expired(arrow: Arrow) -> void:
	arrows.erase(arrow)

func _on_hit(_target: ArcheryTarget, point: Vector2, hit: Dictionary, arrow: Arrow) -> void:
	_kick_shake(bool(hit["broken"]))
	# Pending rewards have an explicit schema; presentation-only hit fields stay here.
	var event: Dictionary = {
		"energy_eligible": arrow.parent_source_id < 0 and hit.get("damage_kind", "") != "area" and not bool(hit.get("active_boosted", false)),
		"hit_id": "%d:%d:%s" % [arrow.shot_id, arrow.source_id, hit["event_id"]],
		"event_id": str(hit["event_id"]), "effective": float(hit["effective"]),
		"broken": bool(hit["broken"]), "critical": bool(hit["critical"]), "bullseye": bool(hit["bullseye"]),
		"reward_score": float(hit["reward_score"]), "reward_gold": float(hit["reward_gold"]),
	}
	if hit.get("damage_kind", "") == "area":
		event["damage_kind"] = "area"
		event["hit_id"] = "%d:%d:area:%s" % [arrow.shot_id, arrow.source_id, hit["event_id"]]
	if bool(hit.get("is_boss", false)): event["is_boss"] = true
	if hit.has("boss_part"): event["boss_part"] = hit["boss_part"]
	if bool(hit["broken"]) and arrow.parent_source_id >= 0 and arrow.effects.child_gold_bonus > 0.0:
		event["parent_source_id"] = arrow.parent_source_id
		event["child_gold_bonus"] = arrow.effects.child_gold_bonus
	pending_volleys[str(arrow.shot_id)].append(event)
	if bool(hit["broken"]) and run.active.target_id == _target.defeat_id():
		run.active.target_id = ""
		run.active.remaining = 0
		run.changed.emit()
	var local: Vector2 = to_local(point)
	var highlighted: bool = bool(hit["critical"]) or bool(hit["bullseye"])
	var part: String = str(hit.get("boss_part", "body"))
	var area: bool = hit.get("damage_kind", "") == "area"
	var tags: Array[String] = []
	if hit["critical"]: tags.append("暴击")
	if hit["bullseye"]: tags.append("靶心")
	if hit["broken"]: tags.append("击倒")
	if bool(hit.get("trait_boosted", false)): tags.append("强化")
	if bool(hit.get("active_boosted", false)): tags.append("战技")
	if area: tags.append("回响")
	if event.has("child_gold_bonus"): tags.append("枝丰")
	if part == "weak": tags.append("弱点")
	if part == "shield": tags.append("护板贯穿" if hit["pierced"] else "护板阻挡")
	var caption_position: Vector2 = local + Vector2(-12, -14)
	if area: caption_position.y -= 18.0
	if _target is ArcheryBoss: caption_position.x = _target.position.x - RunModel.BOSS_RULES.width * 0.5 - 125.0
	if part == "shield": caption_position.y -= 18.0
	var key: String = "%d:%s:%s:%s" % [arrow.shot_id, _target.defeat_id(), part, area]
	CombatCaptions.hit(labels, key, caption_position, float(hit["effective"]), tags, highlighted or bool(hit["broken"]))
	if vfx != null:
		vfx.emit_effect("iron" if _target.armor > 0 or part == "shield" else "wood", local, arrow.velocity)
		if hit["bullseye"]: vfx.emit_effect("bullseye", local)
		if hit["critical"]: vfx.emit_effect("critical", local)
		if hit["pierced"] and not area: vfx.emit_effect("penetrate", local, arrow.velocity)
	var cue: String = "break" if hit["broken"] else ("critical" if hit["critical"] else ("bullseye" if hit["bullseye"] else ("metal_hit" if _target.armor > 0 else "hit")))
	if str(hit.get("boss_part", "")) == "shield": cue = "shield_pass" if bool(hit["pierced"]) else "shield_block"
	elif str(hit.get("boss_part", "")) == "weak": cue = "boss_weak"
	feedback.emit(cue, cosmetic_rng.randf_range(0.94, 1.06))

func _draw() -> void:
	_draw_landscape()
	if run != null and run.active.id == "hunters_mark":
		var marked: ArcheryTarget = _marked_target() if not run.active.target_id.is_empty() else skill_target()
		if marked != null:
			CombatVFX.marker(self, marked, not run.active.target_id.is_empty())
	for ring: Dictionary in area_rings:
		var tint := Color("9fd9da")
		tint.a = clampf(float(ring["life"]) / 0.45, 0.0, 1.0) * 0.6
		for segment: PackedVector2Array in CombatVFX.area_outline(ring["position"], ring["radius"]):
			draw_polyline(segment, tint, 1.0)
	draw_rect(Arrow.FIELD, Color("395054"), false, 1.0)
	_draw_bow()
	if dragging and run != null:
		var velocity: Vector2 = CombatMath.launch_velocity(direction, pull, run.stats)
		for index: int in range(1, 23) if trajectory_guide else []:
			var t: float = float(index) * 0.035
			var point: Vector2 = BOW + CombatMath.displacement(velocity, run.stats.gravity, t)
			draw_rect(Rect2(point.round(), Vector2(2, 2)), Color(0.9, 0.85, 0.6, 0.8 - float(index) * 0.025))
		draw_rect(Rect2(BOW + Vector2(-25, 34), Vector2(50, 3)), Color("283b3c"))
		draw_rect(Rect2(BOW + Vector2(-25, 34), Vector2(50 * pull, 3)), Color("edc879"))
	for arrow: Arrow in arrows:
		for index: int in range(1, mini(arrow.trail.size(), 3 if reduced_effects else 10)):
			var tint: Color = Color("ffdc83") if arrow.active_effect == "sunshot" else (Color("a8dce5") if arrow.active_effect == "quickdraw" else arrow.cosmetic.secondary)
			tint.a = 0.25 * (1.0 - float(index) / 10.0)
			draw_line(arrow.trail[index - 1], arrow.trail[index], tint, 1)
	for particle: Dictionary in particles:
		draw_rect(Rect2(Vector2(particle["position"]).round(), Vector2(2, 2)), particle["color"])
	for label: Dictionary in labels:
		var color: Color = label["color"]
		color.a = minf(1.0, float(label["life"]) * 2.0)
		var font_size: int = int(label.get("font_size", 10))
		var width: float = ThemeDB.fallback_font.get_string_size(label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at: Vector2 = label["position"]
		at.x = clampf(at.x, 12, maxf(12, 628 - width))
		at.y = clampf(at.y, 66, 302)
		draw_string(ThemeDB.fallback_font, at, label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_landscape() -> void:
	CosmeticDrawing.archer(self, CosmeticCatalog.equipped(appearance, "archer"), BOW - ArcherPose.GRIP, visual_pose())

func visual_pose() -> ArcherPose:
	return ArcherPose.sample(direction, dragging, pull, reload_left, visual_reload_duration, recoiling, cast_pose_left, clock)

func _draw_bow() -> void:
	var pose: ArcherPose = visual_pose()
	CosmeticDrawing.bow(self, CosmeticCatalog.equipped(appearance, "bow"), BOW, direction, pose.tension, pose.recoil)
	if run != null and run.active.id == "sunshot" and run.active.remaining > 0 and not reduced_effects:
		draw_arc(BOW, 7 + pose.tension * 3, -1.1, 1.1, 8, Color("e7c97c"), 1)
	if pose.loaded and run != null and run.shots_left > 0:
		CosmeticDrawing.nocked_arrow(self, CosmeticCatalog.equipped(appearance, "arrow"), ArcherPose.string_anchor(BOW, direction, pose.tension), direction, run.stats.arrow_size, run.stats.arrow_count)
