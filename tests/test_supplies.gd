extends RefCounted

var assertion: Callable
var base: RefCounted
var bosses: RefCounted
const PATH: String = "user://tests/t13-supply.json"

func _init(check: Callable) -> void:
	assertion = check
	base = preload("res://tests/test_traits.gd").new(check)
	bosses = preload("res://tests/test_boss.gd").new(check)

func verify(ok: bool, message: String) -> void:
	assertion.call(ok, "T13: " + message)

func run_all(tree: SceneTree) -> void:
	_economy()
	_exhaustion()
	_rewards()
	_disk()
	await _flight(tree)
	await _migration(tree)

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v17"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func _economy() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 1000000000
	var seed: int = run.rng.state
	var stats: Dictionary = run.stats.to_dict()
	var token: Dictionary = run.supply_token()
	verify(not run.buy_supply(token), "playing cannot buy a hidden supply")
	run.open_skills()
	verify(run.supply_remaining() == 2 and run.supply_price() == 24, "configured first segment has two draws at first price24")
	verify(run.buy_supply(token) and run.shots_left == 11 and run.gold == 999999976, "first purchase grants exactly one draw and charges24")
	verify(not run.buy_supply(token) and run.gold_spent == 24, "same stale click cannot charge again")
	verify(run.supply_price() == 39 and run.supply_remaining() == 1, "price rounds up and rises per run purchase")
	verify(run.buy_supply(run.supply_token()) and run.shots_left == 12 and run.gold_spent == 63, "second purchase costs39")
	for index: int in range(20): verify(not run.buy_supply(run.supply_token()), "unlimited wallet cannot bypass two-purchase limit %d" % index)
	verify(run.stats.to_dict() == stats and run.rng.state == seed, "supplies leave build and RNG unchanged")
	for index: int in range(4):
		session.return_to_lobby()
		verify(not run.buy_supply(run.supply_token()), "suspended run cannot buy")
		session.resume_run()
		run.close_skills()
		run.open_skills()
		verify(run.supply_remaining() == 0 and run.supply_price() == 62, "hub and skills reopening preserve limit and cumulative price")
	# Legitimate Boss event resets only the segment budget.
	run.close_skills()
	bosses.prime(run, 100)
	verify(run.begin_boss() and session.record_boss_defeat("boss1", 1200, 240), "Boss victory accepted once")
	verify(run.supply_remaining() == 2 and run.supply_segment == 1 and run.supply_price() == 62, "victory resets allowance while preserving higher price")
	verify(not session.record_boss_defeat("boss1", 1200, 240) and run.supply_remaining() == 2, "duplicate victory never resets again")
	run.offer_encounter()
	var reward: String = run.choices[0]
	run.choose_encounter(reward, run.encounter_offer_id)
	run.open_skills()
	verify(run.buy_supply(run.supply_token()) and run.supply_remaining() == 1 and run.supply_price() == 99, "next segment uses third run purchase price")
	verify(not session.record_boss_defeat("boss1", 1200, 240) and run.supply_remaining() == 1, "late duplicate cannot refresh spent next allowance")
	var spent: int = run.gold_spent
	var skill: RunSkillData = SkillCatalog.find(&"damage")
	verify(run.buy(skill) and run.gold_spending["basic"] == skill.cost, "basic upgrade charges basic ledger")
	run.skill_levels["damage"] = skill.max_level
	run.rebuild_stats()
	var price: int = run.skill_price(skill)
	verify(run.buy(skill) and run.gold_spending["mastery"] == price, "mastery charges its own ledger")
	var equipped: Array[String] = ["heavy_draw"]
	base._equip(run, equipped)
	price = TraitUpgradeCatalog.find("heavy_draw").price(0)
	verify(run.buy_trait("heavy_draw", 0) and run.gold_spending["traits"] == price, "trait reinforcement charges its own ledger")
	verify(run.gold_spent == spent + skill.cost + int(run.gold_spending["mastery"]) + price and run.gold_spending["supplies"] == 125, "four kinds of expenditure accumulate once")
	var rich := RunModel.new()
	rich.gold = 999999999
	rich.record_defeat("wallet-cap", 0, 10)
	verify(rich.gold == 1000000000 and rich.gold_earned == 10, "wallet stays within existing save cap while income keeps actual credited amount")
	verify(SupplyRules.price(run.supply_parameters, 10000000) == 1000000000, "very late price caps without overflow")
	var cap: Dictionary = run.supply_parameters.duplicate()
	cap["first_cost"] = 1000000000
	verify(SupplyRules.price(cap, 0) == 1000000000, "capped starting price works")
	var old: Dictionary = run.to_dict()
	session.end_run("abandoned")
	verify(session.last_run_summary["gold_spent"] == run.gold_spent and session.last_run_summary["supply_total_bought"] == 3 and run.gold == 0, "ending keeps earned/spent totals but clears wallet")
	verify(not run.buy_supply(old) and run.restore_shots(1) == 0, "ended run cannot revive")
	var next: RunModel = session.start_run()
	verify(next.supply_total_bought == 0 and next.supply_remaining() == 2 and next.supply_price() == 24 and next.gold_spent == 0 and next.gold == 0, "only new run resets price, quota and ledger")

