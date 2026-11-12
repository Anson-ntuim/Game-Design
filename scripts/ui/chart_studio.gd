extends Node2D
## 關卡節奏設計台：拖曳放置／移動／擦除音符；尺規顯示 0.5／1／1.5／2 拍實際距離。

const HOME_SCENE := "res://scenes/home.tscn"
const RUN_SPEED := 310.0
const TILE := 40.0
const SNAP := 0.5
const HIT_RADIUS_BEATS := 0.28
const TOOLS: Array[Dictionary] = [
	{"id": "J", "name": "起跳", "color": Color(0.75, 0.8, 0.9)},
	{"id": "O", "name": "長按", "color": Color(1.0, 0.86, 0.35)},
	{"id": "T", "name": "輕點", "color": Color(1.0, 0.7, 0.25)},
	{"id": "R", "name": "衝刺環", "color": Color(0.45, 0.85, 1.0)},
	{"id": "D", "name": "衝刺", "color": Color(0.95, 0.55, 0.85)},
]
const SPACING_EXAMPLES: Array[float] = [0.5, 1.0, 1.5, 2.0]

enum DragMode { NONE, PAINT, MOVE, ERASE, PAN }

var _view: Control
var _camera: Camera2D
var _bpm: float = 120.0
var _tool: int = 1
var _notes: Array[Dictionary] = []
var _scroll: float = 0.0
var _hover_beat: float = -1.0
var _copied: String = ""
var _toast: String = ""
var _toast_t: float = 0.0

var _drag: DragMode = DragMode.NONE
var _drag_note: int = -1
var _drag_kind: String = ""
var _pan_from: Vector2 = Vector2.ZERO
var _pan_scroll0: float = 0.0
var _last_paint_beat: float = -999.0
var _space_pan: bool = false


func _ready() -> void:
	Engine.time_scale = 1.0
	var bg := Background.new()
	bg.quiet = true
	add_child(bg)
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

	_load_example("長短")
	Conductor.start(false)


func px_per_beat() -> float:
	return RUN_SPEED * (60.0 / _bpm)


func tiles_per_beat() -> float:
	return px_per_beat() / TILE


func _board_rect(safe: Rect2) -> Rect2:
	return Rect2(safe.position.x, safe.position.y + 168.0, safe.size.x, safe.size.y - 250.0)


func _ground_y(board: Rect2) -> float:
	return board.position.y + board.size.y * 0.62


func _beat_at_x(board: Rect2, x: float) -> float:
	return _scroll + (x - board.position.x - 48.0) / px_per_beat()


func _x_at_beat(board: Rect2, beat: float) -> float:
	return board.position.x + 48.0 + (beat - _scroll) * px_per_beat()


func _snap_beat(b: float) -> float:
	return snappedf(maxi(0.0, b), SNAP)


