class_name LatencyCalibrator
extends CanvasLayer
## 音訊延遲校正：4 拍預備 → 對拍約 4 小節 → 結果畫面用 ←→ 手動微調前後延遲，Enter 套用、Esc 取消還原。

signal closed

enum Phase { COUNT_IN, TAPPING, ADJUST }

const STEP_MS := 5.0
const STEP_HOLD_MS := 10.0
const HOLD_START := 0.35
const HOLD_REPEAT := 0.08
const MAX_ERR_SEC := 0.22
const TAP_BLEND := 0.55
## 預備拍數（聽到鼓點、先別按）
const COUNT_IN_BEATS := 4
## 對拍小節數（4/4 下＝16 拍）
const TAP_MEASURES := 4

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
var _phase: Phase = Phase.COUNT_IN
## 對齊「下一整拍」才開始數預備拍，避免開場卡在拍中間
var _anchor_beat: int = 0
var _nudge_dir: float = 0.0
var _nudge_hold: float = 0.0
var _nudge_flash: float = 0.0
var _nudge_label: String = ""


func _ready() -> void:
	layer = 22
	_opened_frame = Engine.get_process_frames()
	_saved_ms = GameState.audio_offset_ms
	_draft_ms = _saved_ms
	_anchor_beat = ceili(Conductor.song_beat)
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


func _tap_beats() -> int:
	return TAP_MEASURES * maxi(1, Conductor.beats_per_measure)


func _count_end() -> int:
	return _anchor_beat + COUNT_IN_BEATS


func _tap_end() -> int:
	return _count_end() + _tap_beats()


func _on_beat(beat_index: int) -> void:
	if beat_index == _last_beat:
		return
	_last_beat = beat_index
	if beat_index < _anchor_beat:
		return

	_beat_flash = 1.0
	var bpm_div := maxi(1, Conductor.beats_per_measure)
	var is_downbeat := posmod(beat_index, bpm_div) == 0

	if _phase == Phase.ADJUST:
		## 微調階段繼續給節拍，方便邊聽邊調
		GameState.play_sfx("cue", 7.0 if is_downbeat else 0.0, -10.0 if is_downbeat else -14.0)
		return

	if beat_index < _count_end():
		var step := beat_index - _anchor_beat
		GameState.play_sfx("cue", 12.0 if step == 0 else 5.0, -8.0 if step == 0 else -11.0)
		return

	if beat_index < _tap_end():
		GameState.play_sfx("cue", 7.0 if is_downbeat else 0.0, -10.0 if is_downbeat else -14.0)
		return

	if _phase == Phase.TAPPING:
		_finish_to_adjust()


func _process(delta: float) -> void:
	_beat_flash = move_toward(_beat_flash, 0.0, delta * 4.0)
	_last_flash = move_toward(_last_flash, 0.0, delta * 2.5)
	_nudge_flash = move_toward(_nudge_flash, 0.0, delta * 2.2)

	var b := floori(Conductor.song_beat)
	if _phase == Phase.COUNT_IN and b >= _count_end():
		_phase = Phase.TAPPING
	elif _phase == Phase.TAPPING and b >= _tap_end():
		_finish_to_adjust()

	_view.queue_redraw()
	if Engine.get_process_frames() == _opened_frame:
		return

	if Input.is_action_just_pressed("back"):
		GameState.play_sfx("pluck", GameState.next_note() - 12.0, -6.0)
		closed.emit()
		queue_free()
		return

	if Input.is_action_just_pressed("restart"):
		_restart_session()
		return

	if _phase == Phase.ADJUST:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
			_commit()
			return
		_handle_nudge(delta)
		return

	if Input.is_action_just_pressed("confirm"):
		if _tap_count >= 4:
			_finish_to_adjust()
		else:
			GameState.play_sfx("miss", 0.0, -6.0)
		return

	_handle_nudge(delta)

	if _phase == Phase.TAPPING and Input.is_action_just_pressed("jump"):
		_register_tap()


func _handle_nudge(delta: float) -> void:
	var left := Input.is_action_pressed("move_left") or Input.is_action_pressed("easier")
	var right := Input.is_action_pressed("move_right") or Input.is_action_pressed("harder")
	var dir := 0.0
	if left and not right:
		dir = -1.0
	elif right and not left:
		dir = 1.0

	if dir == 0.0:
		_nudge_dir = 0.0
		_nudge_hold = 0.0
		return

	if dir != _nudge_dir:
		_nudge_dir = dir
		_nudge_hold = 0.0
		_apply_nudge(dir * STEP_MS)
		return

	_nudge_hold += delta
	if _nudge_hold >= HOLD_START:
		_nudge_hold -= HOLD_REPEAT
		_apply_nudge(dir * STEP_HOLD_MS)


