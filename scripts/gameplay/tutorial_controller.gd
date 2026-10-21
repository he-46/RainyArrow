class_name TutorialController
extends Node
## Owns a disposable practice session. No reference to the permanent session or save store.

signal completed
signal leave_requested
signal mute_requested
enum Step { DRAW, BULLSEYE, UPGRADE, ENCOUNTER, COMPLETE }

var session: GameSession
var run: RunModel
var world: ArcheryWorld
var page: TutorialPage
var audio: AudioService
var options: Dictionary
var appearance: Dictionary = {}
var step: Step = Step.DRAW
var paused_by_user: bool = false
var purchased: bool = false
var message: String = ""

func start(sound: AudioService, settings: Dictionary, ui_root: Control, loadout: Dictionary = {}) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio = sound
	options = settings.duplicate(true)
	appearance = loadout.duplicate(true)
	page = TutorialPage.new()
	ui_root.add_child(page)
	page.action.connect(_on_action)
	restart()

func restart() -> void:
	if world != null:
		world.reset_shake()
		remove_child(world)
		world.queue_free()
	if run != null and run.changed.is_connected(_refresh): run.changed.disconnect(_refresh)
	session = GameSession.new(false)
	run = session.start_run()
	run.rng.seed = 1808
	step = Step.DRAW
	paused_by_user = false
	purchased = false
	message = ""
	world = ArcheryWorld.new()
	world.boss_enabled = false
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.run = run
	world.scale = Vector2(2, 2)
	add_child(world)
	world.feedback.connect(audio.play)
	world.draw_released.connect(_released)
	world.shot_settled.connect(_settle)
	world.volley_settled.connect(_refill)
	world.build_field({"targets": [{}]})
	_prepare_target(false)
	world.apply_settings(options)
	world.apply_cosmetics(appearance)
	run.changed.connect(_refresh)
	_refresh()

func apply_settings(settings: Dictionary) -> void:
	options = settings.duplicate(true)
	world.apply_settings(options)
	_refresh()

func _prepare_target(next_life: bool = true) -> void:
	var target: ArcheryTarget = world.targets[0]
	target.spawn(GameCatalog.TARGETS[0], 0, next_life)
	target.anchor = Vector2(316, 231)
	target.scale = Vector2.ONE * 1.4
	target.hp = 12
	target.max_hp = 12
	target.reward_score = 100
	target.reward_gold = 24
	target.tick(0, world.clock)

func _released(_shot_id: int) -> void:
	if step == Step.DRAW:
		step = Step.BULLSEYE
		message = ""
		_refresh()

func _settle(shot_id: int, hits: Array) -> void:
	if step == Step.BULLSEYE:
		# Unlimited aim retries must not open a lesson that has not been reached yet.
		run.encounter_rewards_generated = (run.defeated_count + 1) / EncounterCatalog.RULES.kills_per_reward
	session.settle_shot(shot_id, hits)
	var bullseye_kill: bool = false
	for hit: Dictionary in hits:
		if bool(hit["broken"]) and bool(hit["bullseye"]): bullseye_kill = true
	if step == Step.BULLSEYE:
		if bullseye_kill:
			step = Step.UPGRADE
			message = ""
			audio.play("coin")
		else:
			message = "这次还没击倒靶心，再试一次。\n把箭头送到红色中心；向下拖抬高弹道，拉远可提高速度。"
			# Each retry has a fresh easy target; never increase practice difficulty.
			_prepare_target()
	elif step == Step.ENCOUNTER and run.phase == RunModel.Phase.CHOICE:
		message = "现在从三张卡中选一项。\n至少一项是普通无负面增益；特性在本局展示过就不会再出现。"
	_refill()
	_refresh()

func _refill() -> void:
	if not run.is_finished(): run.restore_shots(maxi(0, RunModel.INITIAL_SHOTS - run.shots_left))

func _prepare_encounter() -> void:
	# Explicitly labelled demonstration progress, never passed to the real session.
	run.encounter_rewards_generated = run.defeated_count / EncounterCatalog.RULES.kills_per_reward
	var next: int = (run.encounter_rewards_generated + 1) * EncounterCatalog.RULES.kills_per_reward
	while run.defeated_count < next - 1:
		run.record_defeat("tutorial-demo-%d" % run.defeated_count, 0, 0)
	_prepare_target()
	world.reload_left = 0
	world.labels.clear()
	world.particles.clear()
	step = Step.ENCOUNTER
	message = ""
	_refresh()

func _on_action(id: String, value: Variant) -> void:
	match id:
		"leave": leave_requested.emit()
		"restart": restart()
		"pause": toggle_pause()
		"mute": mute_requested.emit()
		"skills":
			if step == Step.UPGRADE and not paused_by_user: run.open_skills()
		"purchase":
			if step == Step.UPGRADE and not paused_by_user and run.buy(value as RunSkillData):
				purchased = true
				message = "升级成功！点击「返回靶场」，用下一箭体验变化。\n经验会提升永久等级与天赋点；本教程的收益仅供练习。"
				audio.play("coin")
				_refresh()
		"continue":
			if step == Step.UPGRADE and run.phase == RunModel.Phase.SHOP and not paused_by_user:
				run.close_skills()
				if purchased: _prepare_encounter()
		"encounter_pick":
			if step == Step.ENCOUNTER and not paused_by_user and value is Dictionary and run.choose_encounter(str(value.get("id", "")), int(value.get("offer_id", -1))):
				step = Step.COMPLETE
				message = ""
				audio.play("coin", 1.15)
				_refresh()
				completed.emit()

func toggle_pause() -> void:
	set_paused(not paused_by_user)

func set_paused(value: bool) -> void:
	paused_by_user = value
	world.dragging = false
	world.pull = 0
	world.reset_shake()
	_refresh()

func _refresh() -> void:
	audio.play_music("camp" if step in [Step.UPGRADE, Step.COMPLETE] or run.phase != RunModel.Phase.PLAYING else "battle")
	world.ui_blocked = paused_by_user or step in [Step.UPGRADE, Step.COMPLETE] or run.phase != RunModel.Phase.PLAYING
	var pause_world: bool = paused_by_user or step in [Step.UPGRADE, Step.COMPLETE] or run.phase in [RunModel.Phase.SHOP, RunModel.Phase.CHOICE]
	if pause_world: world.reset_shake()
	get_tree().paused = pause_world
	page.refresh(run, session.profile, step, paused_by_user, bool(options["muted"]), message)
	page.hud.active_icon.reduced_effects = bool(options.get("reduced_effects", false))

func dispose() -> void:
	world.reset_shake()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	if page != null:
		page.get_parent().remove_child(page)
		page.queue_free()
		page = null
	if run.changed.is_connected(_refresh): run.changed.disconnect(_refresh)
