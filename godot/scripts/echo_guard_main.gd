extends Control

const BUS_BGM := "BGM"
const BUS_MIC := "Mic"

var _bgm_player: AudioStreamPlayer
var _mic_player: AudioStreamPlayer
var _segment_player: AudioStreamPlayer

var _cap_bgm: AudioEffectCapture
var _cap_mic: AudioEffectCapture

var _recording := false
var _record_start_ms := 0

var _ref: PackedFloat32Array = PackedFloat32Array()
var _mic: PackedFloat32Array = PackedFloat32Array()

var _mix_rate := 48000
var _out_dir_abs := ""
var _last_capture_dir := ""
var _proc_thread: Thread
var _proc_running := false

@onready var _start_btn: Button = $UI/Row1/StartBtn
@onready var _stop_btn: Button = $UI/Row1/StopBtn
@onready var _open_out_btn: Button = $UI/Row1/OpenOutBtn
@onready var _process_btn: Button = $UI/Row1/ProcessBtn
@onready var _reload_btn: Button = $UI/Row1/ReloadBtn
@onready var _status: Label = $UI/Status
@onready var _segments: ItemList = $UI/Segments
@onready var _play_btn: Button = $UI/Row2/PlayBtn
@onready var _stop_play_btn: Button = $UI/Row2/StopPlayBtn
@onready var _monitor_mic_chk: CheckBox = $UI/Row3/MonitorMicChk


func _ready() -> void:
	_mix_rate = int(ProjectSettings.get_setting("audio/driver/mix_rate", 48000))
	_out_dir_abs = _default_out_dir()
	_apply_cmdline_overrides()
	_setup_buses()
	_setup_players()
	_wire_ui()
	_print_instructions()
	_set_status("Status: idle")
	_set_mic_monitor(false)
	_update_ui()


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
	if _cap_bgm:
		_cap_bgm.clear_buffer()
	if _cap_mic:
		_cap_mic.clear_buffer()
	_set_status("Status: recording… (press R or Stop)")
	_update_ui()


func stop_and_export() -> void:
	_recording = false
	var duration_ms := Time.get_ticks_msec() - _record_start_ms
	print("[echo-guard] recording stopped, duration_ms=%d ref_samples=%d mic_samples=%d" % [duration_ms, _ref.size(), _mic.size()])

	var out_dir := _make_capture_dir()
	_last_capture_dir = out_dir
	var ref_wav := out_dir.path_join("ref_signal.wav")
	var mic_wav := out_dir.path_join("raw_mic.wav")

	_write_wav_pcm16_mono(ref_wav, _mix_rate, _ref)
	_write_wav_pcm16_mono(mic_wav, _mix_rate, _mic)

	print("[echo-guard] wrote: %s" % ref_wav)
	print("[echo-guard] wrote: %s" % mic_wav)
	print("[echo-guard] next: run scripts/step6_process_capture.ps1 -CaptureDir \"%s\"" % out_dir)

	_set_status("Status: exported\n- %s\n- %s\nNext: run scripts/step6_process_capture.ps1" % [mic_wav, ref_wav])
	_reload_segments(false)
	_update_ui()


func _default_out_dir() -> String:
	# Project root is .../echo-guard/godot; default outputs into repo out/godot_capture
	var repo_abs := ProjectSettings.globalize_path("res://..").simplify_path()
	return repo_abs.path_join("out").path_join("godot_capture")


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

	_segment_player = $SegmentPlayer


func _setup_buses() -> void:
	_ensure_bus(BUS_BGM)
	_ensure_bus(BUS_MIC)

	_cap_bgm = AudioEffectCapture.new()
	_cap_mic = AudioEffectCapture.new()

	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	var mic_idx := AudioServer.get_bus_index(BUS_MIC)

	AudioServer.add_bus_effect(bgm_idx, _cap_bgm, 0)
	AudioServer.add_bus_effect(mic_idx, _cap_mic, 0)

	# Avoid feedback/howling by default: still capture mic, but don't monitor it to speakers.
	AudioServer.set_bus_mute(mic_idx, true)

	_drain_captures_discard()


