class_name AudioService
extends Node
## Sound effects and persistent, crossfading music on independent audio buses.

const VOICES: int = 10
const MUSIC_FADE_SECONDS: float = 0.65
const MUSIC: Dictionary = {
	"menu": preload("res://assets/audio/music/01_menu_moonlit_bow.ogg"),
	"camp": preload("res://assets/audio/music/03_ref_campfire_letters.ogg"),
	"battle": preload("res://assets/audio/music/battle_v4/E_ranger_skirmish.ogg"),
}
var music_players: Dictionary = {}
var music_positions: Dictionary = {}
var music_context: String = ""
var music_fade: Tween
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var sound_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var muted: bool = false

func _ready() -> void:
	# Music and its fades continue when the field is paused for menus/upgrades.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for context: String in MUSIC:
		var player := AudioStreamPlayer.new()
		player.name = "Music_" + context
		player.bus = "Music"
		player.stream = MUSIC[context]
		player.volume_linear = 0.0
		add_child(player)
		music_players[context] = player
	# Headless checks use the dummy audio driver; synthesized SFX aren't needed.
	if DisplayServer.get_name() == "headless":
		return
	sound_rng.seed = 8721
	sounds["release"] = _tone(300.0, 0.13, 0.4, -180.0)
	sounds["hit"] = _tone(150.0, 0.1, 0.55, -65.0)
	sounds["bullseye"] = _tone(740.0, 0.17, 0.05, 250.0)
	sounds["break"] = _tone(100.0, 0.19, 0.75, -55.0)
	sounds["critical"] = _tone(540.0, 0.16, 0.2, -140.0)
	sounds["metal_hit"] = _tone(320.0, 0.09, 0.4, -120.0)
	sounds["ricochet"] = _tone(950.0, 0.09, 0.12, -400.0)
	sounds["coin"] = _tone(1050.0, 0.12, 0.0, 450.0)
	sounds["draw"] = _tone(170.0, 0.1, 0.2, 180.0)
	sounds["boss_entry"] = _tone(110.0, 0.45, 0.22, -55.0)
	sounds["boss_phase"] = _tone(220.0, 0.32, 0.18, 310.0)
	sounds["shield_block"] = _tone(90.0, 0.15, 0.7, -30.0)
	sounds["shield_pass"] = _tone(420.0, 0.12, 0.3, 420.0)
	sounds["boss_weak"] = _tone(880.0, 0.22, 0.06, 300.0)
	sounds["boss_victory"] = _tone(520.0, 0.58, 0.0, 700.0)
	sounds["active_skill"] = _tone(390.0, 0.24, 0.08, 460.0)
	for index: int in range(VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)

func play_music(context: String) -> void:
	if context == music_context or not music_players.has(context): return
	music_context = context
	# Cancel stale stop callbacks when navigating again during a crossfade.
	if music_fade != null: music_fade.kill()
	var incoming: AudioStreamPlayer = music_players[context]
	if not incoming.playing:
		incoming.volume_linear = 0.0
		incoming.play(float(music_positions.get(context, 0.0)))
	music_fade = create_tween().set_parallel(true)
	music_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for key: String in music_players:
		var player: AudioStreamPlayer = music_players[key]
		if player.playing:
			music_fade.tween_property(player, "volume_linear", 1.0 if key == context else 0.0, MUSIC_FADE_SECONDS)
	music_fade.chain().tween_callback(_finish_music_fade.bind(context))

func _finish_music_fade(context: String) -> void:
	if context != music_context: return
	for key: String in music_players:
		var player: AudioStreamPlayer = music_players[key]
		if key != context and player.playing:
			music_positions[key] = fmod(player.get_playback_position(), player.stream.get_length())
			player.stop()

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
	if music_fade != null: music_fade.kill()
	for player: AudioStreamPlayer in music_players.values():
		player.stop()
		player.stream = null
	music_players.clear()
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
