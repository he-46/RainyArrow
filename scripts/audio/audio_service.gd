class_name AudioService
extends Node
## Original synthesized placeholder sounds. Replace streams without changing gameplay.

const VOICES: int = 10
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var sound_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var muted: bool = false

func _ready() -> void:
	# Headless CI has no listener; avoid opening audio playback resources there.
	if DisplayServer.get_name() == "headless":
		return
	sound_rng.seed = 8721
	sounds["release"] = _tone(300.0, 0.13, 0.4, -180.0)
	sounds["hit"] = _tone(150.0, 0.1, 0.55, -65.0)
	sounds["bullseye"] = _tone(740.0, 0.17, 0.05, 250.0)
	sounds["break"] = _tone(100.0, 0.19, 0.75, -55.0)
	sounds["coin"] = _tone(1050.0, 0.12, 0.0, 450.0)
	sounds["draw"] = _tone(170.0, 0.1, 0.2, 180.0)
	sounds["boss_entry"] = _tone(110.0, 0.45, 0.22, -55.0)
	sounds["boss_phase"] = _tone(220.0, 0.32, 0.18, 310.0)
	sounds["shield_block"] = _tone(90.0, 0.15, 0.7, -30.0)
	sounds["shield_pass"] = _tone(420.0, 0.12, 0.3, 420.0)
	sounds["boss_weak"] = _tone(880.0, 0.22, 0.06, 300.0)
	sounds["boss_victory"] = _tone(520.0, 0.58, 0.0, 700.0)
	for index: int in range(VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)

func play(cue: String, pitch: float = 1.0) -> void:
	if muted or not sounds.has(cue):
		return
	for player: AudioStreamPlayer in players:
		if not player.playing:
			player.stream = sounds[cue]
			player.bus = "Bow" if cue in ["release", "draw"] else ("UI" if cue == "coin" else "Impact")
			player.pitch_scale = pitch
			player.play()
			return

func apply_settings(options: Dictionary) -> void:
	muted = bool(options["muted"])
	AudioServer.set_bus_mute(0, muted)
	_set_volume("Master", float(options["master_volume"]), -4.0)
	for bus: String in ["Bow", "Impact", "UI"]:
		var trim: float = -2.0 if bus == "Bow" else (-3.0 if bus == "Impact" else -5.0)
		_set_volume(bus, float(options["sfx_volume"]), trim)
	_set_volume("Music", float(options["music_volume"]), -8.0)

func _set_volume(bus: String, volume: float, trim: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0: return
	AudioServer.set_bus_volume_db(index, trim + linear_to_db(maxf(volume, 0.00001)))
	# Zero is true silence, with a finite dB value. Master mute has its own flag.
	if bus != "Master": AudioServer.set_bus_mute(index, volume <= 0.0)
	else: AudioServer.set_bus_mute(index, muted or volume <= 0.0)

func _exit_tree() -> void:
	for player: AudioStreamPlayer in players:
		player.stop()
		player.stream = null
	sounds.clear()

func _tone(frequency: float, duration: float, noise: float, sweep: float) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(float(rate) * duration)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	for index: int in range(count):
		var t: float = float(index) / float(count)
		phase += TAU * (frequency + sweep * t) / float(rate)
		var envelope: float = minf(t * 30.0, 1.0) * pow(1.0 - t, 2.5)
		var sample: float = (sin(phase) * (1.0 - noise) + sound_rng.randf_range(-1, 1) * noise) * envelope * 0.45
		bytes.encode_s16(index * 2, int(sample * 32767.0))
	var sound: AudioStreamWAV = AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = bytes
	return sound
