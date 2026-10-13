extends RefCounted

var assertion: Callable
var base: RefCounted
var bosses: RefCounted

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)
	bosses = preload("res://tests/test_boss.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T12-B: " + message)

func equip(run: RunModel, ids: Array[String]) -> void:
	base._equip(run, ids)

func viable(run: RunModel) -> void:
	run.skill_levels = {"quantity": 3, "critical": 2, "penetration": 2, "ricochet": 2, "size": 2}
	run.rebuild_stats()

func run_all(tree: SceneTree) -> void:
	_all_traits()
	_no_gain()
	_combined()
	_boss_caps()
	await _flight(tree)
	await _premium(tree)
	await _boss(tree)
	await _migration(tree)
	_invalid()

func _all_traits() -> void:
	verify(TraitUpgradeCatalog.ALL.size() == 18, "each selected trait has an independent configurable upgrade resource")
	for id: String in TraitUpgradeCatalog.ALL:
		var run := RunModel.new()
		viable(run)
		var config: TraitUpgradeData = TraitUpgradeCatalog.find(id)
		verify(config.max_level == 3 and config.price(0) > 0 and config.price(1) > config.price(0) and config.price(2) > config.price(1), "finite ranks and increasing prices: " + id)
		run.gold = 1000000
		verify(not run.buy_trait(id, 0), "unselected trait cannot be purchased: " + id)
		var ids: Array[String] = [id]
		if id.begins_with("branch_"): ids.append("piercing_split")
		equip(run, ids)
		verify(not run.buy_trait(id, 0), "active shooting has no upgrade permission: " + id)
		run.open_skills()
		var picks: Dictionary = run.encounter_picks.duplicate()
		for rank: int in range(3):
			var wallet: int = run.gold
			var preview: Dictionary = run.preview_trait(id).effective.to_dict()
			verify(run.trait_has_gain(id) and run.buy_trait(id, rank) and run.gold == wallet - config.price(rank), "one paid rank charges exact increasing price: %s/%d" % [id, rank])
			verify(run.stats.to_dict() == preview and run.trait_rank(id) == rank + 1 and run.encounter_picks == picks and not run.buy_trait(id, rank), "preview is source-derived; stale click does not pay again: %s/%d" % [id, rank])
		var stats: Dictionary = run.stats.to_dict()
		var effects: Dictionary = run.projectile_effects().to_dict()
		for repeat: int in range(10): run.rebuild_stats()
		var loaded := RunModel.from_dict(run.to_dict())
		verify(not run.buy_trait(id, 3) and run.stats.to_dict() == stats and loaded.stats.to_dict() == stats and loaded.projectile_effects().to_dict() == effects and loaded.trait_rank(id) == 3, "max rank and repeated rebuild/restore keep exact source effects: " + id)
		verify(EncounterCatalog.RULES.split_damage == 0.5 and EncounterCatalog.RULES.bounce_multiplier == 1.25 and EncounterCatalog.RULES.heavy_reload_factor == 1.35, "shared baseline resource remains unchanged: " + id)
		verify(run.trait_comparison(id).contains("满阶"), "rank cap visibly retains effects: " + id)
	var run := RunModel.new()
	viable(run)
	equip(run, ["heavy_draw", "slender_gale"])
	run.open_skills()
	run.gold = 10000
	var reload: float = run.stats.reload_seconds
	var size: float = run.stats.arrow_size
	verify(run.buy_trait("heavy_draw", 0) and run.stats.reload_seconds < reload and run.buy_trait("slender_gale", 0) and run.stats.arrow_size > size, "debuff upgrades increase benefits and relieve reload/size costs")
	verify(RunModel.new().trait_levels.is_empty(), "new run clears all trait upgrade ranks")

