extends RefCounted

var assertion: Callable

func _init(check: Callable) -> void:
	assertion = check

func verify(condition: bool, message: String) -> void:
	assertion.call(condition, "T08-C: " + message)

func profile_at(level: int, defeats: int) -> PlayerProfile:
	return PlayerProfile.from_dict({"total_score": PlayerProfile.RULES.threshold(level), "total_defeats": defeats})

func run_all(tree: SceneTree) -> void:
	_catalog_and_profile()
	_checkpoint()
	await _live_ui(tree)

func _catalog_and_profile() -> void:
	var ids: Array[String] = []
	verify(CosmeticCatalog.ALL.size() == 9, "nine appearances provided")
	for slot: String in CosmeticCatalog.SLOTS:
		var count: int = 0
		for skin: CosmeticData in CosmeticCatalog.ALL:
			if skin.slot == slot: count += 1
		verify(count == 3 and CosmeticCatalog.default_for(slot).slot == slot, "three appearances with valid default: " + slot)
	var fresh := PlayerProfile.new()
	verify(fresh.unlocked_cosmetics == PlayerProfile.DEFAULT_COSMETICS, "fresh profile has exactly three defaults")
	for skin: CosmeticData in CosmeticCatalog.ALL:
		verify(not ids.has(skin.id) and CosmeticCatalog.SLOTS.has(skin.slot), "unique ID and valid category: " + skin.id)
		ids.append(skin.id)
		if skin.style == 0: continue
		var below: PlayerProfile = profile_at(maxi(1, skin.required_level - 1), maxi(0, skin.required_defeats - 1))
		verify(not below.unlocked_cosmetics.has(skin.id) and not below.equip_cosmetic(skin.id), "below condition cannot equip: " + skin.id)
		var exact: PlayerProfile = profile_at(skin.required_level, skin.required_defeats)
		var progress: Array = [exact.total_score, exact.total_defeats, exact.talent_points]
		verify(exact.unlocked_cosmetics.has(skin.id) and exact.equip_cosmetic(skin.id), "exact unlock condition equips: " + skin.id)
		verify(exact.equipped_cosmetics[skin.slot] == skin.id and [exact.total_score, exact.total_defeats, exact.talent_points] == progress, "equip does not alter permanent progress: " + skin.id)
		var loaded: PlayerProfile = PlayerProfile.from_dict(exact.to_dict())
		verify(loaded.equipped_cosmetics == exact.equipped_cosmetics and loaded.unlocked_cosmetics == exact.unlocked_cosmetics, "unlocks and equipment restore: " + skin.id)
	verify(not fresh.equip_cosmetic("unknown") and not fresh.equip_cosmetic("bow_default"), "unknown and duplicate equip are rejected")
	var forged: PlayerProfile = PlayerProfile.from_dict({"unlocked_cosmetics": ids, "equipped_cosmetics": {"bow": "bow_ember", "arrow": "arrow_frost", "archer": "archer_dusk"}})
	verify(forged.unlocked_cosmetics == PlayerProfile.DEFAULT_COSMETICS and forged.equipped_cosmetics == fresh.equipped_cosmetics, "supplied unlock list cannot forge permanent entitlement")
	var wrong: Dictionary = profile_at(5, 100).to_dict()
	wrong["equipped_cosmetics"] = {"bow": "arrow_sun", "arrow": "archer_dusk", "archer": "missing"}
	verify(PlayerProfile.from_dict(wrong).equipped_cosmetics == fresh.equipped_cosmetics, "cross-category or unknown saved selection falls back")
	verify(CosmeticCatalog.equipped({"bow": "arrow_sun"}, "bow").id == "bow_default", "renderer validates category too")
	var counted: PlayerProfile = profile_at(1, 24)
	counted.record_defeat(0)
	verify(counted.total_defeats == 25 and counted.unlocked_cosmetics.has("bow_ember"), "zero-score real defeat still unlocks at exact cumulative threshold")
	var levelled: PlayerProfile = profile_at(2, 0)
	levelled.record_defeat(150)
	verify(levelled.level == 3 and levelled.unlocked_cosmetics.has("bow_moon"), "real level gain unlocks immediately")
	levelled.refresh_cosmetics()
	levelled.refresh_cosmetics()
	verify(levelled.unlocked_cosmetics.count("bow_moon") == 1 and levelled.equipped_cosmetics["bow"] == "bow_default", "rechecking unlocks neither duplicates nor auto-equips")
	verify(CosmeticCatalog.equipped({}, "arrow").id == "arrow_default", "old save without selections retains default visual")