func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	_space_pan = Input.is_key_pressed(KEY_SPACE)
	_view.queue_redraw()
	if Input.is_action_just_pressed("back") and _drag == DragMode.NONE:
		get_tree().change_scene_to_file(HOME_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_tool = clampi(key.physical_keycode - KEY_1, 0, TOOLS.size() - 1)
			GameState.play_sfx("pluck", 4.0, -10.0)
		KEY_C:
			_copy_script()
		KEY_X:
			_notes.clear()
			_toast_msg("已清空")
		KEY_E:
			_load_example("長短")
		KEY_R:
			_load_example("半拍")
		KEY_T:
			_load_example("寬距")
		KEY_BRACKETLEFT, KEY_MINUS:
			_bpm = clampf(_bpm - 5.0, 60.0, 200.0)
			_toast_msg("BPM %.0f" % _bpm)
		KEY_BRACKETRIGHT, KEY_EQUAL:
			_bpm = clampf(_bpm + 5.0, 60.0, 200.0)
			_toast_msg("BPM %.0f" % _bpm)


func _on_gui_input(event: InputEvent) -> void:
	var board := _board_rect(UiKit.safe_rect(_view.size))
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion

	if mb:
		_handle_button(mb, board)
	if mm:
		_handle_motion(mm, board)


func _handle_button(mb: InputEventMouseButton, board: Rect2) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_scroll = maxf(0.0, _scroll - 0.5)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_scroll += 0.5
		return

	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_begin_pan(mb.position)
		else:
			_end_drag()
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed and board.has_point(mb.position):
			_drag = DragMode.ERASE
			_erase_at(mb.position, board)
		else:
			_end_drag()
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mb.pressed:
		_end_drag()
		return

	## 左鍵按下
	if _pick_tool_bar(mb.position) or _pick_example_bar(mb.position):
		return

	if _space_pan or not board.has_point(mb.position):
		_begin_pan(mb.position)
		return

	var hit := _hit_note(mb.position, board)
	if hit >= 0:
		_drag = DragMode.MOVE
		_drag_note = hit
		_drag_kind = String(_notes[hit]["kind"])
		## 選中該工具方便之後接著畫
		for i in TOOLS.size():
			if String(TOOLS[i]["id"]) == _drag_kind:
				_tool = i
				break
		GameState.play_sfx("pluck", 2.0, -12.0)
		return

	_drag = DragMode.PAINT
	_drag_kind = String(TOOLS[_tool]["id"])
	_last_paint_beat = -999.0
	_paint_at(mb.position, board)


func _handle_motion(mm: InputEventMouseMotion, board: Rect2) -> void:
	if board.has_point(mm.position):
		_hover_beat = _snap_beat(_beat_at_x(board, mm.position.x))
	else:
		_hover_beat = -1.0

	match _drag:
		DragMode.PAN:
			var dx := mm.position.x - _pan_from.x
			_scroll = maxf(0.0, _pan_scroll0 - dx / px_per_beat())
		DragMode.MOVE:
			if _drag_note >= 0 and _drag_note < _notes.size():
				var beat := _snap_beat(_beat_at_x(board, mm.position.x))
				_notes[_drag_note]["beat"] = beat
				_resolve_overlap(_drag_note)
				_sort_notes()
		DragMode.PAINT:
			_paint_at(mm.position, board)
		DragMode.ERASE:
			if board.has_point(mm.position):
				_erase_at(mm.position, board)
		_:
			pass


func _begin_pan(pos: Vector2) -> void:
	_drag = DragMode.PAN
	_pan_from = pos
	_pan_scroll0 = _scroll


func _end_drag() -> void:
	if _drag == DragMode.MOVE:
		_sort_notes()
	_drag = DragMode.NONE
	_drag_note = -1
	_last_paint_beat = -999.0


func _paint_at(pos: Vector2, board: Rect2) -> void:
	if not board.has_point(pos):
		return
	var beat := _snap_beat(_beat_at_x(board, pos.x))
	if is_equal_approx(beat, _last_paint_beat):
		return
	_last_paint_beat = beat
	_upsert_note(beat, _drag_kind if _drag_kind != "" else String(TOOLS[_tool]["id"]))


func _erase_at(pos: Vector2, board: Rect2) -> void:
	var hit := _hit_note(pos, board)
	if hit >= 0:
		_notes.remove_at(hit)
		if _drag_note == hit:
			_drag_note = -1
		elif _drag_note > hit:
			_drag_note -= 1
		GameState.play_sfx("pluck", -4.0, -14.0)


func _hit_note(pos: Vector2, board: Rect2) -> int:
	var beat := _beat_at_x(board, pos.x)
	var gy := _ground_y(board)
	## 只認軌道附近的點擊
	if absf(pos.y - (gy - 28.0)) > 36.0 and absf(pos.y - gy) > 40.0:
		## 放寬：整條板子垂直都可抓，較直覺
		pass
	var best := -1
	var best_d := HIT_RADIUS_BEATS
	for i in _notes.size():
		var d := absf(float(_notes[i]["beat"]) - beat)
		var x := _x_at_beat(board, float(_notes[i]["beat"]))
		var px := absf(pos.x - x) / px_per_beat()
		var score := mini(d, px)
		if score < best_d:
			best_d = score
			best = i
	return best


func _upsert_note(beat: float, kind: String) -> void:
	## 同一拍同種類 → 略過；同拍其他主音符 → 覆寫（J 可並存）
	for i in _notes.size():
		if is_equal_approx(float(_notes[i]["beat"]), beat) and String(_notes[i]["kind"]) == kind:
			return
	if kind != "J":
		var kept: Array[Dictionary] = []
		for n in _notes:
			if is_equal_approx(float(n["beat"]), beat) and String(n["kind"]) != "J":
				continue
			kept.append(n)
		_notes.clear()
		for n in kept:
			_notes.append(n)
	_notes.append({"beat": beat, "kind": kind})
	_sort_notes()
	GameState.play_sfx("pluck", 8.0, -10.0)


func _resolve_overlap(keep_index: int) -> void:
	if keep_index < 0 or keep_index >= _notes.size():
		return
	var beat := float(_notes[keep_index]["beat"])
	var kind: String = _notes[keep_index]["kind"]
	var i := 0
	while i < _notes.size():
		if i == keep_index:
			i += 1
			continue
		if not is_equal_approx(float(_notes[i]["beat"]), beat):
			i += 1
			continue
		## 同拍：J 可與其他並存；其他互斥
		if kind == "J" or String(_notes[i]["kind"]) == "J":
			if String(_notes[i]["kind"]) == kind:
				_notes.remove_at(i)
				if keep_index > i:
					keep_index -= 1
				continue
			i += 1
			continue
		_notes.remove_at(i)
		if keep_index > i:
			keep_index -= 1
	_drag_note = keep_index


func _sort_notes() -> void:
	_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["beat"]) < float(b["beat"]))
	## 移動後重新找 index
	if _drag == DragMode.MOVE and _drag_kind != "":
		for i in _notes.size():
			if String(_notes[i]["kind"]) == _drag_kind and is_equal_approx(float(_notes[i]["beat"]), _hover_beat):
				_drag_note = i
				break