func _no_gain() -> void:
	var run := RunModel.new()
	equip(run, ["swarm_precision", "unified_arrow", "critical_ricochet", "broad_precision", "critical_flow", "critical_forging", "branch_ricochet", "piercing_split"])
	run.encounter_picks["tempered_tip"] = 1
	run.rebuild_stats()
	run.gold = 1000000
	run.open_skills()
	for id: String in ["swarm_precision", "unified_arrow", "broad_precision", "critical_flow"]:
		verify(not run.trait_has_gain(id) and not run.buy_trait(id, 0) and run.gold == 1000000, "inactive/converted effect refuses empty level: " + id)
	run.encounter_picks["rainfall"] = 100
	run.skill_levels["critical"] = 8
	run.rebuild_stats()
	verify(not run.trait_has_gain("swarm_precision"), "capped linked crit conversion source cannot pay for extra source chance")
	run.mastery_unlocks.assign(["ricochet"])
	run.mastery_levels["ricochet"] = 100
	run.rebuild_stats()
	verify(not run.trait_has_gain("critical_ricochet") and not run.trait_has_gain("branch_ricochet"), "32 bounce cap filters conversion and child extra budget")
	run.suspended = true
	verify(not run.buy_trait("piercing_split", 0), "hub cannot buy upgrades")
	run.suspended = false
	run.gold = 0
	verify(not run.buy_trait("piercing_split", 0) and run.trait_levels.is_empty(), "insufficient funds never change rank")
	verify(EncounterCatalog.find("@upgrade/piercing_split/01") == null and EncounterCatalog.find("@upgrade/windfall/1") == null and EncounterCatalog.find("@upgrade/piercing_split/4") == null, "free target identity is canonical and bounded")
	var charged := RunModel.new()
	equip(charged, ["charged_breach", "piercing_split", "branch_ricochet", "branch_harvest", "ricochet_haste"])
	verify(charged.stats.armor_penetration == 0 and charged.trait_has_gain("piercing_split") and charged.trait_has_gain("branch_ricochet") and charged.trait_has_gain("branch_harvest") and charged.trait_has_gain("ricochet_haste"), "charged penetration supports real children and their bounces even without character penetration")

func _combined() -> void:
	var run := RunModel.new()
	viable(run)
	var ids: Array[String] = []
	for id: String in TraitUpgradeCatalog.ALL: ids.append(id)
	equip(run, ids)
	for id: String in ids: run.trait_levels[id] = 3
	run.rebuild_stats()
	var evaluation: StatEvaluation = run.evaluate_stats(run.skill_levels, run.encounter_picks)
	verify(evaluation.source_arrows == 4 and run.stats.arrow_count == 1 and run.stats.crit_chance == 0 and run.stats.crit_multiplier == 1, "all eighteen max sources preserve directed single-arrow/double conversion pipeline")
	verify(run.stats.armor_penetration == 47 and run.stats.bounces == 20 and is_equal_approx(run.stats.damage, 24 * pow(0.85, 3) * 1.85 * pow(4, 1.3)), "upgraded quantity linkage/denominators/unity and relieved heavy factor give exact combined outputs")
	var effects: Dictionary = run.projectile_effects().to_dict()
	verify(is_equal_approx(effects["split_damage"], 0.8) and effects["split_count"] == 2 and effects["child_bounces"] == 5 and effects["child_gold_bonus"] == 1.25 and effects["bullseye_targets"] == 6 and effects["bullseye_radius"] == 200 and effects["charged_penetration"] == 20, "full ranks strengthen coefficients but preserve child/area/family budgets")
	verify(not run.trait_has_gain("critical_flow") and run.stats.arrow_size <= 6 and run.stats.launch_speed <= 1000 and run.stats.reload_seconds >= 0.15, "converted crit stays zero and existing effective caps remain enforced")
	run.open_skills()
	run.gold = 1000000
	var preview: Dictionary = run.preview_skill(SkillCatalog.find(&"quantity")).to_dict()
	verify(run.buy(SkillCatalog.find(&"quantity")) and run.stats.to_dict() == preview and run.stats.arrow_count == 1, "later basic skills participate in upgraded traits with matching preview")

