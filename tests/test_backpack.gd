extends RefCounted

var assertion: Callable
var base: RefCounted
const SIX: Array[String] = ["piercing_split", "ricochet_haste", "swarm_precision", "unified_arrow", "critical_forging", "critical_ricochet"]
const PATH: String = "user://tests/t16-backpack.json"

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T16: " + message)

func equip(run: RunModel, ids: Array[String]) -> void:
	base._equip(run, ids)

func offer(run: RunModel, id: String) -> void:
	for index: int in range(10): run.record_defeat("backpack-%d" % run.defeated_count, 0, 8)
	run.offer_encounter()
	run.choices.assign([id, "second_wind", "windfall"])
	if EncounterCatalog.find(id).is_trait and not run.seen_encounters.has(id): run.seen_encounters.append(id)

func acquire(run: RunModel, id: String) -> void:
	offer(run, id)
	verify(run.choose_encounter(id, run.encounter_offer_id), "earned artifact occupies a slot: " + id)

func run_all(tree: SceneTree) -> void:
	_capacity_and_replace()
	_removal()
	await _flight(tree)
	await _boss_history(tree)
	_migration_and_validation()

func _capacity_and_replace() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for id: String in SIX: acquire(run, id)
	verify(run.backpack_full() and run.artifact_ids().size() == 6 and run.artifact_capacity == 6, "six real acquisitions fill a new run")
	offer(run, "heavy_draw")
	var token: int = run.encounter_offer_id
	var revision: int = run.artifact_revision
	var original: Dictionary = run.to_dict()
	verify(not run.choose_encounter("heavy_draw", token) and run.to_dict() == original, "full bag refuses seventh artifact without consuming reward")
	verify(not run.choose_encounter("heavy_draw", token - 1, SIX[0], revision) and not run.choose_encounter("heavy_draw", token, SIX[0], revision - 1), "stale offer/revision cannot replace")
	verify(not run.choose_encounter("heavy_draw", token, "windfall", revision) and run.to_dict() == original, "ordinary reward is never a removable item")
	var expected: Dictionary = run.preview_artifact_change("unified_arrow", "heavy_draw").to_dict()
	verify(run.choose_encounter("heavy_draw", token, "unified_arrow", revision), "full slot replacement commits")
	verify(run.artifact_ids().size() == 6 and run.discarded_artifacts.get("unified_arrow") == 0 and not run.encounter_picks.has("unified_arrow") and run.stats.to_dict() == expected, "replacement rebuilds sources with preview equality")
	verify(run.gold == original.gold and run.rng.state == int(original.rng_state) and run.pending_encounters == 0 and not run.choose_encounter("heavy_draw", token, SIX[0], revision), "one replacement costs no money, grants once and never rerolls")
	offer(run, "echo_strike")
	var shots: int = run.shots_left
	verify(run.choose_encounter("second_wind", run.encounter_offer_id) and run.shots_left == shots + 3 and run.artifact_ids().size() == 6, "ordinary immediate reward ignores capacity")
	offer(run, "armor_surplus")
	verify(run.can_skip_encounter() and run.skip_encounter(run.encounter_offer_id) and run.artifact_ids().size() == 6, "full bag may decline entire offer without changing build")
	var fresh: RunModel = session.start_run(true)
	verify(fresh.artifact_capacity == 6 and fresh.artifact_ids().is_empty() and fresh.discarded_artifacts.is_empty() and fresh.gold == 0, "new run clears inventory and coins")

func _removal() -> void:
	for id: String in TraitUpgradeCatalog.ALL:
		var run := RunModel.new()
		run.skill_levels = {"quantity": 3, "critical": 2, "penetration": 2, "ricochet": 2, "size": 2}
		var equipped: Array[String] = [id]
		if id.begins_with("branch_"): equipped.append("piercing_split")
		equip(run, equipped)
		run.trait_levels[id] = 3
		run.rebuild_stats()
		var preview: Dictionary = run.preview_artifact_change(id).to_dict()
		var coins: int = run.gold
		verify(not run.discard_artifact(id, run.artifact_revision), "closed backpack cannot discard " + id)
		run.trait_shop_open = true
		run.suspended = true
		verify(not run.discard_artifact(id, run.artifact_revision), "hub cannot discard " + id)
		run.suspended = false
		var revision: int = run.artifact_revision
		verify(run.discard_artifact(id, revision) and run.stats.to_dict() == preview, "discard source and conversion recalculation " + id)
		verify(run.discarded_artifacts.get(id) == 3 and not run.trait_levels.has(id) and not run.buy_trait(id, 0) and not run.discard_artifact(id, revision) and run.gold == coins, "no refund, hidden rank, duplicate discard or upgrade " + id)
		var restored: RunModel = RunModel.from_dict(run.to_dict())
		verify(restored.stats.to_dict() == preview and restored.discarded_artifacts == run.discarded_artifacts and not restored.trait_shop_open, "restore never reapplies discarded effects or UI permission " + id)
		verify(not run.encounter_has_gain(EncounterCatalog.find(id)), "discarded artifact cannot reenter pool " + id)
	var linked := RunModel.new()
	equip(linked, ["piercing_split", "branch_harvest"])
	linked.trait_shop_open = true
	verify(not linked.discard_artifact("piercing_split", linked.artifact_revision) and linked.artifact_removal_blocker("piercing_split").contains("枝上丰收"), "dependent artifact explains blocked parent removal")
	verify(linked.discard_artifact("branch_harvest", linked.artifact_revision) and linked.discard_artifact("piercing_split", linked.artifact_revision), "dependent can be removed then parent")
	var full := RunModel.new()
	equip(full, SIX)
	offer(full, "branch_harvest")
	verify(not full.choose_encounter("branch_harvest", full.encounter_offer_id, "piercing_split", full.artifact_revision), "incoming cannot replace its own prerequisite")

