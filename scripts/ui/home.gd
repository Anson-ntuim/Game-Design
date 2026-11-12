extends Node2D
## 整合主選單：關卡選擇／難度／畫面／自訂音樂／其他設定，一個介面搞定。

const MAIN_SCENE := "res://scenes/main.tscn"
const CHART_SCENE := "res://scenes/chart_studio.tscn"
const CARD_SIZE := Vector2(280, 200)
const CARD_GAP := 36.0

enum Tab { LEVELS, DIFFICULTY, DISPLAY, MUSIC, OTHER }

const TAB_LABELS: PackedStringArray = ["關卡選擇", "難度設定", "畫面設定", "自訂音樂", "其他設定"]

var _tab: Tab = Tab.LEVELS
var _selected: int = 0
var _section: int = 0
var _display_row: int = 0
var _music_row: int = 0
var _other_row: int = 0
var _view: Control
## 選關卡卡片裁切層：避免左右滑出面板框
var _levels_clip: Control
var _camera: Camera2D
var _slide: float = 0.0
var _levels_panel: Rect2 = Rect2()
var _levels_pulse: float = 0.0
var _levels_edge: Color = Color.WHITE
var _fade: float = 1.0
var _fade_out: float = 0.0
var _bump: float = 0.0
var _diff_bump: float = 0.0
var _quality_bump: float = 0.0
var _theme_bump: float = 0.0
var _skin_bump: float = 0.0
var _blink: float = 0.0
var _input_lock: float = 0.35
var _starting: bool = false
var _guide: MechanicGuide
var _calibrator: LatencyCalibrator
var _music_setup: MusicSetup


func _ready() -> void:
	Engine.time_scale = 1.0
	_selected = clampi(GameState.level_index, 0, maxi(0, LevelData.LEVELS.size() - 1))
	GameState.level_index = _selected
	_section = clampi(GameState.start_section, 0, maxi(0, LevelData.section_titles(_selected).size() - 1))
	_slide = float(_selected)

	add_child(Background.new())
	_camera = Camera2D.new()
	_camera.position = get_viewport_rect().size * 0.5
	add_child(_camera)
	_camera.make_current()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_view)
	_view.draw.connect(_on_view_draw)
	_view.gui_input.connect(_on_gui_input)
	_levels_clip = Control.new()
	_levels_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_levels_clip.clip_contents = true
	_view.add_child(_levels_clip)
	_levels_clip.draw.connect(_on_levels_clip_draw)

	UiKit.clear_minimaps()
	for i in LevelData.LEVELS.size():
		UiKit.minimap(i)

	GameState.reset_stats()
	Conductor.start(false, not (Conductor.custom_music and Conductor.is_music_playing()))
	var tw := create_tween()
	tw.tween_property(self, "_fade", 0.0, 0.7).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_camera.position.x += 28.0 * delta
	_blink += delta
	_input_lock = maxf(0.0, _input_lock - delta)
	_bump = move_toward(_bump, 0.0, delta * 4.0)
	_diff_bump = move_toward(_diff_bump, 0.0, delta * 4.0)
	_quality_bump = move_toward(_quality_bump, 0.0, delta * 4.0)
	_theme_bump = move_toward(_theme_bump, 0.0, delta * 4.0)
	_skin_bump = move_toward(_skin_bump, 0.0, delta * 4.0)
	_slide = lerpf(_slide, float(_selected), 1.0 - exp(-12.0 * delta))
	_view.queue_redraw()
	if is_instance_valid(_levels_clip):
		_levels_clip.queue_redraw()

	if _fade_out > 0.0:
		_fade_out = minf(1.0, _fade_out + delta * 2.4)
		if _fade_out >= 1.0 and _starting:
			get_tree().change_scene_to_file(MAIN_SCENE)
		return

	if _starting or _fade > 0.05 or _input_lock > 0.0:
		return
	if is_instance_valid(_guide) or is_instance_valid(_calibrator) or is_instance_valid(_music_setup):
		return
	_handle_input()


func _overlay_open() -> bool:
	return is_instance_valid(_guide) or is_instance_valid(_calibrator) or is_instance_valid(_music_setup)