func _boss_caps() -> void:
	var offers: RefCounted = preload("res://tests/test_encounter_expansion.gd").new(assertion)
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	offers.capped(run)
	run.pending_encounters = 0
	run.reward_queue.clear()
	equip(run, ["piercing_split"])
	run.boss_active = true
	verify(session.record_boss_defeat("boss%d" % run.boss_round, 1200, 240), "earned capped Boss creates one valid source")
	run.boss_active = false
	verify(run.offer_encounter() and run.choices.size() == 1 and run.choices[0] == "@upgrade/piercing_split/1" and not run.can_skip_encounter(), "ordinary cap can still offer a useful positive free rank without forcing a debuff")
	var path: String = "user://tests/t12b-capped-boss.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.to_dict()), "one free-only capped offer is a valid persistent choice")
	var good: String = FileAccess.get_file_as_string(path)
	for mutation: int in range(5):
		var bad: Dictionary = session.to_dict()
		match mutation:
			0: bad["run"]["choices"] = ["@upgrade/piercing_split/2"]
			1: bad["run"]["choices"] = ["@upgrade/charged_breach/1"]
			2: bad["run"]["reward_queue"][0] = {"kind": "ordinary", "round": 0}
			3:
				bad["run"]["choices"] = []
				bad["run"]["offer_exhausted"] = true
			4: bad["run"]["choices"] = ["@upgrade/piercing_split/1", "@upgrade/piercing_split/1"]
		verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "forged free target/source/exhaustion rejected: %d" % mutation)
	verify(run.choose_encounter(run.choices[0], run.encounter_offer_id), "capped free offer grants its one target")
	run.trait_levels["piercing_split"] = 3
	verify(store.write(session.to_dict()), "completed free record may remain at an earlier rank than later paid ranks")
	good = FileAccess.get_file_as_string(path)
	var bad: Dictionary = session.to_dict()
	bad["run"]["boss_reward_log"][0]["choice"] = "@upgrade/piercing_split/4"
	verify(not store.write(bad), "invalid claimed rank cannot forge completed reward")
	bad = session.to_dict()
	bad["run"]["trait_levels"]["piercing_split"] = 1
	bad["run"]["boss_reward_log"][0]["choice"] = "@upgrade/piercing_split/2"
	verify(not store.write(bad), "claimed rank must be present in owned source")
	bad = session.to_dict()
	bad["run"]["boss_round"] += 1
	bad["run"]["bosses_defeated"] += 1
	bad["run"]["boss_next_defeats"] += 100
	var record: Dictionary = bad["run"]["boss_reward_log"][0].duplicate()
	record["round"] = bad["run"]["boss_round"]
	bad["run"]["credited_defeats"]["boss%d" % record["round"]] = true
	bad["run"]["boss_reward_log"].append(record)
	verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "two Boss identities cannot claim the same free trait rank")
	run.phase = RunModel.Phase.PLAYING
	run.boss_round += 1
	run.boss_next_defeats += 100
	run.boss_active = true
	session.record_boss_defeat("boss%d" % run.boss_round, 1200, 240)
	run.boss_active = false
	verify(run.offer_encounter() and run.offer_exhausted and run.choices.is_empty() and run.can_skip_encounter(), "fully capped ordinary and trait rewards use explicit keep-build acknowledgement")
	verify(store.write(session.to_dict()) and run.skip_encounter(run.encounter_offer_id) and run.boss_reward_log.back()["choice"] == RunModel.NO_GAIN, "exhausted Boss acknowledges once and preserves paid/free ranks and supply")
	clean(path)

