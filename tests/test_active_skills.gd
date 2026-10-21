extends RefCounted

var assertion: Callable
const PATH: String = "user://tests/active-skills-save.json"

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "ACTIVE: " + message)

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".legacy-v22"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func run_all(tree: SceneTree) -> void:
	_profile_and_energy()
	await _world_and_save(tree)
	await _navigation(tree)

func _profile_and_energy() -> void:
	var session := GameSession.new()
	var profile: PlayerProfile = session.profile
	verify(not profile.unlock_active("missing"), "unknown skill rejected")
	verify(profile.unlock_active("sunshot") and profile.equipped_active == "sunshot" and profile.talent_points == 0, "first choice free and equipped")
	verify(not profile.unlock_active("sunshot") and not profile.unlock_active("quickdraw"), "duplicate and unaffordable unlocks rejected")
	profile.record_score(10000)
	var before: int = profile.talent_points
	verify(profile.unlock_active("quickdraw") and profile.unlock_active("hunters_mark") and profile.talent_points == before - 4, "other skills cost two points each")
	verify(profile.to_dict() == PlayerProfile.from_dict(profile.to_dict()).to_dict(), "unlock ledger and equipment roundtrip")
	verify(session.equip_active("quickdraw"), "lobby may equip unlocked skill")
	var run: RunModel = session.start_run()
	verify(run.active.id == "quickdraw" and run.active.energy == 0, "new run snapshots equipped skill with empty energy")
	session.return_to_lobby()
	verify(not session.equip_active("sunshot"), "returning to lobby cannot change active run skill")
	verify(session.reset_talents() == 4 and profile.active_unlocks.is_empty() and profile.talent_points == before, "reset refunds paid unlocks and resets free choice")
	verify(run.active.id == "quickdraw", "reset leaves current run skill snapshot intact")
	verify(session.unlock_active("hunters_mark") and profile.equipped_active == "hunters_mark", "free choice can be reselected")
	session.resume_run()
	verify(not session.unlock_active("sunshot") and not session.equip_active("hunters_mark"), "combat cannot unlock or equip")
	run.stats.arrow_count = 32
	verify(run.consume_shot() and run.active.energy == 8, "32-arrow draw earns only eight energy")
	var hits: Array = []
	for index: int in range(32):
		hits.append({"hit_id": "1:%d:target" % index, "effective": 1.0, "broken": false, "critical": false, "bullseye": true, "energy_eligible": true})
	verify(session.settle_shot(run.shot_sequence, hits) and run.active.energy == 14, "whole volley gets at most four hit plus two bullseye energy")
	verify(not session.settle_shot(run.shot_sequence, hits) and run.active.energy == 14, "settlement replay cannot mint energy")
	run.consume_shot()
	for hit: Dictionary in hits: hit.energy_eligible = false
	session.settle_shot(run.shot_sequence, hits)
	verify(run.active.energy == 22, "secondary or skill damage supplies no hit energy")
	run.active.gain(999)
	verify(run.active.energy == 100, "energy capped")
	run.active.energy = 39
	verify(not run.active.cast() and run.active.energy == 39, "insufficient energy cannot cast")
	run.active.energy = 100
	verify(run.active.cast() and run.active.energy == 60 and run.active.remaining == 2, "quickdraw spends energy once")
	verify(not run.active.cast() and run.active.energy == 60, "armed skill cannot be stacked")
	var state: Dictionary = run.active.to_dict()
	verify(ActiveAbility.from_dict(state).to_dict() == state, "active effect and anti-repeat interval survive restore")
	var invalid: Dictionary = state.duplicate()
	invalid.energy = NAN
	verify(not ActiveAbility.valid(invalid), "nonfinite energy rejected")
	invalid = state.duplicate(); invalid.remaining = 3
	verify(not ActiveAbility.valid(invalid), "impossible duration rejected")
	var next: RunModel = session.start_run(true)
	verify(next.active.id == "hunters_mark" and next.active.energy == 0 and next.active.remaining == 0, "new adventure resets energy and adopts new selection")