func _pick_tool_bar(pos: Vector2) -> bool:
	var safe := UiKit.safe_rect(_view.size)
	var x := safe.position.x
	var y := safe.position.y + 78.0
	for i in TOOLS.size():
		var r := Rect2(x + i * 118.0, y, 110.0, 32.0)
		if r.has_point(pos):
			_tool = i
			GameState.play_sfx("pluck", 4.0, -10.0)
			return true
	return false


func _pick_example_bar(pos: Vector2) -> bool:
	var safe := UiKit.safe_rect(_view.size)
	var labels := ["長短按範例", "半拍連點", "寬距範例", "複製腳本", "清空"]
	var x := safe.position.x
	var y := safe.position.y + 118.0
	for i in labels.size():
		var r := Rect2(x + i * 132.0, y, 124.0, 28.0)
		if r.has_point(pos):
			match i:
				0: _load_example("長短")
				1: _load_example("半拍")
				2: _load_example("寬距")
				3: _copy_script()
				4:
					_notes.clear()
					_toast_msg("已清空")
			return true
	return false


func _load_example(which: String) -> void:
	_notes.clear()
	var raw: Array = []
	match which:
		"半拍":
			raw = [
				{"beat": 0.0, "kind": "J"}, {"beat": 1.0, "kind": "T"},
				{"beat": 1.5, "kind": "T"}, {"beat": 2.0, "kind": "T"}, {"beat": 2.5, "kind": "T"},
			]
			_toast_msg("半拍連點（拖曳可改位置）")
		"寬距":
			raw = [
				{"beat": 0.0, "kind": "J"}, {"beat": 2.0, "kind": "O"},
				{"beat": 4.0, "kind": "O"}, {"beat": 6.0, "kind": "R"}, {"beat": 7.0, "kind": "D"},
			]
			_toast_msg("寬距範例（2.0 拍）")
		_:
			raw = [
				{"beat": 0.0, "kind": "J"}, {"beat": 1.0, "kind": "O"},
				{"beat": 2.0, "kind": "T"}, {"beat": 2.5, "kind": "T"}, {"beat": 3.0, "kind": "T"},
				{"beat": 4.0, "kind": "O"}, {"beat": 5.5, "kind": "R"}, {"beat": 6.5, "kind": "D"},
			]
			_toast_msg("長短按範例（拖音符可移動）")
	for n in raw:
		_notes.append(n)
	GameState.play_sfx("cue", 0.0, -10.0)


func _note_to_token(n: Dictionary) -> String:
	var b := float(n["beat"])
	var k: String = n["kind"]
	var bs := "%s" % b if fposmod(b, 1.0) > 0.01 else "%d" % int(b)
	match k:
		"J": return "J(%s)" % bs
		"O": return "O(%s)" % bs
		"T": return "O(%s, T)" % bs
		"R": return "R(%s)" % bs
		"D": return "D(%s)" % bs
	return "?"


func _copy_script() -> void:
	var parts: PackedStringArray = []
	for n in _notes:
		parts.append(_note_to_token(n))
	_copied = ", ".join(parts)
	DisplayServer.clipboard_set(_copied)
	_toast_msg("已複製腳本")
	GameState.play_sfx("cue", 5.0, -8.0)


func _toast_msg(s: String) -> void:
	_toast = s
	_toast_t = 2.2