func _apply_nudge(amount: float) -> void:
	var before := _draft_ms
	_draft_ms = clampf(_draft_ms + amount, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
	if is_equal_approx(before, _draft_ms):
		return
	GameState.set_audio_offset_ms(_draft_ms, false)
	_nudge_flash = 1.0
	if amount < 0.0:
		_nudge_label = "提早 %.0f ms" % absf(amount)
	else:
		_nudge_label = "延後 %.0f ms" % absf(amount)
	GameState.play_sfx("pluck", GameState.next_note(), -8.0)


func _restart_session() -> void:
	_tap_count = 0
	_draft_ms = 0.0
	_last_err_ms = 0.0
	_last_flash = 1.0
	_nudge_flash = 0.0
	_nudge_label = ""
	_nudge_dir = 0.0
	_nudge_hold = 0.0
	_phase = Phase.COUNT_IN
	_anchor_beat = ceili(Conductor.song_beat)
	GameState.set_audio_offset_ms(0.0, false)
	GameState.play_sfx("pluck", GameState.next_note() - 5.0, -6.0)


func _finish_to_adjust() -> void:
	if _phase == Phase.ADJUST:
		return
	_phase = Phase.ADJUST
	_nudge_dir = 0.0
	_nudge_hold = 0.0
	GameState.set_audio_offset_ms(_draft_ms, false)
	GameState.play_sfx("cue", 0.0, -4.0)


func _register_tap() -> void:
	var beat := Conductor.song_beat
	var nearest := roundf(beat)
	var err_sec := (beat - nearest) * Conductor.sec_per_beat / maxf(Conductor.rate, 0.01)
	_last_err_ms = err_sec * 1000.0
	_last_flash = 1.0
	if absf(err_sec) > MAX_ERR_SEC:
		GameState.play_sfx("miss", 0.0, -4.0)
		return
	## 正誤差＝相對時鐘按晚了 → 加大 offset 讓時鐘後退對齊耳朵
	_draft_ms = clampf(
		_draft_ms + err_sec * 1000.0 * TAP_BLEND,
		GameState.AUDIO_OFFSET_MIN,
		GameState.AUDIO_OFFSET_MAX
	)
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

	var subtitle := ""
	var detail := ""
	match _phase:
		Phase.COUNT_IN:
			var remain: int = clampi(_count_end() - floori(Conductor.song_beat), 1, COUNT_IN_BEATS)
			subtitle = "先聽四拍　預備中"
			detail = "還有 %d 拍開始對拍　先別按" % remain
			if floori(Conductor.song_beat) >= _count_end() - 1:
				detail = "下一拍開始　跟著空白鍵打"
		Phase.TAPPING:
			var done := clampi(floori(Conductor.song_beat) - _count_end(), 0, _tap_beats())
			var bars_done := done / maxi(1, Conductor.beats_per_measure)
			subtitle = "跟著鼓點按空白鍵"
			detail = "第 %d／%d 小節　已對 %d 次" % [mini(bars_done + 1, TAP_MEASURES), TAP_MEASURES, _tap_count]
		Phase.ADJUST:
			subtitle = "手動微調延遲"
			detail = "看著圓圈聽鼓點：偏早按 ←，偏晚按 →，調到剛好再套用"

	UiKit.text(_view, Vector2(safe.position.x, top + 48), safe.size.x,
		subtitle, 18, Color(1, 1, 1, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(_view, Vector2(safe.position.x, top + 76), safe.size.x,
		detail, 15, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER)

	var center := Vector2(cx, safe.position.y + safe.size.y * 0.40)
	var radius := 88.0 + 10.0 * pulse + 14.0 * _beat_flash
	_view.draw_circle(center, radius + 18.0, Color(edge, 0.08 + 0.12 * pulse))
	_view.draw_arc(center, radius, 0.0, TAU, 64, Color(edge, 0.55 + 0.35 * pulse), 4.0, true)
	_view.draw_circle(center, 22.0 + 10.0 * pulse, edge.lerp(Color.WHITE, pulse))
	var frac := Conductor.beat_fraction()
	var ring_r := lerpf(160.0, 28.0, frac)
	var ring_col := Color(UiKit.GOLD, 0.25 + 0.55 * frac)
	if _phase == Phase.COUNT_IN:
		ring_col = Color(edge, 0.2 + 0.35 * frac)
	elif _phase == Phase.ADJUST:
		ring_col = Color(0.55, 1.0, 0.75, 0.3 + 0.5 * frac)
	_view.draw_arc(center, ring_r, 0.0, TAU, 48, ring_col, 3.0, true)

	## 進度：預備 4 拍 + 對拍 4 小節（微調階段視為已跑完）
	var total := float(COUNT_IN_BEATS + _tap_beats())
	var progressed := clampf(float(floori(Conductor.song_beat) - _anchor_beat), 0.0, total)
	if _phase == Phase.ADJUST:
		progressed = total
	var bar := Rect2(cx - 160.0, center.y + 112.0, 320.0, 10.0)
	_view.draw_rect(bar, Color(1, 1, 1, 0.12), true)
	_view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * (progressed / total), bar.size.y)),
		Color(edge, 0.85), true)
	var split_x := bar.position.x + bar.size.x * (float(COUNT_IN_BEATS) / total)
	_view.draw_line(Vector2(split_x, bar.position.y - 2.0), Vector2(split_x, bar.end.y + 2.0),
		Color(1, 1, 1, 0.35), 2.0)

	_draw_offset_slider(cx, center.y + 148.0, edge)

	var offset_label := "%+.0f ms" % _draft_ms
	var ow := UiKit.width_of(offset_label, 42, UiKit.title_font())
	UiKit.bold_text(_view, Vector2(cx - ow * 0.5, center.y + 188), -1, offset_label, 42, Color.WHITE, edge)
	var meaning := "剛好對齊"
	if _draft_ms > 2.0:
		meaning = "補償聲音偏晚"
	elif _draft_ms < -2.0:
		meaning = "補償聲音偏早"
	if _phase == Phase.ADJUST:
		meaning = "聽鼓點調到舒服　%s" % meaning
	UiKit.text(_view, Vector2(safe.position.x, center.y + 216), safe.size.x, meaning, 16,
		Color(edge.lerp(Color.WHITE, 0.3), 0.9), HORIZONTAL_ALIGNMENT_CENTER)

	if _nudge_flash > 0.0 and _nudge_label != "":
		UiKit.text(_view, Vector2(safe.position.x, center.y + 240), safe.size.x, _nudge_label, 18,
			Color(UiKit.GOLD, _nudge_flash), HORIZONTAL_ALIGNMENT_CENTER)
	elif _last_flash > 0.0 and _phase == Phase.TAPPING:
		var a := _last_flash
		var tag := "早 %.0f ms" % absf(_last_err_ms) if _last_err_ms < 0.0 else "晚 %.0f ms" % absf(_last_err_ms)
		if absf(_last_err_ms) <= 30.0:
			tag = "完美　" + tag
		elif absf(_last_err_ms) <= 60.0:
			tag = "還行　" + tag
		var col := Color(0.45, 1.0, 0.7, a) if absf(_last_err_ms) <= 30.0 else Color(UiKit.GOLD, a)
		if absf(_last_err_ms) > 60.0:
			col = Color(1.0, 0.55, 0.5, a)
		UiKit.text(_view, Vector2(safe.position.x, center.y + 240), safe.size.x, tag, 20, col, HORIZONTAL_ALIGNMENT_CENTER)

	var tip_y := safe.end.y - 92.0
	UiKit.panel(_view, Rect2(cx - 340, tip_y - 8, 680, 78), edge, 0.0, 0.95, 12.0)
	var tip := "先聽四拍，再跟著打四小節；打完可手動微調延遲"
	if _phase == Phase.TAPPING:
		tip = "空白鍵對拍　←→ 也可微調　對夠可 Enter 進入微調"
	elif _phase == Phase.ADJUST:
		tip = "← 感覺偏早　→ 感覺偏晚　長按加速　調好按 Enter 套用"
	UiKit.text(_view, Vector2(cx - 320, tip_y + 18), 640, tip, 15, Color(1, 1, 1, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	match _phase:
		Phase.TAPPING:
			UiKit.key_hints(_view, cx, tip_y + 44, [
				[["空白鍵"], "對拍"], [["←", "→"], "微調"], [["Enter"], "微調頁"], [["R"], "重來"], [["Esc"], "取消"],
			], edge, 0.9)
		Phase.ADJUST:
			UiKit.key_hints(_view, cx, tip_y + 44, [
				[["←"], "提早"], [["→"], "延後"], [["Enter"], "套用"], [["R"], "重來"], [["Esc"], "取消"],
			], edge, 0.9)
		_:
			UiKit.key_hints(_view, cx, tip_y + 44, [
				[["←", "→"], "微調"], [["Esc"], "取消"],
			], edge, 0.9)


func _draw_offset_slider(cx: float, y: float, edge: Color) -> void:
	var half := 170.0
	var track := Rect2(cx - half, y, half * 2.0, 8.0)
	_view.draw_rect(track, Color(1, 1, 1, 0.12), true)
	_view.draw_line(Vector2(cx, y - 4.0), Vector2(cx, y + 12.0), Color(1, 1, 1, 0.28), 2.0)
	var t := inverse_lerp(GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX, _draft_ms)
	var knox := lerpf(track.position.x, track.end.x, t)
	_view.draw_circle(Vector2(knox, y + 4.0), 9.0, edge)
	_view.draw_circle(Vector2(knox, y + 4.0), 4.0, Color.WHITE)
	UiKit.text(_view, Vector2(track.position.x - 8.0, y + 16.0), 80, "← 提早", 13,
		Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT)
	UiKit.text(_view, Vector2(track.end.x - 72.0, y + 16.0), 80, "延後 →", 13,
		Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