func _checkpoint() -> void:
	var session := GameSession.new()
	session.profile = profile_at(4, 24)
	session.start_run()
	session.capture_checkpoint({"clock": 3.0})
	session.profile.record_defeat(10000)
	session.profile.equip_cosmetic("bow_moon")
	var payload: Dictionary = session.save_payload()
	verify(payload["profile"]["equipped_cosmetics"]["bow"] == "bow_moon" and payload["profile"]["total_score"] == PlayerProfile.RULES.threshold(4) and payload["world"]["clock"] == 3, "equipment merges without mixing newer XP/world into checkpoint")
	verify(not payload["profile"]["unlocked_cosmetics"].has("bow_ember") and not payload["profile"]["unlocked_cosmetics"].has("archer_crimson"), "unlock list remains at checkpoint entitlement")
	session.profile.equip_cosmetic("archer_crimson")
	verify(GameSession.from_dict(session.save_payload()).profile.equipped_cosmetics["archer"] == "archer_default", "new progress cannot smuggle equipment beyond saved entitlement")
	var path: String = "user://tests/t08c/save.json"
	DirAccess.make_dir_recursive_absolute("user://tests/t08c")
	var store := SaveStore.new(path, [])
	verify(store.write(payload), "current schema stores cosmetic fields")
	var bytes: String = FileAccess.get_file_as_string(path)
	var restored: GameSession = GameSession.from_dict(store.read())
	verify(restored.profile.equipped_cosmetics["bow"] == "bow_moon" and restored.profile.unlocked_cosmetics.has("arrow_frost"), "disk restores loadout and derives earned unlocks")
	verify(FileAccess.get_file_as_string(path) == bytes and store.migration_notice.is_empty(), "reading current cosmetics never rewrites or migrates save")

func _page(main: Node) -> CosmeticsPage:
	return main.router.page.get_child(1) as CosmeticsPage

