extends RefCounted

var assertion: Callable
var bosses: RefCounted
var bag: RefCounted
const PATH: String = "user://tests/t17-contracts.json"

func _init(check: Callable) -> void:
	assertion = check
	bosses = preload("res://tests/test_boss.gd").new(check)
	bag = preload("res://tests/test_backpack.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T17: " + message)

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v21"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func resolve(run: RunModel) -> void:
	while run.pending_encounters > 0:
		run.offer_encounter()
		run.choices.assign(["second_wind", "windfall", "steady_power"])
		verify(run.choose_encounter("second_wind", run.encounter_offer_id), "resolve earned reward without changing score or coin efficiency")

func kills(session: GameSession, count: int) -> void:
	for index: int in range(count):
		session.record_defeat("contract-%d" % session.run.defeated_count, 40, 8)
		resolve(session.run)

func run_all(tree: SceneTree) -> void:
	_values_and_economy()
	_rewards()
	await _ordinary(tree)
	await _boss_flight(tree)
	await _migration(tree)

func _values_and_economy() -> void:
	verify(ContractCatalog.ALL.size() == 8, "eight categories")
	var all: Dictionary = {}
	var store := SaveStore.new(PATH)
	for item: Dictionary in ContractCatalog.ALL:
		for rank: int in [1, 2]:
			var session := GameSession.new()
			var selection: Dictionary = {item.id: rank}
			var run: RunModel = session.start_run(false, "hell", selection)
			verify(run != null and run.challenge.risk == rank, "each rank starts " + item.id + str(rank))
			verify(store._valid_run(run.to_dict()), "each category valid at disk boundary " + item.id + str(rank))
			var restored := RunModel.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
			verify(restored.challenge == run.challenge and restored.field_parameters() == run.field_parameters(), "JSON numeric normalization " + item.id + str(rank))
		all[item.id] = 2
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "hell", all)
	verify(run.challenge.risk == 16 and run.initial_shots == 12 and run.artifact_capacity == 4 and run.supply_remaining() == 0, "max contract resource limits")
	verify(run.mode_parameters == {"target_health": 1.5, "boss_health": 2.0, "score": 1.0, "health_growth": 0.06}, "preset origin does not stack legacy Hell multipliers")
	var exposed: Dictionary = run.challenge
	exposed.selection.clear()
	verify(run.challenge.selection.size() == 8, "returned snapshot cannot mutate active contract")
	for invalid: Variant in [{"unknown": 1}, {"health": 0}, {"health": 3}, {"health": 1.5}, {"health": "2"}, {"health": true}, []]:
		verify(session.start_run(true, "normal", invalid) == null and session.run == run and not run.is_finished(), "invalid selection does not abandon existing run " + str(invalid))
	run.gold = 100000
	run.open_skills()
	var skill: RunSkillData = SkillCatalog.find("damage")
	var price: int = ceili(skill.cost * 1.5)
	verify(run.skill_price(skill) == price and run.buy(skill) and run.gold == 100000 - price and run.gold_spending.basic == price, "real basic purchase charges rounded contract price")
	verify(not run.buy_supply(run.supply_token()), "no purchase through API when supply prohibited")
	while not run.skill_is_mastery(skill): verify(run.buy(skill), "basic purchases reach mastery under price contract")
	price = ceili(skill.paced_price(0, true) * 1.5)
	var before_mastery: int = run.gold
	verify(run.skill_price(skill) == price and run.buy(skill) and run.gold == before_mastery - price and run.gold_spending.mastery == price, "mastery uses same contract price and spending bucket")
	run.close_skills()
	for id: String in ["piercing_split", "ricochet_haste", "swarm_precision", "unified_arrow"]: bag.acquire(run, id)
	verify(run.backpack_full() and run.artifact_ids().size() == 4, "four earned artifacts fill restricted bag")
	bag.offer(run, "heavy_draw")
	verify(not run.choose_encounter("heavy_draw", run.encounter_offer_id), "fifth artifact requires replacement")
	verify(run.choose_encounter("heavy_draw", run.encounter_offer_id, "unified_arrow", run.artifact_revision) and run.artifact_ids().size() == 4, "restricted bag replacement remains atomic")
	run.trait_shop_open = true
	var wallet: int = run.gold
	price = ceili(TraitUpgradeCatalog.find("heavy_draw").price(0) * 1.5)
	verify(run.trait_price("heavy_draw", 0) == price and run.buy_trait("heavy_draw", 0) and run.gold == wallet - price and run.gold_spending.traits == price, "artifact upgrade charges displayed contract price")
	verify(not run.buy_trait("heavy_draw", 0), "duplicate rank click cannot spend twice")
	var data: Dictionary = run.to_dict()
	verify(store._valid_run(data), "restricted bag and purchases form valid save")
	for key: String in ["risk", "version"]:
		var bad: Dictionary = data.duplicate(true)
		bad.challenge[key] += 1
		verify(not store._valid_run(bad), "reject modified snapshot " + key)
	for key: String in data.challenge.parameters:
		var bad: Dictionary = data.duplicate(true)
		bad.challenge.parameters[key] += 0.1
		verify(not store._valid_run(bad), "reject inconsistent sampled parameter " + key)
	for key: String in ["artifact_capacity", "contract_stage_base_score", "contract_stage_bonus_earned"]:
		var bad: Dictionary = data.duplicate(true)
		bad[key] += 100
		verify(not store._valid_run(bad), "reject inconsistent run ledger " + key)
	var limited := RunModel.new("normal", {"supply": 1})
	limited.gold = 1000
	limited.open_skills()
	verify(limited.buy_supply(limited.supply_token()) and limited.supply_remaining() == 0 and not limited.buy_supply(limited.supply_token()), "rank I supply grants exactly one purchase per stage")
	verify(store._valid_run(limited.to_dict()), "one-purchase contract has valid supply ledger")
	var bad: Dictionary = data.duplicate(true)
	bad.supply_parameters.limit = 2
	verify(not store._valid_run(bad), "reject reopened prohibited supplies")

