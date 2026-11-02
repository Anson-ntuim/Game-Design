class_name MusicSetup
extends CanvasLayer
## 選歌、離線 BPM 偵測、試聽對拍與每首歌的第一拍校正。

signal closed

var _root: Control
var _status: Label
var _source: Label
var _confidence: Label
var _progress: ProgressBar
var _bpm: SpinBox
var _offset: SpinBox
var _seek: HSlider
var _time_label: Label
var _beat_view: Control
var _apply: Button
var _play: Button
var _tap_bpm: Button
var _metronome: CheckButton
var _preview: AudioStreamPlayer
var _click: AudioStreamPlayer
var _dialog: FileDialog
var _file_callback: Variant
var _picker: Variant
var _playing: bool = false
var _preview_from: float = 0.0
var _preview_usec: int = 0
var _last_click: int = -999
var _tap_times: Array[float] = []
var _flash: float = 0.0
var _updating_seek: bool = false
var _seeking: bool = false
var _finishing: bool = false
var _applied: bool = false


func _ready() -> void:
	layer = 30
	Engine.time_scale = 1.0
	Conductor.stop()
	_preview = AudioStreamPlayer.new()
	_preview.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_preview.volume_db = -5.0
	add_child(_preview)
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/sfx/block.wav")
	_click.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_click.volume_db = -14.0
	add_child(_click)
	_build_ui()
	MusicLibrary.progress.connect(_on_progress)
	MusicLibrary.analyzed.connect(_on_analyzed)
	MusicLibrary.failed.connect(_on_error)
	if OS.has_feature("web"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		bridge.eval(FileAccess.get_file_as_string("res://scripts/web/music_picker.js"), true)
		_picker = bridge.get_interface("JumpMusicPicker")
		_file_callback = bridge.create_callback(_web_file_selected)
	if Conductor.custom_music:
		_status.text = "讀取已保存的歌曲與校正…"
		MusicLibrary.load_active_draft()
	else:
		MusicLibrary.draft_stream = null
		MusicLibrary.draft_bytes = PackedByteArray()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.06, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.11)
	style.border_color = UiKit.FLOAT
	style.set_border_width_all(1)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font = UiKit.font()
	theme.default_font_size = 16
	panel.theme = theme
	margin.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := _label(header, "自訂音樂與節拍校正", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", UiKit.GOLD)
	_button(header, "返回選關", _finish, "CloseMusic")
	var files := HBoxContainer.new()
	body.add_child(files)
	_button(files, "選擇音樂", _choose_file, "ImportMusic")
	_button(files, "恢復內建音樂", _restore_builtin, "BuiltinMusic")
	_source = _label(files, "WAV / MP3 / OGG　最多 32 MB", 15)
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status = _label(body, "選擇歌曲後會自動偵測 BPM；音樂只在你的裝置／瀏覽器內處理。", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 6
	_progress.visible = false
	body.add_child(_progress)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var bpm_row := HBoxContainer.new()
	content.add_child(bpm_row)
	_label(bpm_row, "歌曲 BPM", 16).custom_minimum_size.x = 120
	_bpm = SpinBox.new()
	_bpm.name = "SongBpm"
	_bpm.min_value = 40
	_bpm.max_value = 240
	_bpm.step = 0.1
	_bpm.value = 120
	_bpm.custom_minimum_size.x = 150
	bpm_row.add_child(_bpm)
	_bpm.value_changed.connect(_settings_changed)
	_button(bpm_row, "÷ 2", func() -> void: _bpm.value *= 0.5, "HalfBpm")
	_button(bpm_row, "× 2", func() -> void: _bpm.value *= 2.0, "DoubleBpm")
	_confidence = _label(content, "可手動修正 BPM；一拍聽起來太快或太慢時，試試半速／倍速。", 14)
	_confidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var offset_row := HBoxContainer.new()
	content.add_child(offset_row)
	_label(offset_row, "第 1 拍位置", 16).custom_minimum_size.x = 120
	_offset = SpinBox.new()
	_offset.name = "FirstBeatMs"
	_offset.min_value = 0
	_offset.max_value = 600000
	_offset.step = 5
	_offset.suffix = " ms"
	_offset.custom_minimum_size.x = 150
	offset_row.add_child(_offset)
	_offset.value_changed.connect(_settings_changed)
	_button(offset_row, "−10 ms", func() -> void: _offset.value -= 10)
	_button(offset_row, "+10 ms", func() -> void: _offset.value += 10)
	_button(offset_row, "此刻設為第 1 拍", _set_first_beat, "SetFirstBeat")
	var explanation := _label(content, "BPM 決定拍速；第 1 拍位置決定拍點落在哪裡。裝置延遲沿用選關畫面的 O 校正。", 14)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_beat_view = Control.new()
	_beat_view.custom_minimum_size.y = 100
	_beat_view.clip_contents = true
	_beat_view.draw.connect(_draw_beat)
	content.add_child(_beat_view)
	_seek = HSlider.new()
	_seek.name = "MusicSeek"
	_seek.max_value = 1
	_seek.step = 0.05
	_seek.custom_minimum_size.y = 28
	_seek.drag_started.connect(func() -> void: _seeking = true)
	_seek.drag_ended.connect(func(changed: bool) -> void:
		_seeking = false
		if changed:
			_seek_to(_seek.value))
	_seek.value_changed.connect(func(value: float) -> void:
		if not _updating_seek and not _seeking:
			_seek_to(value))
	content.add_child(_seek)
	_time_label = _label(content, "0:00 / 0:00", 14)
	var transport := HBoxContainer.new()
	content.add_child(transport)
	_play = _button(transport, "試聽", _toggle_preview, "PreviewMusic")
	_play.disabled = true
	_button(transport, "從頭重播", func() -> void: _start_preview(0.0), "RestartPreview")
	_button(transport, "對拍（空白鍵）", _tap, "TapBeat")
	_metronome = CheckButton.new()
	_metronome.text = "播放拍點提示音"
	_metronome.button_pressed = true
	transport.add_child(_metronome)
	_tap_bpm = _button(content, "跟著歌曲鼓點按至少 4 次，可用敲擊速度校正 BPM", _use_tap_bpm, "UseTapBpm")
	_tap_bpm.disabled = true
	var footer := HBoxContainer.new()
	body.add_child(footer)
	var note := _label(footer, "原速音樂 1×；世界速度依歌曲 BPM 調整，變速線再乘倍率。", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(footer, "取消", _finish, "CancelMusic")
	_apply = _button(footer, "套用並返回", _apply_music, "ApplyMusic")
	_apply.disabled = true


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, node_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	if node_name != "":
		button.name = node_name
	button.custom_minimum_size.y = 38
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _choose_file() -> void:
	_pause_preview()
	if OS.has_feature("web"):
		_picker.open(_file_callback)
		return
	if not is_instance_valid(_dialog):
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.filters = PackedStringArray(["*.wav;WAV 音樂", "*.mp3;MP3 音樂", "*.ogg;OGG Vorbis"])
		_dialog.file_selected.connect(func(path: String) -> void: MusicLibrary.import_path(path))
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.75)


func _web_file_selected(args: Array) -> void:
	if _finishing or args.size() < 3:
		return
	if String(args[2]) != "":
		_on_error(String(args[2]))
		return
	if args[1] == null:
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var bytes: PackedByteArray = bridge.js_buffer_to_packed_byte_array(args[1])
	MusicLibrary.import_bytes(bytes, String(args[0]))


func _on_progress(value: float, message: String) -> void:
	_progress.visible = true
	_progress.value = value
	_status.text = message + "　%d%%" % roundi(value * 100)
	_apply.disabled = true
	_report(message)


func _on_analyzed(result: Dictionary) -> void:
	_progress.visible = false
	_preview.stop()
	_playing = false
	_preview.stream = MusicLibrary.draft_stream
	_preview_from = 0.0
	_clear_taps()
	_bpm.value = float(result["bpm"])
	_offset.max_value = maxf(0, _preview.stream.get_length() * 1000 - 100)
	_offset.value = float(result["offset"]) * 1000
	_seek.max_value = _preview.stream.get_length()
	_source.text = MusicLibrary.draft_name
	var confidence := float(result.get("confidence", 0))
	_confidence.text = "自動偵測：%.1f BPM　可信度：%s" % [float(result["bpm"]), "高" if confidence > 0.6 else ("中" if confidence > 0.3 else "低，請試聽並校正")]
	_status.text = String(result.get("notice", "按試聽，再跟著歌曲鼓點按空白鍵；聽提示音有沒有對準。"))
	_apply.disabled = false
	_play.text = "試聽"
	_play.disabled = false
	_report("音樂分析完成：%s，%.1f BPM，第 1 拍 %.0f ms" % [MusicLibrary.draft_name, _bpm.value, _offset.value])


func _on_error(message: String) -> void:
	_progress.visible = false
	_status.text = message
	_apply.disabled = MusicLibrary.draft_stream == null or MusicLibrary.busy
	_report(message)


func _report(message: String) -> void:
	if _picker:
		_picker.report(message)


func _settings_changed(_value: float) -> void:
	_last_click = floori((_preview_time(false) - _offset.value / 1000) / (60.0 / _bpm.value)) if _playing else -999


func _start_preview(position: float) -> void:
	if MusicLibrary.busy or _preview.stream == null:
		return
	_preview_from = clampf(position, 0.0, _preview.stream.get_length() - 0.01)
	_preview_usec = Time.get_ticks_usec()
	_preview.pitch_scale = 1.0
	_preview.play(_preview_from)
	_playing = true
	_play.text = "暫停"
	_last_click = -999
	_clear_taps()


func _pause_preview() -> void:
	if _playing:
		_preview_from = _preview_time(false)
	_preview.stop()
	_playing = false
	_play.text = "試聽"


func _toggle_preview() -> void:
	if _playing:
		_pause_preview()
	else:
		_start_preview(0.0 if _preview_from >= _seek.max_value - 0.1 else _preview_from)


func _seek_to(position: float) -> void:
	if _playing:
		_start_preview(position)
	else:
		_preview_from = position
	_clear_taps()


func _preview_time(audible: bool = true) -> float:
	var time := _preview_from
	if _playing:
		time += float(Time.get_ticks_usec() - _preview_usec) / 1000000.0
	if audible and _playing:
		time -= AudioServer.get_output_latency() + GameState.audio_offset_ms / 1000.0
	return clampf(time, 0.0, _seek.max_value)


func _set_first_beat() -> void:
	if _preview.stream:
		_offset.value = _preview_time() * 1000
		_status.text = "已將目前聽到的位置設為第 1 拍，可用 ±10 ms 微調。"


func _tap() -> void:
	if not _playing:
		_status.text = "請先按試聽，再跟著歌曲鼓點對拍。"
		return
	var time := _preview_time()
	if not _tap_times.is_empty() and (time <= _tap_times[-1] or time - _tap_times[-1] > 2.0):
		_clear_taps()
	_tap_times.append(time)
	if _tap_times.size() > 16:
		_tap_times.pop_front()
	var period := 60.0 / _bpm.value
	var offset := _offset.value / 1000
	var error := time - offset - roundf((time - offset) / period) * period
	_offset.value = maxf(0.0, offset + error * 0.35) * 1000
	_flash = 1.0
	_status.text = "已對拍 %d 次　%s %.0f ms" % [_tap_times.size(), "晚" if error > 0 else "早", absf(error) * 1000]
	_report(_status.text)
	var tapped := _tapped_bpm()
	_tap_bpm.disabled = tapped <= 0
	if tapped > 0:
		_tap_bpm.text = "敲擊推估 %.1f BPM（按此套用）" % tapped


func _clear_taps() -> void:
	_tap_times.clear()
	_tap_bpm.disabled = true
	_tap_bpm.text = "跟著歌曲鼓點按至少 4 次，可用敲擊速度校正 BPM"


func _tapped_bpm() -> float:
	if _tap_times.size() < 4:
		return 0.0
	var intervals: Array[float] = []
	for i in range(1, _tap_times.size()):
		var gap := _tap_times[i] - _tap_times[i - 1]
		if gap >= 0.24 and gap <= 1.6:
			intervals.append(gap)
	if intervals.size() < 3:
		return 0.0
	intervals.sort()
	return clampf(60.0 / intervals[intervals.size() / 2], 40.0, 240.0)


func _use_tap_bpm() -> void:
	var value := _tapped_bpm()
	if value > 0:
		_bpm.value = snappedf(value, 0.1)
		_status.text = "已套用敲擊 BPM，再對幾拍確認第一拍位置。"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_finish()
	elif event.is_action_pressed("jump") and not get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()
		_tap()


func _process(_delta: float) -> void:
	_flash = move_toward(_flash, 0.0, 0.06)
	var time := _preview_time()
	if _playing and time >= _seek.max_value - 0.02:
		_pause_preview()
	if not _seeking:
		_updating_seek = true
		_seek.value = time
		_updating_seek = false
	_time_label.text = "%d:%02d / %d:%02d" % [int(time) / 60, int(time) % 60, int(_seek.max_value) / 60, int(_seek.max_value) % 60]
	if _playing:
		var beat := floori((_preview_time(false) - _offset.value / 1000) / (60.0 / _bpm.value))
		if beat != _last_click:
			_last_click = beat
			if beat >= 0 and _metronome.button_pressed:
				_click.pitch_scale = 1.5 if posmod(beat, 4) == 0 else 1.0
				_click.play()
	_beat_view.queue_redraw()


func _draw_beat() -> void:
	var beat := (_preview_time() - _offset.value / 1000) / (60.0 / _bpm.value)
	var phase := fposmod(beat, 1.0)
	var pulse := exp(-phase * 8)
	var center := Vector2(48, 48)
	_beat_view.draw_circle(center, 20 + pulse * 8, UiKit.FLOAT.lerp(UiKit.GOLD, _flash))
	_beat_view.draw_arc(center, lerpf(44.0, 20.0, phase), 0, TAU, 48, UiKit.GOLD, 2, true)
	UiKit.text(_beat_view, Vector2(110, 32), _beat_view.size.x - 120,
		"等待第 1 拍" if beat < 0 else "第 %d 拍　%.1f BPM" % [floori(beat) + 1, _bpm.value], 20, Color.WHITE)
	UiKit.text(_beat_view, Vector2(110, 63), _beat_view.size.x - 120,
		"世界基準 %.2f×　歌曲原速 1×　空白鍵跟著歌曲鼓點對拍" % (_bpm.value / 120.0), 14, UiKit.FLOAT)


func _apply_music() -> void:
	if MusicLibrary.apply_draft(_bpm.value, _offset.value / 1000):
		_report("自訂音樂已套用：%.1f BPM，第 1 拍 %.0f ms" % [_bpm.value, _offset.value])
		_applied = true
		_finish()


func _restore_builtin() -> void:
	MusicLibrary.restore_builtin()
	_report("已恢復內建音樂")
	_applied = true
	_finish()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_pause_preview()
	MusicLibrary.cancel_analysis()
	if not _applied:
		MusicLibrary.draft_stream = null
		MusicLibrary.draft_bytes = PackedByteArray()
	Conductor.start(false)
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	MusicLibrary.cancel_analysis()
	if _picker:
		_picker.cancel()