func _on_view_draw() -> void:
	var size := _view.size
	var safe := UiKit.safe_rect(size)
	var ink := Color(0.86, 0.88, 0.9)
	var mute := Color(0.5, 0.52, 0.56)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

	UiKit.text(_view, safe.position + Vector2(0, 28), -1, "關卡設計台", 28, ink)
	UiKit.text(_view, safe.position + Vector2(180, 28), -1,
		"BPM %.0f　1 拍 = %.0f px（%.2f 格）" % [_bpm, px_per_beat(), tiles_per_beat()], 15, mute)

	_draw_spacing_legend(safe, ink, mute)
	_draw_tool_bar(safe, ink)
	_draw_example_bar(safe, mute)

	var board := _board_rect(safe)
	_draw_board(board, ink, mute)

	var mode_hint := "拖空白畫音符　拖音符移動　右鍵擦除　空白鍵＋拖／中鍵平移　滾輪捲動"
	match _drag:
		DragMode.PAINT: mode_hint = "繪製中…"
		DragMode.MOVE: mode_hint = "移動音符中…"
		DragMode.ERASE: mode_hint = "擦除中…"
		DragMode.PAN: mode_hint = "平移時間軸…"
		_:
			pass
	UiKit.text(_view, Vector2(safe.position.x, safe.end.y - 36), safe.size.x,
		"%s　｜　1–5 工具　C 複製　Esc 返回" % mode_hint, 13, Color(mute, 0.9))
	if _copied != "":
		UiKit.text(_view, Vector2(safe.position.x, safe.end.y - 16), safe.size.x,
			_copied.left(110) + ("…" if _copied.length() > 110 else ""), 12, Color(UiKit.FLOAT, 0.9))
	if _toast_t > 0.0:
		var a := clampf(_toast_t, 0.0, 1.0)
		var tw := UiKit.width_of(_toast, 16)
		UiKit.pill(_view, Vector2(safe.get_center().x - tw * 0.5 - 14, safe.position.y + 40), _toast,
			Color(ink, 0.9 * a), Color(0.05, 0.05, 0.08), 16)


func _draw_spacing_legend(safe: Rect2, ink: Color, mute: Color) -> void:
	var y := safe.position.y + 44.0
	UiKit.text(_view, Vector2(safe.position.x, y + 14), -1, "距離尺規", 13, mute)
	var x := safe.position.x + 100.0
	for gap in SPACING_EXAMPLES:
		var w := gap * px_per_beat()
		var col := Color(1.0, 0.86, 0.35) if gap <= 1.0 else Color(0.45, 0.85, 1.0)
		_view.draw_rect(Rect2(x, y + 2, w, 10), Color(col, 0.85))
		_view.draw_line(Vector2(x, y), Vector2(x, y + 14), Color(ink, 0.7), 1.0)
		_view.draw_line(Vector2(x + w, y), Vector2(x + w, y + 14), Color(ink, 0.7), 1.0)
		UiKit.text(_view, Vector2(x, y + 28), -1, "%.1f拍 %.0fpx" % [gap, w], 12, Color(mute, 0.95))
		_view.draw_circle(Vector2(x, y + 7), 5.0, Color(col, 1.0))
		_view.draw_circle(Vector2(x + w, y + 7), 4.0 if gap < 1.0 else 5.0, Color(col, 0.7))
		x += w + 28.0


func _draw_tool_bar(safe: Rect2, ink: Color) -> void:
	var x := safe.position.x
	var y := safe.position.y + 78.0
	for i in TOOLS.size():
		var t: Dictionary = TOOLS[i]
		var r := Rect2(x + i * 118.0, y, 110.0, 32.0)
		var on := i == _tool
		_view.draw_rect(r, Color(1, 1, 1, 0.08 if on else 0.03))
		_view.draw_rect(r, Color(t["color"] if on else ink, 0.7 if on else 0.2), false, 1.5 if on else 1.0)
		UiKit.text(_view, r.position + Vector2(10, 22), -1, "%d %s" % [i + 1, t["name"]], 14,
			t["color"] if on else Color(ink, 0.65))


func _draw_example_bar(safe: Rect2, mute: Color) -> void:
	var labels := ["長短按範例", "半拍連點", "寬距範例", "複製腳本", "清空"]
	var x := safe.position.x
	var y := safe.position.y + 118.0
	for i in labels.size():
		var r := Rect2(x + i * 132.0, y, 124.0, 28.0)
		_view.draw_rect(r, Color(1, 1, 1, 0.04))
		_view.draw_rect(r, Color(mute, 0.35), false, 1.0)
		var w := UiKit.width_of(labels[i], 13)
		UiKit.text(_view, Vector2(r.get_center().x - w * 0.5, r.position.y + 19), -1, labels[i], 13, Color(mute, 0.95))


