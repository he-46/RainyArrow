extends RefCounted
## T11-C: real primary/area sources, conditional accuracy and v13 flight recovery.

const IDS: Array[String] = ["charged_breach", "bullseye_wave", "critical_flow", "broad_precision"]
const EFFECT_KEYS: Array[String] = ["charged_penetration", "bullseye_radius", "bullseye_damage", "bullseye_targets", "critical_damage", "critical_limit", "size_bullseye", "size_bullseye_limit"]
var assertion: Callable
var base: RefCounted
var fixture: RefCounted
var offers: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)
	fixture = preload("res://tests/test_penetration_traits.gd").new(check)
	offers = preload("res://tests/test_encounter_expansion.gd").new(check)

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T11-C: " + message)

func setup(tree: SceneTree, ids: Array[String]) -> Dictionary:
	return fixture.setup(tree, ids)

func run_all(tree: SceneTree) -> void:
	_catalog()
	await _charge(tree)
	await _critical_and_children(tree)
	await _precision(tree)
	await _area(tree)
	await _area_caps(tree)
	await _boss(tree)
	await _rewards_and_disk(tree)
	await _selection(tree)
	await _legacy(tree)

func _catalog() -> void:
	var run := RunModel.new()
	var before: Dictionary = run.stats.to_dict()
	for id: String in IDS:
		var reward: EncounterData = EncounterCatalog.find(id)
		verify(reward != null and reward.is_trait and not reward.has_debuff and reward.trait_key == id, "unique trait metadata: " + id)
		verify(not run.encounter_comparison(reward).is_empty(), "configured conditional preview: " + id)
	base._equip(run, IDS)
	verify(run.stats.to_dict() == before, "four conditional effects do not overwrite character attributes")
	var effects: ArrowEffects = run.projectile_effects()
	verify(effects.charged_penetration == 8 and effects.bullseye_radius == 140 and effects.bullseye_damage == 0.4 and effects.bullseye_targets == 6 and effects.critical_damage == 0.12 and effects.critical_limit == 5 and effects.size_bullseye == 0.15 and effects.size_bullseye_limit == 0.75, "all configured coefficients freeze together")
	verify(ArrowEffects.from_dict(effects.to_dict()).to_dict() == effects.to_dict() and RunModel.from_dict(run.to_dict()).projectile_effects().to_dict() == effects.to_dict(), "effect and selection round trips are stable")
	run.skill_levels["size"] = 2
	run.rebuild_stats()
	var next_bonus: String = "%.1f%%" % ((run.preview_skill_evaluation(SkillCatalog.find(&"size")).effective.arrow_size - 1) * 15)
	verify(run.encounter_comparison(EncounterCatalog.find("broad_precision")).contains("10.5%") and run.skill_comparison(SkillCatalog.find(&"size")).contains("靶心增伤 +10.5% → +" + next_bonus), "size encounter and skill preview expose actual conditional benefit")
	verify(run.stat_explanations(run.evaluate_stats(run.skill_levels, run.encounter_picks)).size() >= 4, "history explains conditional calculations")
	var rng := RandomNumberGenerator.new()
	rng.seed = 91574
	var seen: Array[String] = []
	var safe_all: bool = true
	var unique_all: bool = true
	for iteration: int in range(70):
		var previous: Array[String] = seen.duplicate()
		var safe: bool = false
		for id: String in EncounterCatalog.draft(rng, seen, EncounterCatalog.ALL):
			var reward: EncounterData = EncounterCatalog.find(id)
			if reward.is_trait: unique_all = unique_all and not previous.has(id)
			else: safe = safe or not reward.has_debuff
		safe_all = safe_all and safe
	verify(EncounterCatalog.ALL.size() == 24 and seen.size() == 18 and safe_all and unique_all, "twenty-four entries preserve ordinary safety and unique trait display")