func _live_ui(tree: SceneTree) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	main._on_action("start", null)
	main._on_action("cosmetics", null)
	verify(_page(main).equip_buttons.size() == 9 and main.world == null, "actual page shows nine previews without constructing combat")
	verify((_page(main).equip_buttons["bow_moon"] as Button).disabled and (_page(main).equip_buttons["bow_default"] as Button).disabled, "locked and equipped buttons disabled")
	main._on_action("cosmetic_equip", "bow_ember")
	verify(main.session.profile.equipped_cosmetics["bow"] == "bow_default", "forged locked button request cannot equip")
	main._on_action("back", null)
	main.session.profile = profile_at(5, 100)
	main._on_action("range", null)
	main.world.set_physics_process(false)
	main.world.set_process(false)
	main.run.gold = 77
	main.run.skill_levels = {"penetration": 1, "ricochet": 1}
	main.run.encounter_picks = {"piercing_split": 1, "ricochet_haste": 1, "rainfall": 1}
	main.run.seen_encounters.assign(["piercing_split", "ricochet_haste"])
	main.run.defeated_count = 30
	main.run.encounter_rewards_generated = 3
	main.run.rebuild_stats()
	main.run.stats.gravity = 0
	main.run.stats.spread_degrees = 0
	main.run.stats.crit_chance = 0
	main.world.targets[0].anchor = Vector2(180, 238)
	main.world.targets[0].tick(0, 0)
	main.world.direction = Vector2.RIGHT
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	main.world.arrows[0]._physics_process(0.21)
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	verify(main.world.arrows.size() == 4 and main.world.arrows[2].parent_source_id >= 0, "actual penetration creates child family for cosmetic verification")
	var combat: Dictionary = main.world.snapshot()
	var stats: Dictionary = main.run.stats.to_dict()
	var shots: int = main.run.shots_left
	var random_state: int = main.run.rng.state
	var score: float = main.session.profile.total_score
	var defeats: int = main.session.profile.total_defeats
	var points: int = main.session.profile.talent_points
	main._on_action("hub", null)
	main._on_action("cosmetics", null)
	for id: String in ["bow_moon", "arrow_frost", "archer_crimson"]:
		var button: Button = _page(main).equip_buttons[id]
		verify(not button.disabled, "earned real equip button available: " + id)
		button.pressed.emit()
		verify(main.session.profile.equipped_cosmetics[CosmeticCatalog.find(id).slot] == id and (_page(main).equip_buttons[id] as Button).disabled, "actual click equips and marks current card: " + id)
	verify(_page(main).preview.loadout == main.session.profile.equipped_cosmetics and main.world.appearance == main.session.profile.equipped_cosmetics, "page preview and paused world share actual selected loadout")
	for arrow: Arrow in main.world.arrows:
		verify(arrow.cosmetic.id == "arrow_frost", "immediate recolor includes both roots and children")
	verify(main.world.snapshot() == combat and main.run.stats.to_dict() == stats and main.run.shots_left == shots and main.run.gold == 77, "equipping leaves family snapshots, stats, draws and coins unchanged")
	verify(main.run.rng.state == random_state and main.session.profile.total_score == score and main.session.profile.total_defeats == defeats and main.session.profile.talent_points == points, "equipping never changes RNG or permanent growth")
	var saved: Dictionary = main.saves.read()
	verify(saved["profile"]["equipped_cosmetics"] == main.session.profile.equipped_cosmetics and not saved["world"]["arrows"][0].has("cosmetic"), "only profile holds cosmetic save fields; projectile schema stays same")
	var restored: GameSession = GameSession.from_dict(saved)
	var copy := ArcheryWorld.new()
	copy.run = restored.run
	copy.scale = Vector2(2, 2)
	tree.root.add_child(copy)
	copy.build_field(restored.world_snapshot)
	copy.apply_cosmetics(restored.profile.equipped_cosmetics)
	for arrow: Arrow in copy.arrows: arrow.set_physics_process(false)
	verify(copy.snapshot() == combat and copy.arrows.all(func(arrow: Arrow) -> bool: return arrow.cosmetic.id == "arrow_frost"), "disk rebuild preserves exact family physics and re-applies selected visuals")
	copy.apply_cosmetics(copy.appearance)
	verify(copy.appearance == restored.profile.equipped_cosmetics, "re-applying loadout is stable even from own dictionary")
	copy.queue_free()
	await tree.process_frame
	main._on_action("back", null)
	main._on_action("range", null)
	main._on_action("cosmetic_equip", "bow_ember")
	verify(main.session.profile.equipped_cosmetics["bow"] == "bow_moon", "combat route rejects out-of-page equip request")
	main.world.reload_left = 0
	main.world.pull = 1
	main.world._release()
	for arrow: Arrow in main.world.arrows: arrow.set_physics_process(false)
	verify(main.world.arrows.size() == 6 and main.world.arrows[4].cosmetic.id == "arrow_frost" and main.run.shots_left == shots - 1, "future draw uses same appearance while charging exactly one draw")
	var formal_profile: Dictionary = main.session.profile.to_dict()
	main._on_action("tutorial", null)
	verify(main.tutorial.world.appearance == formal_profile["equipped_cosmetics"], "tutorial displays chosen permanent loadout")
	main.tutorial.session.profile.record_defeat(1000000)
	verify(main.session.profile.to_dict() == formal_profile, "tutorial leveling cannot unlock or change formal cosmetics")
	main.tutorial.restart()
	verify(main.tutorial.world.appearance == formal_profile["equipped_cosmetics"], "practice replay retains copied loadout")
	main._on_action("back", null)
	main._on_action("hub", null)
	# Fresh session and lazy world exercise saved equipped appearance on Continue.
	saved = main.saves.read()
	main._discard_world()
	main.run.changed.disconnect(main._refresh)
	main.session = GameSession.from_dict(saved)
	main.run = main.session.run
	main.run.changed.connect(main._refresh)
	main._on_action("home", null)
	main._on_action("resume_hub", null)
	main._on_action("range", null)
	verify(main.world.appearance == formal_profile["equipped_cosmetics"] and main.world.arrows.all(func(arrow: Arrow) -> bool: return arrow.cosmetic.id == "arrow_frost"), "lazy Continue reapplies saved bow, archer and inflight arrow visuals")
	main._on_action("hub", null)
	main._on_action("cosmetics", null)
	for id: String in PlayerProfile.DEFAULT_COSMETICS: (_page(main).equip_buttons[id] as Button).pressed.emit()
	verify(main.world.appearance == PlayerProfile.new().equipped_cosmetics and main.world.arrows.all(func(arrow: Arrow) -> bool: return arrow.cosmetic.id == "arrow_default"), "default buttons restore all visuals")
	main.queue_free()
	await tree.process_frame
