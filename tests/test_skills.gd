extends RefCounted

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T04: " + message)

func run_all(tree: SceneTree) -> void:
	_damage_and_skills()
	_collision(tree)
	await _in_flight(tree)
	_migrate_v3()

func _damage_and_skills() -> void:
	var bow := BowStats.new()
	bow.crit_chance = 0
	bow.armor_penetration = 3
	var less: Dictionary = CombatMath.resolve_hit(bow, 1, false, 100, 0.9, 5)
	var equal: Dictionary = CombatMath.resolve_hit(bow, 1, false, 100, 0.9, 3)
	var greater: Dictionary = CombatMath.resolve_hit(bow, 1, false, 100, 0.9, 2)
	verify(less["effective"] == 22 and not less["pierced"], "Uncancelled armor subtracts damage and blocks penetration")
	verify(equal["effective"] == 24 and not equal["pierced"], "Equal penetration fully cancels armor but cannot pass through")
	verify(greater["effective"] == 24 and greater["pierced"], "Strictly greater penetration passes without damage decay")
	verify(CombatMath.resolve_hit(bow, 1, false, 100, 0.9, 100)["effective"] == 1, "Heavy armor still takes minimum one damage")
	bow.crit_chance = 1
	verify(CombatMath.resolve_hit(bow, 1, false, 100, 0.9, 5)["effective"] == 46, "Critical multiplier applies before flat armor reduction")
	verify(CombatMath.resolve_hit(bow, 1, false, 0.5, 0.9, 100)["effective"] == 0.5, "Minimum damage never exceeds remaining health")
	var run := RunModel.new()
	run.open_skills()
	run.gold = 100000000
	for skill: RunSkillData in SkillCatalog.ALL:
		verify(skill.price(1) > skill.price(0), "Prices increase: " + String(skill.id))
		for rank: int in range(skill.max_level): run.buy(skill)
		var wallet: int = run.gold
		verify(run.skill_is_mastery(skill) and run.can_buy(skill) and run.gold == wallet, "Max basic rank unlocks mastery without charging on display: " + String(skill.id))
	var stats: Dictionary = run.stats.to_dict()
	var restored: RunModel = RunModel.from_dict(run.to_dict())
	verify(restored.skill_levels == run.skill_levels and restored.stats.to_dict() == stats, "All six ranks and compound effects survive save/load")
	var reverse := RunModel.new()
	for index: int in range(SkillCatalog.ALL.size() - 1, -1, -1):
		var skill: RunSkillData = SkillCatalog.ALL[index]
		reverse.skill_levels[String(skill.id)] = skill.max_level
	reverse.rebuild_stats()
	verify(reverse.stats.to_dict() == stats, "Purchase insertion order never changes multiplicative damage")

func _arrow(field: Node2D, at: Vector2, speed: Vector2, bounces: int = 0, penetration: int = 0, size: float = 1) -> Arrow:
	var bow := BowStats.new()
	bow.gravity = 0
	bow.crit_chance = 0
	bow.bounces = bounces
	bow.armor_penetration = penetration
	bow.arrow_size = size
	var arrow := Arrow.new()
	arrow.setup(at, speed, bow, 1, RandomNumberGenerator.new())
	field.add_child(arrow)
	arrow.set_physics_process(false)
	return arrow

func _target(field: Node2D, at: Vector2, armor: int = 0) -> ArcheryTarget:
	var target := ArcheryTarget.new()
	target.configure(GameCatalog.TARGETS[0], at, 1, 0)
	target.armor = armor
	field.add_child(target)
	return target

