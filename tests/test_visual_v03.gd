extends RefCounted
var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "V03: " + message)

func debris(world: ArcheryWorld) -> Array[TargetBreakup]:
	var result: Array[TargetBreakup] = []
	for child: Node in world.get_children():
		if child is TargetBreakup: result.append(child)
	return result

func run_all(tree: SceneTree) -> void:
	tree.paused = false
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	var base: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
	var world: ArcheryWorld = base.field(tree, session)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var target: ArcheryTarget = world.targets[0]
	for data: TargetData in GameCatalog.TARGETS:
		target.spawn(data, 0)
		for size: float in [1.0, 3.0]:
			target.scale = Vector2.ONE * size
			for factor: float in [1.0, 0.5]:
				target.difficulty_parameters["bullseye_scale"] = factor
				var before: Dictionary = target.snapshot()
				var body: Rect2 = TargetArt.body_rect(target)
				var weak: Rect2 = TargetArt.weak_rect(target)
				var hit_rect: Rect2 = target.collision_volumes()[0].rect
				verify(body.size * target.scale == hit_rect.size and body.position * target.scale + target.position == hit_rect.position, "visible body equals contact rectangle for %s scale %s" % [data.id, size])
				verify(target.is_bullseye(target.to_global(Vector2(0, weak.end.y - 0.01))) and not target.is_bullseye(target.to_global(Vector2(0, weak.end.y + 0.01))), "painted bullseye follows talent size and contract")
				verify(before == target.snapshot(), "art sampling leaves target save intact")
	target.scale = Vector2.ONE
	var bow := BowStats.new()
	bow.damage = 100000
	bow.crit_chance = 0
	var rng_state: int = run.rng.state
	var hit: Dictionary = target.receive_hit(bow, 1, target.global_position, 1)
	verify(hit.broken and debris(world).size() == 1, "real death emits one breakup")
	var effect: TargetBreakup = debris(world)[0]
	effect.set_process(false)
	verify(not effect.cleared and effect.pieces.size() == 8 and effect.get_groups().is_empty() and not effect.is_class("CollisionObject2D"), "death shards are visual-only nodes")
	verify(target.receive_hit(bow, 1, target.global_position, 1).is_empty() and debris(world).size() == 1, "dead target cannot hit or shatter twice")
	await tree.process_frame
	verify(target.collision_layer == 0 and run.rng.state == rng_state, "dead collider disabled and presentation consumes no combat randomness")
	var before: Dictionary = world.snapshot().duplicate(true)
	effect._process(0.1)
	verify(before == world.snapshot() and run.defeated_count == 0 and run.gold == 0, "debris animation never settles rewards or mutates combat")
	effect.set_process(true)
	tree.paused = true
	var age: float = effect.age
	await tree.create_timer(0.05, true).timeout
	verify(effect.age == age, "debris freezes with paused combat")
	tree.paused = false
	effect.set_process(false)
	effect._process(TargetBreakup.DURATION)
	await tree.process_frame
	verify(not is_instance_valid(effect), "breakup cleans itself up")
	target.spawn(GameCatalog.TARGETS[0], 0)
	verify(target.hp == target.max_hp and target.collision_layer == 2, "respawn returns full surface and collision")
	base.prime(run, 100)
	var gold: int = run.gold
	world._advance_boss()
	verify(world.targets.is_empty() and debris(world).size() == 3, "Boss entry clears all ordinary faces into shards")
	var all_clear: bool = true
	for item: TargetBreakup in debris(world):
		all_clear = all_clear and item.cleared
		item.set_process(false)
	verify(all_clear and run.gold == gold and run.defeated_count == 100 and run.pending_encounters == 0, "entry shards have clear appearance and no phantom rewards")
	var boss: ArcheryBoss = world.boss
	var weak: Rect2 = TargetArt.weak_rect(boss)
	var body: Rect2 = TargetArt.body_rect(boss)
	verify(weak == Rect2(boss.collision_volumes()[0].rect.position - boss.position, boss.collision_volumes()[0].rect.size), "Boss core uses exact weak collider")
	verify(body == Rect2(boss.collision_volumes()[1].rect.position - boss.position, boss.collision_volumes()[1].rect.size), "Boss armor uses exact body collider")
	boss.hp = boss.max_hp * 0.4
	boss.refresh_phase()
	boss.tick(0.6, 0)
	var shield: Rect2 = TargetArt.shield_rect(boss)
	verify(shield == Rect2(boss.collision_volumes()[0].rect.position - boss.position, boss.collision_volumes()[0].rect.size), "moving shield art follows actual shield position and size")
	var saved: Dictionary = boss.snapshot().duplicate(true)
	boss.restore(saved)
	verify(TargetArt.shield_rect(boss) == shield and TargetArt.weak_rect(boss) == weak and boss.snapshot() == saved, "restoring moving Boss reproduces art geometry")
	boss.combat_schema = 0
	weak = TargetArt.weak_rect(boss)
	verify(boss.is_bullseye(boss.to_global(Vector2(0, weak.end.y - 0.01))) and not boss.is_bullseye(boss.to_global(Vector2(0, weak.end.y + 0.01))), "legacy Boss band matches legacy bullseye rather than new rules")
	boss.combat_schema = 1
	hit = boss.receive_contact(bow, 1, boss.global_position, 1, "weak")
	verify(hit.broken and debris(world).size() == 4 and not debris(world).back().cleared, "Boss defeat has player-break appearance exactly once")
	verify(boss.receive_contact(bow, 1, boss.global_position, 1, "weak").is_empty(), "Boss death animation cannot award another hit")
	world.queue_free()
	await tree.process_frame