func _world_and_save(tree: SceneTree) -> void:
	clean()
	DirAccess.make_dir_recursive_absolute("user://tests")
	var session := GameSession.new()
	session.profile.unlock_active("sunshot")
	var run: RunModel = session.start_run(false, "normal", ContractCatalog.preset("hard"))
	var world := ArcheryWorld.new()
	world.run = run
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.shot_settled.connect(session.settle_shot)
	world.build_field()
	world.pull = 0.05
	world._release()
	verify(run.active.energy == 0 and run.shot_sequence == 0, "cancelled draw earns no energy")
	world._physics_process(30)
	verify(run.active.energy == 0, "time cannot replenish energy")
	run.active.energy = 100
	verify(world.activate_skill() and run.active.energy == 40, "world activates sunshot")
	verify(not world.activate_skill(), "repeated button/key cannot double charge")
	world.pull = 1
	world._release()
	var arrow: Arrow = world.arrows[0]
	arrow.set_physics_process(false)
	var target: ArcheryTarget = world.targets[0]
	var stats: BowStats = arrow.contact_stats(target, target.global_position, "body")
	verify(run.active.remaining == 0 and run.active.energy == 48, "one buff charge consumed per pull; normal draw still gives eight")
	verify(is_equal_approx(stats.damage, run.stats.damage * 2) and stats.armor_penetration == run.stats.armor_penetration + 12, "sunshot doubles damage and adds twelve armor penetration")
	verify(arrow.stats.damage == run.stats.damage, "temporary power does not mutate persistent stats")
	var child := Arrow.new()
	child.stats = arrow.stats.duplicate()
	child.inherit_combat(arrow)
	verify(child.active_effect == "sunshot" and is_equal_approx(child.contact_stats(target, target.global_position, "body").damage, stats.damage), "split descendants inherit temporary effect once")
	child.free()
	session.capture_checkpoint(world.snapshot())
	var store := SaveStore.new(PATH)
	verify(store.write(session.to_dict()), "in-flight empowered arrows save successfully: " + store.last_error)
	var restored := GameSession.from_dict(store.read())
	verify(restored.run.active.to_dict() == run.active.to_dict(), "disk preserves energy and remaining charges")
	var resumed := Arrow.new()
	resumed.restore(restored.world_snapshot.arrows[0], restored.run.rng)
	verify(resumed.snapshot() == arrow.snapshot(), "in-flight buff restores exactly")
	resumed.free()
	var malformed: Dictionary = session.to_dict()
	malformed.run.active.energy = 101
	verify(not store.write(malformed), "save rejects energy above cap")
	malformed = session.to_dict()
	malformed.profile.active_unlocks.quickdraw = 0
	verify(not store.write(malformed), "save rejects a second free skill")
	# v22 migration must preserve all existing contract parameters and live arrows.
	var legacy: Dictionary = session.to_dict()
	for key: String in ["active_schema", "active_unlocks", "equipped_active"]: legacy.profile.erase(key)
	legacy.run.erase("active_schema"); legacy.run.erase("active")
	for old_arrow: Dictionary in legacy.world.arrows:
		old_arrow.erase("active_effect"); old_arrow.erase("active_target")
	var bytes: String = JSON.stringify({"version": 22, "payload": legacy}, "", true, true)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(bytes); file.close()
	var migrated: Dictionary = store.read()
	verify(not migrated.is_empty(), "v22 migrates")
	if not migrated.is_empty():
		verify(migrated.run.challenge == legacy.run.challenge and migrated.run.mode_parameters == legacy.run.mode_parameters, "v22 migration retains exact contract and difficulty")
		verify(migrated.run.active.id == "" and migrated.run.active.energy == 0, "old ongoing run starts without retroactive skill or energy")
		verify(FileAccess.get_file_as_string(PATH + ".legacy-v22") == bytes, "old save archived before migration")
	# Mark attaches to a target life, not its reusable slot.
	run.active = ActiveAbility.new(); run.active.id = "hunters_mark"; run.active.energy = 100
	world.direction = (target.position - world.BOW).normalized()
	verify(world.activate_skill() and run.active.target_id == target.defeat_id(), "mark chooses target along aim")
	world.pull = 1; world._release()
	var marked: Arrow = world.arrows.back()
	marked.set_physics_process(false)
	verify(is_equal_approx(marked.contact_stats(target, target.global_position, "body").damage, marked.stats.damage * 1.6), "marked target takes bonus")
	verify(is_equal_approx(marked.contact_stats(world.targets[1], world.targets[1].global_position, "body").damage, marked.stats.damage), "unmarked target receives no bonus")
	target.generation += 1
	verify(is_equal_approx(marked.contact_stats(target, target.global_position, "body").damage, marked.stats.damage), "mark never carries to respawned target")
	world._physics_process(0.01)
	verify(run.active.remaining == 0 and run.active.target_id == "", "lost target ends unused marked draws")
	run.active = ActiveAbility.new(); run.active.id = "quickdraw"; run.active.energy = 100
	world.reload_left = 1.5
	verify(world.activate_skill() and world.reload_left == 0, "quickdraw clears current reload")
	var shots: int = run.shots_left
	for index: int in range(3):
		world.pull = 1; world._release()
		world.arrows.back().set_physics_process(false)
		verify(is_zero_approx(world.reload_left) if index < 2 else world.reload_left > 0, "quickdraw applies to precisely two post-shot reloads")
	verify(run.shots_left == shots - 3, "quickdraw never refunds ammunition")
	run.active.remaining = 0; run.active.cooldown = 0; run.active.energy = 100
	run.open_skills()
	verify(not world.activate_skill() and run.active.energy == 100, "shop blocks casting")
	run.close_skills(); session.return_to_lobby()
	verify(not world.activate_skill(), "suspended run blocks casting")
	world.queue_free()
	await tree.process_frame
	clean()

func _navigation(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._on_action("start", null)
	main._on_action("active_skills", null)
	var button: Button = main.router.page.find_child("sunshot", true, false)
	verify(button != null and not button.disabled and button.text == "免费选择", "real talent skill page offers first free choice")
	button.pressed.emit()
	verify(main.session.profile.equipped_active == "sunshot", "actual free choice button unlocks and equips")
	main._on_action("back", null)
	verify(main.router.route == "talents", "skill page returns to talent tree")
	main._on_action("back", null)
	verify(main.router.route == "hub", "talent page retains lobby return path")
	main._on_action("range", null)
	main.world.set_physics_process(false); main.world.set_process(false)
	main.run.active.energy = 100
	main._process(0)
	verify(not main.hud.active_button.disabled and main.hud.energy_bar.value == 100, "HUD displays energy and available skill")
	main.hud.active_button.pressed.emit()
	verify(main.run.active.remaining == 1 and main.run.active.energy == 40, "actual HUD button activates skill")
	main._navigate("pause")
	main._on_action("active_cast", null)
	verify(main.run.active.energy == 40, "pause route rejects activation")
	main._navigate("hub"); main._navigate("active_skills")
	verify((main.router.page.find_child("sunshot", true, false) as Button).disabled, "active run equipment UI locked")
	var saved: Dictionary = main.saves.read()
	verify(not saved.is_empty() and saved.run.active.energy == 40 and saved.run.active.remaining == 1, "armed skill persists through actual navigation saves")
	main.queue_free()
	await tree.process_frame
