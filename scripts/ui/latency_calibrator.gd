class_name LatencyCalibrator
extends CanvasLayer
## 音訊延遲校正：跟著聽到的鼓點按空白鍵，依誤差收斂偏移；←→ 微調、Enter 完成、Esc 取消還原。

signal closed

const STEP_MS := 5.0
const MAX_ERR_SEC := 0.22
## 每次對拍只吃一部分誤差，避免單次打滑就把偏移拉爆
const TAP_BLEND := 0.7

var _view: Control
var _opened_frame: int = 0
var _saved_ms: float = 0.0
var _draft_ms: float = 0.0
var _tap_count: int = 0
var _last_err_ms: float = 0.0
var _last_flash: float = 0.0
var _beat_flash: float = 0.0
var _last_beat: int = -9999
var _committed: bool = false


func _ready() -> void:
	layer = 22
	_opened_frame = Engine.get_process_frames()
	_saved_ms = GameState.audio_offset_ms
	_draft_ms = _saved_ms
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_on_view_draw)
	Conductor.beat.connect(_on_beat)
	GameState.play_sfx("cue", 0.0, -6.0)


func _exit_tree() -> void:
	if Conductor.beat.is_connected(_on_beat):
		Conductor.beat.disconnect(_on_beat)
	if not _committed:
		GameState.set_audio_offset_ms(_saved_ms, true)


func _on_beat(beat_index: int) -> void:
	if beat_index == _last_beat:
		return
	_last_beat = beat_index
	_beat_flash = 1.0
	if posmod(beat_index, Conductor.beats_per_measure) == 0:
		GameState.play_sfx("cue", 7.0, -10.0)


