extends "res://tests/simulate_progression.gd"
## Actual projectile audit. A resumed earned build is distinct from a fresh campaign.
class AuditWorld extends ArcheryWorld:
	var hits: Array[Dictionary] = []
	func _on_hit(target: ArcheryTarget, point: Vector2, hit: Dictionary, arrow: Arrow) -> void:
		if target is ArcheryBoss:
			hits.append({"boss": target.round_number, "draw": arrow.shot_id,
				"source": arrow.source_id, "child": arrow.parent_source_id >= 0,
				"part": hit.get("boss_part", "body"), "raw": hit.get("raw", 0),
				"effective": hit.effective, "critical": hit.critical, "active": arrow.active_effect,
				"bounce": arrow.bounce_stacks, "penetration": arrow.penetration_stacks,
				"base_damage": arrow.stats.damage, "phase_after": target.battle_phase,
				"resisted": hit.get("resisted", 0),
				"hp_after": target.hp})
		super._on_hit(target, point, hit, arrow)

func simulate() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"): quit(1); return
	variant = "resilient"
	trials = 6
	var aim_error: float = 0.0
	var route: String = "quantity"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
		if arg.begins_with("--trials="): trials = int(arg.trim_prefix("--trials="))
		if arg.begins_with("--aim-error="): aim_error = float(arg.trim_prefix("--aim-error="))
		if arg.begins_with("--route="): route = arg.trim_prefix("--route=")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/t09b-earned-boss.json"))
	var saved: Dictionary = envelope.get("payload", {})
	if saved.is_empty(): push_error("Earned checkpoint required"); quit(1); return
	if not SaveStore.new()._valid_payload(saved): push_error("Invalid earned checkpoint"); quit(1); return
	var output: Array[Dictionary] = []
	for trial: int in range(trials):
		var session := GameSession.from_dict(saved)
		var run: RunModel = session.run
		# Controlled comparison of the same earned build, not a real save migration.
		if variant == "resilient":
			run.balance_revision = 2
			if OS.get_cmdline_user_args().has("--economy-current"):
				run.balance_revision = 3
				run.rebuild_stats()
			session.world_snapshot.boss["impact_revision"] = 1
			session.world_snapshot.boss["volley_pressure"] = {}
		else:
			run.balance_revision = 1
			session.world_snapshot.boss["impact_revision"] = 0
			session.world_snapshot.boss["volley_pressure"] = {}
		run.rng.seed = 39000 + trial
		var w := AuditWorld.new()
		w.run = run
		root.add_child(w)
		w.set_process(false)
		w.set_physics_process(false)
		w.shot_settled.connect(session.settle_shot)
		w.build_field(session.world_snapshot)
		var entries: Array[Dictionary] = []
		var seen: int = 0
		var start: int = run.shot_sequence
		for step: int in range(1200):
			if run.is_finished() or run.bosses_defeated >= 3 or run.shot_sequence - start >= 260: break
			if run.phase == RunModel.Phase.CHOICE: choose(run); continue
			if run.phase == RunModel.Phase.SUPPLY:
				if not run.buy_supply(run.supply_token()): run.decline_supply(run.supply_offer_id)
				continue
			tick(w, 180)
			if run.phase != RunModel.Phase.PLAYING: continue
			if w.boss != null and run.boss_round != seen:
				seen = run.boss_round
				entries.append({"boss": seen, "draw": run.shot_sequence, "hp": w.boss.max_hp, "stats": run.stats.to_dict(), "gold": run.gold, "spent": run.gold_spent, "shots": run.shots_left})
			buy(run, route)
			w.direction = aim(w).rotated(aim_error * sin(float(run.shot_sequence) * 2.399963 + trial))
			if w.can_activate_skill(): w.activate_skill()
			w.pull = 1
			w._release()
			tick(w, 1500)
		var row := {"trial": trial, "route": route, "aim_error_radians": aim_error, "bosses": run.bosses_defeated, "kills": run.defeated_count, "draws": run.shot_sequence - start, "finished": run.is_finished(), "gold": run.gold, "spent": run.gold_spent, "entries": entries, "hits": w.hits}
		output.append(row)
		print("BOSS AUDIT ", trial, " bosses=", run.bosses_defeated, " kills=", run.defeated_count, " draws=", run.shot_sequence - start)
		w.queue_free()
		await process_frame
	var suffix: String = "-error" if aim_error > 0 else ""
	if OS.get_cmdline_user_args().has("--economy-current"): suffix += "-economy"
	var file := FileAccess.open("res://artifacts/t09b2-" + variant + "-" + route + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	quit()