func _charge(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["charged_breach", "armor_surplus", "wall_forging"])
	var world: ArcheryWorld = f.world
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow.stats.armor_penetration = 0
	for sample: Array in [[0.0, 0], [0.125, 1], [0.499, 3], [0.5, 4], [0.999, 7], [1.0, 8]]:
		arrow.pull = float(sample[0])
		verify(arrow.contact_stats(world.targets[0], world.targets[0].global_position, "body").armor_penetration == int(sample[1]), "pull uses floor at " + str(sample[0]))
	arrow.pull = 1
	arrow.bounce_stacks = 2
	var shot: BowStats = arrow.contact_stats(world.targets[0], world.targets[0].global_position, "body")
	verify(shot.armor_penetration == 14 and is_equal_approx(shot.damage, 128) and arrow.stats.armor_penetration == 0, "charge and wall armor feed surplus without rewriting launch stats")
	arrow.stats.armor_penetration = 1000000
	verify(arrow.contact_stats(world.targets[0], world.targets[0].global_position, "body").armor_penetration == 1000000, "combined conditional penetration retains million cap")
	world.queue_free()
	await tree.process_frame
	for pull: float in [0.5, 1.0]:
		f = setup(tree, ["charged_breach"])
		world = f.world
		world.run.stats.armor_penetration = 0
		world.targets[0].armor = 4
		arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
		arrow.pull = pull
		arrow._physics_process(0.07)
		verify(arrow.done == (pull == 0.5) and arrow.hit_slots == [0], "half pull equal armor stops; full pull actually traverses")
		verify(is_equal_approx(world.targets[0].hp, 10000 - 100 * lerpf(0.7, 1.0, pull)), "pull still participates in primary damage")
		world.queue_free()
		await tree.process_frame

func _critical_and_children(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["critical_flow", "piercing_edge", "piercing_split"])
	var world: ArcheryWorld = f.world
	world.run.stats.crit_chance = 1
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.03)
	verify(world.targets[0].hp == 9800 and arrow.critical_stacks == 1 and arrow.penetration_stacks == 0, "first real crit gains future damage after its own unboosted hit")
	arrow._physics_process(0.04)
	base._freeze(world)
	verify(world.arrows.size() == 3 and world.arrows[1].critical_stacks == 1 and world.arrows[1].penetration_stacks == 1 and world.arrows[1].stats.damage == 50, "split children carry earned critical plus exit stacks with half base")
	arrow._physics_process(0.18)
	verify(is_equal_approx(world.targets[1].hp, 10000 - 100 * 1.12 * 1.15 * 2) and arrow.critical_stacks == 2 and arrow.penetration_stacks == 2, "later crit uses prior critical and penetration multipliers, then gains one layer")
	verify(arrow.stats.damage == 100 and world.run.stats.damage == 100, "critical progression never compounds raw or launch damage")
	world.queue_free()
	await tree.process_frame
	f = setup(tree, ["critical_flow", "critical_forging"])
	world = f.world
	world.run.rebuild_stats()
	world.run.stats.gravity = 0
	arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.3)
	verify(arrow.stats.crit_chance == 0 and arrow.critical_stacks == 0, "crit-to-armor conversion cannot fabricate critical-flow triggers")
	world.queue_free()
	await tree.process_frame
	f = setup(tree, ["critical_flow"])
	world = f.world
	world.run.stats.crit_chance = 1
	for index: int in range(7):
		var target: ArcheryTarget
		if index < 3: target = world.targets[index]
		else:
			target = ArcheryTarget.new()
			target.configure(GameCatalog.TARGETS[0], Vector2.ZERO, 1, index)
			world.add_child(target)
			world.targets.append(target)
		target.anchor = Vector2(130 + 65 * index, 150)
		target.tick(0, 0)
		target.hp = 10000
		target.max_hp = 10000
		target.armor = 0
	arrow = base._primary(world, Vector2(100, 150), Vector2(1000, 0))
	arrow._physics_process(0.45)
	verify(arrow.critical_stacks == 5 and world.targets[5].hp == 9680 and world.targets[6].hp == 9680, "seven primary crits cap at sixty-percent future damage")
	world.queue_free()
	await tree.process_frame

func _precision(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["broad_precision"])
	var world: ArcheryWorld = f.world
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	for size: float in [0.5, 1.0, 2.0, 6.0]:
		arrow.stats.arrow_size = size
		var expected: float = 100 * (1 + minf(maxf(size - 1, 0) * 0.15, 0.75))
		verify(is_equal_approx(arrow.contact_stats(world.targets[0], world.targets[0].global_position, "body").damage, expected), "center precision scales from actual size " + str(size))
		verify(arrow.contact_stats(world.targets[0], world.targets[0].global_position + Vector2(0, 12), "body").damage == 100, "larger arrowhead never widens center criterion")
	arrow.stats.arrow_size = 6
	arrow.position = Vector2(140, 160)
	arrow._physics_process(0.1)
	verify(world.targets[0].hp == 9900 and not world.pending_volleys["1"][0]["bullseye"], "real large-head grazing hit gets ordinary damage")
	world.queue_free()
	await tree.process_frame

