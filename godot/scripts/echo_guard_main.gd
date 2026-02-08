extends Control

const BUS_BGM := "BGM"
const BUS_MIC := "Mic"

const CAPTURE_EFFECT_NAME := "AudioEffectCapture"

var _bgm_player: AudioStreamPlayer
var _mic_player: AudioStreamPlayer

var _cap_bgm: AudioEffectCapture
var _cap_mic: AudioEffectCapture

var _recording := false
var _record_start_ms := 0

var _ref: PackedFloat32Array = PackedFloat32Array()
var _mic: PackedFloat32Array = PackedFloat32Array()

var _mix_rate := 48000
var _out_dir_abs := ""


func _ready() -> void:
	_mix_rate = int(ProjectSettings.get_setting("audio/driver/mix_rate", 48000))
	_out_dir_abs = _default_out_dir()
	_apply_cmdline_overrides()
	_setup_buses()
	_setup_players()
	_print_instructions()


func _process(_delta: float) -> void:
	if not _recording:
		_drain_captures_discard()
		return

	_pull_aligned_frames()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if not _recording:
				start_recording()
			else:
				stop_and_export()


func start_recording() -> void:
	_recording = true
	_record_start_ms = Time.get_ticks_msec()
	_ref = PackedFloat32Array()
	_mic = PackedFloat32Array()
	print("[echo-guard] recording started")


func stop_and_export() -> void:
	_recording = false
	var duration_ms := Time.get_ticks_msec() - _record_start_ms
	print("[echo-guard] recording stopped, duration_ms=%d ref_samples=%d mic_samples=%d" % [duration_ms, _ref.size(), _mic.size()])

	var out_dir := _make_capture_dir()
	var ref_wav := out_dir.path_join("ref_signal.wav")
	var mic_wav := out_dir.path_join("raw_mic.wav")

	_write_wav_pcm16_mono(ref_wav, _mix_rate, _ref)
	_write_wav_pcm16_mono(mic_wav, _mix_rate, _mic)

	print("[echo-guard] wrote: %s" % ref_wav)
	print("[echo-guard] wrote: %s" % mic_wav)
	print("[echo-guard] next: run scripts/step6_process_capture.ps1 -CaptureDir \"%s\"" % out_dir)


func _default_out_dir() -> String:
	# Project root is .../echo-guard/godot; default outputs into repo out/godot_capture
	var repo_abs := ProjectSettings.globalize_path("res://..")
	repo_abs = repo_abs.simplify_path()
	var out_abs := repo_abs.path_join("out").path_join("godot_capture")
	return out_abs


func _make_capture_dir() -> String:
	DirAccess.make_dir_recursive_absolute(_out_dir_abs)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := _out_dir_abs.path_join(stamp)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _setup_players() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)

	var bgm_path := "res://assets/audio/pixel_coffee_break.mp3"
	if ResourceLoader.exists(bgm_path):
		_bgm_player.stream = load(bgm_path)
		_bgm_player.autoplay = true
		_bgm_player.play()
	else:
		push_warning("BGM not found: %s" % bgm_path)

	if _should_enable_mic():
		_mic_player = AudioStreamPlayer.new()
		_mic_player.bus = BUS_MIC
		add_child(_mic_player)

		var mic_stream := AudioStreamMicrophone.new()
		_mic_player.stream = mic_stream
		_mic_player.autoplay = true
		_mic_player.play()
	else:
		print("[echo-guard] mic disabled (headless or --eg-no-mic)")


func _setup_buses() -> void:
	_ensure_bus(BUS_BGM)
	_ensure_bus(BUS_MIC)

	_cap_bgm = AudioEffectCapture.new()
	_cap_mic = AudioEffectCapture.new()

	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	var mic_idx := AudioServer.get_bus_index(BUS_MIC)

	AudioServer.add_bus_effect(bgm_idx, _cap_bgm, 0)
	AudioServer.add_bus_effect(mic_idx, _cap_mic, 0)

	_drain_captures_discard()


func _ensure_bus(name: String) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx != -1:
		return
	AudioServer.add_bus()
	var new_idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(new_idx, name)
	AudioServer.set_bus_send(new_idx, "Master")


func _drain_captures_discard() -> void:
	# Prevent buffer buildup while idle.
	if _cap_bgm and _cap_bgm.get_frames_available() > 0:
		_cap_bgm.get_buffer(_cap_bgm.get_frames_available())
	if _cap_mic and _cap_mic.get_frames_available() > 0:
		_cap_mic.get_buffer(_cap_mic.get_frames_available())


func _pull_aligned_frames() -> void:
	if not _cap_bgm or not _cap_mic:
		return

	var bgm_avail := int(_cap_bgm.get_frames_available())
	var mic_avail := int(_cap_mic.get_frames_available())
	var n: int = mini(bgm_avail, mic_avail)
	if n <= 0:
		return

	var bgm_buf: PackedVector2Array = _cap_bgm.get_buffer(n)
	var mic_buf: PackedVector2Array = _cap_mic.get_buffer(n)

	_ref.resize(_ref.size() + n)
	_mic.resize(_mic.size() + n)

	var base: int = _ref.size() - n
	for i in range(n):
		var b: Vector2 = bgm_buf[i]
		var m: Vector2 = mic_buf[i]
		_ref[base + i] = (b.x + b.y) * 0.5
		_mic[base + i] = (m.x + m.y) * 0.5


func _write_wav_pcm16_mono(path_abs: String, sample_rate: int, samples: PackedFloat32Array) -> void:
	var f := FileAccess.open(path_abs, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open for write: %s" % path_abs)
		return

	var num_channels := 1
	var bits_per_sample := 16
	var bytes_per_sample := bits_per_sample / 8
	var data_bytes := samples.size() * bytes_per_sample
	var block_align := num_channels * bytes_per_sample
	var byte_rate := sample_rate * block_align
	var riff_size := 4 + (8 + 16) + (8 + data_bytes)

	# RIFF header
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(riff_size)
	f.store_buffer("WAVE".to_ascii_buffer())

	# fmt chunk
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1) # PCM
	f.store_16(num_channels)
	f.store_32(sample_rate)
	f.store_32(byte_rate)
	f.store_16(block_align)
	f.store_16(bits_per_sample)

	# data chunk
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_bytes)

	for x in samples:
		var v := int(round(clamp(x, -1.0, 1.0) * 32767.0))
		if v < -32768:
			v = -32768
		if v > 32767:
			v = 32767
		f.store_16(v)

	f.close()


func _print_instructions() -> void:
	print("")


func _should_enable_mic() -> bool:
	if OS.has_feature("headless"):
		return false
	var user_args := OS.get_cmdline_user_args()
	return not user_args.has("--eg-no-mic")


func _apply_cmdline_overrides() -> void:
	var user_args := OS.get_cmdline_user_args()
	var i := 0
	while i < user_args.size():
		var a := user_args[i]
		if a == "--eg-out-dir" and i + 1 < user_args.size():
			_out_dir_abs = user_args[i + 1]
			i += 2
			continue
		i += 1
	print("echo-guard Godot Step 6")
	print("- BGM: res://assets/audio/pixel_coffee_break.mp3 (bus=%s)" % BUS_BGM)
	print("- Mic: AudioStreamMicrophone (bus=%s)" % BUS_MIC)
	print("- Hotkey: Press R to start/stop + export")
	print("- Output base: %s" % _out_dir_abs)
	print("")
