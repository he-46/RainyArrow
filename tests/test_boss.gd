extends RefCounted
## T10-A: real arrows, threshold choices, clear/rebuild identities and v7 migration.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T10-A: " + message)

func prime(run: RunModel, count: int) -> void:
	run.defeated_count = count
	run.difficulty_step = count
	run.encounter_rewards_generated = count / 10
	run.encounter_picks = {"windfall": count / 10}
	run.rebuild_stats()

func field(tree: SceneTree, session: GameSession, saved: Dictionary = {}) -> ArcheryWorld:
	var world := ArcheryWorld.new()
	world.run = session.run
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.shot_settled.connect(session.settle_shot)
	world.build_field(saved)
	return world

func tick(world: ArcheryWorld, steps: int) -> void:
	for index: int in range(steps):
		if world.run.suspended or world.run.phase != RunModel.Phase.PLAYING: continue
		for arrow: Arrow in world.arrows.duplicate():
			arrow.set_physics_process(false)
			arrow._physics_process(1.0 / 120.0)
		world._physics_process(1.0 / 120.0)

func fire(world: ArcheryWorld, damage: float, count: int = 1, penetration: int = 0) -> void:
	world.run.stats.damage = damage
	world.run.stats.gravity = 0
	world.run.stats.crit_chance = 0
	world.run.stats.arrow_count = count
	world.run.stats.spread_degrees = 0
	world.run.stats.armor_penetration = penetration
	world.run.stats.bounces = 0
	world.direction = (world.boss.position + Vector2(0, 40) - ArcheryWorld.BOW).normalized() if world.boss != null else Vector2.RIGHT
	world.pull = 1
	world.reload_left = 0
	world._release()
	for arrow: Arrow in world.arrows: arrow.set_physics_process(false)

func choose_safe(run: RunModel) -> void:
	while run.phase == RunModel.Phase.CHOICE:
		if run.can_skip_encounter():
			run.skip_encounter(run.encounter_offer_id)
			continue
		for id: String in run.choices.duplicate():
			var reward: EncounterData = EncounterCatalog.find(id)
			if not reward.is_trait and reward.draws == 0 and run.encounter_has_gain(reward):
				run.choose_encounter(id, run.encounter_offer_id)
				break
			if id == run.choices.back():
				run.choose_encounter("second_wind", run.encounter_offer_id)

func run_all(tree: SceneTree) -> void:
	tree.paused = false
	await _life_cycle(tree)
	await _over_threshold(tree)
	await _zero_draws(tree)
	await _migration(tree)
	await _main_ui(tree)

