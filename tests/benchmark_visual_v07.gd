extends SceneTree
## Deterministic 120 Hz replay with one rendered frame per tick, not a real-time FPS claim.
const DT: float = 1.0 / 120.0
const STEPS: int = 720
var main: Node
var failures: int = 0
var reports: Array[Dictionary] = []
var previous_states: Dictionary = {}
var tag: String = "baseline"

func _initialize() -> void: _run.call_deferred()
func verify(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("V07 BENCH: " + message)

func summary(samples: Array[float]) -> Dictionary:
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	var total: float = 0
	for value: float in ordered: total += value
	return {"mean_ms": total / ordered.size(), "p50_ms": ordered[int(ordered.size() * 0.5)], "p95_ms": ordered[int(ordered.size() * 0.95)], "p99_ms": ordered[int(ordered.size() * 0.99)], "max_ms": ordered.back()}

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--test-mode"):
		quit(1)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.capture_path = "v07-benchmark"
	main.session.profile.settings.screen_shake = false
	for extent: Vector2i in [Vector2i(960, 540), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(extent)
		await create_timer(0.15).timeout
		for kind: String in ["targets", "boss"]:
			for reduced: bool in [false, true]:
				await measure(extent, kind, reduced)
	var output := {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "os": OS.get_name(), "vsync": DisplayServer.window_get_vsync_mode(), "physics_hz": 120, "steps": STEPS, "warmup_steps": 120, "method": "fixed-step replay, one rendered frame/tick; step CPU excludes rendering; frame wall includes draw and scheduler; not live FPS", "results": reports, "failures": failures}
	var file := FileAccess.open("res://artifacts/v07-performance-" + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print("V07 BENCH RESULT: %d scenarios, %d failures; %s" % [reports.size(), failures, tag])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)

func measure(extent: Vector2i, kind: String, reduced: bool) -> void:
	main._new_run("normal", null, true)
	var w: ArcheryWorld = main.world
	var r: RunModel = main.run
	w.set_process(false)
	w.set_physics_process(false)
	w.vfx.set_process(false)
	r.rng.seed = 70717
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
		# A broad first target guarantees all 32 mothers exit and create 64 real children.
		w.targets[0].anchor = Vector2(300, 220)
		w.targets[0].scale.y = 3
	r.encounter_picks = {"piercing_split": 1, "ricochet_haste": 1, "echo_strike": 1, "bullseye_wave": 1, "branch_ricochet": 1}
	r.rebuild_stats()
	r.stats.arrow_count = 32
	r.stats.spread_degrees = 0.35
	r.stats.damage = 1
	r.stats.crit_chance = 0.5
	r.stats.armor_penetration = 100
	r.stats.bounces = 6
	r.stats.gravity = 0
	r.stats.launch_speed = 500
	r.shots_left = 20
	w.direction = Vector2.RIGHT
	main.session.profile.settings.reduced_effects = reduced
	w.apply_settings(main.session.profile.settings)
	main._refresh()
	# These fixtures intentionally use artificial endurance; never write them as player saves.
	w.volley_settled.disconnect(main._save_checkpoint)
	var step_samples: Array[float] = []
	var frame_samples: Array[float] = []
	var peak_arrows: int = 0
	var peak_vfx: int = 0
	var peak_labels: int = 0
	var max_children: int = 0
	var bounces: int = 0
	var hits: int = 0
	for tick: int in range(STEPS):
		var frame_start: int = Time.get_ticks_usec()
		var step_start: int = frame_start
		if tick % 120 == 0:
			w.reload_left = 0
			w.pull = 1
			w._release()
		for arrow: Arrow in w.arrows.duplicate():
			arrow.set_physics_process(false)
			var old_bounces: int = arrow.remaining_bounces
			var old_hits: int = arrow.hit_slots.size()
			arrow._physics_process(DT)
			bounces += maxi(0, old_bounces - arrow.remaining_bounces)
			hits += maxi(0, arrow.hit_slots.size() - old_hits)
		# Children created during this tick first advance on the next deterministic tick.
		for arrow: Arrow in w.arrows: arrow.set_physics_process(false)
		w._physics_process(DT)
		w._process(DT)
		w.vfx._process(DT)
		var cpu_ms: float = (Time.get_ticks_usec() - step_start) / 1000.0
		peak_arrows = maxi(peak_arrows, w.arrows.size())
		peak_vfx = maxi(peak_vfx, w.vfx.events.size())
		peak_labels = maxi(peak_labels, w.labels.size())
		for ledger: Dictionary in w.projectile_ledger.values(): max_children = maxi(max_children, int(ledger.children))
		await process_frame
		await RenderingServer.frame_post_draw
		if tick >= 120:
			step_samples.append(cpu_ms)
			frame_samples.append((Time.get_ticks_usec() - frame_start) / 1000.0)
		if tick == 270:
			root.get_texture().get_image().save_png("res://artifacts/v07-stress-%s-%d-%s.png" % [kind, extent.x, "reduced" if reduced else "full"])
	verify(max_children == 64, "actual split reaches per-draw budget: " + kind)
	verify(bounces > 0 and hits > 0, "real contacts and bounces: " + kind)
	verify(peak_vfx <= (CombatVFX.REDUCED_LIMIT if reduced else CombatVFX.LIMIT) and peak_labels <= CombatCaptions.LIMIT, "bounded presentation")
	var state: Dictionary = w.snapshot().duplicate(true)
	state["rng"] = r.rng.state
	var key: String = "%s-%d" % [kind, extent.x]
	if reduced: verify(previous_states[key] == state, "full/reduced preserve identical simulation: " + key)
	else: previous_states[key] = state
	var report := {"scene": kind, "width": extent.x, "reduced": reduced, "peak_arrows": peak_arrows, "children_per_draw": max_children, "bounces": bounces, "contacts": hits, "peak_effects": peak_vfx, "peak_captions": peak_labels, "cpu_step": summary(step_samples), "render_frame_wall": summary(frame_samples)}
	reports.append(report)
	print(JSON.stringify(report))
