extends "res://tests/benchmark_visual_v07.gd"
## Real-time endurance fixtures; artificial HP/ammunition, never a balance sample.
var duration: float = 120.0

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): duration = clampf(arg.trim_prefix("--seconds=").to_float(), 15, 1800)
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "endurance-fixture"
	main.session.profile.settings.screen_shake = false
	for kind: String in ["targets", "boss"]:
		await soak(kind)
	var output := {"method": "real-time native window, 60 FPS cap, 120 Hz physics; artificial HP/ammunition; Dummy audio", "seconds_per_scene": duration, "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "results": reports, "failures": failures}
	var file := FileAccess.open("res://artifacts/t09c-soak.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("T09C SOAK: %d scenes, %d failures" % [reports.size(), failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)

func soak(kind: String) -> void:
	main._new_run("normal", null, true)
	var w: ArcheryWorld = main.world
	var r: RunModel = main.run
	r.rng.seed = 91020
	if kind == "boss":
		preload("res://tests/test_boss.gd").new(verify).prime(r, 100)
		w._physics_process(0)
		w.boss.max_hp = 100000000
		w.boss.hp = 40000000
		w.boss.refresh_phase()
	else:
		r.talent_effects.target_count = 6
		w.build_field()
		for target: ArcheryTarget in w.targets:
			target.max_hp = 100000000
			target.hp = target.max_hp
			target.armor = 0
		w.targets[0].anchor = Vector2(300, 220)
		w.targets[0].scale.y = 3
	r.encounter_picks = {"piercing_split": 1, "ricochet_haste": 1, "echo_strike": 1, "bullseye_wave": 1, "branch_ricochet": 1}
	r.rebuild_stats()
	r.stats.arrow_count = 32
	r.stats.spread_degrees = 0.35
	r.stats.damage = 1
	r.stats.armor_penetration = 100
	r.stats.bounces = 6
	r.stats.gravity = 0
	r.stats.launch_speed = 500
	r.shots_left = 10000
	w.direction = Vector2.RIGHT
	w.volley_settled.disconnect(main._save_checkpoint)
	main._refresh()
	var start: int = Time.get_ticks_msec()
	var last: int = start
	var next_draw: float = 0
	var next_sample: float = 0
	var frame_ms: Array[float] = []
	var samples: Array[Dictionary] = []
	var peaks := {"arrows": 0, "labels": 0, "effects": 0, "ledgers": 0, "children": 0}
	while (Time.get_ticks_msec() - start) / 1000.0 < duration:
		await process_frame
		var now: int = Time.get_ticks_msec()
		var elapsed: float = (now - start) / 1000.0
		if elapsed > 15: frame_ms.append(float(now - last))
		last = now
		if elapsed >= next_draw:
			w.pull = 1
			w._release()
			next_draw = elapsed + 1.0
		peaks.arrows = maxi(peaks.arrows, w.arrows.size())
		peaks.labels = maxi(peaks.labels, w.labels.size())
		peaks.effects = maxi(peaks.effects, w.vfx.events.size())
		peaks.ledgers = maxi(peaks.ledgers, w.projectile_ledger.size())
		for ledger: Dictionary in w.projectile_ledger.values():
			peaks.children = maxi(peaks.children, int(ledger.children))
		if elapsed >= next_sample:
			samples.append({"seconds": elapsed, "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "nodes": get_node_count(), "arrows": w.arrows.size(), "ledgers": w.projectile_ledger.size()})
			next_sample = elapsed + 5
	await create_timer(Arrow.MAX_LIFETIME + 2).timeout
	verify(r.shot_sequence >= int(duration) - 4, "real-time shots progressed: " + kind)
	verify(w.arrows.is_empty() and w.projectile_ledger.is_empty() and w.pending_volleys.is_empty(), "arrows and settlement ledgers drain: " + kind)
	verify(w.labels.is_empty() and w.vfx.events.is_empty(), "captions and effects drain: " + kind)
	verify(peaks.labels <= CombatCaptions.LIMIT and peaks.effects <= CombatVFX.LIMIT and peaks.children <= ArcheryWorld.MAX_SPLIT_CHILDREN, "presentation and child budgets: " + kind)
	if kind == "targets": verify(peaks.children == 64, "stress actually exercises split budget")
	if kind == "boss": verify(w.boss.volley_pressure.is_empty(), "Boss pressure ledger drains")
	var growth: float = float(samples.back().memory_bytes) - float(samples[mini(4, samples.size() - 1)].memory_bytes)
	verify(growth < 32 * 1024 * 1024, "post-warmup tracked memory growth below 32 MiB: " + kind)
	reports.append({"scene": kind, "draws": r.shot_sequence, "simulation_seconds": w.clock, "frame_wall": summary(frame_ms) if not frame_ms.is_empty() else {}, "peaks": peaks, "post_warmup_memory_growth_bytes": growth, "samples": samples, "drained_nodes": get_node_count()})
	print("T09C SOAK scene=", kind, " draws=", r.shot_sequence, " peaks=", peaks, " growth=", growth)