func _handle_input() -> void:
	## Tab／[ ] 切分頁
	var tab_step := 0
	if Input.is_action_just_pressed("quality_down") or Input.is_action_just_pressed("ui_focus_prev"):
		tab_step = -1
	elif Input.is_action_just_pressed("quality_up") or Input.is_action_just_pressed("ui_focus_next"):
		tab_step = 1
	if tab_step != 0:
		_set_tab(posmod(int(_tab) + tab_step, TAB_LABELS.size()))
		return

	if Input.is_action_just_pressed("music_setup"):
		if _tab != Tab.MUSIC:
			_set_tab(Tab.MUSIC)
		_open_music_setup()
		return
	if Input.is_action_just_pressed("guide"):
		_open_guide()
		return
	if Input.is_action_just_pressed("calibrate"):
		_open_calibrator()
		return

	match _tab:
		Tab.LEVELS:
			_handle_levels()
		Tab.DIFFICULTY:
			_handle_difficulty()
		Tab.DISPLAY:
			_handle_display()
		Tab.MUSIC:
			_handle_music()
		Tab.OTHER:
			_handle_other()


func _set_tab(index: int) -> void:
	_tab = index as Tab
	_display_row = 0
	_music_row = 0
	_other_row = 0
	GameState.play_sfx("pluck", 4.0, -10.0)


func _handle_levels() -> void:
	var step := 0
	if Input.is_action_just_pressed("move_left"):
		step = -1
	elif Input.is_action_just_pressed("move_right"):
		step = 1
	if step != 0:
		var next := clampi(_selected + step, 0, LevelData.LEVELS.size() - 1)
		if next != _selected:
			_selected = next
			_section = 0
			_bump = 1.0
			GameState.play_sfx("pluck", GameState.next_note(), -6.0)
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_start_level(_selected)


func _handle_difficulty() -> void:
	var step := 0
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
		step = -1
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder") \
			or Input.is_action_just_pressed("confirm"):
		step = 1
	if step != 0:
		var d := clampi(GameState.difficulty + step, 0, GameState.DIFFICULTIES.size() - 1)
		if d != GameState.difficulty:
			GameState.set_difficulty(d)
			_diff_bump = 1.0
			GameState.play_sfx("pluck", 7.0, -8.0)


func _handle_display() -> void:
	var rows := _display_row_count()
	if Input.is_action_just_pressed("up"):
		_display_row = posmod(_display_row - 1, rows)
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("down"):
		_display_row = posmod(_display_row + 1, rows)
		GameState.play_sfx("pluck", 3.0, -10.0)
	var step := 0
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
		step = -1
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder") \
			or Input.is_action_just_pressed("confirm"):
		step = 1
	if step == 0:
		return
	match _display_row:
		0:
			var q := clampi(GameState.quality + step, 0, GameState.QUALITIES.size() - 1)
			if q != GameState.quality:
				GameState.set_quality(q)
				_quality_bump = 1.0
				GameState.play_sfx("pluck", 5.0, -8.0)
		1:
			if GameState.SKINS.size() > 1:
				GameState.set_skin(GameState.skin + step)
				_skin_bump = 1.0
				GameState.play_sfx("pluck", 12.0, -6.0)


func _display_row_count() -> int:
	## 風格固定心動之城，畫面設定不再切主題
	return 2 if GameState.SKINS.size() > 1 else 1


func _handle_music() -> void:
	if Input.is_action_just_pressed("up"):
		_music_row = posmod(_music_row - 1, 2)
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("down"):
		_music_row = posmod(_music_row + 1, 2)
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("back"):
		_set_tab(Tab.LEVELS)
	elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		## 尚未自訂曲時，「推薦速度」列的 Enter 改開選歌，避免像卡住
		if _music_row == 1 and Conductor.custom_music:
			_toggle_recommended_tempo()
		else:
			_music_row = 0
			_open_music_setup()
	elif _music_row == 1 and (
			Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right")
			or Input.is_action_just_pressed("easier") or Input.is_action_just_pressed("harder")):
		_toggle_recommended_tempo()


func _toggle_recommended_tempo() -> void:
	if not Conductor.custom_music:
		_music_row = 0
		GameState.play_sfx("pluck", 5.0, -8.0)
		_open_music_setup()
		return
	GameState.set_prefer_reference_tempo(not Conductor.prefer_reference_tempo)
	GameState.play_sfx("pluck", 8.0 if Conductor.prefer_reference_tempo else 2.0, -8.0)