func _process(delta: float) -> void:
	_beat_flash = move_toward(_beat_flash, 0.0, delta * 4.0)
	_last_flash = move_toward(_last_flash, 0.0, delta * 2.5)
	_view.queue_redraw()
	if Engine.get_process_frames() == _opened_frame:
		return

	if Input.is_action_just_pressed("back"):
		GameState.play_sfx("pluck", GameState.next_note() - 12.0, -6.0)
		closed.emit()
		queue_free()
		return

	if Input.is_action_just_pressed("confirm"):
		_commit()
		return

	if Input.is_action_just_pressed("restart"):
		_tap_count = 0
		_draft_ms = 0.0
		_last_err_ms = 0.0
		_last_flash = 1.0
		GameState.set_audio_offset_ms(0.0, false)
		GameState.play_sfx("pluck", GameState.next_note() - 5.0, -6.0)
		return

	var nudge := 0.0
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
		nudge = -STEP_MS
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder"):
		nudge = STEP_MS
	if nudge != 0.0:
		_draft_ms = clampf(_draft_ms + nudge, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
		GameState.set_audio_offset_ms(_draft_ms, false)
		GameState.play_sfx("pluck", GameState.next_note(), -8.0)

	if Input.is_action_just_pressed("jump"):
		_register_tap()


func _register_tap() -> void:
	var b := Conductor.song_beat
	var nearest := roundf(b)
	var err_sec := (b - nearest) * Conductor.sec_per_beat
	_last_err_ms = err_sec * 1000.0
	_last_flash = 1.0
	if absf(err_sec) > MAX_ERR_SEC:
		GameState.play_sfx("miss", 0.0, -4.0)
		return
	## 正誤差＝相對時鐘按晚了（多半是聲音晚到）→ 加大 user_offset 讓時鐘後退對齊耳朵
	_draft_ms = clampf(_draft_ms + err_sec * 1000.0 * TAP_BLEND, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
	GameState.set_audio_offset_ms(_draft_ms, false)
	_tap_count += 1
	var grade := absf(_last_err_ms)
	if grade <= 30.0:
		GameState.play_sfx("pluck", GameState.next_note() + 12.0, -4.0)
	elif grade <= 60.0:
		GameState.play_sfx("pluck", GameState.next_note() + 5.0, -5.0)
	else:
		GameState.play_sfx("pluck", GameState.next_note(), -6.0)


func _commit() -> void:
	_committed = true
	GameState.set_audio_offset_ms(_draft_ms)
	GameState.play_sfx("cue", 0.0, -4.0)
	closed.emit()
	queue_free()


func _on_view_draw() -> void:
	var size := _view.size
	var safe := UiKit.safe_rect(size)
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(7.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.08, 0.82))

	var cx := safe.get_center().x
	var top := safe.position.y + 36.0
	var title := "音訊延遲校正"
	var tw := UiKit.width_of(title, 16) + 36.0
	UiKit.pill(_view, Vector2(cx - tw * 0.5, top), title, edge, UiKit.INK, 16)
	UiKit.text(_view, Vector2(safe.position.x, top + 48), safe.size.x,
		"聽到鼓點時按空白鍵　外圈收到中央就是拍點", 18, Color(1, 1, 1, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(_view, Vector2(safe.position.x, top + 76), safe.size.x,
		"耳機／網頁／藍牙常會讓聲音晚到，對完再進關", 15, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER)

	var center := Vector2(cx, safe.position.y + safe.size.y * 0.42)
	var radius := 88.0 + 10.0 * pulse + 14.0 * _beat_flash
	_view.draw_circle(center, radius + 18.0, Color(edge, 0.08 + 0.12 * pulse))
	_view.draw_arc(center, radius, 0.0, TAU, 64, Color(edge, 0.55 + 0.35 * pulse), 4.0, true)
	_view.draw_circle(center, 22.0 + 10.0 * pulse, edge.lerp(Color.WHITE, pulse))
	## frac 0＝剛過拍、接近 1＝下一拍將到；外圈收到中央時就是該按的瞬間
	var frac := Conductor.beat_fraction()
	var ring_r := lerpf(160.0, 28.0, frac)
	_view.draw_arc(center, ring_r, 0.0, TAU, 48, Color(UiKit.GOLD, 0.25 + 0.55 * frac), 3.0, true)

	var offset_label := "%+.0f ms" % _draft_ms
	var ow := UiKit.width_of(offset_label, 42, UiKit.title_font())
	UiKit.bold_text(_view, Vector2(cx - ow * 0.5, center.y + 150), -1, offset_label, 42, Color.WHITE, edge)
	var meaning := "剛好對齊"
	if _draft_ms > 2.0:
		meaning = "補償聲音偏晚"
	elif _draft_ms < -2.0:
		meaning = "補償聲音偏早"
	if _tap_count > 0:
		meaning = "%s　已對 %d 次" % [meaning, _tap_count]
	UiKit.text(_view, Vector2(safe.position.x, center.y + 178), safe.size.x, meaning, 16,
		Color(edge.lerp(Color.WHITE, 0.3), 0.9), HORIZONTAL_ALIGNMENT_CENTER)

	if _last_flash > 0.0:
		var a := _last_flash
		var tag := "早 %.0f ms" % absf(_last_err_ms) if _last_err_ms < 0.0 else "晚 %.0f ms" % absf(_last_err_ms)
		if absf(_last_err_ms) <= 30.0:
			tag = "完美　" + tag
		elif absf(_last_err_ms) <= 60.0:
			tag = "還行　" + tag
		var col := Color(0.45, 1.0, 0.7, a) if absf(_last_err_ms) <= 30.0 else Color(UiKit.GOLD, a)
		if absf(_last_err_ms) > 60.0:
			col = Color(1.0, 0.55, 0.5, a)
		UiKit.text(_view, Vector2(safe.position.x, center.y + 208), safe.size.x, tag, 20, col, HORIZONTAL_ALIGNMENT_CENTER)

	var tip_y := safe.end.y - 92.0
	UiKit.panel(_view, Rect2(cx - 320, tip_y - 8, 640, 78), edge, 0.0, 0.95, 12.0)
	UiKit.text(_view, Vector2(cx - 300, tip_y + 24), 600,
		"多按幾次收斂　←→ 每次 5 ms　R 歸零　Enter 完成　Esc 取消",
		15, Color(1, 1, 1, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.key_hints(_view, cx, tip_y + 42, [
		[["空白鍵"], "對拍"], [["←", "→"], "微調"], [["Enter"], "完成"], [["Esc"], "取消"],
	], edge, 0.9)