func _exhaustion() -> void:
	for wallet: int in [0, 23, 24, 1000000000]:
		var session := GameSession.new()
		var run: RunModel = session.start_run()
		run.gold = wallet
		run.shots_left = 0
		run.settle_volley()
		if wallet < 24:
			verify(run.is_finished() and not session.has_active_run() and run.gold == 0, "insufficient funds end directly: %d" % wallet)
		else:
			verify(run.phase == RunModel.Phase.SUPPLY and session.has_active_run(), "eligible exhaustion offers buy or end: %d" % wallet)
			var token: Dictionary = run.supply_token()
			run.settle_volley()
			verify(run.supply_token() == token and not run.consume_shot() and not run.open_skills() and run.restore_shots(1) == 0, "decision is fixed and blocks further combat")
			for field: String in token:
				var stale: Dictionary = token.duplicate()
				stale[field] += 1
				verify(not run.buy_supply(stale), "reject stale supply token field " + field)
			verify(not run.decline_supply(run.supply_offer_id + 1), "stale decline cannot end another decision")
			verify(run.buy_supply(token) and run.phase == RunModel.Phase.PLAYING and run.shots_left == 1, "decision purchase continues current field")
			verify(not run.buy_supply(token) and not run.decline_supply(int(token["offer_id"])), "handled decision cannot be replayed")
			run.consume_shot()
			run.settle_volley()
			if wallet == 24:
				verify(run.is_finished(), "price increase with empty wallet ends next draw")
			else:
				verify(run.phase == RunModel.Phase.SUPPLY and run.supply_offer_id == 2, "second eligible decision gets distinct identity")
				run.buy_supply(run.supply_token())
				run.consume_shot()
				run.settle_volley()
				verify(run.is_finished() and run.gold == 0 and run.gold_spent == 63, "quota exhaustion ends despite huge remaining wealth")
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 100
	run.shots_left = 0
	run.settle_volley()
	var offer: int = run.supply_offer_id
	session.return_to_lobby()
	verify(not run.decline_supply(offer) and not run.buy_supply(run.supply_token()), "hub suspends decision actions")
	session.resume_run()
	verify(run.decline_supply(offer) and run.is_finished() and session.last_run_summary["gold_discarded"] == 100, "explicit decline ends and records discarded wallet")
	verify(not run.decline_supply(offer) and not run.buy_supply(run.supply_token()), "terminal decision stays terminal")

func _rewards() -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	for index: int in range(10): session.record_defeat("pending%d" % index, 40, 8)
	run.shots_left = 0
	run.settle_volley()
	verify(run.phase == RunModel.Phase.CHOICE and run.supply_offer_id == 0, "earned ordinary choice precedes supply decision")
	run.choices.assign(["second_wind", "windfall", "rainfall"])
	run.choose_encounter("second_wind", run.encounter_offer_id)
	run.settle_volley()
	verify(run.phase == RunModel.Phase.PLAYING and run.shots_left > 0 and run.supply_offer_id == 0, "free encounter draws prevent premature prompt")
	# Model-level talent refund uses the same completed draw transaction.
	run.shots_left = 1
	run.consume_shot()
	run.talent_effects["kill_refund"] = 1.0
	var hits: Array = [{"hit_id": "1:0:refund", "event_id": "refund", "effective": 1.0, "broken": true, "bullseye": false, "critical": false, "reward_score": 40.0, "reward_gold": 8.0}]
	verify(session.settle_shot(run.shot_sequence, hits), "final family settlement applies guaranteed talent refund")
	run.settle_volley()
	verify(run.shots_left == 1 and run.phase == RunModel.Phase.PLAYING and run.supply_offer_id == 0, "refund completes before zero-draw evaluation")