func nearby(world: ArcheryWorld) -> void:
	world.targets[1].anchor = Vector2(230, 150)
	world.targets[2].anchor = Vector2(430, 150)
	for target: ArcheryTarget in world.targets: target.tick(0, 0)

func _area(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["bullseye_wave", "critical_flow"])
	var world: ArcheryWorld = f.world
	nearby(world)
	world.run.stats.crit_chance = 1
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	var random: int = world.run.rng.state
	var expected_random := RandomNumberGenerator.new()
	expected_random.state = random
	expected_random.randf()
	arrow._physics_process(0.03)
	verify(world.targets[0].hp == 9800 and world.targets[1].hp == 9920 and world.targets[2].hp == 10000, "center crit sends forty percent actual damage only to in-range neighbor")
	verify(arrow.critical_stacks == 1 and arrow.area_slots == [1] and world.pending_volleys["1"].size() == 2, "secondary adds independent source without critical-flow recursion")
	var hit: Dictionary = world.pending_volleys["1"][1]
	verify(hit["damage_kind"] == "area" and not hit["critical"] and not hit["bullseye"] and hit["hit_id"] != world.pending_volleys["1"][0]["hit_id"], "area ledger has explicit identity and no counterfeit accuracy")
	verify(world.run.rng.state == expected_random.state, "secondary damage consumes no additional combat RNG")
	world._on_area(arrow, world.targets[0], Vector2(171, 150), 999.0, 20)
	verify(world.targets[1].hp == 9920 and world.pending_volleys["1"].size() == 2, "repeated pulse cannot damage the same area slot twice")
	arrow._physics_process(0.14)
	verify(is_equal_approx(world.targets[1].hp, 9696) and arrow.critical_stacks == 2 and world.pending_volleys["1"].size() == 4, "ordinary neighbor can receive one physical contact plus its one area contact")
	verify(is_equal_approx(world.targets[0].hp, 9710.4) and world.targets[2].hp == 10000, "next real bullseye may send one bounded return pulse without recursion")
	var child := Arrow.new()
	child.setup(arrow.position, arrow.velocity, arrow.stats, arrow.pull, world.run.rng)
	child.effects = ArrowEffects.from_dict(arrow.effects.to_dict())
	child.inherit_combat(arrow)
	verify(child.area_slots == arrow.area_slots and child.critical_stacks == 2, "child inherits area exclusions and earned critical stacks")
	child.free()
	world.queue_free()
	await tree.process_frame

func _area_caps(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["bullseye_wave"])
	var world: ArcheryWorld = f.world
	for target: ArcheryTarget in world.targets:
		target.anchor = Vector2(180 + target.slot * 5, 150)
		target.tick(0, 0)
	for index: int in range(3, 10):
		var target := ArcheryTarget.new()
		target.configure(GameCatalog.TARGETS[0], Vector2(180 + index * 5, 150), 1, index)
		world.add_child(target)
		world.targets.append(target)
		target.hp = 10000
		target.max_hp = 10000
		target.armor = 0
	world.targets[1].armor = 25
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.023)
	verify(arrow.area_slots.size() == 6 and world.pending_volleys["1"].size() == 7, "one primary center pulse is bounded at six secondary victims")
	verify(world.targets[1].hp == 9965 and world.targets[6].hp == 9960 and world.targets[7].hp == 10000, "secondary subtracts current body armor, and seventh neighbor remains untouched")
	verify(arrow.hit_slots == [0] and arrow.critical_stacks == 0 and not arrow.split_pending, "area contacts do not enter physical penetration/split/critical pipeline")
	world.queue_free()
	await tree.process_frame

