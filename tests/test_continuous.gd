extends RefCounted
## Live field, final-projectile settlement and v2 migration regressions.

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T03: " + message)

func run_all(tree: SceneTree) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	main._new_run()
	await tree.physics_frame
	await tree.physics_frame
	var target: ArcheryTarget = main.world.targets[0]
	var untouched: ArcheryTarget = main.world.targets[1]
	var original_hp: float = untouched.max_hp
	target.anchor = Vector2(180, 238)
	target.hp = 1
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 0
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	for index: int in range(80): await tree.physics_frame
	verify(main.run.defeated_count == 1 and main.run.score == 40 and main.run.gold == 8, "Actual lethal arrow awards one configured kill reward")
	verify(main.session.profile.total_score == 40 and main.session.profile.total_defeats == 1, "Actual kill reaches permanent profile")
	verify(target.hp == 0 and target.respawn_left > 0, "Destroyed target waits before replenishment")
	var event_id: String = target.defeat_id()
	verify(not main.session.record_defeat(event_id, 40, 8) and main.run.gold == 8, "Repeated kill event cannot duplicate coins or XP")
	var checkpoint: Dictionary = main.saves.read()
	verify(checkpoint["world"]["targets"][0]["hp"] == 0, "Settled checkpoint retains dead target and respawn timer")
	for index: int in range(150): await tree.physics_frame
	verify(target.generation == 1 and target.hp == target.max_hp and target.max_hp > 48, "Respawn has new identity and increased health")
	verify(target.reward_score > 40 and target.reward_gold > 8, "New target samples increased score and coin rewards")
	verify(untouched.max_hp == original_hp and untouched.hp == original_hp, "Existing targets do not mutate when difficulty increases")
	var values: Dictionary = ArcheryTarget.RULES.target_values(GameCatalog.TARGETS[0], 25)
	verify(int(values["armor"]) == 5 and float(values["max_hp"]) > target.max_hp, "Armor and health curves grow with defeated count")
	var field: Dictionary = main.world.snapshot()
	var saved_target: Dictionary = target.snapshot()
	main._discard_world()
	main._create_world(field)
	verify(main.world.targets[0].snapshot() == saved_target, "Live target restores exact sampled stats and generation")
	var restored: GameSession = GameSession.from_dict(checkpoint)
	verify(not restored.record_defeat(event_id, 40, 8) and restored.profile.total_score == 40, "Reloaded dead target cannot award twice")
	# Final volley kills three targets before any end transition, even with multiple arrows.
	main._new_run()
	main.run.shots_left = 1
	main.run.stats.damage = 1000
	main.run.stats.gravity = 0
	main.run.stats.crit_chance = 0
	main.run.stats.armor_penetration = 2
	main.run.stats.arrow_count = 3
	main.run.stats.spread_degrees = 0
	for index: int in range(3):
		main.world.targets[index].anchor = Vector2(180 + 40 * index, 238)
	await tree.physics_frame
	await tree.physics_frame
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	verify(main.run.shots_left == 0 and not main.run.is_finished(), "Spending final draw does not end while projectiles remain")
	main._on_action("skills", null)
	verify(main.run.phase == RunModel.Phase.SHOP and tree.paused, "Skills pause in-flight transaction")
	main._continue()
	for index: int in range(180): await tree.physics_frame
	verify(main.run.defeated_count == 3 and main.run.defeat_score == 120, "Final multi-arrow piercing volley credits all kills exactly once")
	verify(main.run.phase == RunModel.Phase.SUPPLY and main.world.arrows.is_empty(), "All arrows finish before affordable supply offer")
	main._on_action("supply_end", main.run.supply_offer_id)
	verify(main.run.is_finished() and main.world.arrows.is_empty(), "Run ends only after every arrow expires")
	verify(main.session.profile.total_score == 160 and main.session.profile.level == 2 and main.session.profile.talent_points == 1, "Final volley level-up is retained in permanent profile")
	verify(main.session.last_run_summary["gold_earned"] == 24 and main.run.gold == 0, "Result records earned coins while clearing local wallet")
	var terminal: GameSession = GameSession.from_dict(main.saves.read())
	verify(terminal.run.is_finished() and terminal.profile.total_score == 160, "Terminal save contains final kills and level-up")
	# A real kill callback can rescue the final volley before exhaustion is evaluated.
	main._new_run()
	main.run.shots_left = 1
	main.run.stats.damage = 1000
	main.run.stats.gravity = 0
	main.world.targets[0].anchor = Vector2(180, 238)
	main.session.defeat_recorded.connect(func(_id: String) -> void: main.run.restore_shots(1))
	await tree.physics_frame
	await tree.physics_frame
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	for index: int in range(100): await tree.physics_frame
	verify(main.run.shots_left == 1 and not main.run.is_finished(), "Live final-arrow refund saves the run")
	verify(main.run.difficulty_step == 1, "New adventure starts difficulty from zero")
	main._new_run()
	main.run.shots_left = 0
	var empty_field: Dictionary = main.world.snapshot()
	main._discard_world()
	main._create_world(empty_field)
	await tree.physics_frame
	await tree.physics_frame
	verify(main.run.is_finished(), "Restoring a settled zero-ammo run reaches result instead of getting stuck")
	main.queue_free()
	await tree.process_frame
	_migration()

func _migration() -> void:
	var path: String = "user://tests/t03-migration.json"
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v2"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var session := GameSession.new()
	session.profile.record_defeat(250)
	session.start_run()
	var old: Dictionary = session.to_dict()
	old["run"]["ruleset"] = "prototype_v1"
	old["run"]["phase"] = RunModel.Phase.CHOICE
	old["run"]["stage"] = 4
	old["run"]["score"] = 9999
	old["run"]["shots_left"] = 3
	old["run"]["gold"] = 27
	old["run"].erase("skill_schema")
	for key: String in ["backpack_schema", "artifact_capacity", "artifact_revision", "discarded_artifacts", "trait_schema", "trait_levels", "mastery_schema", "mastery_levels", "mastery_unlocks"]: old["run"].erase(key)
	for key: String in ["encounter_schema", "encounter_picks", "encounter_rewards_generated", "encounter_offer_id"]: old["run"].erase(key)
	old["run"]["skill_levels"] = {"power": 2}
	old["run"].erase("starting_level")
	old["run"]["choices"] = ["lucky"]
	old["world"] = {"clock": 4.5, "targets": [{"hp": 17.0, "respawn_left": 0.0}]}
	var bytes: String = JSON.stringify({"version": 2, "payload": old})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
	var store := SaveStore.new(path)
	var migrated: GameSession = GameSession.from_dict(store.read())
	verify(FileAccess.get_file_as_string(path + ".legacy-v2") == bytes, "V2 source is archived byte for byte before upgrade")
	verify(migrated.run.ruleset == "continuous_v1" and migrated.run.phase == RunModel.Phase.PLAYING and migrated.run.choices.is_empty(), "V2 shop/choice converts to continuous play without obsolete reward")
	verify(migrated.run.shots_left == 3 and migrated.run.gold == 27 and migrated.run.legacy_skill_levels["power"] == 2, "Migration retains ammo, wallet and build")
	verify(migrated.run.score == 0 and migrated.profile.total_score == 250 and migrated.run.starting_level == 3, "Old hit score never creates XP or false level growth")
	verify(migrated.world_snapshot["targets"][0]["hp"] == 17, "Legacy target durability is retained")
	var reloaded: GameSession = GameSession.from_dict(store.read())
	verify(store.migration_notice.is_empty() and reloaded.profile.talent_points == 2, "V3 reload neither repeats migration nor grants more points")
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v2"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

