class_name MusicSetup
extends CanvasLayer
## 精簡自訂音樂：選歌 → 聽 → 不準就打拍子 → 看結果 → 套用。

signal closed

var _root: Control
var _status: Label
var _result: Label
var _progress: ProgressBar
var _play: Button
var _apply: Button
var _bpm_label: Label
var _bpm_buttons: Array[Button] = []
var _offset_buttons: Array[Button] = []
var _preview: AudioStreamPlayer
var _click: AudioStreamPlayer
var _dialog: FileDialog
var _file_callback: Variant
var _picker: Variant
## Web：JumpMusicPicker 已注入（不依賴 get_interface 一定成功）
var _web_picker_ok: bool = false
var _playing: bool = false
var _preview_from: float = 0.0
var _preview_usec: int = 0
var _bpm: float = 120.0
var _offset_sec: float = 0.0
var _tap_times: Array[float] = []
var _flash: float = 0.0
var _finishing: bool = false
var _applied: bool = false
var _beat_view: Control
var _last_click: int = -999
const BPM_MIN := 40.0
const BPM_MAX := 240.0


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
	## 延後掛選檔，避免 Web bridge／內嵌腳本例外把整頁卡死
	if OS.has_feature("web"):
		call_deferred("_setup_web_picker")
	if Conductor.custom_music:
		_status.text = "讀取已保存的歌曲…"
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
		margin.add_theme_constant_override("margin_" + side, 36)
	_root.add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.11)
	style.border_color = UiKit.FLOAT
	style.set_border_width_all(1)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font = UiKit.font()
	theme.default_font_size = 17
	panel.theme = theme
	margin.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)

	var title := _label(body, "自訂音樂", 28)
	title.add_theme_color_override("font_color", UiKit.GOLD)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	_button(row, "選擇音樂", _choose_file, "ImportMusic")
	_button(row, "恢復內建", _restore_builtin, "BuiltinMusic")
	_button(row, "返回", _finish, "CloseMusic")

	_status = _label(body, "選一首歌，聽看看拍點準不準。不準就跟著鼓點按空白鍵。", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 8
	_progress.visible = false
	body.add_child(_progress)

	_beat_view = Control.new()
	_beat_view.custom_minimum_size = Vector2(0, 110)
	_beat_view.draw.connect(_draw_beat)
	body.add_child(_beat_view)

	_result = _label(body, "尚未分析", 20)
	_result.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var bpm_row := HBoxContainer.new()
	bpm_row.add_theme_constant_override("separation", 8)
	body.add_child(bpm_row)
	_bpm_label = _label(bpm_row, "BPM 120.0", 18)
	_bpm_label.custom_minimum_size.x = 120
	_bpm_buttons.append(_button(bpm_row, "÷2", func() -> void: _nudge_bpm_factor(0.5), "BpmHalf"))
	_bpm_buttons.append(_button(bpm_row, "×2", func() -> void: _nudge_bpm_factor(2.0), "BpmDouble"))
	_bpm_buttons.append(_button(bpm_row, "−1", func() -> void: _nudge_bpm(-1.0), "BpmMinus1"))
	_bpm_buttons.append(_button(bpm_row, "+1", func() -> void: _nudge_bpm(1.0), "BpmPlus1"))
	_bpm_buttons.append(_button(bpm_row, "−0.1", func() -> void: _nudge_bpm(-0.1), "BpmMinusFine"))
	_bpm_buttons.append(_button(bpm_row, "+0.1", func() -> void: _nudge_bpm(0.1), "BpmPlusFine"))

	var offset_row := HBoxContainer.new()
	offset_row.add_theme_constant_override("separation", 8)
	body.add_child(offset_row)
	var offset_title := _label(offset_row, "第 1 拍", 16)
	offset_title.custom_minimum_size.x = 72
	_offset_buttons.append(_button(offset_row, "−10 ms", func() -> void: _nudge_offset_ms(-10.0), "OffsetMinus10"))
	_offset_buttons.append(_button(offset_row, "+10 ms", func() -> void: _nudge_offset_ms(10.0), "OffsetPlus10"))
	_offset_buttons.append(_button(offset_row, "−1 ms", func() -> void: _nudge_offset_ms(-1.0), "OffsetMinus1"))
	_offset_buttons.append(_button(offset_row, "+1 ms", func() -> void: _nudge_offset_ms(1.0), "OffsetPlus1"))
	_set_tune_enabled(false)

	var tip_text := "空白鍵對拍　÷2／×2 調 BPM　←→ 微調 BPM　Enter 套用　Esc 返回"
	if OS.has_feature("web"):
		tip_text = "選檔層可拖放。空白鍵對拍　÷2／×2／± 調 BPM　Enter 套用　Esc 返回"
	var tip := _label(body, tip_text, 14)
	tip.add_theme_color_override("font_color", UiKit.FLOAT)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_play = _button(actions, "試聽", _toggle_preview, "PreviewMusic")
	_play.disabled = true
	_apply = _button(actions, "套用這首歌", _apply_music, "ApplyMusic")
	_apply.disabled = true
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL


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
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _setup_web_picker() -> void:
	## 優先用 index.html 已注入的 JumpMusicPicker；否則再 eval 內嵌腳本
	_web_picker_ok = false
	_picker = null
	if not OS.has_feature("web") or not is_inside_tree():
		return
	var bridge: Variant = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		_status.text = "此瀏覽器沒有選檔橋接，請用桌面版或換瀏覽器"
		return
	_file_callback = bridge.create_callback(_web_file_selected)
	var ready := bool(bridge.eval("typeof JumpMusicPicker !== 'undefined'", true))
	if not ready:
		var code := FileAccess.get_file_as_string("res://scripts/web/music_picker.js")
		if code.is_empty():
			code = MusicPickerEmbed.SOURCE
		if not code.strip_edges().is_empty():
			bridge.eval(code, true)
		ready = bool(bridge.eval("typeof JumpMusicPicker !== 'undefined'", true))
	_web_picker_ok = ready
	_picker = bridge.get_interface("JumpMusicPicker")
	if not _web_picker_ok:
		_status.text = "選檔元件未就緒：請確認上傳最新 Web 包，或改用新分頁／桌面版"


func _open_web_picker() -> bool:
	if not _web_picker_ok:
		_setup_web_picker()
	if not _web_picker_ok:
		return false
	var bridge: Variant = Engine.get_singleton("JavaScriptBridge")
	_file_callback = bridge.create_callback(_web_file_selected)
	var win: Variant = bridge.get_interface("window")
	if win != null:
		win._JumpMusicGodotCb = _file_callback
		bridge.eval("JumpMusicPicker.open(window._JumpMusicGodotCb)", true)
		return true
	if _picker != null:
		_picker.open(_file_callback)
		return true
	return false


func _choose_file() -> void:
	_pause_preview()
	if OS.has_feature("web"):
		## itch iframe 裡不能只靠程式 click；picker 會開 HTML 遮罩讓玩家直接點／拖放
		if not _open_web_picker():
			_on_error("網頁選檔元件未載入。請重新匯出 Web（需含 music_picker.js），或改用桌面版／新分頁開啟")
			return
		_status.text = "請在跳出的選檔層選擇或拖入音樂…"
		return
	if not is_instance_valid(_dialog):
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.filters = PackedStringArray(["*.wav;WAV", "*.mp3;MP3", "*.ogg;OGG"])
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
	_status.text = "%s　%d%%" % [message, roundi(value * 100)]
	_apply.disabled = true
	_set_tune_enabled(false)


func _on_analyzed(result: Dictionary) -> void:
	_progress.visible = false
	_preview.stop()
	_playing = false
	_preview.stream = MusicLibrary.draft_stream
	_preview_from = 0.0
	_tap_times.clear()
	_bpm = clampf(float(result.get("bpm", 120.0)), BPM_MIN, BPM_MAX)
	_offset_sec = maxf(0.0, float(result.get("offset", 0.0)))
	_play.disabled = false
	_play.text = "試聽"
	_apply.disabled = false
	_set_tune_enabled(true)
	_show_result("自動偵測完成")
	_status.text = "試聽後可 ÷2／×2 或 ± 微調 BPM；拍點不準再空白鍵校正，或調第 1 拍。"
	_start_preview(0.0)


func _on_error(message: String) -> void:
	_progress.visible = false
	_status.text = message
	_apply.disabled = MusicLibrary.draft_stream == null or MusicLibrary.busy
	_set_tune_enabled(MusicLibrary.draft_stream != null and not MusicLibrary.busy)


func _set_tune_enabled(on: bool) -> void:
	for b in _bpm_buttons:
		b.disabled = not on
	for b in _offset_buttons:
		b.disabled = not on
	_refresh_bpm_label()


func _refresh_bpm_label() -> void:
	if is_instance_valid(_bpm_label):
		_bpm_label.text = "BPM %.1f" % _bpm


func _nudge_bpm(delta: float) -> void:
	if MusicLibrary.draft_stream == null:
		return
	_set_bpm(_bpm + delta, "手動微調 BPM")


func _nudge_bpm_factor(factor: float) -> void:
	if MusicLibrary.draft_stream == null:
		return
	var next := _bpm * factor
	if next < BPM_MIN or next > BPM_MAX:
		_status.text = "BPM 只能在 %.0f～%.0f 之間" % [BPM_MIN, BPM_MAX]
		return
	var prefix := "BPM ×2" if is_equal_approx(factor, 2.0) else ("BPM ÷2" if is_equal_approx(factor, 0.5) else "BPM 調整")
	_set_bpm(next, prefix)


func _set_bpm(value: float, prefix: String) -> void:
	_bpm = clampf(snappedf(value, 0.1), BPM_MIN, BPM_MAX)
	_tap_times.clear()
	_show_result(prefix)
	_status.text = "目前 %.1f BPM。聽起來是半拍／雙拍就用 ÷2／×2。" % _bpm
	_refresh_bpm_label()
	GameState.play_sfx("pluck", GameState.next_note(), -10.0)


func _nudge_offset_ms(delta_ms: float) -> void:
	if MusicLibrary.draft_stream == null:
		return
	var length := _preview.stream.get_length() if _preview.stream else 0.0
	_offset_sec = clampf(_offset_sec + delta_ms / 1000.0, 0.0, maxf(0.0, length - 0.1))
	_show_result("第 1 拍微調")
	_status.text = "第 1 拍 %.0f ms。跟著提示音聽是否對上鼓點。" % (_offset_sec * 1000.0)
	GameState.play_sfx("pluck", GameState.next_note() - 3.0, -10.0)


func _show_result(prefix: String) -> void:
	var name := MusicLibrary.draft_name if MusicLibrary.draft_name != "" else "未命名"
	name = UiKit.safe_text(name)
	var sections: Array = MusicLibrary.draft_result.get("sections", [])
	var feel := ""
	if not sections.is_empty():
		var feels: PackedStringArray = []
		for s in sections:
			var f := String((s as Dictionary).get("feel", ""))
			if f != "" and feels.find(f) < 0:
				feels.append(f)
		if not feels.is_empty():
			feel = "\n節奏變化：" + "、".join(feels)
	_result.text = "%s\n%s\nBPM %.1f　第 1 拍 %.0f ms%s" % [prefix, name, _bpm, _offset_sec * 1000.0, feel]
	_refresh_bpm_label()


func _start_preview(position: float) -> void:
	if MusicLibrary.busy or _preview.stream == null:
		return
	_preview_from = clampf(position, 0.0, maxf(0.0, _preview.stream.get_length() - 0.01))
	_preview_usec = Time.get_ticks_usec()
	_preview.pitch_scale = 1.0
	_preview.play(_preview_from)
	_playing = true
	_play.text = "暫停"
	_last_click = -999


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
		_start_preview(_preview_from)


func _preview_time(audible: bool = true) -> float:
	var time := _preview_from
	if _playing:
		time += float(Time.get_ticks_usec() - _preview_usec) / 1000000.0
	if audible and _playing:
		time -= AudioServer.get_output_latency() + GameState.audio_offset_ms / 1000.0
	var length := _preview.stream.get_length() if _preview.stream else 0.0
	return clampf(time, 0.0, maxf(0.0, length))


func _tap() -> void:
	if not _playing:
		_status.text = "請先按試聽，再跟著鼓點打拍。"
		return
	var time := _preview_time()
	if not _tap_times.is_empty() and (time <= _tap_times[-1] or time - _tap_times[-1] > 2.0):
		_tap_times.clear()
	_tap_times.append(time)
	if _tap_times.size() > 16:
		_tap_times.pop_front()
	var period := 60.0 / maxf(_bpm, 1.0)
	var error := time - _offset_sec - roundf((time - _offset_sec) / period) * period
	_offset_sec = maxf(0.0, _offset_sec + error * 0.4)
	_flash = 1.0
	## 敲夠次數時用間隔估 BPM
	var tapped := _tapped_bpm()
	if tapped > 0.0:
		_bpm = tapped
		_refresh_bpm_label()
	_status.text = "已打 %d 拍　相對提示音 %s %.0f ms" % [
		_tap_times.size(), "晚" if error > 0.0 else "早", absf(error) * 1000.0]
	_show_result("校正結果")


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
	return clampf(60.0 / intervals[intervals.size() / 2], BPM_MIN, BPM_MAX)


func _apply_music() -> void:
	if MusicLibrary.apply_draft(_bpm, _offset_sec):
		_show_result("已套用")
		_status.text = "這首歌會用在關卡裡；過關後音樂會接著播，不會重頭。"
		_applied = true
		_finish()
	else:
		_apply.disabled = MusicLibrary.draft_stream == null or MusicLibrary.busy


func _restore_builtin() -> void:
	MusicLibrary.restore_builtin()
	_status.text = "已恢復內建音樂"
	_result.text = "內建音樂　120 BPM"
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
	Conductor.start(false, true)
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	MusicLibrary.cancel_analysis()
	if OS.has_feature("web"):
		var bridge: Variant = Engine.get_singleton("JavaScriptBridge")
		if bridge != null:
			bridge.eval(
				"try{if(window.JumpMusicPicker&&JumpMusicPicker.cancel)JumpMusicPicker.cancel();}catch(e){}",
				true)
	_picker = null
	_web_picker_ok = false


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_finish()
	elif event.is_action_pressed("confirm") and not _apply.disabled:
		get_viewport().set_input_as_handled()
		_apply_music()
	elif event.is_action_pressed("jump") and not get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()
		_tap()
	elif MusicLibrary.draft_stream != null:
		if event.is_action_pressed("move_left") or event.is_action_pressed("easier"):
			get_viewport().set_input_as_handled()
			_nudge_bpm(-1.0)
		elif event.is_action_pressed("move_right") or event.is_action_pressed("harder"):
			get_viewport().set_input_as_handled()
			_nudge_bpm(1.0)
		elif event.is_action_pressed("up"):
			get_viewport().set_input_as_handled()
			_nudge_bpm_factor(2.0)
		elif event.is_action_pressed("down"):
			get_viewport().set_input_as_handled()
			_nudge_bpm_factor(0.5)


func _process(_delta: float) -> void:
	_flash = move_toward(_flash, 0.0, 0.06)
	if _playing and _preview.stream and _preview_time(false) >= _preview.stream.get_length() - 0.05:
		_pause_preview()
	if _playing:
		var beat := floori((_preview_time(false) - _offset_sec) / (60.0 / maxf(_bpm, 1.0)))
		if beat != _last_click and beat >= 0:
			_last_click = beat
			_click.pitch_scale = 1.5 if posmod(beat, 4) == 0 else 1.0
			_click.play()
	_beat_view.queue_redraw()


func _draw_beat() -> void:
	var beat := (_preview_time() - _offset_sec) / (60.0 / maxf(_bpm, 1.0))
	var phase := fposmod(beat, 1.0)
	var pulse := exp(-phase * 8.0) if _playing else 0.0
	var center := Vector2(56, 55)
	_beat_view.draw_circle(center, 22 + pulse * 10 + _flash * 6, UiKit.FLOAT.lerp(UiKit.GOLD, _flash))
	_beat_view.draw_arc(center, lerpf(48.0, 22.0, phase), 0, TAU, 48, UiKit.GOLD, 2.5, true)
	var msg := "等待歌曲…" if MusicLibrary.draft_stream == null \
		else ("等待第 1 拍" if beat < 0 else "第 %d 拍" % (floori(beat) + 1))
	UiKit.text(_beat_view, Vector2(120, 36), _beat_view.size.x - 140, msg, 22, Color.WHITE)
	UiKit.text(_beat_view, Vector2(120, 68), _beat_view.size.x - 140,
		"%.1f BPM　跟著鼓點按空白鍵校正" % _bpm, 15, UiKit.FLOAT)
