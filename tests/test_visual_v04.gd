extends RefCounted
var assertion: Callable
func _init(check: Callable) -> void: assertion = check
func verify(ok: bool, message: String) -> void: assertion.call(ok, "V04: " + message)

func run_all(tree: SceneTree) -> void:
	var bounded: bool = true
	var outlines: Array[PackedVector2Array] = CombatVFX.area_outline(Vector2(620, 290), 170)
	for segment: PackedVector2Array in outlines:
		for point: Vector2 in segment: bounded = bounded and Arrow.FIELD.has_point(point)
	verify(not outlines.is_empty() and bounded, "large edge wave remains inside combat field and cannot cover HUD")
	tree.paused = false
	var profile := PlayerProfile.new()
	verify(not profile.settings.reduced_effects and not PlayerProfile.from_dict({}).settings.reduced_effects, "old profiles default to full effects")
	verify(profile.set_setting("reduced_effects", true) and PlayerProfile.from_dict(profile.to_dict()).settings.reduced_effects, "reduced option survives profile roundtrip")
	var icon := ActiveSkillIcon.new()
	tree.root.add_child(icon)
	icon.update_charge("run:sunshot", false, 0, 1)
	icon.update_charge("run:sunshot", true, 0, 1)
	verify(icon.pulse_left == 0.45, "energy threshold starts one pulse")
	icon._process(0.2)
	icon.configure("sunshot", false)
	icon.update_charge("run:sunshot", true, 0, 1)
	verify(is_equal_approx(icon.pulse_left, 0.25), "unavailable cast state cannot retrigger charge pulse")
	icon.update_charge("run:sunshot", false, 1, 1)
	verify(icon.pulse_left == 0, "spending energy immediately clears ready pulse")
	icon.update_charge("run:quickdraw", false, 2, 2)
	verify(icon.remaining == 2 and icon.segments == 2, "quickdraw uses two remaining-draw segments")
	icon.reduced_effects = true
	icon.update_charge("run:quickdraw", true, 0, 2)
	verify(icon.pulse_left == 0, "reduced mode suppresses pulse")
	icon.queue_free()
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	var world: ArcheryWorld = preload("res://tests/test_boss.gd").new(assertion).field(tree, session)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.vfx.set_process(false)
	var target: ArcheryTarget = world.targets[0]
	target.position.y = ArcheryWorld.BOW.y
	target.hp = 10000
	target.max_hp = 10000
	run.stats.arrow_count = 16
	run.stats.damage = 1
	run.stats.crit_chance = 1
	run.stats.gravity = 0
	run.stats.spread_degrees = 0
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	for arrow: Arrow in world.arrows.duplicate():
		arrow.set_physics_process(false)
		arrow._physics_process(0.6)
	verify(world.labels.size() == 1 and world.labels[0].count == 16, "sixteen real arrows merge into one volley-target caption")
	verify(world.labels[0].tags.has("暴击") and world.labels[0].tags.has("靶心") and world.labels[0].text.contains("合计"), "merged damage keeps critical and bullseye distinction")
	var captions: Array[Dictionary] = []
	CombatCaptions.hit(captions, "1:target:body:false", Vector2(400, 200), 10, ["暴击"], true)
	CombatCaptions.hit(captions, "2:target:body:false", Vector2(400, 200), 20, ["靶心"], true)
	verify(captions.size() == 2 and captions[1].position.y <= captions[0].position.y - 16, "consecutive volleys retain separate damage totals and rows")
	verify(world.vfx.events.any(func(e: Dictionary) -> bool: return e.kind == "critical") and world.vfx.events.any(func(e: Dictionary) -> bool: return e.kind == "bullseye"), "real hits emit independent crit and bullseye shapes")
	var saved: Dictionary = world.snapshot().duplicate(true)
	var random_state: int = run.rng.state
	world.vfx._process(0.08)
	verify(world.snapshot() == saved and run.rng.state == random_state, "effects cannot change flight, settlement, or randomness")
	world.vfx.events.clear()
	var arrow: Arrow = preload("res://tests/test_boss_combat.gd").new(assertion).shot(world, Vector2(628, 100), Vector2(200, -20), 1, 0, 1)
	arrow._physics_process(0.02)
	verify(world.vfx.events.size() == 1 and world.vfx.events[0].kind == "bounce" and world.vfx.events[0].direction.is_equal_approx(arrow.velocity.normalized()), "ricochet uses actual outgoing velocity")
	for i: int in range(200): world.vfx.emit_effect("critical", Vector2(400, 220))
	verify(world.vfx.events.size() == CombatVFX.LIMIT, "dense effect events are bounded")
	for i: int in range(100): world.add_caption({"text": str(i), "position": Vector2.ZERO, "life": 1.0, "color": Color.WHITE})
	verify(world.labels.size() == CombatCaptions.LIMIT, "all floating messages share bounded budget")
	for i: int in range(30): TargetBreakup.spawn_from(target)
	var chunks: int = 0
	for child: Node in world.get_children():
		if child is TargetBreakup: chunks += 1
	verify(chunks == TargetBreakup.MAX_ACTIVE, "destruction effects have separate bounded budget")
	world.apply_settings(profile.settings)
	verify(world.vfx.reduced and world.vfx.events.is_empty(), "changing setting clears existing burst effects")
	verify(TargetBreakup.spawn_from(target) == null, "reduced mode skips debris")
	world.vfx.emit_effect("wood", Vector2.ZERO)
	world.vfx.emit_effect("sunshot", Vector2.ZERO)
	verify(world.vfx.events.is_empty(), "reduced mode omits decorative chips and flashes")
	for i: int in range(100): world.vfx.emit_effect("bullseye", Vector2(300, 200))
	verify(world.vfx.events.size() == CombatVFX.REDUCED_LIMIT, "reduced mode retains bounded essential hit cues")
	world.vfx.set_process(true)
	tree.paused = true
	var age: float = world.vfx.events[0].age
	await tree.create_timer(0.05, true).timeout
	verify(world.vfx.events[0].age == age, "paused field freezes effects")
	tree.paused = false
	world.vfx.set_process(false)
	world.vfx._process(0.5)
	verify(world.vfx.events.is_empty(), "effects expire after resuming")
	world.queue_free()
	await tree.process_frame