func _disk() -> void:
	clean()
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 200
	run.open_skills()
	run.buy_supply(run.supply_token())
	run.close_skills()
	run.shots_left = 0
	run.settle_volley()
	session.capture_checkpoint({})
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "fixed zero-draw decision writes v18")
	var original: Dictionary = store.read()
	var restored: GameSession = GameSession.from_dict(original)
	verify(restored.run.to_dict() == run.to_dict() and restored.run.phase == RunModel.Phase.SUPPLY, "disk restores exact allowance, price, ledger, offer and RNG")
	var token: Dictionary = restored.run.supply_token()
	verify(restored.run.buy_supply(token) and not restored.run.buy_supply(token) and restored.run.gold_spent == 63, "continued decision charges once")
	for change: Array in [["supply_total_bought", -1], ["supply_total_bought", 1.5], ["supply_segment_bought", 3], ["supply_segment", 1], ["supply_offer_id", 0], ["supply_offer_id", 4], ["gold_spent", 0], ["gold_spent", NAN], ["shots_left", 1], ["gold", 38], ["phase", 6], ["economy_schema", 2], ["pending_encounters", 1], ["finished_reason", "exhausted"]]:
		var bad: Dictionary = original.duplicate(true)
		bad["run"][change[0]] = change[1]
		verify(not store.write(bad), "reject invalid decision field: " + str(change))
	for change: Array in [["limit", 0], ["limit", 11], ["draws", 0], ["draws", 1.5], ["first_cost", 0], ["growth", 1.0], ["growth", NAN], ["growth", INF]]:
		var bad: Dictionary = original.duplicate(true)
		bad["run"]["supply_parameters"][change[0]] = change[1]
		verify(not store.write(bad), "reject invalid sampled supply parameters: " + str(change))
	for key: String in ["supply_parameters", "supply_total_bought", "supply_segment_bought", "supply_segment", "supply_offer_id", "gold_spent", "gold_spending", "economy_schema"]:
		var bad: Dictionary = original.duplicate(true)
		bad["run"].erase(key)
		verify(not store.write(bad), "current write requires economy field " + key)
	for category: String in run.gold_spending:
		var bad: Dictionary = original.duplicate(true)
		bad["run"]["gold_spending"][category] += 1
		verify(not store.write(bad), "ledger sum must match: " + category)
	var bad: Dictionary = original.duplicate(true)
	bad["world"]["waiting_for_settle"] = true
	verify(not store.write(bad), "decision cannot save before world settlement")
	restored.capture_checkpoint({})
	verify(store.write(restored.save_payload()), "post-purchase state persists")
	var good: String = FileAccess.get_file_as_string(PATH)
	var damaged := FileAccess.open(PATH, FileAccess.WRITE)
	damaged.store_string("{bad")
	damaged.close()
	var fallback := GameSession.from_dict(store.read())
	verify(fallback.run.supply_total_bought == 1 and fallback.run.phase == RunModel.Phase.SUPPLY and fallback.run.gold_spent == 24, "corrupt latest save restores previous whole transaction")
	verify(fallback.run.buy_supply(fallback.run.supply_token()) and fallback.run.gold_spent == 63, "backup can complete decision once without double charge")
	var future := FileAccess.open(PATH, FileAccess.WRITE)
	future.store_string(good.replace('"version":%d' % SaveStore.VERSION, '"version":999'))
	future.close()
	store.read()
	verify(store.write_blocked and not store.write(restored.save_payload()), "future version protection remains intact")
	clean()