func _flight(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	equip(run, ["heavy_draw"])
	run.gold = 5000
	run.trait_shop_open = true
	verify(run.buy_trait("heavy_draw", 0), "backpack retains paid upgrades")
	var helper: RefCounted = preload("res://tests/test_boss.gd").new(assertion)
	var world: ArcheryWorld = helper.field(tree, session)
	world.direction = Vector2.RIGHT
	world.pull = 1
	world._release()
	var arrow: Arrow = world.arrows[0]
	arrow.set_physics_process(false)
	var frozen: Dictionary = arrow.snapshot()
	var spent: int = run.gold_spent
	verify(run.discard_artifact("heavy_draw", run.artifact_revision) and arrow.snapshot() == frozen and run.stats.damage == 24 and run.gold_spent == spent, "in-flight arrow freezes paid artifact; next launch uses rebuilt stats")
	session.capture_checkpoint(world.snapshot())
	clean()
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "discard plus frozen flight saves atomically")
	var saved: Dictionary = store.read()
	verify(not saved.is_empty(), "discarded flight can be read")
	if not saved.is_empty():
		var loaded := GameSession.from_dict(saved)
		var copy: ArcheryWorld = helper.field(tree, loaded, loaded.world_snapshot)
		var actual: Dictionary = copy.arrows[0].stats.to_dict()
		var expected: Dictionary = arrow.stats.to_dict()
		verify(absf(actual.damage - expected.damage) <= 1.0e-12, "frozen fractional damage survives JSON within one rounding step")
		expected.damage = actual.damage
		verify(actual == expected and loaded.run.stats.damage == 24 and loaded.run.discarded_artifacts.get("heavy_draw") == 1, "disk keeps old projectile and new inventory separately")
		copy.queue_free()
	world.queue_free()
	await tree.process_frame
	clean()

func _boss_history(tree: SceneTree) -> void:
	var fixture: RefCounted = preload("res://tests/test_trait_upgrades.gd").new(assertion)
	var data: Dictionary = fixture.boss_setup(tree)
	var session: GameSession = data.session
	var run: RunModel = session.run
	run.choices.assign(["@upgrade/piercing_split/1", "second_wind", "windfall"])
	verify(run.choose_encounter("@upgrade/piercing_split/1", run.encounter_offer_id), "real boss grants free artifact rank")
	run.trait_shop_open = true
	verify(run.discard_artifact("piercing_split", run.artifact_revision), "free upgraded artifact can be discarded")
	data.world._physics_process(0)
	session.capture_checkpoint(data.world.snapshot())
	clean()
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "boss historical upgrade remains valid after discarding active source")
	var saved: Dictionary = store.read()
	verify(not saved.is_empty() and saved.run.boss_reward_log[0].choice == "@upgrade/piercing_split/1" and saved.run.discarded_artifacts.piercing_split == 1 and not saved.run.trait_levels.has("piercing_split"), "historical rank is retained without reequipping")
	data.world.queue_free()
	await tree.process_frame
	clean()

func _migration_and_validation() -> void:
	clean()
	var session := GameSession.new()
	session.start_run()
	session.record_defeat("score", 500, 8)
	session.end_run("abandoned")
	var board: Array[Dictionary] = session.profile.leaderboard.entries
	var run: RunModel = session.start_run(true, "hell")
	var ids: Array[String] = SIX.duplicate()
	ids.append("heavy_draw")
	equip(run, ids)
	run.trait_levels["heavy_draw"] = 2
	run.rebuild_stats()
	var old: Dictionary = session.to_dict()
	for key: String in ["backpack_schema", "artifact_capacity", "artifact_revision", "discarded_artifacts"]: old.run.erase(key)
	var bytes: String = JSON.stringify({"version": 20, "payload": old}, "", true, true)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(PATH)
	var payload: Dictionary = store.read()
	verify(not payload.is_empty(), "v20 can migrate")
	if payload.is_empty(): return
	var loaded := GameSession.from_dict(payload)
	verify(FileAccess.get_file_as_string(PATH + ".legacy-v20") == bytes and loaded.run.artifact_capacity == 7 and loaded.run.artifact_ids().size() == 7 and loaded.run.trait_rank("heavy_draw") == 2, "migration preserves bytes, legacy overflow and upgrade ranks")
	verify(loaded.profile.leaderboard.entries == board and loaded.run.mode_id == "hell" and loaded.run.rng.state == run.rng.state, "v20 upgrade preserves leaderboard, difficulty and RNG")
	var valid: Dictionary = loaded.to_dict()
	verify(store.write(valid), "migrated overflow writes v21")
	for key: String in ["artifact_capacity", "artifact_revision", "discarded_artifacts", "backpack_schema"]:
		var broken: Dictionary = valid.duplicate(true)
		broken.run.erase(key)
		verify(not store.write(broken), "missing backpack field rejected " + key)
	var broken: Dictionary = valid.duplicate(true)
	broken.run.artifact_capacity = 6
	verify(not store.write(broken), "modern overflow is rejected")
	for discarded: Dictionary in [{"heavy_draw": 2}, {"windfall": 0}, {"echo_strike": 4}, {"echo_strike": -1}]:
		broken = valid.duplicate(true)
		broken.run.discarded_artifacts = discarded
		verify(not store.write(broken), "invalid discarded identity/rank/disjoint ledger rejected")
	verify(loaded.start_run(true).artifact_capacity == 6, "legacy extra slots end with the old adventure")
	clean()

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v20"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