func _ensure_bus(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return
	AudioServer.add_bus()
	var new_idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(new_idx, bus_name)
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
	var bytes_per_sample := int(bits_per_sample / 8.0)
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


func _wire_ui() -> void:
	_start_btn.pressed.connect(func() -> void:
		if not _recording:
			start_recording()
	)
	_stop_btn.pressed.connect(func() -> void:
		if _recording:
			stop_and_export()
	)
	_open_out_btn.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(_out_dir_abs)
		OS.shell_open(_out_dir_abs)
	)
	_process_btn.pressed.connect(func() -> void:
		_process_last_capture()
	)
	_reload_btn.pressed.connect(func() -> void:
		_reload_segments()
	)
	_play_btn.pressed.connect(func() -> void:
		_play_selected()
	)
	_stop_play_btn.pressed.connect(func() -> void:
		if _segment_player and _segment_player.playing:
			_segment_player.stop()
	)
	_monitor_mic_chk.toggled.connect(func(enabled: bool) -> void:
		_set_mic_monitor(enabled)
	)

	_segments.item_selected.connect(func(_idx: int) -> void:
		_update_ui()
	)
	_segments.gui_input.connect(func(_event: InputEvent) -> void:
		_update_ui()
	)
	_segments.item_activated.connect(func(_idx: int) -> void:
		_play_selected()
	)


func _update_ui() -> void:
	_start_btn.disabled = _recording
	_stop_btn.disabled = not _recording
	_play_btn.disabled = _segments.get_selected_items().is_empty()
	_process_btn.disabled = _recording or _proc_running
	_reload_btn.disabled = _proc_running


func _set_mic_monitor(enabled: bool) -> void:
	var mic_idx := AudioServer.get_bus_index(BUS_MIC)
	if mic_idx == -1:
		return
	AudioServer.set_bus_mute(mic_idx, not enabled)


func _set_status(text: String) -> void:
	_status.text = text


func _latest_capture_dir() -> String:
	if not DirAccess.dir_exists_absolute(_out_dir_abs):
		return ""
	var d := DirAccess.open(_out_dir_abs)
	if d == null:
		return ""
	var entries := PackedStringArray()
	d.list_dir_begin()
	while true:
		var entry_name := d.get_next()
		if entry_name == "":
			break
		if entry_name.begins_with("."):
			continue
		if d.current_is_dir():
			entries.append(entry_name)
	d.list_dir_end()
	entries.sort()
	if entries.is_empty():
		return ""
	return _out_dir_abs.path_join(entries[entries.size() - 1])


func _reload_segments(update_status: bool = true) -> void:
	var base := _last_capture_dir
	if base == "":
		base = _latest_capture_dir()
	if base == "":
		_segments.clear()
		if update_status:
			_set_status("Status: no captures yet. Press Start/Stop to export first.")
		return

	var vad_dir := base.path_join("vad")
	_segments.clear()

	if not DirAccess.dir_exists_absolute(vad_dir):
		if update_status:
			_set_status("Status: exported at %s\n(No vad/ yet. Run scripts/step6_process_capture.ps1)" % base)
		return

	var d := DirAccess.open(vad_dir)
	if d == null:
		_set_status("Status: cannot open vad dir: %s" % vad_dir)
		return

	var files := PackedStringArray()
	d.list_dir_begin()
	while true:
		var entry_name := d.get_next()
		if entry_name == "":
			break
		if d.current_is_dir():
			continue
		if entry_name.begins_with("segment_") and entry_name.ends_with(".wav"):
			files.append(entry_name)
	d.list_dir_end()
	files.sort()

	for f in files:
		_segments.add_item(f)

	var vad_txt := vad_dir.path_join("vad_result.txt")
	if FileAccess.file_exists(vad_txt):
		if update_status:
			_set_status("Status: segments loaded (%d) from %s" % [files.size(), vad_dir])
	else:
		if update_status:
			if _proc_running:
				_set_status("Status: processing… (waiting for vad_result.txt)\n%s" % vad_dir)
			else:
				_set_status("Status: vad/ exists but vad_result.txt missing: %s" % vad_dir)

	_update_ui()


func _play_selected() -> void:
	var sel := _segments.get_selected_items()
	if sel.is_empty():
		return

	var base := _last_capture_dir
	if base == "":
		base = _latest_capture_dir()
	if base == "":
		return

	var vad_dir := base.path_join("vad")
	var filename := _segments.get_item_text(sel[0])
	var path_abs := vad_dir.path_join(filename)

	var stream := _load_wav_as_stream(path_abs)
	if stream == null:
		_set_status("Status: failed to load WAV: %s" % path_abs)
		return

	_segment_player.stream = stream
	_segment_player.play()
	_set_status("Status: playing %s" % filename)

