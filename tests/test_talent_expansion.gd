extends RefCounted
## T15: deeper branches, capped linkage, immutable openings and real projectiles.
var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T15: " + message)

func rich() -> GameSession:
	var session := GameSession.new()
	session.profile.record_score(1.0e12)
	return session

func learn(session: GameSession, id: String, ranks: int = 1) -> void:
	for index: int in range(ranks):
		verify(session.purchase_talent(id), "purchase " + id)

func path(session: GameSession, prefix: String, side: String, finish: bool = true) -> void:
	learn(session, prefix + "_root")
	learn(session, prefix + "_" + side, 2)
	learn(session, prefix + "_master_" + side)
	if finish:
		learn(session, prefix + "_advanced_" + side, 2)
		learn(session, prefix + "_capstone_" + side)

func run_all(tree: SceneTree) -> void:
	_rules()
	_numbers()
	_coin_linkage()
	await _flight_and_disk(tree)
	await _field_geometry(tree)

func _rules() -> void:
	for prefix: String in ["quiver", "economy", "damage", "field"]:
		for side: String in ["left", "right"]:
			var session: GameSession = rich()
			var points: int = session.profile.talent_points
			verify(not session.purchase_talent(prefix + "_advanced_" + side), "advanced tier requires specialization")
			path(session, prefix, side, false)
			verify(not session.purchase_talent(prefix + "_capstone_" + side), "capstone cannot skip advanced tier")
			learn(session, prefix + "_advanced_" + side)
			verify(not session.purchase_talent(prefix + "_capstone_" + side), "capstone needs both advanced ranks")
			learn(session, prefix + "_advanced_" + side)
			learn(session, prefix + "_capstone_" + side)
			verify(points - session.profile.talent_points == 32, "path costs 1 + 2 + 3 + 4 + 5 + 7 + 10")
			verify(not session.purchase_talent(prefix + "_advanced_" + side) and not session.purchase_talent(prefix + "_capstone_" + side), "new ranks are bounded")
			var other: String = "right" if side == "left" else "left"
			learn(session, prefix + "_" + other, 2)
			verify(not session.purchase_talent(prefix + "_master_" + other) and not session.purchase_talent(prefix + "_advanced_" + other), "exclusion propagates through the other specialization")
			var state: Dictionary = session.profile.to_dict()
			verify(PlayerProfile.from_dict(state).to_dict() == state, "extended ranks and ledger round-trip " + prefix + side)
			state["talents"].erase(prefix + "_master_" + side)
			var pruned: PlayerProfile = PlayerProfile.from_dict(state)
			verify(not pruned.talents.has(prefix + "_advanced_" + side) and not pruned.talents.has(prefix + "_capstone_" + side), "orphaned new nodes are pruned")
			verify(session.reset_talents() == 37 and session.reset_talents() == 0, "exact deeper spending refunded once")
	var poor := GameSession.new()
	poor.profile.record_score(PlayerProfile.RULES.threshold(15))
	path(poor, "damage", "left", false)
	var original: Dictionary = poor.profile.to_dict()
	verify(not poor.purchase_talent("damage_advanced_left") and poor.profile.to_dict() == original, "insufficient deep-tier points cannot mutate profile")