func _life_cycle(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	prime(run, 99)
	var world: ArcheryWorld = field(tree, session)
	world._physics_process(0)
	verify(world.boss == null and not run.boss_due() and run.boss_next_defeats == 100, "99 kills has ordinary targets and the first 100 threshold")
	world.targets[0].anchor = Vector2(180, 238)
	world.targets[0].hp = 1
	world.targets[0].tick(0, 0)
	var old_ids: Array[String] = []
	for target: ArcheryTarget in world.targets: old_ids.append(target.defeat_id())
	fire(world, 100)
	tick(world, 100)
	verify(run.defeated_count == 100 and run.phase == RunModel.Phase.CHOICE and run.boss_due(), "the real hundredth kill offers its encounter before Boss entry")
	verify(world.boss == null and world.targets.size() == 3, "choice keeps the old field until entry")
	verify(run.pending_encounters == 1 and run.score == 40 and session.profile.total_defeats == 1, "the threshold kill rewards exactly once")
	var offer: Array[String] = run.choices.duplicate()
	var offer_id: int = run.encounter_offer_id
	session.capture_checkpoint(world.snapshot())
	var waiting: GameSession = GameSession.from_dict(session.save_payload())
	verify(waiting.run.choices == offer and waiting.run.encounter_offer_id == offer_id and waiting.run.boss_due(), "pending Boss and fixed choice survive a checkpoint together")
	choose_safe(run)
	var coins: int = run.gold
	var xp: float = session.profile.total_score
	var draws: int = run.shots_left
	world._physics_process(0)
	verify(run.boss_active and run.boss_round == 1 and run.boss_next_defeats == 200, "first entry consumes only the 100 threshold")
	verify(world.targets.is_empty() and world.boss != null and world.boss.slot == -1, "entry clears every ordinary collider and creates one distinct Boss")
	verify(run.gold == coins and session.profile.total_score == xp and run.shots_left == draws and run.defeated_count == 100, "automatic shattering awards no coins, XP, refunds or kill progress")
	verify((world.boss.collider.shape as RectangleShape2D).size == Vector2(46, 124) and world.boss.max_hp == 2880 and world.boss.armor == 20, "mechanical collider and tripled first-round values are sampled")
	for node: Node in tree.get_nodes_in_group("archery_targets"):
		if node.get_parent() == world: verify(node == world.boss, "only the Boss remains in this world's target group")
	tick(world, 400)
	verify(world.targets.is_empty() and world.boss.hp == world.boss.max_hp, "ordinary respawn timers cannot repopulate a Boss fight")
	verify(not session.record_defeat("fake-normal", 40, 8), "ordinary kill API cannot mint progress during a Boss fight")
	fire(world, 120)
	tick(world, 160)
	verify(world.boss.hp == 2780 and run.defeated_count == 100 and run.score == 40, "a real nonlethal Boss arrow damages through armor without rewards")
	verify(session.profile.total_score == xp and run.gold == coins and world.pending_volleys.is_empty(), "nonlethal shot settlement gives no Boss score or currency")
	# Store a damaged Boss with a live arrow and a spent draw.
	fire(world, 120)
	var arrow_state: Dictionary = world.arrows[0].snapshot()
	session.return_to_lobby()
	session.capture_checkpoint(world.snapshot())
	var path: String = "user://tests/t10a-flight.json"
	clean(path)
	var store := SaveStore.new(path)
	verify(store.write(session.save_payload()), "v8 accepts a suspended damaged Boss and its live arrow")
	var loaded: GameSession = GameSession.from_dict(store.read())
	verify(loaded.run.suspended and loaded.run.boss_active and loaded.run.boss_round == 1 and loaded.run.boss_next_defeats == 200, "disk retains Boss mode, round, next threshold and lobby pause")
	verify(loaded.run.shots_left == run.shots_left and loaded.run.gold == run.gold and loaded.run.rng.state == run.rng.state, "disk restores spent draws, wallet and combat RNG")
	loaded.resume_run()
	var restored: ArcheryWorld = field(tree, loaded, loaded.world_snapshot)
	verify(restored.targets.is_empty() and restored.boss.snapshot() == world.boss.snapshot() and restored.arrows[0].snapshot() == arrow_state, "lazy world restoration preserves exact Boss HP and launch snapshot")
	for arrow: Arrow in restored.arrows: arrow.set_physics_process(false)
	tick(restored, 160)
	verify(restored.boss.hp == 2680 and loaded.run.defeated_count == 100, "restored live arrow hits the damaged Boss once")
	loaded.capture_checkpoint(restored.snapshot())
	verify(store.write(loaded.save_payload()), "restored nonlethal settlement is still a valid transaction")
	var good: String = FileAccess.get_file_as_string(path)
	var bad: Dictionary = loaded.to_dict()
	bad["world"]["targets"] = [{"hp": 10}]
	verify(not store.write(bad) and FileAccess.get_file_as_string(path) == good, "Boss save with ordinary targets is rejected without overwriting")
	bad = loaded.to_dict()
	bad["world"]["boss"] = null
	verify(not store.write(bad), "active Boss cannot be saved with a missing Boss body")
	bad = loaded.to_dict()
	bad["run"]["boss_next_defeats"] = 100
	verify(not store.write(bad), "spent threshold cannot be rolled back by inconsistent save data")
	bad = loaded.to_dict()
	bad["run"].erase("boss_schema")
	verify(not store.write(bad), "new saves cannot silently fall back to a legacy Boss baseline")
	# Multi-arrow victory waits for the full family; new field IDs cannot alias old kills.
	var boss_xp: float = loaded.profile.total_score
	var boss_gold: int = loaded.run.gold
	var boss_reward: float = restored.boss.reward_gold * loaded.run.stats.gold_multiplier
	loaded.run.shots_left = 2
	fire(restored, 100000, 3, 21)
	tick(restored, 92)
	verify(restored.boss != null and restored.boss.hp == 0 and loaded.run.boss_active and not restored.arrows.is_empty(), "lethal Boss contact waits for all penetrating arrows before transition")
	loaded.capture_checkpoint(restored.snapshot())
	verify(store.write(loaded.save_payload()), "uncredited lethal Boss and remaining arrows save together")
	var post_hit: Dictionary = store.read()
	restored.queue_free()
	loaded = GameSession.from_dict(post_hit)
	restored = field(tree, loaded, loaded.world_snapshot)
	for arrow: Arrow in restored.arrows: arrow.set_physics_process(false)
	verify(restored.boss.hp == 0 and loaded.run.bosses_defeated == 0 and restored.targets.is_empty(), "restoring a lethal in-flight hit neither heals Boss nor credits it prematurely")
	tick(restored, 180)
	verify(loaded.run.pending_encounters == 1 and loaded.run.reward_source()["kind"] == "boss", "victory waits for one Boss reward without ordinary progress")
	choose_safe(loaded.run)
	restored._physics_process(0)
	verify(not loaded.run.boss_active and loaded.run.bosses_defeated == 1 and loaded.run.boss_round == 1 and restored.boss == null, "three arrows award one Boss victory and return to ordinary mode")
	verify(loaded.run.defeated_count == 100 and loaded.run.difficulty_step == 100 and loaded.run.pending_encounters == 0, "Boss victory never advances ordinary kills, difficulty or ten-kill encounters")
	verify(loaded.profile.total_score == boss_xp + 1200 and loaded.profile.total_defeats == 1 and loaded.run.score == 1240, "Boss grants permanent score without inflating ordinary kill totals")
	verify(loaded.run.gold == boss_gold + floori(boss_reward) and loaded.run.shots_left == 4, "Boss coin reward pays once and victory adds three draws")
	verify(restored.targets.size() == 3 and not loaded.run.is_finished(), "victory rebuilds an ordinary field in the same playable run")
	for target: ArcheryTarget in restored.targets:
		verify(not old_ids.has(target.defeat_id()) and target.hp == target.max_hp and target.spawn_difficulty == 100, "new target samples current growth and uses a fresh defeat identity")
	verify(not loaded.record_boss_defeat("boss1", 1200, 240), "victory ledger rejects replay after returning to field")
	var first_hp: float = RunModel.BOSS_RULES.values(1)["max_hp"]
	prime(loaded.run, 199)
	loaded.run.shots_left = 10
	verify(not loaded.run.boss_due(), "199 kills does not trigger the second Boss early")
	restored.targets[0].anchor = Vector2(180, 238)
	restored.targets[0].hp = 1
	restored.targets[0].tick(0, restored.clock)
	fire(restored, 1000)
	tick(restored, 100)
	verify(loaded.run.defeated_count == 200 and loaded.run.phase == RunModel.Phase.CHOICE, "the real two-hundredth kill earns another ordinary choice")
	choose_safe(loaded.run)
	restored._physics_process(0)
	verify(loaded.run.boss_round == 2 and loaded.run.boss_next_defeats == 300 and restored.boss.max_hp > first_hp and restored.boss.armor == 26, "second appearance has higher health/armor and consumes the 200 threshold")
	var round_snapshot: Dictionary = restored.boss.snapshot()
	tick(restored, 10)
	verify(restored.boss.snapshot() == round_snapshot and restored.targets.is_empty(), "repeated ticks do not duplicate or reset a live Boss")
	var reset: RunModel = loaded.start_run(true)
	verify(reset.boss_round == 0 and reset.bosses_defeated == 0 and reset.boss_next_defeats == 100 and not reset.boss_active, "a new run resets only local Boss progress")
	world.queue_free()
	restored.queue_free()
	await tree.process_frame
	clean(path)

func _over_threshold(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	prime(run, 99)
	var world: ArcheryWorld = field(tree, session)
	for index: int in range(3):
		world.targets[index].anchor = Vector2(180 + index * 40, 238)
		world.targets[index].hp = 1
		world.targets[index].tick(0, 0)
	fire(world, 10000, 3, 2)
	tick(world, 160)
	verify(run.defeated_count == 102 and run.pending_encounters == 1 and run.phase == RunModel.Phase.CHOICE, "a real piercing volley keeps all three kills when crossing 100")
	verify(session.profile.total_defeats == 3 and run.score == 120 and world.boss == null, "all real rewards settle before the entry clear")
	choose_safe(run)
	var draws: int = run.shots_left
	fire(world, 24)
	verify(run.shots_left == draws and world.arrows.is_empty(), "pending entry prevents another draw from indefinitely delaying Boss")
	world._physics_process(0)
	verify(run.boss_active and run.boss_round == 1 and run.defeated_count == 102 and run.boss_next_defeats == 200, "entry preserves surplus kills toward the next 200 threshold")
	world.queue_free()
	await tree.process_frame

func _zero_draws(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	prime(run, 100)
	var world: ArcheryWorld = field(tree, session)
	world._physics_process(0)
	run.shots_left = 1
	fire(world, 30)
	tick(world, 200)
	verify(run.is_finished() and run.boss_active and run.bosses_defeated == 0 and world.targets.is_empty(), "nonlethal final Boss arrow ends after settlement without replenishing ordinary targets")
	verify(not session.has_active_run() and run.gold == 0 and not run.finished_reason.is_empty(), "exhausted Boss run cannot continue or retain local coins")
	world.queue_free()
	await tree.process_frame
	var winner := GameSession.new()
	run = winner.start_run()
	prime(run, 100)
	world = field(tree, winner)
	world._physics_process(0)
	run.shots_left = 1
	fire(world, 100000, 3)
	tick(world, 200)
	verify(not run.is_finished() and run.shots_left == 3 and run.phase == RunModel.Phase.CHOICE and run.bosses_defeated == 1 and winner.profile.total_score == 1200 and run.defeated_count == 100, "final-arrow Boss victory grants draws and a choice before exhaustion")
	winner.end_run("abandoned")
	verify(winner.last_run_summary["bosses_defeated"] == 1 and winner.last_run_summary["defeat_score"] == 1200, "terminal summary retains the last Boss reward")
	world.queue_free()
	await tree.process_frame
	var rescue := GameSession.new()
	run = rescue.start_run()
	prime(run, 100)
	world = field(tree, rescue)
	world._physics_process(0)
	run.shots_left = 1
	run.talent_effects["kill_refund"] = 1.0
	run.talent_effects["crit_refund"] = 1.0
	fire(world, 100000, 3)
	for arrow: Arrow in world.arrows: arrow.stats.crit_chance = 1.0
	tick(world, 200)
	verify(run.shots_left == 4 and not run.is_finished() and run.bosses_defeated == 1, "victory supply combines with a shared one-draw talent refund")
	choose_safe(run)
	world._physics_process(0)
	verify(world.boss == null and world.targets.size() == 3 and run.defeated_count == 100, "refunded Boss victory returns to playable ordinary field without free kill progress")
	world.queue_free()
	await tree.process_frame

func _migration(tree: SceneTree) -> void:
	var session := GameSession.new()
	var run: RunModel = session.start_run()
	prime(run, 250)
	var world: ArcheryWorld = field(tree, session)
	# A legacy run at 250 kills has no Boss gating before migration.
	world.boss_enabled = false
	fire(world, 24)
	run.encounter_picks["windfall"] = 24
	run.pending_encounters = 1
	run.offer_encounter()
	session.capture_checkpoint(world.snapshot())
	var old: Dictionary = session.save_payload()
	for key: String in ["boss_schema", "boss_round", "bosses_defeated", "boss_next_defeats", "boss_active", "boss_reward_schema", "reward_queue", "boss_reward_log"]: old["run"].erase(key)
	old["world"].erase("boss")
	old["world"].erase("field_generation")
	var path: String = "user://tests/t10a-v7.json"
	clean(path)
	var bytes: String = JSON.stringify({"version": 7, "payload": old}, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var migrated: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v7") == bytes and JSON.parse_string(FileAccess.get_file_as_string(path))["version"] == SaveStore.VERSION, "v7 source is archived byte-for-byte before current migration")
	verify(migrated.run.boss_round == 2 and migrated.run.boss_next_defeats == 300 and not migrated.run.boss_due() and migrated.run.bosses_defeated == 0, "250 legacy kills establish a 300 baseline without retroactive Boss fights or victories")
	verify(migrated.run.choices == run.choices and migrated.run.encounter_offer_id == run.encounter_offer_id and migrated.run.rng.state == run.rng.state, "v7 migration preserves fixed choice and RNG")
	verify(migrated.run.gold == run.gold and migrated.run.shots_left == run.shots_left and migrated.profile.to_dict() == session.profile.to_dict(), "migration never refills draws or replays coins/XP")
	verify(migrated.world_snapshot["arrows"] == JSON.parse_string(JSON.stringify(old["world"]["arrows"], "", true, true)) and migrated.world_snapshot["targets"] == JSON.parse_string(JSON.stringify(old["world"]["targets"], "", true, true)), "legacy flight and ordinary target state stay intact")
	var current: String = FileAccess.get_file_as_string(path)
	store.read()
	verify(store.migration_notice.is_empty() and FileAccess.get_file_as_string(path) == current, "v8 repeated reads do not migrate or rewrite again")
	world.queue_free()
	await tree.process_frame
	clean(path)

func _main_ui(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._new_run()
	main.world.set_physics_process(false)
	prime(main.run, 100)
	main.world._physics_process(0)
	main.hud.update_boss(main.run, main.world)
	verify(main.hud.boss_panel.visible and main.hud.boss_title.text.contains("铁弦巨靶") and main.hud.boss_health.value == 2880, "actual range HUD displays Boss title, armor and health")
	main.world.boss.hp = 432
	main.world.boss.refresh_phase()
	main.hud.update_boss(main.run, main.world)
	verify(main.hud.boss_health.value == 432 and main.hud.boss_title.text.contains("432 / 2880"), "health bar follows damage without granting rewards")
	main._on_action("skills", null)
	verify(tree.paused and main.run.phase == RunModel.Phase.SHOP and main.world.boss.hp == 432, "skills pause the same damaged Boss")
	main._on_action("continue", null)
	main._on_action("hub", null)
	var payload: Dictionary = main.saves.read()
	verify(payload["run"]["boss_active"] and payload["world"]["boss"]["hp"] == 432 and payload["world"]["targets"].is_empty(), "real hub action persists Boss instead of ordinary targets")
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(payload)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	verify(main.world.boss.hp == 432 and main.world.targets.is_empty() and main.run.boss_round == 1 and main.run.boss_next_defeats == 200, "real lazy Continue restores damage and does not refill or re-enter Boss")
	main._on_action("tutorial", null)
	verify(not main.tutorial.world.boss_enabled and main.world.boss.hp == 432, "practice disables Boss progression while preserving formal Boss")
	main._stop_tutorial()
	verify(main.world.boss.hp == 432 and main.run.boss_active, "leaving practice returns to the same Boss")
	main.queue_free()
	await tree.process_frame
	tree.paused = false

func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v7"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