func _flight(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	viable(run)
	equip(run, ["piercing_split", "branch_harvest", "branch_ricochet", "charged_breach", "ricochet_haste", "wall_forging", "echo_strike", "bullseye_wave", "piercing_edge", "armor_surplus", "critical_flow", "broad_precision"])
	var world: ArcheryWorld = base._world(tree, session)
	world.set_process(false)
	world.reload_left = 0.31
	for target: ArcheryTarget in world.targets:
		target.hp = 10000
		target.max_hp = 10000
	var parent: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	var frozen: Dictionary = parent.snapshot()
	run.open_skills()
	run.gold = 1000000
	for id: String in run.encounter_picks:
		verify(run.buy_trait(id, 0) and parent.snapshot() == frozen and world.reload_left == 0.31, "paid conditional upgrade freezes old arrow, params and reload: " + id)
	run.close_skills()
	parent._physics_process(0.13)
	base._freeze(world)
	verify(world.arrows.size() == 3 and world.arrows[1].stats.damage == float(frozen["stats"]["damage"]) * 0.5 and world.arrows[1].effects.child_gold_bonus == 0.5 and world.arrows[1].remaining_bounces == parent.remaining_bounces + 2, "old mother split created after upgrade retains old damage, gold and child bounce snapshot")
	var fresh: Arrow = base._primary(world, Vector2(160, 150), Vector2(500, 0))
	fresh.stats.gravity = 0
	fresh.stats.crit_chance = 0
	fresh._physics_process(0.13)
	base._freeze(world)
	var child: Arrow = world.arrows.back()
	verify(child.parent_source_id == fresh.source_id and is_equal_approx(child.stats.damage, run.stats.damage * 0.6) and child.effects.child_gold_bonus == 0.75 and child.remaining_bounces == fresh.remaining_bounces + 3 and child.effects.split_count == 0, "next real family gets stronger finite children without recursive splitting")
	child.position = Vector2(625, 90)
	child.velocity = Vector2(500, 0)
	child._physics_process(0.02)
	verify(child.velocity.x < 0 and is_equal_approx(child.velocity.length(), 675) and child.bounce_stacks == 1 and child.echo_ready, "upgraded haste, armor and echo trigger on actual reflection")
	var contact: BowStats = child.contact_stats(world.targets[0], world.targets[0].global_position, "body")
	verify(contact.armor_penetration == child.stats.armor_penetration + 5 + 12 and contact.damage > child.stats.damage, "charged and wall penetration and conditional damage use upgraded launch parameters")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t12b-flight.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "mixed old/new conditional families persist atomically")
	var loaded := GameSession.from_dict(store.read())
	var copy: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
	base._freeze(copy)
	verify(same_flight(copy.snapshot(), world.snapshot()) and loaded.run.trait_levels == run.trait_levels and loaded.run.rng.state == run.rng.state, "disk freezes both original and upgraded effects and family premiums")
	for field: ArcheryWorld in [world, copy]:
		for arrow: Arrow in field.arrows.duplicate(): arrow._physics_process(0.01)
	base._freeze(world)
	base._freeze(copy)
	verify(same_flight(copy.snapshot(), world.snapshot()) and loaded.run.rng.state == run.rng.state, "continued physics and RNG remain deterministic within frozen damage ULP")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func boss_setup(tree: SceneTree) -> Dictionary:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	bosses.prime(run, 100)
	run.encounter_picks["windfall"] = 8
	equip(run, ["charged_breach", "piercing_split"])
	viable(run)
	var world: ArcheryWorld = bosses.field(tree, session)
	world._physics_process(0)
	run.shots_left = 1
	bosses.fire(world, 100000, 3, 21)
	bosses.tick(world, 400)
	return {"session": session, "world": world}