func _numbers() -> void:
	var session: GameSession = rich()
	path(session, "quiver", "left")
	var run: RunModel = session.start_run()
	verify(run.initial_shots == 20 and run.shots_left == 20 and is_equal_approx(run.stats.damage, 26.4), "draw reserves and damage apply once")
	verify(is_equal_approx(run.talent_effects["kill_refund"], .4), "refund extension adds four percentage points")
	session = rich()
	path(session, "quiver", "right")
	run = session.start_run()
	run.skill_levels["quantity"] = 2
	run.rebuild_stats()
	verify(run.stats.arrow_count == 3 and is_equal_approx(run.stats.crit_chance, .20) and is_equal_approx(run.stats.crit_multiplier, 2.3), "extra arrows link critical chance")
	run.encounter_picks["unified_arrow"] = 1
	run.rebuild_stats()
	verify(run.stats.arrow_count == 1 and is_equal_approx(run.stats.crit_chance, .20), "unity retains source arrow critical bonus")
	var raw: BowStats = run.calculate_raw_stats(run.skill_levels, run.encounter_picks)
	raw.arrow_count = 32
	verify(is_equal_approx(run._evaluate_raw(raw, {}).effective.crit_chance, .28), "critical arrow linkage caps at ten percentage points")
	run.encounter_picks["critical_forging"] = 1
	run.rebuild_stats()
	verify(run.stats.crit_chance == 0 and run.stats.armor_penetration == 10, "talent crit participates in conversion without escaping its debuff")

	session = rich()
	path(session, "damage", "left")
	run = session.start_run()
	verify(is_equal_approx(run.stats.damage, 91.2) and is_equal_approx(run.stats.arrow_size, 1.5), "heavy specialization links damage and actual arrow size")
	session = rich()
	path(session, "damage", "right")
	run = session.start_run()
	verify("\n".join(run.stat_explanations(run.evaluate_stats({}, {}))).contains("透甲锋芒：条件增伤 +8.0%"), "tooltip explains actual capped talent linkage")
	verify(run.stats.armor_penetration == 16 and run.stats.launch_speed == 540 and is_equal_approx(run.stats.damage, 30.24), "piercing specialization uses effective penetration")
	run.encounter_picks["critical_forging"] = 1
	run.rebuild_stats()
	verify(run.stats.armor_penetration == 21 and is_equal_approx(run.stats.damage, 30.94), "forged penetration contributes to capped damage linkage")
	raw = run.calculate_raw_stats({}, {})
	raw.armor_penetration = 1000000
	verify(is_equal_approx(run._evaluate_raw(raw, {}).effective.damage, raw.damage * 1.3), "penetration damage bonus caps at thirty percent")

	session = rich()
	path(session, "field", "left")
	run = session.start_run()
	verify(run.stats.arrow_count == 3 and run.stats.bounces == 1 and is_equal_approx(run.stats.damage, 25.92), "dense field grants real arrows, one bounce and source-count damage")
	raw = run.calculate_raw_stats({}, {})
	raw.arrow_count = 32
	verify(is_equal_approx(run._evaluate_raw(raw, {}).effective.damage, raw.damage * 1.28), "source count damage cap is twenty-eight percent")
	session = rich()
	path(session, "field", "right")
	run = session.start_run()
	verify(is_equal_approx(run.stats.arrow_size, 1.3) and is_equal_approx(run.stats.damage, 24.72) and is_equal_approx(run.stats.crit_multiplier, 2.4), "giant field links real arrow size and crit multiplier")
	raw = run.calculate_raw_stats({}, {})
	raw.arrow_size = 6
	verify(is_equal_approx(run._evaluate_raw(raw, {}).effective.damage, raw.damage * 1.3), "size damage cap is thirty percent")
	# A talent-linked preview must remain identical to the actual purchased build.
	run.gold = 10000
	run.open_skills()
	var size_skill: RunSkillData = SkillCatalog.find(&"size")
	var preview: Dictionary = run.preview_skill(size_skill).to_dict()
	verify(run.buy(size_skill) and run.stats.to_dict() == preview, "skill purchase preview includes size talent linkage exactly")
	var stable: Dictionary = run.stats.to_dict()
	for index: int in range(5): run.rebuild_stats()
	verify(run.stats.to_dict() == stable and GameCatalog.BASE_BOW.damage == 24 and GameCatalog.BASE_BOW.arrow_size == 1, "rebuilding never compounds bonuses or changes shared base")

func hit(id: String, bullseye: bool = false) -> Dictionary:
	return {"hit_id": id, "event_id": id, "effective": 1.0, "broken": true, "critical": false, "bullseye": bullseye, "reward_score": 40.0, "reward_gold": 10.0}

func _coin_linkage() -> void:
	var session: GameSession = rich()
	path(session, "economy", "left")
	var run: RunModel = session.start_run()
	verify(is_equal_approx(run.stats.damage, 25.2), "gold efficiency links damage without wallet dependence")
	run.combo = 100
	run.consume_shot()
	verify(session.settle_shot(run.shot_sequence, [hit("extended-combo")]) and is_equal_approx(run.gold_earned, 32.75), "gold combo caps at nine prior hit draws")
	run.consume_shot()
	session.settle_shot(run.shot_sequence, [])
	run.consume_shot()
	session.settle_shot(run.shot_sequence, [hit("after-miss")])
	verify(run.combo == 1 and is_equal_approx(run.gold_earned, 45.25), "miss still resets extended combo")
	var before: Dictionary = run.to_dict()
	verify(not session.settle_shot(run.shot_sequence, [hit("duplicate")]) and run.to_dict() == before, "no repeated extended combo payout")
	var raw: BowStats = run.calculate_raw_stats({}, {"windfall": 100})
	verify(is_equal_approx(raw.damage, 38.4), "gold damage uses actual four-times gold efficiency cap")
	session = rich()
	path(session, "economy", "right")
	run = session.start_run()
	run.consume_shot()
	session.settle_shot(run.shot_sequence, [hit("bullseye", true)])
	verify(is_equal_approx(run.gold_earned, 31.05) and is_equal_approx(run.stats.crit_chance, .18) and is_equal_approx(run.stats.crit_multiplier, 2.2), "bullseye specialization pays gold once and grants crit stats")