func _boss(tree: SceneTree) -> void:
	var combat: RefCounted = preload("res://tests/test_boss_combat.gd").new(assertion)
	var world: ArcheryWorld = combat.setup(tree)
	var selected: Array[String] = ["broad_precision", "charged_breach", "bullseye_wave", "critical_flow"]
	base._equip(world.run, selected)
	world.run.encounter_picks["windfall"] = 6
	world.run.rebuild_stats()
	var arrow: Arrow = combat.shot(world, Vector2(430, 205), Vector2(500, 0), 100.0, 0, 1)
	world.waiting_for_settle = true
	arrow.stats.arrow_size = 6
	var boss: ArcheryBoss = world.boss
	verify(arrow.contact_stats(boss, boss.global_position, "weak").damage == 175 and arrow.contact_stats(boss, boss.global_position + Vector2(0, boss.parameters["weak_half_height"] + 1), "body").damage == 100, "Boss precision uses exact core center band, not arrow radius")
	arrow._physics_process(0.1)
	verify(is_equal_approx(boss.hp, 960 - 306.25) and arrow.hit_slots.has(-1) and arrow.hit_slots.has(-3) and arrow.area_slots.is_empty(), "actual broad weak hit applies size and boss factors once; its pulse cannot hit same shared life")
	verify(world.pending_volleys["1"].size() == 1 and world.targets.is_empty(), "Boss-only pulse cannot manufacture ordinary victims, extra rewards or shield hits")
	# An independent nearby primary can pulse a Boss body only once, excluding aliases.
	var primary := ArcheryTarget.new()
	primary.configure(GameCatalog.TARGETS[0], Vector2(410, 205), 1, 0)
	world.add_child(primary)
	var second: Arrow = combat.shot(world, Vector2(380, 205), Vector2(500, 0), 100, 0, 0)
	var hp: float = boss.hp
	world._on_area(second, primary, primary.global_position, 100, 0)
	verify(boss.hp == hp - 80 and second.area_slots == [-1] and second.hit_slots.has(-1) and second.hit_slots.has(-3), "area uses Boss body armor and claims shared life aliases once, with no weak multiplier")
	world._on_area(second, primary, primary.global_position, 100, 0)
	verify(boss.hp == hp - 80 and not world.pending_volleys["2"][0]["critical"] and world.pending_volleys["2"][0]["boss_part"] == "body", "second pulse cannot reapply same Boss HP or manufacture shield/crit accuracy")
	second._physics_process(0.25)
	verify(boss.hp == hp - 80, "physical core/body cannot hit Boss again after this arrow's area hit")
	world.queue_free()
	await tree.process_frame

func _rewards_and_disk(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["bullseye_wave", "critical_flow", "piercing_edge"])
	var world: ArcheryWorld = f.world
	var session: GameSession = f.session
	nearby(world)
	world.targets[1].hp = 10
	world.targets[1].max_hp = 10
	world.run.stats.crit_chance = 1
	world.run.shots_left = 1
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow._physics_process(0.03)
	verify(world.targets[1].hp == 0 and session.profile.total_score == 0 and world.run.shots_left == 0 and arrow.critical_stacks == 1 and arrow.penetration_exits.size() == 1, "last-draw area kill waits for family settlement; direct dynamic state remains pending")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t11c-flight.json"
	clean(path)
	var store := SaveStore.new(path)
	var payload: Dictionary = session.save_payload()
	verify(store.write(payload), "dead area victim, unique events and pending dynamic flight serialize atomically")
	var loaded := GameSession.from_dict(store.read())
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	copy.shot_settled.connect(loaded.settle_shot)
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(loaded.world_snapshot)
	base._freeze(copy)
	verify(copy.snapshot() == world.snapshot() and copy.run.rng.state == world.run.rng.state, "disk restores primary/area ledger, exclusions, crit layers, exits and RNG exactly")
	for field: ArcheryWorld in [world, copy]: field.arrows[0]._physics_process(0.2)
	verify(copy.snapshot() == world.snapshot() and copy.run.rng.state == world.run.rng.state, "resumed flight neither replays pulse nor diverges after exit")
	for field: ArcheryWorld in [world, copy]:
		field.arrows[0]._finish()
		field._settle_shots()
	verify(session.profile.total_score == 40 and loaded.profile.total_score == 40 and world.run.gold == 8 and loaded.run.gold == 8 and world.run.defeated_count == 31 and world.run.combo == 1, "single area kill grants XP/gold/ordinary progress once and one draw combo")
	world._settle_shots()
	verify(world.run.gold == 8 and session.profile.total_score == 40, "repeated settlement cannot duplicate area rewards")
	world.run.settle_volley()
	verify(world.run.is_finished() and world.run.gold == 0 and session.last_run_summary["defeat_score"] == 40, "last draw ends only after area reward is settled")
	for key: String in EFFECT_KEYS:
		var bad: Dictionary = payload.duplicate(true)
		bad["world"]["arrows"][0]["effects"].erase(key)
		verify(not store.write(bad), "current flight rejects missing frozen coefficient: " + key)
	var bad: Dictionary = payload.duplicate(true)
	bad["world"]["arrows"][0]["critical_stacks"] = 6
	verify(not store.write(bad), "reject critical layers above frozen limit")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["area_slots"] = [1, 1]
	verify(not store.write(bad), "reject duplicate area victims")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["area_slots"] = [-2]
	verify(not store.write(bad), "reject shield as area victim")
	bad = payload.duplicate(true)
	bad["world"]["arrows"][0]["effects"]["bullseye_damage"] = NAN
	verify(not store.write(bad), "reject nonfinite area coefficient")
	bad = payload.duplicate(true)
	bad["world"]["pending_volleys"]["1"][1]["critical"] = true
	verify(not store.write(bad), "reject forged secondary critical trigger")
	bad = payload.duplicate(true)
	bad["world"]["pending_volleys"]["1"][1]["damage_kind"] = "chain"
	verify(not store.write(bad), "reject unknown secondary damage kind")
	bad = payload.duplicate(true)
	bad["world"]["pending_volleys"]["1"][1]["hit_id"] = "1:0:slot1-life0"
	verify(not store.write(bad), "reject secondary event masquerading as primary identity")
	verify(store.read() == JSON.parse_string(JSON.stringify(payload, "", true, true)), "failed writes leave previous good area transaction intact")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _selection(tree: SceneTree) -> void:
	for id: String in IDS:
		var f: Dictionary = setup(tree, [])
		var world: ArcheryWorld = f.world
		var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
		var snapshot: Dictionary = arrow.snapshot()
		offers.entitle(world.run)
		world.run.offer_encounter()
		world.run.choices.assign(["second_wind", id, "steady_power"])
		if not world.run.seen_encounters.has(id): world.run.seen_encounters.append(id)
		verify(world.run.choose_encounter(id, world.run.encounter_offer_id) and arrow.snapshot() == snapshot, "selection preserves old live arrow: " + id)
		var next: Arrow = base._primary(world, Vector2(160, 90), Vector2(500, 0))
		verify(next.effects.to_dict() == world.run.projectile_effects().to_dict() and next.effects.to_dict() != arrow.effects.to_dict(), "next draw alone receives new conditional effect: " + id)
		world.queue_free()
		await tree.process_frame