func _other_items() -> Array[String]:
	var items: Array[String] = [
		"延遲校正",
		"機關說明",
		"關卡設計台",
	]
	if not OS.has_feature("web"):
		items.append("離開遊戲")
	return items


func _handle_other() -> void:
	var items := _other_items()
	if Input.is_action_just_pressed("up"):
		_other_row = posmod(_other_row - 1, items.size())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("down"):
		_other_row = posmod(_other_row + 1, items.size())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_activate_other(items[_other_row])


func _activate_other(item: String) -> void:
	if item == "延遲校正":
		_open_calibrator()
	elif item == "機關說明":
		_open_guide()
	elif item == "關卡設計台":
		get_tree().change_scene_to_file(CHART_SCENE)
	elif item == "離開遊戲":
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _starting or _overlay_open() or _fade > 0.05:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var digit := key.physical_keycode - KEY_1
	if digit >= 0 and digit < TAB_LABELS.size() and key.alt_pressed:
		_set_tab(digit)
		return
	if _tab == Tab.LEVELS:
		if digit >= 0 and digit < LevelData.LEVELS.size():
			_selected = digit
			_start_level(digit)
	elif digit >= 0 and digit < TAB_LABELS.size():
		_set_tab(digit)


func _start_level(idx: int) -> void:
	if _starting or LevelData.LEVELS.is_empty():
		return
	_starting = true
	GameState.level_index = idx
	GameState.start_section = 0
	GameState.play_sfx("cue", 0.0, -4.0)
	_fade_out = 0.01


func _open_guide() -> void:
	_guide = MechanicGuide.new()
	add_child(_guide)
	GameState.play_sfx("pluck", 7.0, -6.0)


func _open_calibrator() -> void:
	_calibrator = LatencyCalibrator.new()
	add_child(_calibrator)
	GameState.play_sfx("pluck", 7.0, -6.0)


func _open_music_setup() -> void:
	if is_instance_valid(_music_setup):
		if not _music_setup.is_inside_tree():
			_music_setup = null
		else:
			return
	_music_row = 0
	_music_setup = MusicSetup.new()
	_music_setup.closed.connect(func() -> void:
		_input_lock = 0.2
		_music_setup = null
	)
	_music_setup.tree_exited.connect(func() -> void:
		_music_setup = null
		_input_lock = maxf(_input_lock, 0.15)
	)
	add_child(_music_setup)
	GameState.play_sfx("pluck", 7.0, -6.0)


func _on_gui_input(event: InputEvent) -> void:
	if _starting or _overlay_open() or _fade > 0.05 or _input_lock > 0.0:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var safe := UiKit.safe_rect(_view.size)
	var nav := _nav_rect(safe)
	for i in TAB_LABELS.size():
		if _tab_row_rect(nav, i).has_point(mb.position):
			_set_tab(i)
			return
	var panel := _panel_rect(safe)
	match _tab:
		Tab.LEVELS:
			for i in LevelData.LEVELS.size():
				var offset := (i - _slide) * (CARD_SIZE.x + CARD_GAP)
				var c := Vector2(panel.get_center().x + offset, panel.position.y + 150.0)
				if Rect2(c - CARD_SIZE * 0.5, CARD_SIZE).has_point(mb.position):
					if i == _selected:
						_start_level(i)
					else:
						_selected = i
						_section = 0
						_bump = 1.0
						GameState.play_sfx("pluck", GameState.next_note(), -6.0)
					return
		Tab.DIFFICULTY:
			_nudge_diff_at(panel, mb.position)
		Tab.DISPLAY:
			_click_display(panel, mb.position)
		Tab.MUSIC:
			var info := Rect2(panel.position + Vector2(24, 70), Vector2(panel.size.x - 48, 120))
			if info.has_point(mb.position) or _music_setup_rect(panel).has_point(mb.position):
				_music_row = 0
				_open_music_setup()
				return
			if _music_tempo_rect(panel).has_point(mb.position):
				_music_row = 1
				_toggle_recommended_tempo()
				return
		Tab.OTHER:
			var items := _other_items()
			for i in items.size():
				if _other_row_rect(panel, i).has_point(mb.position):
					_other_row = i
					_activate_other(items[i])
					return