func _collision(tree: SceneTree) -> void:
	var rect := Rect2(100, 100, 20, 20)
	verify(SweepMath.circle_rect(Vector2(95, 95), Vector2(-10, 0), 6, rect).is_empty(), "Expanded-box corner false positives are excluded")
	verify(not SweepMath.circle_rect(Vector2(80, 94), Vector2(40, 0), 6, rect).is_empty(), "Tangential round-corner collision is detected")
	var field := Node2D.new()
	tree.root.add_child(field)
	var arrow: Arrow = _arrow(field, Vector2(620, 150), Vector2(1200, 400), 1)
	arrow._physics_process(0.02)
	verify(arrow.velocity == Vector2(-1200, 400) and arrow.remaining_bounces == 0, "Oblique wall impact reflects normal component and spends one bounce")
	verify(arrow.position.distance_to(Vector2(616, 158)) < 0.01 and not arrow.done, "Unused frame time continues after reflection")
	verify(is_equal_approx(arrow.velocity.length(), Vector2(1200, 400).length()), "Wall bounce preserves instantaneous speed")
	arrow.free()
	arrow = _arrow(field, Vector2(620, 296), Vector2(1000, 1000), 1)
	arrow._physics_process(0.02)
	verify(arrow.velocity == Vector2(-1000, -1000) and arrow.remaining_bounces == 0, "Exact corner reflects both axes with one bounce")
	verify(arrow.position.distance_to(Vector2(620, 296)) < 0.01, "Corner collision does not trap arrow")
	arrow.free()
	arrow = _arrow(field, Vector2(320, 150), Vector2(20000, 0), 4)
	arrow._physics_process(0.1)
	verify(arrow.remaining_bounces == 1 and absf(arrow.position.x - 180) < 0.01 and not arrow.done, "Several boundary contacts resolve in one large step")
	arrow.free()
	arrow = _arrow(field, Vector2(630, 150), Vector2(1000, 0), 1)
	arrow._physics_process(0.01)
	verify(arrow.velocity.x < 0 and arrow.position.x < 630 and not arrow.done, "Starting on wall pointing outward bounces once without a loop")
	arrow.free()
	arrow = _arrow(field, Vector2(620, 150), Vector2(1000, 0))
	arrow._physics_process(0.02)
	verify(arrow.done, "No bounce budget expires at the first edge")
	arrow.free()
	var target: ArcheryTarget = _target(field, Vector2(550, 150))
	arrow = _arrow(field, Vector2(620, 150), Vector2(2000, 0), 1)
	arrow._physics_process(0.1)
	verify(target.hp == 24 and arrow.done, "Reflection followed by target collision occurs in remaining same-frame time")
	arrow.free()
	target.free()
	target = _target(field, Vector2(600, 150))
	arrow = _arrow(field, Vector2(580, 150), Vector2(1000, 0), 1, 1)
	arrow._physics_process(0.1)
	verify(target.hp == 24 and not arrow.done and arrow.hit_slots == [0], "Returning bounce cannot damage same target twice")
	var state: Dictionary = arrow.snapshot()
	var restored := Arrow.new()
	restored.restore(state, RandomNumberGenerator.new())
	field.add_child(restored)
	restored.set_physics_process(false)
	arrow._physics_process(0.1)
	restored._physics_process(0.1)
	verify(arrow.snapshot() == restored.snapshot() and target.hp == 24, "Projectile snapshot preserves flight, used bounce budget and hit exclusion")
	arrow.free()
	restored.free()
	target.free()
	target = _target(field, Vector2(200, 200))
	arrow = _arrow(field, Vector2(100, 228), Vector2(20000, 0), 0, 0, 1)
	arrow._physics_process(0.01)
	verify(target.hp == 48, "Small arrow misses a path outside target")
	arrow.free()
	arrow = _arrow(field, Vector2(100, 228), Vector2(20000, 0), 0, 0, 3)
	var hits: Array[Dictionary] = []
	arrow.struck.connect(func(_t: ArcheryTarget, _p: Vector2, hit: Dictionary) -> void: hits.append(hit))
	arrow._physics_process(0.01)
	verify(target.hp == 24 and hits.size() == 1 and not hits[0]["bullseye"], "Large head catches high-speed graze without enlarging bullseye")
	arrow.free()
	target.free()
	target = _target(field, Vector2(180, 150), 2)
	target.hp = 1
	arrow = _arrow(field, Vector2(100, 150), Vector2(20000, 0), 0, 2)
	arrow._physics_process(0.01)
	verify(target.hp == 0 and arrow.done, "Lethal hit with equal armor does not grant penetration")
	target.respawn_left = 0.002
	var target_state: Dictionary = target.snapshot()
	target.restore(target_state)
	verify(is_equal_approx(target.respawn_left, 0.002), "Near-expiry respawn timer restores without adding delay")
	field.free()

func _in_flight(tree: SceneTree) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.run.gold = 100
	main.world.direction = Vector2(1, -0.4).normalized()
	main.world.pull = 1
	main.world._release()
	await tree.physics_frame
	main._on_action("skills", null)
	var arrow: Arrow = main.world.arrows[0]
	var at: Vector2 = arrow.position
	var before: Dictionary = arrow.stats.to_dict()
	for index: int in range(3): await tree.physics_frame
	verify(tree.paused and arrow.position == at, "Opening skills freezes live projectile")
	var grid: GridContainer = main.hud.content.get_child(2)
	(grid.get_child(2) as Button).pressed.emit()
	verify(main.run.stats.damage == 32 and arrow.stats.to_dict() == before, "Purchase affects future shots, not in-flight snapshot")
	var payload: Dictionary = main.saves.read()
	verify(payload["world"]["arrows"].size() == 1 and payload["run"]["gold"] == 88, "Save commits purchase and in-flight arrow together")
	var bad: Dictionary = payload.duplicate(true)
	bad["world"]["arrows"][0]["velocity"] = ["invalid", 0]
	verify(not main.saves.write(bad), "Malformed in-flight snapshot cannot overwrite a valid save")
	var state: Dictionary = arrow.snapshot()
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._enter_range()
	verify(tree.paused and main.world.arrows[0].snapshot() == state, "Disk restore returns to paused skills and exact projectile")
	verify(main.run.stats.damage == 32 and main.world.arrows[0].stats.damage == 24 and main.run.shots_left == 9, "Restore retains new build, old projectile damage and spent draw")
	main._continue()
	await tree.physics_frame
	await tree.physics_frame
	verify(not tree.paused and main.world.arrows[0].position != at, "Closing restored skills resumes the original flight")
	main.queue_free()
	await tree.process_frame

func _migrate_v3() -> void:
	var path: String = "user://tests/t04-migration.json"
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v3"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var session := GameSession.new()
	session.start_run()
	var payload: Dictionary = session.to_dict()
	payload["run"].erase("skill_schema")
	for key: String in ["trait_schema", "trait_levels", "mastery_schema", "mastery_levels", "mastery_unlocks"]: payload["run"].erase(key)
	payload["run"]["skill_levels"] = {"power": 2, "pierce": 1, "critical": 2}
	var original: String = JSON.stringify({"version": 3, "payload": payload})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store := SaveStore.new(path)
	var result: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v3") == original, "V3 bytes archived before six-skill migration")
	verify(result.run.skill_levels.is_empty() and result.run.legacy_skill_levels.size() == 3, "Legacy ranks cannot collide with modern critical skill")
	verify(result.run.stats.damage == 40 and result.run.stats.armor_penetration == 1 and result.run.stats.crit_multiplier == 3, "Legacy damage, critical and converted penetration remain effective")
	var reloaded: GameSession = GameSession.from_dict(store.read())
	verify(reloaded.run.stats.to_dict() == result.run.stats.to_dict() and store.migration_notice.is_empty(), "Repeated V4 load neither compounds nor remigrates old bonuses")
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v3"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