func _process_last_capture() -> void:
	if _proc_running:
		return
	if OS.has_feature("web"): # sanity
		_set_status("Status: processing not supported on web")
		return

	var cap_dir := _last_capture_dir
	if cap_dir == "":
		cap_dir = _latest_capture_dir()
	if cap_dir == "":
		_set_status("Status: no captures yet. Export first.")
		return

	var mic_wav := cap_dir.path_join("raw_mic.wav")
	var ref_wav := cap_dir.path_join("ref_signal.wav")
	if not FileAccess.file_exists(mic_wav) or not FileAccess.file_exists(ref_wav):
		_set_status("Status: capture incomplete (missing raw_mic.wav/ref_signal.wav)\n%s" % cap_dir)
		return

	var script_abs := ProjectSettings.globalize_path("res://../scripts/step6_process_capture.ps1").simplify_path()
	if not FileAccess.file_exists(script_abs):
		_set_status("Status: missing script: %s" % script_abs)
		return

	_proc_running = true
	_update_ui()
	_set_status("Status: processing… (AEC+VAD)\n%s" % cap_dir)

	var args := PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", script_abs,
		"-CaptureDir", cap_dir,
	])

	_proc_thread = Thread.new()
	_proc_thread.start(Callable(self, "_thread_run_process").bind(args, cap_dir))


func _thread_run_process(args: PackedStringArray, cap_dir: String) -> void:
	var output: Array = []
	var code := OS.execute("pwsh", args, output, true, true)
	var text := ""
	for line in output:
		text += str(line) + "\n"
	call_deferred("_on_process_done", code, text, cap_dir)


func _on_process_done(code: int, text: String, cap_dir: String) -> void:
	if _proc_thread:
		_proc_thread.wait_to_finish()
	_proc_thread = null
	_proc_running = false

	if code == 0:
		_reload_segments(true)
	else:
		_set_status("Status: process failed (code=%d)\n%s\n\n%s" % [code, cap_dir, text])
		_reload_segments(false)
	_update_ui()


func _read_u16_le(b: PackedByteArray, off: int) -> int:
	return int(b[off]) | (int(b[off + 1]) << 8)


func _read_u32_le(b: PackedByteArray, off: int) -> int:
	return int(b[off]) | (int(b[off + 1]) << 8) | (int(b[off + 2]) << 16) | (int(b[off + 3]) << 24)


func _load_wav_as_stream(path_abs: String) -> AudioStreamWAV:
	var f := FileAccess.open(path_abs, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()

	if bytes.size() < 12:
		return null

	var riff := bytes.slice(0, 4).get_string_from_ascii()
	var wave := bytes.slice(8, 12).get_string_from_ascii()
	if riff != "RIFF" or wave != "WAVE":
		return null

	var channels := 0
	var sample_rate := 0
	var bits := 0
	var data := PackedByteArray()

	var pos := 12
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := _read_u32_le(bytes, pos + 4)
		var chunk_start := pos + 8
		var chunk_end := chunk_start + sz
		if chunk_end > bytes.size():
			break

		if id == "fmt " and sz >= 16:
			var audio_format := _read_u16_le(bytes, chunk_start + 0)
			channels = _read_u16_le(bytes, chunk_start + 2)
			sample_rate = _read_u32_le(bytes, chunk_start + 4)
			bits = _read_u16_le(bytes, chunk_start + 14)
			if audio_format != 1:
				return null
		elif id == "data":
			data = bytes.slice(chunk_start, chunk_end)

		pos = chunk_end + (sz % 2)

	if bits != 16:
		return null
	if channels != 1 and channels != 2:
		return null
	if data.is_empty():
		return null

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = channels == 2
	wav.data = data
	return wav


func _print_instructions() -> void:
	print("")
	print("echo-guard Godot Step 6")
	print("- BGM: res://assets/audio/pixel_coffee_break.mp3 (bus=%s)" % BUS_BGM)
	print("- Mic: AudioStreamMicrophone (bus=%s)" % BUS_MIC)
	print("- Hotkey: Press R to start/stop + export")
	print("- Output base: %s" % _out_dir_abs)
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