func _rewards() -> void:
	var selection: Dictionary = {"health": 2, "armor": 2, "boss": 2, "quiver": 1, "supply": 2, "prices": 1, "slots": 2}
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "normal", selection)
	kills(session, 100)
	verify(run.defeat_score == 5600 and session.profile.total_score == 5600 and run.contract_stage_base_score == 4000 and run.contract_stage_bonus_earned == 0 and run.gold == 800, "ordinary risk pays score and XP, global risk waits for Boss")
	verify(run.begin_boss() and session.record_boss_defeat("boss1", 1200, 240), "earned Boss victory settles")
	verify(is_equal_approx(run.defeat_score, 10280) and is_equal_approx(session.profile.total_score, 10280) and run.gold == 1040, "Boss score plus stage base bonus paid once, coins unchanged")
	verify(is_equal_approx(run.contract_stage_bonus_earned, 3120) and run.contract_stage_base_score == 0 and is_equal_approx(run.boss_reward_log[0].contract_bonus, 3120), "stage ledger resets and logs actual awarded bonus")
	verify(not session.record_boss_defeat("boss1", 1200, 240) and is_equal_approx(run.defeat_score, 10280), "duplicate Boss settlement cannot replay stage bonus")
	resolve(run)
	run.boss_active = false # World normally reopens the field after the victory choice.
	kills(session, 100)
	verify(run.contract_stage_base_score == 4000 and run.begin_boss() and session.record_boss_defeat("boss2", 1200, 240), "second stage collects only new ordinary base points")
	verify(is_equal_approx(run.defeat_score, 20560) and is_equal_approx(run.contract_stage_bonus_earned, 6240), "second stage does not reuse first stage points")
	resolve(run)
	run.boss_active = false
	session.end_run("abandoned")
	verify(session.profile.leaderboard.entries.size() == 1 and session.profile.leaderboard.entries[0].challenge == run.challenge and session.last_run_summary.challenge == run.challenge, "rank and terminal summary retain exact contract")
	clean()
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "completed contract and ranking save")
	var restored := GameSession.from_dict(store.read())
	verify(restored.profile.leaderboard.entries[0].challenge == run.challenge, "ranking metadata survives JSON")
	verify(restored.last_run_summary.challenge == run.challenge, "terminal summary uses canonical contract numeric types")
	verify(store.write(restored.save_payload()), "completed contract can be saved again after disk reload")
	restored.return_to_lobby()
	restored.profile.unlock_active("sunshot")
	restored.capture_checkpoint(restored.world_snapshot)
	verify(store.write(restored.save_payload()) and GameSession.from_dict(store.read()).profile.equipped_active == "sunshot", "post-completion permanent edits persist before starting another adventure")
	restored.end_run("abandoned")
	verify(restored.profile.leaderboard.entries.size() == 1, "continued terminal run does not duplicate rank")
	var early := GameSession.new()
	early.start_run(false, "normal", {"boss": 2, "quiver": 2})
	kills(early, 9)
	early.end_run("abandoned")
	verify(early.profile.total_score == 360 and early.last_run_summary.defeat_score == 360 and early.run.contract_stage_bonus_earned == 0, "quitting before Boss cannot earn Boss or global score bonus")
	clean()