func _nudge_diff_at(panel: Rect2, pos: Vector2) -> void:
	var box := Rect2(panel.position + Vector2(24, 72), Vector2(panel.size.x - 48, 120))
	if not box.has_point(pos):
		return
	var n := GameState.DIFFICULTIES.size()
	var seg_w := (box.size.x - 36.0 - 6.0 * (n - 1)) / n
	for i in n:
		var r := Rect2(box.position + Vector2(18.0 + i * (seg_w + 6.0), 42), Vector2(seg_w, 40))
		if r.has_point(pos):
			GameState.set_difficulty(i)
			_diff_bump = 1.0
			GameState.play_sfx("pluck", 7.0, -8.0)
			return


func _click_display(panel: Rect2, pos: Vector2) -> void:
	for i in _display_row_count():
		var r := _display_row_rect(panel, i)
		if not r.has_point(pos):
			continue
		_display_row = i
		match i:
			0:
				GameState.set_quality(posmod(GameState.quality + 1, GameState.QUALITIES.size()))
				_quality_bump = 1.0
			1:
				GameState.set_skin(GameState.skin + 1)
				_skin_bump = 1.0
		GameState.play_sfx("pluck", 6.0, -8.0)
		return


func _nav_rect(safe: Rect2) -> Rect2:
	return Rect2(safe.position.x, safe.position.y + 78.0, 196.0, safe.size.y - 120.0)


func _panel_rect(safe: Rect2) -> Rect2:
	var nav := _nav_rect(safe)
	return Rect2(nav.end.x + 18.0, nav.position.y, safe.end.x - nav.end.x - 18.0, nav.size.y)


func _tab_row_rect(nav: Rect2, index: int) -> Rect2:
	return Rect2(nav.position.x + 8.0, nav.position.y + 16.0 + index * 58.0, nav.size.x - 16.0, 48.0)


func _display_row_rect(panel: Rect2, index: int) -> Rect2:
	return Rect2(panel.position.x + 24.0, panel.position.y + 64.0 + index * 108.0, panel.size.x - 48.0, 96.0)


func _other_row_rect(panel: Rect2, index: int) -> Rect2:
	return Rect2(panel.position.x + 40.0, panel.position.y + 70.0 + index * 52.0, panel.size.x - 80.0, 44.0)


func _music_setup_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position.x + 40.0, panel.position.y + 210.0, panel.size.x - 80.0, 44.0)


func _music_tempo_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position.x + 40.0, panel.position.y + 268.0, panel.size.x - 80.0, 72.0)


func _on_view_draw() -> void:
	var size := _view.size
	var safe := UiKit.safe_rect(size)
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(6.0) * GameState.anim_amount()

	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	var shade := size.y * 0.32
	_view.draw_polygon(
		PackedVector2Array([Vector2(0, size.y - shade), Vector2(size.x, size.y - shade), size, Vector2(0, size.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55)]))

	_draw_title(safe, edge, pulse)
	var nav := _nav_rect(safe)
	var panel := _panel_rect(safe)
	_draw_nav(nav, edge, pulse)
	UiKit.panel(_view, panel, edge, 0.15 + 0.1 * pulse, 0.92, 16.0)

	if is_instance_valid(_levels_clip):
		_levels_clip.visible = _tab == Tab.LEVELS
	match _tab:
		Tab.LEVELS:
			_draw_levels(panel, edge, pulse)
		Tab.DIFFICULTY:
			_draw_difficulty(panel, edge, pulse)
		Tab.DISPLAY:
			_draw_display(panel, edge, pulse)
		Tab.MUSIC:
			_draw_music(panel, edge, pulse)
		Tab.OTHER:
			_draw_other(panel, edge, pulse)

	_draw_hints(safe, edge)
	if absf(GameState.audio_offset_ms) >= 0.5:
		var off := "延遲 %+.0f ms" % GameState.audio_offset_ms
		UiKit.pill(_view, Vector2(safe.end.x - UiKit.width_of(off, 13) - 28.0, safe.position.y + 8.0),
			off, Color(UiKit.FLOAT, 0.9), UiKit.INK, 13)

	if _fade > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, _fade))
	if _fade_out > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, _fade_out))


