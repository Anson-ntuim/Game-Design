extends SceneTree
## Godot --headless --path . --fixed-fps 120 --script res://tools/check_custom_music.gd

var failures := 0
var checks := 0
var _saved: Dictionary = {}


func _initialize() -> void:
	for name in ["custom_music.audio", "custom_music.cfg", "save.cfg"]:
		var path: String = "user://" + name
		_saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	if await _tests() != true:
		check(false, "Music tests aborted")
	var conductor := root.get_node("Conductor")
	conductor.stop()
	for audio: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	for path: String in _saved:
		if _saved[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(_saved[path])
			file.close()
	Engine.time_scale = 1
	await process_frame
	OS.delay_msec(100)
	print("Custom music: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _tests() -> bool:
	var library := root.get_node("MusicLibrary")
	var conductor := root.get_node("Conductor")
	conductor.stop()
	conductor.set_process(false)
	var analyzer = load("res://scripts/audio/bpm_analyzer.gd")
	for value in [65.0, 90.0, 120.0, 150.0, 173.5, 200.0]:
		var name := "beat_%s.wav" % (str(int(value)) if value == int(value) else str(value))
		var stream: AudioStream = library.decode(FileAccess.get_file_as_bytes("res://build/music_tests/" + name), name)
		check(stream != null, "WAV failed to load: " + name)
		if stream == null:
			continue
		var result: Dictionary = await analyzer.analyze(stream, self, func(_v: float, _m: String) -> void: pass, func() -> bool: return false)
		print(name, " → ", result.get("bpm"), " offset=", result.get("offset"), " confidence=", result.get("confidence"))
		check(not result.has("error"), "Analysis failed: " + name)
		check(absf(float(result.get("bpm", 0)) - value) < 1.5, "Wrong BPM: " + name)
		var offset_error := absf(fposmod(float(result.get("offset", 0)) - 0.23 + 30.0 / value, 60.0 / value) - 30.0 / value)
		check(offset_error < 0.04, "Wrong beat phase: " + name)
	for extension in ["mp3", "ogg"]:
		var name: String = "beat_150." + extension
		var stream: AudioStream = library.decode(FileAccess.get_file_as_bytes("res://build/music_tests/" + name), name)
		check(stream != null, "Cannot decode " + extension)
		if stream:
			var result: Dictionary = await analyzer.analyze(stream, self, func(_v: float, _m: String) -> void: pass, func() -> bool: return false)
			check(absf(float(result.get("bpm", 0)) - 150) < 1.5, "Compressed audio BPM mismatch: " + extension)
	var intro: AudioStream = library.decode(FileAccess.get_file_as_bytes("res://build/music_tests/intro_120.wav"), "intro_120.wav")
	var intro_result: Dictionary = await analyzer.analyze(intro, self, func(_v: float, _m: String) -> void: pass, func() -> bool: return false)
	check(absf(float(intro_result.get("offset", 0)) - 2.23) < 0.04, "Intro must be included in first-beat offset")
	check(library.decode("invalid".to_utf8_buffer(), "bad.mp3") == null, "Malformed audio accepted")
	var silent := PackedFloat32Array()
	silent.resize(1000)
	check(analyzer.detect(silent).has("error"), "Silence should not invent a tempo")
	# 匯入分析會跨影格；取消後不得由舊工作發出完成訊號。
	var completions := [0]
	var on_done := func(_result: Dictionary) -> void: completions[0] += 1
	library.analyzed.connect(on_done)
	library.import_path("res://build/music_tests/beat_150.wav")
	check(library.busy, "Analysis should yield so cancellation remains available")
	library.cancel_analysis()
	for frame in 4:
		await process_frame
	check(not library.busy and completions[0] == 0, "Cancelled analysis published stale result")
	library.analyzed.disconnect(on_done)
	await library.import_path("res://build/music_tests/silence.wav")
	check(library.draft_result.get("confidence", 1) == 0 and library.draft_result.has("notice"), "Silent song should offer manual calibration without invented confidence")
	await library.import_path("res://build/music_tests/beat_150.wav")
	check(not library.busy and library.draft_stream != null, "Import did not finish")
	check(library.apply_draft(150, 0.23), "Could not apply music")
	check(conductor.custom_music and conductor.bpm == 150, "Custom music not configured")
	conductor.user_offset = 0
	conductor.start(true)
	check(is_equal_approx(conductor.rate, 1) and is_equal_approx(conductor.world_rate, 1.25), "Uploaded BPM must affect world only at original speed")
	check(is_equal_approx(conductor._player.pitch_scale, 1) and is_equal_approx(Engine.time_scale, 1.25), "Song was double-scaled")
	conductor.set_rate(1.2)
	check(absf(conductor.current_bpm - 180) < 0.01 and is_equal_approx(Engine.time_scale, 1.5), "1.2× line must produce 180 BPM / 1.5× world")
	conductor.set_rate(0.8)
	check(absf(conductor.current_bpm - 120) < 0.01 and is_equal_approx(Engine.time_scale, 1.0), "0.8× line must produce 120 BPM / 1× world")
	var before: float = conductor.song_position
	conductor.set_rate(1.0)
	check(absf(conductor.song_position - before) < 0.01, "Rate switch jumped song clock")
	check(absf(fposmod((conductor._custom_loop_end - conductor.first_beat_offset) / conductor.sec_per_beat, 8)) < 0.001, "Loop end must align to musical phrase")
	root.get_node("GameState").level_index = 4
	var level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	level.set_world_tempo(90, false)
	check(absf(conductor.current_bpm - 112.5) < 0.01 and is_equal_approx(conductor.world_rate, 0.9375), "Custom song + slow line mismatch")
	level.set_world_tempo(150, false)
	check(absf(conductor.current_bpm - 187.5) < 0.01 and is_equal_approx(conductor._player.pitch_scale, 1.25), "Custom song + fast line mismatch")
	level.queue_free()
	await process_frame
	conductor.start(false)
	check(is_equal_approx(Engine.time_scale, 1), "Menu must stay at normal UI speed")
	var panel = load("res://scripts/ui/music_setup.gd").new()
	root.add_child(panel)
	await process_frame
	# 等既有歌曲分析完成再操作草稿，避免背景讀取覆寫手動校正。
	for frame in 1000:
		if not library.busy:
			break
		await process_frame
	var taps: Array[float] = [0.23, 0.63, 1.03, 1.43, 1.83]
	panel._tap_times = taps
	check(absf(panel._tapped_bpm() - 150) < 0.1, "Tap tempo estimate incorrect")
	panel._bpm.value = 75
	panel._use_tap_bpm()
	check(panel._bpm.value == 150, "Tap BPM button did not apply")
	panel._offset.value = 315
	panel._apply_music()
	await process_frame
	check(absf(conductor.first_beat_offset - 0.315) < 0.001, "Per-track calibration was not applied")
	await library.import_path("res://build/music_tests/beat_150.wav")
	check(absf(float(library.draft_result["offset"]) - 0.315) < 0.001, "Saved song calibration was not restored")
	library.restore_builtin()
	conductor.start(true)
	check(not conductor.custom_music and conductor.bpm == 120 and is_equal_approx(Engine.time_scale, 1), "Builtin restore failed")
	var menu = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	check(menu.has_node("CanvasLayer/Control/MusicSettings") or menu._music_button != null, "Music entry missing from selection menu")
	menu.queue_free()
	await process_frame
	await process_frame
	return true