func _ordinary(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "hell", {"health": 2, "armor": 2, "bullseye": 2})
	var world: ArcheryWorld = bosses.field(tree, session)
	world.boss_enabled = false
	var first: ArcheryTarget = world.targets[0]
	first.anchor = Vector2(180, 238)
	first.tick(0, 0)
	for index: int in range(1, world.targets.size()):
		world.targets[index].anchor = Vector2(350 + index * 80, 100)
		world.targets[index].tick(0, 0)
	verify(first.max_hp == 72 and first.armor == 4 and first.reward_score == 40 and first.reward_gold == 8, "real target samples HP and armor while ledger retains base reward")
	verify(first.is_bullseye(first.global_position) and not first.is_bullseye(first.global_position + Vector2(0, first.definition.radius * first.global_scale.y * 0.2)), "shrunk bullseye uses actual hit boundary")
	bosses.fire(world, 1000, 3)
	bosses.tick(world, 220)
	verify(run.defeated_count == 1 and run.defeat_score == 64 and session.profile.total_score == 64 and run.gold == 8 and run.contract_stage_base_score == 40, "actual three-arrow kill receives one scoped reward")
	world._settle_shots()
	verify(run.defeat_score == 64, "repeated real volley cannot repay")
	world.queue_free()
	await tree.process_frame

func _boss_flight(tree: SceneTree) -> void:
	clean()
	var session := GameSession.new()
	var run: RunModel = session.start_run(false, "normal", {"boss": 2, "quiver": 1, "supply": 2, "slots": 2})
	kills(session, 100)
	var world: ArcheryWorld = bosses.field(tree, session)
	world._physics_process(0)
	verify(world.boss.max_hp == 5760 and world.boss.armor == 20 and world.targets.is_empty(), "Boss contract spawns stronger Boss and clears ordinary field")
	world.boss.hp = 2000
	world.boss.refresh_phase()
	bosses.fire(world, 100000, 3, 1000)
	var shot: Dictionary = world.arrows[0].snapshot()
	session.capture_checkpoint(world.snapshot())
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "contract stage and live Boss arrows save")
	var disk: Dictionary = store.read()
	verify(not disk.is_empty(), "contract flight reads")
	if disk.is_empty():
		world.queue_free()
		await tree.process_frame
		return
	var loaded := GameSession.from_dict(disk)
	var copy: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
	verify(copy.arrows[0].snapshot() == shot and loaded.run.challenge == run.challenge and loaded.run.contract_stage_base_score == 4000, "disk preserves projectile, challenge and pending stage score")
	for field: ArcheryWorld in [world, copy]: bosses.tick(field, 180)
	verify(run.bosses_defeated == 1 and loaded.run.bosses_defeated == 1 and is_equal_approx(run.defeat_score, 8160) and is_equal_approx(loaded.run.defeat_score, 8160), "original and continued Boss pay same one-time score")
	verify(is_equal_approx(loaded.profile.total_score, 8160) and loaded.run.supply_remaining() == 0 and loaded.run.artifact_capacity == 4, "victory does not reopen banned supply or restore bag slots")
	loaded.capture_checkpoint(copy.snapshot())
	verify(store.write(loaded.save_payload()), "post-victory fixed reward and stage ledger save")
	for field: ArcheryWorld in [world, copy]: field.queue_free()
	await tree.process_frame
	clean()

func _migration(tree: SceneTree) -> void:
	clean()
	var session := GameSession.new()
	session.start_run(false, "normal")
	session.record_defeat("old-rank", 40, 8)
	session.end_run("abandoned")
	var old_board: Array[Dictionary] = session.profile.leaderboard.entries.duplicate(true)
	var run: RunModel = session.start_run(false, "hell")
	bag.acquire(run, "heavy_draw")
	run.gold = 10000
	run.trait_shop_open = true
	run.buy_trait("heavy_draw", 0)
	run.discard_artifact("heavy_draw", run.artifact_revision)
	var world: ArcheryWorld = bosses.field(tree, session)
	bosses.fire(world, 24)
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.to_dict()
	for key: String in ["challenge_schema", "challenge", "contract_stage_base_score", "contract_stage_bonus_earned"]: payload.run.erase(key)
	var bytes: String = JSON.stringify({"version": 21, "payload": payload}, "", true, true)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(PATH)
	var disk: Dictionary = store.read()
	verify(not disk.is_empty(), "v21 backpack save migrates")
	if not disk.is_empty():
		var restored := GameSession.from_dict(disk)
		verify(restored.run.challenge.is_empty() and restored.run.mode_id == "hell" and restored.run.mode_parameters == run.mode_parameters, "legacy Hell keeps original score and growth")
		verify(restored.profile.leaderboard.entries == old_board, "v21 migration retains existing top-three records")
		verify(restored.run.discarded_artifacts == run.discarded_artifacts and restored.run.gold_spent == run.gold_spent and restored.world_snapshot == JSON.parse_string(bytes).payload.world, "migration preserves discarded paid artifacts and flight")
		verify(FileAccess.get_file_as_string(PATH + ".legacy-v21") == bytes, "original v21 bytes archived")
		var current: String = FileAccess.get_file_as_string(PATH)
		store.read()
		verify(FileAccess.get_file_as_string(PATH) == current, "repeated migration does not alter save")
	world.queue_free()
	await tree.process_frame
	clean()