func _flight_and_disk(tree: SceneTree) -> void:
	var session: GameSession = rich()
	path(session, "damage", "right")
	var run: RunModel = session.start_run()
	var helper: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
	var world: ArcheryWorld = helper.field(tree, session)
	for index: int in range(world.targets.size()):
		world.targets[index].anchor = Vector2(180 + index * 140, 238 if index == 0 else 100)
		world.targets[index].tick(0, 0)
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	var arrow: Arrow = world.arrows[0]
	arrow.set_physics_process(false)
	var launched: Dictionary = arrow.snapshot()
	verify(is_equal_approx(arrow.stats.damage, 30.24) and arrow.stats.armor_penetration == 16 and arrow.velocity.x == 540, "real arrow captures talent-linked damage, penetration and speed")
	session.return_to_lobby()
	var old_stats: Dictionary = run.stats.to_dict()
	var old_snapshot: Dictionary = run.talent_snapshot.duplicate(true)
	verify(session.reset_talents() == 32, "lobby resets extended talents exactly")
	path(session, "field", "right")
	verify(run.talent_snapshot == old_snapshot and run.stats.to_dict() == old_stats and arrow.snapshot() == launched, "respec and new purchases cannot alter active run or flight")
	session.capture_checkpoint(world.snapshot())
	var save_path: String = "user://tests/t15-talents.json"
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)
	var store := SaveStore.new(save_path)
	verify(store.write(session.save_payload()), "existing v20 envelope accepts additive talent expansion")
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(restored.profile.to_dict() == session.profile.to_dict() and TalentCatalog.valid_ranks(restored.run.talent_snapshot) == old_snapshot, "disk preserves new permanent choices separately from current run snapshot")
	restored.resume_run()
	var resumed: ArcheryWorld = helper.field(tree, restored, restored.world_snapshot)
	var restored_arrow: Dictionary = resumed.arrows[0].snapshot()
	var expected_arrow: Dictionary = launched.duplicate(true)
	verify(absf(restored_arrow["stats"]["damage"] - expected_arrow["stats"]["damage"]) <= 1.0e-12, "only fractional damage allows JSON last-bit rounding")
	expected_arrow["stats"]["damage"] = restored_arrow["stats"]["damage"]
	verify(restored_arrow == expected_arrow and resumed.targets[0].hp == 48, "all other in-flight fields and target survive exactly")
	helper.tick(resumed, 200)
	verify(is_equal_approx(resumed.targets[0].hp, 17.76) and restored.run.shots_left == 9 and restored.run.defeated_count == 0, "restored real shot deals linked damage without phantom defeat")
	var next: RunModel = restored.start_run(true)
	verify(next.talent_snapshot == restored.profile.talents and is_equal_approx(next.stats.arrow_size, 1.3) and next.stats.armor_penetration == 0 and next.shots_left == 10, "new run takes new specialization with no old penetration or refill leakage")
	world.queue_free()
	resumed.queue_free()
	await tree.process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)

func _field_geometry(tree: SceneTree) -> void:
	for side: String in ["left", "right"]:
		var session: GameSession = rich()
		path(session, "field", side)
		session.start_run()
		var helper: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
		var world: ArcheryWorld = helper.field(tree, session)
		verify(world.targets.size() == (15 if side == "left" else 4), "expanded field has catalog target count " + side)
		verify(is_equal_approx(world.targets[0].scale.x, 1.1 if side == "left" else 2.3) and world.targets[0].max_hp == 48, "expanded target scale changes geometry without inflating health")
		if side == "left":
			session.run.stats.gravity = 0
			session.run.stats.spread_degrees = 0
			world.direction = Vector2.RIGHT
			world.pull = 1
			world._release()
			verify(world.arrows.size() == 3 and session.run.shots_left == 9, "new multishot consumes exactly one draw")
			for arrow: Arrow in world.arrows:
				arrow.set_physics_process(false)
				arrow.position = Vector2(620, 238)
				arrow._physics_process(.1)
				verify(arrow.velocity.x < 0 and arrow.remaining_bounces == 0, "capstone bounce follows reflected velocity once")
		world.queue_free()
		await tree.process_frame
		# Full existing branches together with new tiers exercise the largest supported fields.
		session.return_to_lobby()
		learn(session, "field_root", 2)
		learn(session, "field_" + ("right" if side == "left" else "left"), 2)
		session.start_run(true)
		world = helper.field(tree, session)
		verify(world.targets.size() == (17 if side == "left" else 10), "fully invested field respects expanded count " + side)
		for target: ArcheryTarget in world.targets:
			var rect: Rect2 = target.collision_volumes()[0]["rect"]
			verify(Arrow.FIELD.encloses(rect), "expanded extreme target collider remains within shooting bounds")
		world.queue_free()
		await tree.process_frame
