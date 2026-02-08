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
var _clean_native: PackedFloat32Array = PackedFloat32Array()
var _native_proc: Object
var _native_last_rms := 0.0
var _active_capture_dir := ""

# Native VAD segmentation (10 ms frames).
var _vad_native_lines: PackedStringArray = PackedStringArray()
var _vad_native_frame_idx := 0
var _seg_active := false
var _seg_index := 0
var _seg_samples: PackedFloat32Array = PackedFloat32Array()
var _seg_tail_frames: Array = []
var _pre_roll_frames: Array = []
var _speech_run := 0
var _silence_run := 0

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
	_clean_native = PackedFloat32Array()
	_vad_native_lines = PackedStringArray()
	_vad_native_frame_idx = 0
	_seg_active = false
	_seg_index = 0
	_seg_samples = PackedFloat32Array()
	_seg_tail_frames = []
	_pre_roll_frames = []
	_speech_run = 0
	_silence_run = 0

	_active_capture_dir = _make_capture_dir()
	_last_capture_dir = _active_capture_dir
	DirAccess.make_dir_recursive_absolute(_active_capture_dir.path_join("vad_native"))

	if _cap_bgm:
		_cap_bgm.clear_buffer()
	if _cap_mic:
		_cap_mic.clear_buffer()
	_set_status("Status: recording… (press R or Stop)")
	_update_ui()


func stop_and_export() -> void:
	_recording = false
	var duration_ms := Time.get_ticks_msec() - _record_start_ms
	print("[echo-guard] recording stopped, duration_ms=%d ref_samples=%d mic_samples=%d clean_samples=%d" % [duration_ms, _ref.size(), _mic.size(), _clean_native.size()])

	var out_dir := _active_capture_dir
	if out_dir == "":
		out_dir = _make_capture_dir()
		_last_capture_dir = out_dir
	var ref_wav := out_dir.path_join("ref_signal.wav")
	var mic_wav := out_dir.path_join("raw_mic.wav")
	var clean_native_wav := out_dir.path_join("clean_native.wav")

	_write_wav_pcm16_mono(ref_wav, _mix_rate, _ref)
	_write_wav_pcm16_mono(mic_wav, _mix_rate, _mic)
	if not _clean_native.is_empty():
		_write_wav_pcm16_mono(clean_native_wav, _mix_rate, _clean_native)

	_finalize_segment_if_needed()
	_write_vad_native_log()
	_active_capture_dir = ""

	print("[echo-guard] wrote: %s" % ref_wav)
	print("[echo-guard] wrote: %s" % mic_wav)
	if not _clean_native.is_empty():
		print("[echo-guard] wrote: %s" % clean_native_wav)
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

func _try_init_native() -> void:
	_native_proc = null
	_native_last_rms = 0.0

	# Explicitly load the .gdextension resource so the class is available even if the project setting
	# isn't applied (useful for headless runs or misconfigured projects).
	var ext_path := "res://gdextension/echo_guard.gdextension"
	if ResourceLoader.exists(ext_path):
		ResourceLoader.load(ext_path)

	if not ClassDB.class_exists("EchoGuardProcessor"):
		print("[echo-guard] native extension not loaded (EchoGuardProcessor missing)")
		return
	_native_proc = ClassDB.instantiate("EchoGuardProcessor")
	if _native_proc == null:
		print("[echo-guard] native extension instantiate failed")
		return
	_native_proc.call("set_sample_rate_hz", _mix_rate)
	_native_proc.call("set_delay_ms", 0)
	_native_proc.call("set_post_gain", 2.0) # default boost; tweak later via UI
	print("[echo-guard] native extension loaded: EchoGuardProcessor")


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
	var ref_tmp := PackedFloat32Array()
	var mic_tmp := PackedFloat32Array()
	ref_tmp.resize(n)
	mic_tmp.resize(n)

	var base: int = _ref.size() - n
	for i in range(n):
		var b: Vector2 = bgm_buf[i]
		var m: Vector2 = mic_buf[i]
		var r := (b.x + b.y) * 0.5
		var mic := (m.x + m.y) * 0.5
		_ref[base + i] = r
		_mic[base + i] = mic
		ref_tmp[i] = r
		mic_tmp[i] = mic

	if _native_proc != null:
		var res = _native_proc.call("process_chunk", mic_tmp, ref_tmp)
		if typeof(res) == TYPE_DICTIONARY and res.has("clean"):
			var c: PackedFloat32Array = res["clean"]
			if not c.is_empty():
				var old := _clean_native.size()
				_clean_native.resize(old + c.size())
				for i in range(c.size()):
					_clean_native[old + i] = c[i]
				if res.has("voice_frames"):
					_segment_native_vad(c, res["voice_frames"])
			if res.has("rms"):
				_native_last_rms = float(res["rms"])

func _frame_size() -> int:
	return int(_mix_rate / 100) # 10 ms frames