func _flight(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 200
	run.shots_left = 1
	var world: ArcheryWorld = base._world(tree, session)
	world.boss_enabled = false
	var parent: Arrow = base._primary(world, Vector2(100, 100), Vector2(400, 0))
	var shot: int = parent.shot_id
	var child := Arrow.new()
	child.setup(Vector2(120, 100), Vector2(350, 0), parent.stats, 1, run.rng)
	child.shot_id = shot
	child.effects = ArrowEffects.from_dict(parent.effects.to_dict())
	child.source_id = 1
	world.projectile_ledger[str(shot)]["children"] = 1
	child.parent_source_id = parent.source_id
	world._attach_arrow(child)
	child.set_physics_process(false)
	world.reload_left = 0.3
	var frozen: Dictionary = world.snapshot()
	run.open_skills()
	verify(run.buy_supply(run.supply_token()) and world.snapshot() == frozen and run.shots_left == 1, "in-flight skill supply preserves family and current reload")
	run.close_skills()
	run.shots_left = 0
	parent._finish()
	world._physics_process(0)
	verify(run.phase == RunModel.Phase.PLAYING and world.arrows.size() == 1 and run.supply_offer_id == 0, "no prompt while descendant remains in flight")
	child._finish()
	world._physics_process(0)
	verify(run.phase == RunModel.Phase.SUPPLY and world.arrows.is_empty() and world.pending_volleys.is_empty() and run.last_settled_shot == shot, "prompt only after entire family settles")
	var snapshot: Dictionary = world.snapshot()
	clean()
	session.capture_checkpoint(snapshot)
	var store := SaveStore.new(PATH)
	verify(store.write(session.save_payload()), "completed family decision saves real world")
	var loaded := GameSession.from_dict(store.read())
	var continued: ArcheryWorld = bosses.field(tree, loaded, loaded.world_snapshot)
	verify(continued.is_settled() and not continued.waiting_for_settle and continued.snapshot() == snapshot, "decision Continue keeps completed family settled")
	loaded.capture_checkpoint(continued.snapshot())
	verify(store.write(loaded.save_payload()), "decision can save again immediately after Continue")
	continued.queue_free()
	clean()
	var score: float = run.defeat_score
	verify(run.buy_supply(run.supply_token()) and run.shots_left == 1 and world.snapshot() == snapshot and run.defeat_score == score, "buying final supply continues exact settled world")
	world.queue_free()
	await tree.process_frame

func _migration(tree: SceneTree) -> void:
	clean()
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	run.gold = 50
	run.gold_earned = 100
	var world: ArcheryWorld = base._world(tree, session)
	base._primary(world, Vector2(100, 100), Vector2(300, 0))
	world.reload_left = 0.27
	session.capture_checkpoint(world.snapshot())
	var payload: Dictionary = session.to_dict()
	payload["run"].erase("economy_schema")
	var bytes: String = JSON.stringify({"version": 17, "payload": payload}, "", true, true)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(PATH)
	var loaded := GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(PATH + ".legacy-v17") == bytes and JSON.parse_string(FileAccess.get_file_as_string(PATH))["version"] == SaveStore.VERSION, "v17 raw bytes archived before migration")
	verify(loaded.run.supply_total_bought == 0 and loaded.run.supply_remaining() == 2 and loaded.run.gold_spent == 50 and loaded.run.gold_spending["legacy"] == 50, "old active ledger reconstructs unclassified spend and grants new segment allowance")
	verify(loaded.world_snapshot == JSON.parse_string(bytes)["payload"]["world"] and loaded.run.rng.state == run.rng.state and loaded.run.gold == 50 and loaded.run.shots_left == 9, "migration preserves old in-flight stats, reload, RNG and wallet")
	var current: String = FileAccess.get_file_as_string(PATH)
	store.read()
	verify(FileAccess.get_file_as_string(PATH) == current and store.migration_notice.is_empty(), "repeat read never remigrates allowance or spend")
	# Terminal v17 summary has the original wallet before clearing.
	session.end_run("abandoned")
	payload = session.to_dict()
	payload["run"].erase("economy_schema")
	var terminal := GameSession.from_dict(payload)
	verify(terminal.run.is_finished() and terminal.run.gold_spent == 50 and terminal.run.gold == 0 and not terminal.run.buy_supply(terminal.run.supply_token()), "old ended run uses discarded wallet and never revives")
	world.queue_free()
	await tree.process_frame
	clean()