func _draw_board(board: Rect2, ink: Color, mute: Color) -> void:
	_view.draw_rect(board, Color(0.02, 0.025, 0.04, 0.72))
	_view.draw_rect(board, Color(ink, 0.18), false, 1.0)
	var ground_y := _ground_y(board)
	_view.draw_line(Vector2(board.position.x, ground_y), Vector2(board.end.x, ground_y), Color(ink, 0.35), 2.0)

	var beat0 := floorf(_scroll)
	var beat1 := ceili(_scroll + board.size.x / px_per_beat()) + 1
	for b in range(int(beat0), int(beat1) + 1):
		var x := _x_at_beat(board, float(b))
		if x < board.position.x or x > board.end.x:
			continue
		var major := posmod(b, 4) == 0
		var h := board.size.y * (0.55 if major else 0.22)
		_view.draw_line(Vector2(x, ground_y - h), Vector2(x, ground_y + 12),
			Color(ink, 0.45 if major else 0.18), 1.0)
		if major:
			UiKit.text(_view, Vector2(x + 4, ground_y + 28), -1, "%d" % b, 12, Color(mute, 0.8))
		var xh := _x_at_beat(board, float(b) + 0.5)
		if xh >= board.position.x and xh <= board.end.x:
			_view.draw_line(Vector2(xh, ground_y - 18), Vector2(xh, ground_y), Color(ink, 0.1), 1.0)

	if _hover_beat >= 0.0 and _drag != DragMode.MOVE:
		var hx := _x_at_beat(board, _hover_beat)
		if hx >= board.position.x and hx <= board.end.x:
			var col: Color = TOOLS[_tool]["color"]
			_view.draw_line(Vector2(hx, board.position.y + 8), Vector2(hx, ground_y), Color(col, 0.35), 1.0)
			_draw_note_glyph(Vector2(hx, ground_y - 28), String(TOOLS[_tool]["id"]), col, 0.4)
			UiKit.text(_view, Vector2(hx + 8, board.position.y + 22), -1, "%.1f 拍" % _hover_beat, 12, Color(col, 0.8))

	for i in _notes.size():
		var n: Dictionary = _notes[i]
		var b := float(n["beat"])
		var x := _x_at_beat(board, b)
		if x < board.position.x - 20 or x > board.end.x + 20:
			continue
		var kind: String = n["kind"]
		var col := Color(1, 1, 1)
		for t in TOOLS:
			if String(t["id"]) == kind:
				col = t["color"]
				break
		var selected := _drag == DragMode.MOVE and i == _drag_note
		if selected:
			_view.draw_circle(Vector2(x, ground_y - 28), 18.0, Color(col, 0.2))
			_view.draw_line(Vector2(x, board.position.y + 8), Vector2(x, ground_y), Color(col, 0.5), 1.5)
		_draw_note_glyph(Vector2(x, ground_y - 28), kind, col, 1.0)

	_draw_gap_labels(board, ground_y, mute)


func _draw_gap_labels(board: Rect2, ground_y: float, mute: Color) -> void:
	var seq: Array[Dictionary] = []
	for n in _notes:
		if String(n["kind"]) != "J":
			seq.append(n)
	for i in range(seq.size() - 1):
		var a := float(seq[i]["beat"])
		var b := float(seq[i + 1]["beat"])
		var gap := b - a
		var x0 := _x_at_beat(board, a)
		var x1 := _x_at_beat(board, b)
		if x1 < board.position.x or x0 > board.end.x:
			continue
		var mid := (x0 + x1) * 0.5
		var label := "%.1f拍" % gap
		var w := UiKit.width_of(label, 12)
		_view.draw_line(Vector2(x0, ground_y + 40), Vector2(x1, ground_y + 40), Color(mute, 0.35), 1.0)
		UiKit.text(_view, Vector2(mid - w * 0.5, ground_y + 54), -1, label, 12, Color(mute, 0.75))


func _draw_note_glyph(pos: Vector2, kind: String, col: Color, a: float) -> void:
	match kind:
		"J":
			_view.draw_colored_polygon(PackedVector2Array([
				pos + Vector2(0, -10), pos + Vector2(8, 8), pos + Vector2(-8, 8)
			]), Color(col, a))
		"O":
			_view.draw_circle(pos, 12.0, Color(col, 0.25 * a))
			_view.draw_circle(pos, 9.0, Color(col, a))
		"T":
			_view.draw_circle(pos, 7.0, Color(col, a))
			_view.draw_arc(pos, 11.0, 0.0, TAU, 20, Color(col, 0.7 * a), 1.5, true)
		"R":
			_view.draw_arc(pos, 11.0, 0.0, TAU, 24, Color(col, a), 2.5, true)
			_view.draw_arc(pos, 6.0, 0.0, TAU, 16, Color(col, 0.6 * a), 1.5, true)
		"D":
			_view.draw_colored_polygon(PackedVector2Array([
				pos + Vector2(-10, -6), pos + Vector2(10, 0), pos + Vector2(-10, 6)
			]), Color(col, a))