func _segment_native_vad(clean_chunk: PackedFloat32Array, voice_frames: PackedByteArray) -> void:
	# Basic segmenter:
	# - Start after 300ms of consecutive voice.
	# - End after 1500ms of consecutive silence (keep only last 300ms as tail).
	var frame := _frame_size()
	if frame <= 0:
		return
	var speech_confirm := 30
	var silence_confirm := 150
	var pre_roll_keep := 10
	var tail_keep := 30

	var num_frames := voice_frames.size()
	for fi in range(num_frames):
		var start := fi * frame
		if start >= clean_chunk.size():
			break
		var end := mini(start + frame, clean_chunk.size())
		var is_voice := voice_frames[fi] != 0

		# Extract frame samples.
		var frame_samples := PackedFloat32Array()
		frame_samples.resize(end - start)
		for i in range(end - start):
			frame_samples[i] = clean_chunk[start + i]

		# VAD log line (frame_idx voice_flag)
		_vad_native_lines.append("%d\t%d" % [_vad_native_frame_idx, 1 if is_voice else 0])
		_vad_native_frame_idx += 1

		if is_voice:
			_speech_run += 1
			_silence_run = 0
		else:
			_silence_run += 1
			_speech_run = 0

		if not _seg_active:
			# Maintain pre-roll ring buffer.
			_pre_roll_frames.append(frame_samples)
			while _pre_roll_frames.size() > pre_roll_keep:
				_pre_roll_frames.pop_front()

			if is_voice and _speech_run >= speech_confirm:
				_seg_active = true
				_seg_samples = PackedFloat32Array()
				_seg_tail_frames = []
				for fr in _pre_roll_frames:
					_append_samples(_seg_samples, fr)
				_pre_roll_frames = []
				_append_samples(_seg_samples, frame_samples)
			continue

		# Segment active.
		if is_voice:
			# Flush kept tail.
			for fr in _seg_tail_frames:
				_append_samples(_seg_samples, fr)
			_seg_tail_frames = []
			_append_samples(_seg_samples, frame_samples)
		else:
			# Keep last tail_keep frames only.
			_seg_tail_frames.append(frame_samples)
			while _seg_tail_frames.size() > tail_keep:
				_seg_tail_frames.pop_front()

		if _silence_run >= silence_confirm:
			_finalize_segment()

func _append_samples(dst: PackedFloat32Array, src: PackedFloat32Array) -> void:
	if src.is_empty():
		return
	var old := dst.size()
	dst.resize(old + src.size())
	for i in range(src.size()):
		dst[old + i] = src[i]

func _finalize_segment_if_needed() -> void:
	if _seg_active:
		_finalize_segment()

func _finalize_segment() -> void:
	if not _seg_active:
		return

	# Include kept tail for natural endings.
	for fr in _seg_tail_frames:
		_append_samples(_seg_samples, fr)

	_seg_tail_frames = []
	_seg_active = false
	_speech_run = 0
	_silence_run = 0

	if _seg_samples.is_empty():
		return

	var base := _last_capture_dir
	if base == "":
		base = _active_capture_dir
	if base == "":
		return

	var vad_dir := base.path_join("vad_native")
	DirAccess.make_dir_recursive_absolute(vad_dir)
	_seg_index += 1
	var filename := "segment_%03d.wav" % _seg_index
	var out := vad_dir.path_join(filename)
	_write_wav_pcm16_mono(out, _mix_rate, _seg_samples)
	_seg_samples = PackedFloat32Array()

func _write_vad_native_log() -> void:
	var base := _last_capture_dir
	if base == "":
		base = _active_capture_dir
	if base == "":
		return
	var vad_dir := base.path_join("vad_native")
	if not DirAccess.dir_exists_absolute(vad_dir):
		return
	var txt := vad_dir.path_join("vad_result.txt")
	var f := FileAccess.open(txt, FileAccess.WRITE)
	if f == null:
		return
	for line in _vad_native_lines:
		f.store_line(line)
	f.close()


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

	var vad_dir := base.path_join("vad_native")
	if not DirAccess.dir_exists_absolute(vad_dir):
		vad_dir = base.path_join("vad")
	_segments.clear()

	if not DirAccess.dir_exists_absolute(vad_dir):
		if update_status:
			_set_status("Status: exported at %s\n(No vad_native/ or vad/ yet.)" % base)
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
				_set_status("Status: vad folder exists but vad_result.txt missing: %s" % vad_dir)

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

	var vad_dir := base.path_join("vad_native")
	if not DirAccess.dir_exists_absolute(vad_dir):
		vad_dir = base.path_join("vad")
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
	_try_init_native()
	if _native_proc != null:
		print("- Native: EchoGuardProcessor loaded (AEC+VAD backend if built)")
	else:
		print("- Native: not loaded (build Step 7 to enable realtime processing)")
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