func _premium(tree: SceneTree) -> void:
	var fixture: RefCounted = preload("res://tests/test_branch_traits.gd").new(assertion)
	var ids: Array[String] = ["piercing_split", "branch_harvest", "branch_ricochet", "bullseye_wave"]
	var f: Dictionary = fixture.setup(tree, ids)
	var world: ArcheryWorld = f.world
	world.set_process(false)
	var session: GameSession = f.session
	var run: RunModel = session.run
	viable(run)
	run.gold = 10000
	run.open_skills()
	for id: String in ids: verify(run.buy_trait(id, 0), "reward flight purchases real first rank: " + id)
	run.close_skills()
	run.gold = 0
	run.encounter_picks["windfall"] = 2
	preload("res://tests/test_encounter_expansion.gd").new(assertion).entitle(run, 0)
	run.rebuild_stats()
	run.stats.damage = 100
	run.stats.gravity = 0
	run.stats.crit_chance = 0
	run.stats.arrow_size = 1
	run.shots_left = 1
	world.targets[1].hp = 10
	world.targets[1].max_hp = 10
	world.targets[2].anchor = Vector2(330, 150)
	world.targets[2].tick(0, 0)
	world.targets[2].hp = 3
	world.targets[2].max_hp = 3
	var parent: Arrow = base._primary(world, Vector2(160, 160), Vector2(500, 0))
	parent._physics_process(0.07)
	base._freeze(world)
	var child: Arrow = world.arrows[1]
	child.position = Vector2(250, 150)
	child.velocity = Vector2(500, 0)
	child._physics_process(0.04)
	verify(world.targets[1].hp == 0 and world.targets[2].hp == 0 and run.gold == 0 and session.profile.total_score == 0, "upgraded child direct and stronger area kills wait for final-draw family")
	var ledger: Array = world.pending_volleys["1"]
	var premiums: Array[Dictionary] = []
	for hit: Dictionary in ledger:
		if hit.has("child_gold_bonus"): premiums.append(hit)
	verify(premiums.size() == 2 and premiums[0]["child_gold_bonus"] == 0.75 and premiums[1]["child_gold_bonus"] == 0.75 and premiums[1]["damage_kind"] == "area" and child.effects.bullseye_damage == 0.5 and child.stats.damage == 60, "real physical/area sources stamp upgraded frozen premium without changing base reward")
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t12b-premium.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "upgraded pending child premium persists before settlement")
	var loaded := GameSession.from_dict(store.read())
	var copy: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
	base._freeze(copy)
	for field: ArcheryWorld in [world, copy]:
		field.pending_volleys["1"].append(field.pending_volleys["1"][1].duplicate(true))
		for arrow: Arrow in field.arrows.duplicate(): arrow._finish()
		field._settle_shots()
	verify(run.gold == 42 and copy.run.gold == 42 and session.profile.total_score == 80 and loaded.profile.total_score == 80, "upgraded direct and area child each earns8×1.75×1.5 once, even after disk or duplicate hit")
	world._settle_shots()
	run.settle_volley()
	verify(run.phase == RunModel.Phase.SUPPLY, "upgraded premium settles before affordable supply choice")
	run.decline_supply(run.supply_offer_id)
	verify(run.is_finished() and run.gold == 0 and session.last_run_summary["gold_earned"] == 42 and session.last_run_summary["defeat_score"] == 80, "last draw summary retains real upgraded earnings and clears wallet")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _boss(tree: SceneTree) -> void:
	var f: Dictionary = boss_setup(tree)
	var session: GameSession = f.session
	var world: ArcheryWorld = f.world
	var run: RunModel = session.run
	verify(run.phase == RunModel.Phase.CHOICE and run.shots_left == 3 and run.boss_reward_log.size() == 1 and world.targets.is_empty(), "last real draw settles boss family once and holds dead arena for free upgrade choice")
	var free_id: String = ""
	var ordinary: bool = false
	var seen: Array[String] = run.seen_encounters.duplicate()
	for id: String in run.choices:
		var reward: EncounterData = EncounterCatalog.find(id)
		if reward.upgrade_trait.is_empty(): ordinary = ordinary or not reward.has_debuff and not reward.is_trait
		else: free_id = id
	verify(not free_id.is_empty() and ordinary and run.choices.size() == 3, "boss provides selected useful upgrade and a safe ordinary fallback")
	var choices: Array[String] = run.choices.duplicate()
	var offer: int = run.encounter_offer_id
	var rng_state: int = run.rng.state
	session.return_to_lobby()
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t12b-boss.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "free rank target and pending boss source save")
	var loaded := GameSession.from_dict(store.read())
	verify(loaded.run.choices == choices and loaded.run.encounter_offer_id == offer and loaded.run.rng.state == rng_state and not loaded.run.choose_encounter(free_id, offer), "fixed free targets/RNG/token retained; lobby cannot collect")
	loaded.resume_run()
	var wallet: int = loaded.run.gold
	var picks: Dictionary = loaded.run.encounter_picks.duplicate()
	verify(not loaded.run.choose_encounter(free_id, offer - 1) and not loaded.run.buy_trait(TraitUpgradeCatalog.decode(free_id)["id"], 0), "stale token and paid action cannot consume fixed free choice")
	verify(loaded.run.choose_encounter(free_id, offer) and loaded.run.gold == wallet and loaded.run.encounter_picks == picks and loaded.run.trait_rank(TraitUpgradeCatalog.decode(free_id)["id"]) == 1, "free choice grants one rank with no charge or extra ordinary pick")
	verify(not loaded.run.choose_encounter(free_id, offer) and loaded.run.boss_reward_log[0]["choice"] == free_id and loaded.run.reward_queue.is_empty() and loaded.run.seen_encounters == seen, "boss upgrade consumes and journals one source without reserving traits")
	var copy: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
	copy._physics_process(0)
	loaded.capture_checkpoint(copy.snapshot())
	verify(not loaded.run.boss_active and copy.targets.size() == 3 and store.write(loaded.save_payload()), "choice resumes ordinary field and saves completed free grant")
	verify(GameSession.from_dict(store.read()).run.trait_levels == loaded.run.trait_levels, "completed free grant restores without replay")
	var fallback := RunModel.new()
	var pool: Array[String] = fallback._draft_boss()
	verify(pool.size() == 3 and not pool[0].begins_with("@"), "boss with no owned useful traits falls back to ordinary rewards")
	for id: String in TraitUpgradeCatalog.ALL: fallback.trait_levels[id] = 3
	verify(fallback._draft_boss().size() == 3, "maxed trait build uses safe ordinary rewards")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean(path)