func _draw_title(safe: Rect2, edge: Color, pulse: float) -> void:
	var title := GameState.GAME_TITLE
	var tw := UiKit.width_of(title, 34, UiKit.title_font())
	UiKit.text(_view, Vector2(safe.position.x, safe.position.y + 42), -1, title, 34,
		Color(0.92, 0.95, 1.0, 0.95), HORIZONTAL_ALIGNMENT_LEFT, UiKit.title_font())
	_view.draw_line(Vector2(safe.position.x, safe.position.y + 56),
		Vector2(safe.position.x + maxf(tw * 0.55, 120.0), safe.position.y + 56), Color(edge, 0.45 + 0.2 * pulse), 1.5)
	UiKit.text(_view, Vector2(safe.position.x + tw + 16.0, safe.position.y + 38), -1, "主選單", 14, Color(edge, 0.75))


func _draw_nav(nav: Rect2, edge: Color, pulse: float) -> void:
	UiKit.panel(_view, nav, edge, 0.08, 0.9, 14.0)
	for i in TAB_LABELS.size():
		var r := _tab_row_rect(nav, i)
		var on := i == int(_tab)
		if on:
			_view.draw_colored_polygon(UiKit.chamfer(r, 8.0), Color(edge, 0.22 + 0.12 * pulse))
			_view.draw_rect(Rect2(r.position.x, r.position.y + 8.0, 4.0, r.size.y - 16.0), Color(edge, 0.95))
		UiKit.text(_view, Vector2(r.position.x + 18.0, r.get_center().y + 7.0), -1, TAB_LABELS[i],
			18 if on else 16, Color(1, 1, 1, 0.98) if on else Color(1, 1, 1, 0.55))
		UiKit.text(_view, Vector2(r.end.x - 28.0, r.get_center().y + 6.0), -1, str(i + 1), 13,
			Color(edge, 0.8) if on else Color(1, 1, 1, 0.28))


func _levels_clip_rect(panel: Rect2) -> Rect2:
	## 標題下方到面板內；卡片不會畫出框外
	return Rect2(
		panel.position.x + 14.0,
		panel.position.y + 48.0,
		maxi(8.0, panel.size.x - 28.0),
		maxi(8.0, panel.size.y - 48.0 - 18.0)
	)


func _draw_levels(panel: Rect2, edge: Color, pulse: float) -> void:
	UiKit.text(_view, panel.position + Vector2(24, 36), -1, "選擇關卡", 20, Color(edge, 0.9))
	_levels_panel = panel
	_levels_edge = edge
	_levels_pulse = pulse
	var clip := _levels_clip_rect(panel)
	_levels_clip.visible = true
	_levels_clip.position = clip.position
	_levels_clip.size = clip.size


func _on_levels_clip_draw() -> void:
	if _tab != Tab.LEVELS or not _levels_clip.visible:
		return
	var panel := _levels_panel
	var edge := _levels_edge
	var pulse := _levels_pulse
	## 轉成裁切層本地座標
	var origin := _levels_clip.position
	var center_y := panel.position.y + 150.0 - origin.y
	for i in LevelData.LEVELS.size():
		var offset := (i - _slide) * (CARD_SIZE.x + CARD_GAP)
		var center := Vector2(panel.get_center().x - origin.x + offset, center_y)
		## 完全在裁切區外就跳過
		var half := CARD_SIZE * 0.55
		if center.x + half.x < -4.0 or center.x - half.x > _levels_clip.size.x + 4.0:
			continue
		_draw_card(_levels_clip, i, center, i == _selected, edge, pulse)
	_draw_dots(_levels_clip, Vector2(panel.get_center().x - origin.x, center_y + CARD_SIZE.y * 0.5 + 28.0), edge)