func _legacy(tree: SceneTree) -> void:
	var f: Dictionary = setup(tree, ["piercing_edge", "armor_surplus", "echo_strike", "wall_forging", "piercing_split"])
	var world: ArcheryWorld = f.world
	var session: GameSession = f.session
	var arrow: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	arrow.bounce_stacks = 2
	arrow.echo_ready = true
	arrow._physics_process(0.03)
	world.reload_left = 0.31
	offers.entitle(world.run)
	world.run.offer_encounter()
	world.run.choices.assign(["second_wind", "steady_power", "quick_nock"])
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	for old: Dictionary in payload["world"]["arrows"]:
		old["combat_schema"] = 1
		old.erase("critical_stacks")
		old.erase("area_slots")
		for key: String in EFFECT_KEYS: old["effects"].erase(key)
	var path: String = "user://tests/t11c-v13.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 13, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v13") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v13 original archived byte-for-byte before v14 migration")
	verify(loaded.run.choices == world.run.choices and loaded.run.encounter_offer_id == world.run.encounter_offer_id and loaded.run.rng.state == world.run.rng.state, "new catalog does not reroll old group, token or RNG")
	var migrated: Dictionary = loaded.world_snapshot["arrows"][0]
	verify(migrated["combat_schema"] == 3 and migrated["critical_stacks"] == 0 and migrated["area_slots"].is_empty() and migrated["effects"]["bullseye_damage"] == 0 and migrated["effects"]["charged_penetration"] == 0, "old arrow gains neutral accuracy effects with zero new state")
	verify(migrated["stats"] == JSON.parse_string(JSON.stringify(payload["world"]["arrows"][0]["stats"], "", true, true)) and migrated["bounce_stacks"] == 2 and migrated["penetration_exits"].size() == 1 and migrated["split_pending"] and loaded.world_snapshot["reload_left"] == 0.31, "old damage/armor/bounce/exit/split and reload remain untouched")
	var copy := ArcheryWorld.new()
	copy.run = loaded.run
	tree.root.add_child(copy)
	copy.set_physics_process(false)
	copy.build_field(loaded.world_snapshot)
	base._freeze(copy)
	verify(copy.snapshot() == world.snapshot(), "neutral upgraded v13 arrow simulates with identical complete snapshot")
	verify(store.write(loaded.to_dict()) and not store.read().is_empty() and store.migration_notice.is_empty(), "same-version read does not repeat migration or multiply effects")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v13"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