func _migration(tree: SceneTree) -> void:
	var f: Dictionary = boss_setup(tree)
	var session: GameSession = f.session
	var world: ArcheryWorld = f.world
	# Actual v16 boss drafts contained ordinary candidates only; preserve rather than re-draft.
	session.run.choices.assign(["second_wind", "steady_power", "tempered_tip"])
	session.run.mastery_levels = {"damage": 2}
	session.run.mastery_unlocks.assign(["damage"])
	session.run.rebuild_stats()
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.save_payload()
	for key: String in ["trait_schema", "trait_levels"]: payload["run"].erase(key)
	var path: String = "user://tests/t12b-v16.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 16, "payload": payload}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v16") == bytes and int(JSON.parse_string(FileAccess.get_file_as_string(path))["version"]) == SaveStore.VERSION, "v16 archived byte for byte before version17")
	verify(loaded.run.trait_levels.is_empty() and loaded.run.mastery_levels == session.run.mastery_levels and loaded.run.stats.to_dict() == session.run.stats.to_dict(), "trait ranks start zero and mastery/build remain unchanged")
	verify(loaded.run.choices == session.run.choices and loaded.run.encounter_offer_id == session.run.encounter_offer_id and loaded.run.rng.state == session.run.rng.state and loaded.world_snapshot == JSON.parse_string(bytes)["payload"]["world"] and loaded.run.reward_queue == JSON.parse_string(bytes)["payload"]["run"]["reward_queue"], "old fixed boss choice/world/queue/RNG remains original")
	verify(not store.read().is_empty() and store.migration_notice.is_empty(), "repeat read never re-grants or re-drafts")
	world.queue_free()
	await tree.process_frame
	clean(path)

func _invalid() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	viable(run)
	equip(run, ["charged_breach"])
	run.open_skills()
	run.gold = 10000
	run.buy_trait("charged_breach", 0)
	var payload: Dictionary = session.to_dict()
	var path: String = "user://tests/t12b-invalid.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(payload), "legitimate paid rank saves")
	var good: String = FileAccess.get_file_as_string(path)
	for mutation: int in range(11):
		var bad: Dictionary = payload.duplicate(true)
		match mutation:
			0: bad["run"].erase("trait_schema")
			1: bad["run"].erase("trait_levels")
			2: bad["run"]["trait_levels"]["charged_breach"] = 1.5
			3: bad["run"]["trait_levels"]["charged_breach"] = 4
			4: bad["run"]["trait_levels"]["charged_breach"] = -1
			5: bad["run"]["trait_levels"]["charged_breach"] = NAN
			6: bad["run"]["trait_levels"]["unknown"] = 1
			7: bad["run"]["trait_levels"]["windfall"] = 1
			8: bad["run"]["trait_levels"]["piercing_split"] = 1
			9: bad["run"]["trait_schema"] = 1.5
			10: bad["run"]["trait_levels"] = []
		verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "invalid upgrade source rejected without overwriting good file: %d" % mutation)
	clean(path)

func clean(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".legacy-v16"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func same_flight(a: Dictionary, b: Dictionary) -> bool:
	# JSON can round 24*0.85^3 by one ULP; only this frozen damage gets a tolerance.
	if a["arrows"].size() != b["arrows"].size(): return false
	for i: int in range(a["arrows"].size()):
		if absf(float(a["arrows"][i]["stats"]["damage"]) - float(b["arrows"][i]["stats"]["damage"])) > 1.0e-12: return false
		a["arrows"][i]["stats"]["damage"] = 0.0
		b["arrows"][i]["stats"]["damage"] = 0.0
	return a == b