func _draw_card(ci: CanvasItem, i: int, center: Vector2, selected: bool, edge: Color, pulse: float) -> void:
	var info: Dictionary = LevelData.LEVELS[i]
	var s := 1.03 + 0.012 * pulse + 0.035 * _bump if selected else 0.88
	var alpha := 1.0 if selected else 0.42
	ci.draw_set_transform(center, 0.0, Vector2(s, s))
	var r := Rect2(-CARD_SIZE * 0.5, CARD_SIZE)
	var accent := edge
	if i == 3 or bool(info.get("tempo_stage", false)):
		accent = UiKit.FLOAT if selected else Color(0.55, 0.78, 0.95)
	UiKit.panel(ci, r, accent if selected else Color(0.8, 0.85, 1.0),
		0.55 + 0.35 * pulse if selected else 0.0, 1.0 if selected else 0.75, 16.0)
	var x := r.position.x + 20.0
	var y := r.position.y
	var w := r.size.x - 40.0
	var code := LevelData.level_code(i)
	UiKit.text(ci, Vector2(x, y + 28), w, "STAGE", 12, Color(accent, 0.9 * alpha), HORIZONTAL_ALIGNMENT_CENTER)
	var nw := UiKit.width_of(code, 52, UiKit.title_font())
	UiKit.bold_text(ci, Vector2(r.get_center().x - nw * 0.5, y + 88), -1, code, 52, Color(1, 1, 1, alpha), accent)
	UiKit.draw_minimap(ci, i, Rect2(x, y + 110, w, 36), edge, alpha)
	var rec: Dictionary = GameState.records.get(i, {})
	var fy := r.end.y - 28.0
	if rec.is_empty():
		UiKit.text(ci, Vector2(x, fy + 14), w, "尚未通關", 14, Color(1, 1, 1, 0.45 * alpha), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UiKit.text(ci, Vector2(x, fy + 14), w,
			"最佳 %.1f 秒　死 %d" % [float(rec["time"]), int(rec["deaths"])], 14, Color(UiKit.GOLD, alpha), HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_set_transform(Vector2.ZERO)


func _draw_dots(ci: CanvasItem, c: Vector2, edge: Color) -> void:
	var n := LevelData.LEVELS.size()
	if n <= 0:
		return
	var total := (n - 1) * 16.0 + 18.0
	var x := c.x - total * 0.5
	for i in n:
		var on := i == _selected
		var w := 24.0 if on else 8.0
		var r := Rect2(x, c.y - 3, w, 7)
		ci.draw_rect(Rect2(r.position + Vector2(3, 0), r.size - Vector2(6, 0)),
			Color(edge, 1.0) if on else Color(1, 1, 1, 0.28))
		ci.draw_circle(r.position + Vector2(3, 3.5), 3.5, Color(edge, 1.0) if on else Color(1, 1, 1, 0.28))
		ci.draw_circle(Vector2(r.end.x - 3, r.position.y + 3.5), 3.5,
			Color(edge, 1.0) if on else Color(1, 1, 1, 0.28))
		x += w + 8.0


func _draw_difficulty(panel: Rect2, edge: Color, pulse: float) -> void:
	UiKit.text(_view, panel.position + Vector2(24, 36), -1, "判定難度", 20, Color(edge, 0.9))
	var box := Rect2(panel.position + Vector2(24, 72), Vector2(panel.size.x - 48, 150))
	UiKit.panel(_view, box, edge, 0.45 * _diff_bump, 0.85, 12.0)
	var n := GameState.DIFFICULTIES.size()
	var seg_w := (box.size.x - 36.0 - 6.0 * (n - 1)) / n
	for i in n:
		var on := i == GameState.difficulty
		var r := Rect2(box.position + Vector2(18.0 + i * (seg_w + 6.0), 48), Vector2(seg_w, 40))
		if on:
			r = r.grow(2.0 * _diff_bump)
			_view.draw_colored_polygon(UiKit.chamfer(r, 8.0), Color(edge, 0.85 + 0.15 * pulse))
		else:
			var loop := UiKit.chamfer(r, 8.0)
			_view.draw_colored_polygon(loop, Color(1, 1, 1, 0.06))
			loop.append(loop[0])
			_view.draw_polyline(loop, Color(1, 1, 1, 0.22), 1.0, true)
		_view.draw_string(UiKit.font(), Vector2(r.position.x, r.position.y + 26),
			String(GameState.DIFFICULTIES[i]["name"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18,
			UiKit.INK if on else Color(1, 1, 1, 0.55))
	var d: Dictionary = GameState.DIFFICULTIES[GameState.difficulty]
	var sub := "音符、衝刺環、光牆隨時可用，不用對拍" if GameState.free_rhythm() else \
		"早 %d 幀／晚 %d 幀內按下都算準（60fps）" % [int(d["early"]), int(d["late"])]
	UiKit.text(_view, Vector2(box.position.x, box.end.y - 28), box.size.x, sub, 15,
		Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(_view, panel.position + Vector2(24, panel.size.y - 48), panel.size.x - 48,
		"←→ 或 Q／E 調整判定窗寬度", 14, Color(1, 1, 1, 0.45))


func _draw_display(panel: Rect2, edge: Color, pulse: float) -> void:
	UiKit.text(_view, panel.position + Vector2(24, 36), -1, "畫面設定", 20, Color(edge, 0.9))
	## 畫質
	_draw_setting_block(_display_row_rect(panel, 0), "畫質", _display_row == 0, edge, _quality_bump, pulse)
	var qn := GameState.QUALITIES.size()
	var qbox := _display_row_rect(panel, 0)
	var seg_w := (qbox.size.x - 36.0 - 6.0 * (qn - 1)) / qn
	for i in qn:
		var on := i == GameState.quality
		var r := Rect2(qbox.position + Vector2(18.0 + i * (seg_w + 6.0), 42), Vector2(seg_w, 34))
		if on:
			_view.draw_colored_polygon(UiKit.chamfer(r, 7.0), Color(edge, 0.85 + 0.1 * pulse))
		else:
			_view.draw_colored_polygon(UiKit.chamfer(r, 7.0), Color(1, 1, 1, 0.06))
		_view.draw_string(UiKit.font(), Vector2(r.position.x, r.position.y + 23),
			String(GameState.QUALITIES[i]["name"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16,
			UiKit.INK if on else Color(1, 1, 1, 0.55))

	if GameState.SKINS.size() > 1:
		_draw_setting_block(_display_row_rect(panel, 1), "造型", _display_row == 1, edge, _skin_bump, pulse)
		var sbox := _display_row_rect(panel, 1)
		var feet := sbox.position + Vector2(70, 88)
		var pose := "jump_0" if _skin_bump > 0.3 else Player.idle_pose(Conductor.song_beat)
		Player.draw_skin(_view, GameState.skin, feet + Vector2(0, -sin(_skin_bump * PI) * 12.0),
			Vector2(1.45, 1.45), 0.0, Color.WHITE, pose)
		UiKit.text(_view, sbox.position + Vector2(130, 62), sbox.size.x - 150,
			String(GameState.SKINS[GameState.skin]["name"]), 22, Color.WHITE)


func _draw_setting_block(box: Rect2, title: String, on: bool, edge: Color, bump: float, pulse: float) -> void:
	UiKit.panel(_view, box, edge, (0.35 if on else 0.08) + 0.35 * bump, 0.88 if on else 0.75, 12.0)
	UiKit.text(_view, box.position + Vector2(18, 26), -1, title, 14, Color(edge, 0.95 if on else 0.7))
	if on:
		_view.draw_rect(Rect2(box.position.x + 4, box.position.y + 12, 3, box.size.y - 24), Color(edge, 0.7 + 0.3 * pulse))


func _draw_music(panel: Rect2, edge: Color, pulse: float) -> void:
	UiKit.text(_view, panel.position + Vector2(24, 36), -1, "自訂音樂", 20, Color(edge, 0.9))
	var box := Rect2(panel.position + Vector2(24, 70), Vector2(panel.size.x - 48, 120))
	UiKit.panel(_view, box, edge, 0.2, 0.9, 12.0)
	var title := Conductor.track_name if Conductor.track_name != "" else "內建音樂"
	## 自訂檔名可能含字型子集沒有的漢字，顯示前先過濾
	title = UiKit.safe_text(title)
	var line2 := "%.1f BPM" % Conductor.bpm
	if Conductor.custom_music:
		line2 += "　自訂曲"
		if not Conductor.rhythm_sections.is_empty():
			line2 += "　%d 段節奏" % Conductor.rhythm_sections.size()
	else:
		line2 += "　內建曲"
	UiKit.text(_view, box.position + Vector2(24, 42), box.size.x - 48, title, 24, Color.WHITE)
	UiKit.text(_view, box.position + Vector2(24, 78), box.size.x - 48, line2, 15, Color(1, 1, 1, 0.7))
	UiKit.text(_view, box.position + Vector2(24, 104), box.size.x - 48,
		"選歌 → 試聽 → 打拍校正 → 套用", 14, Color(UiKit.FLOAT, 0.85))

	var setup_r := _music_setup_rect(panel)
	var setup_on := _music_row == 0
	## 永遠畫成可點按鈕，避免看起來像停用
	UiKit.panel(_view, setup_r, edge, 0.4 if setup_on else 0.22, 0.95, 10.0)
	if setup_on:
		_view.draw_rect(Rect2(setup_r.position.x + 4, setup_r.position.y + 10, 3, setup_r.size.y - 20),
			Color(edge, 0.8 + 0.2 * pulse))
	UiKit.text(_view, Vector2(setup_r.position.x + 18.0, setup_r.get_center().y + 7.0), -1,
		"開啟音樂設定　Enter / 點這裡", 18, Color(1, 1, 1, 0.98))

	var tempo_r := _music_tempo_rect(panel)
	var tempo_on := _music_row == 1
	var can_reco := Conductor.custom_music
	var reco_on := Conductor.prefer_reference_tempo and can_reco
	UiKit.panel(_view, tempo_r, edge, 0.35 if tempo_on else 0.12, 0.9 if tempo_on else 0.75, 10.0)
	if tempo_on:
		_view.draw_rect(Rect2(tempo_r.position.x + 4, tempo_r.position.y + 12, 3, tempo_r.size.y - 24),
			Color(edge, 0.75 + 0.25 * pulse))
	var state := "開" if reco_on else "關"
	if not can_reco:
		state = "需自訂曲"
	UiKit.text(_view, tempo_r.position + Vector2(18, 28), -1, "推薦速度　%s" % state, 18,
		Color(1, 1, 1, 0.98) if tempo_on else Color(1, 1, 1, 0.6))
	var reco_rate := Conductor.recommended_rate()
	var sub := "把世界節奏對齊 120 BPM 設計手感（歌曲 %.2f×）" % reco_rate if can_reco \
		else "先套用自訂歌曲後才能開啟"
	if reco_on:
		sub = "已開啟　歌曲 %.2f×　世界約 %.0f BPM 手感" % [
			Conductor.rate, Conductor.REFERENCE_BPM * Conductor.world_rate]
	UiKit.text(_view, tempo_r.position + Vector2(18, 56), tempo_r.size.x - 36, sub, 13, Color(1, 1, 1, 0.55))


func _draw_other(panel: Rect2, edge: Color, pulse: float) -> void:
	UiKit.text(_view, panel.position + Vector2(24, 36), -1, "其他設定", 20, Color(edge, 0.9))
	var items := _other_items()
	for i in items.size():
		var r := _other_row_rect(panel, i)
		var on := i == _other_row
		if on:
			_view.draw_colored_polygon(UiKit.chamfer(r, 8.0), Color(edge, 0.2 + 0.12 * pulse))
		UiKit.text(_view, Vector2(r.position.x + 18.0, r.get_center().y + 7.0), -1, items[i],
			18 if on else 16, Color(1, 1, 1, 0.98) if on else Color(1, 1, 1, 0.55))
	## 右下角角色陪伴
	var feet := Vector2(panel.end.x - 90.0, panel.end.y - 36.0)
	Player.draw_skin(_view, GameState.skin, feet + Vector2(0, sin(_blink * 1.4) * 2.0),
		Vector2(1.5, 1.5), 0.0, Color(1, 1, 1, 0.92), Player.idle_pose(Conductor.song_beat))


func _draw_hints(safe: Rect2, edge: Color) -> void:
	var hints: Array = [[["[", "]"], "分頁"]]
	match _tab:
		Tab.LEVELS:
			hints.append_array([[["←", "→"], "選關"], [["Enter"], "開始"]])
		Tab.DIFFICULTY:
			hints.append_array([[["←", "→"], "調整"], [["Q", "E"], "判定"]])
		Tab.DISPLAY:
			hints.append_array([[["↑", "↓"], "項目"], [["←", "→"], "調整"]])
		Tab.MUSIC:
			hints.append_array([[["↑", "↓"], "項目"], [["Enter"], "確定／切換"]])
		Tab.OTHER:
			hints.append_array([[["↑", "↓"], "選擇"], [["Enter"], "確定"]])
	hints.append([["H"], "機關"])
	hints.append([["O"], "校正"])
	UiKit.key_hints(_view, safe.get_center().x, safe.end.y - 16, hints, edge, 0.9)
