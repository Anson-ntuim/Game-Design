class_name LatencyCalibrator
extends CanvasLayer
## 聲音延遲校正（第一次開遊戲會自動跳出，之後主選單按 O）：
##   ① 說明：一個鼓＋一句話「聽到鼓聲就按空白鍵」，按一下開始
##   ② 預備：先聽 4 下鼓聲（畫面上數 4、3、2、1）
##   ③ 對拍：跟著鼓聲按 8 下。這時畫面不跟拍子動，只在「你按下去」時鼓彈一下，才量得到耳朵聽到的時間
##   ④ 結果：用中位數算出延遲並套用；可以再測一次，覺得還是不準再用 ←→ 微調
## 空白鍵、Enter、滑鼠左鍵、觸控都算「按」。Esc 跳過（保留原本的設定）。

signal closed

enum Phase { INTRO, COUNT_IN, TAPPING, RESULT }

const COUNT_IN_BEATS := 4
const TAP_BEATS := 12
## 前幾下當暖身不算（剛開始常常抓不準）
const WARMUP_TAPS := 2
## 按的時間離最近一拍超過這麼多秒就不算（大概是亂按）
const MAX_ERR_SEC := 0.22
## 至少要對到幾下才算數
const MIN_TAPS := 5
const NUDGE_MS := 5.0

## 第一次開遊戲時跳出：說明頁多一句「之後可以在主選單重新校正」
var first_run: bool = false

var _view: Control
var _phase: Phase = Phase.INTRO
var _saved_ms: float = 0.0
var _result_ms: float = 0.0
var _errors: Array[float] = []
## 確認頁試按的誤差（秒，最近 8 下）
var _tests: Array[float] = []
var _start_beat: int = 0
var _last_beat: int = -9999
var _hit: float = 0.0
var _hit_err: float = 0.0
var _opened_frame: int = 0
var _committed: bool = false
var _too_few: bool = false
var _duck_before: float = 0.0
## 剛打開的這段時間不收輸入（上一個畫面按的鍵、點擊不要直接帶進來）
const INPUT_GRACE := 0.6
var _age: float = 0.0
## 說明頁／預備時鼓聲響起的小喇叭動畫（對拍時不顯示，避免看畫面按）
var _ping: float = 0.0


func _ready() -> void:
	layer = 22
	_opened_frame = Engine.get_process_frames()
	_saved_ms = GameState.audio_offset_ms
	_result_ms = _saved_ms
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_view)
	_view.draw.connect(_on_view_draw)
	_view.gui_input.connect(_on_gui_input)
	## 校正時把背景音樂幾乎關掉，只聽得到鼓聲
	_duck_before = Conductor.duck_target
	Conductor.duck_target = 1.0


func _exit_tree() -> void:
	Conductor.duck_target = _duck_before
	if not _committed:
		GameState.set_audio_offset_ms(_saved_ms, true)


# ---------------------------------------------------------------- 流程

func _start() -> void:
	_phase = Phase.COUNT_IN
	_errors.clear()
	_tests.clear()
	_too_few = false
	## 量測時用原本的設定當基準，量完再一次算好新的值
	GameState.set_audio_offset_ms(_saved_ms, false)
	_start_beat = ceili(_raw_beat())
	GameState.play_sfx("pluck", 7.0, -6.0)


## 不含玩家目前延遲設定的拍子：鼓聲和量測都用這個，校正結果才不會一次比一次偏
## （以前用含延遲的拍子，鼓聲跟著舊設定移動，量到的誤差又加回去，會越校越大）
func _raw_beat() -> float:
	return Conductor.audio_beat


func _on_beat(beat_index: int) -> void:
	if beat_index == _last_beat:
		return
	_last_beat = beat_index
	if _phase == Phase.RESULT:
		## 確認頁：鼓繼續打，讓玩家對照落下的球
		if not _too_few:
			_drum(posmod(beat_index, 4) == 0)
		return
	## 說明頁也一直打鼓：一打開就聽得到「要跟的是這個聲音」（沒聲音也馬上知道要開喇叭）
	if _phase == Phase.INTRO:
		_drum(posmod(beat_index, 4) == 0)
		return
	if beat_index < _start_beat:
		return
	var step := beat_index - _start_beat
	if step < COUNT_IN_BEATS + TAP_BEATS:
		_drum(step % 4 == 0)
	if step == COUNT_IN_BEATS:
		_phase = Phase.TAPPING
	elif step >= COUNT_IN_BEATS + TAP_BEATS:
		_finish()


## 鼓聲：拍手＋提示音疊在一起，夠大聲、起音清楚；每小節第一下高一點
func _drum(down: bool) -> void:
	GameState.play_sfx("clap", 0.0, 0.0 if down else -2.0)
	GameState.play_sfx("cue", 7.0 if down else 0.0, -1.0 if down else -3.0)
	_ping = 1.0


func _finish() -> void:
	_phase = Phase.RESULT
	if _errors.size() < MIN_TAPS:
		_too_few = true
		_result_ms = _saved_ms
		GameState.play_sfx("miss", 0.0, -6.0)
		return
	## 去掉暖身的前幾下，取中位數（偶爾按歪一兩下不影響）
	var used := _errors.slice(mini(WARMUP_TAPS, _errors.size() - MIN_TAPS))
	used.sort()
	var mid: float = used[used.size() / 2]
	## 鼓聲用提示音時計，已經提早了「裝置回報的輸出延遲」，和音樂同時到耳朵；
	## 所以按鍵比拍子晚多少，就是玩家設定要補的（藍牙耳機、瀏覽器額外的延遲）。每次重算，不疊加在舊設定上
	var ms := mid * 1000.0
	_result_ms = clampf(ms, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
	GameState.set_audio_offset_ms(_result_ms, false)
	GameState.play_sfx("cue", 12.0, -4.0)


func _tap() -> void:
	match _phase:
		Phase.INTRO:
			_start()
		Phase.TAPPING:
			var beat := _raw_beat()
			var err := (beat - roundf(beat)) * Conductor.sec_per_beat / maxf(Conductor.rate, 0.01)
			_hit = 1.0
			_hit_err = err
			## 按下去不出聲：自己的按鍵聲會干擾對鼓聲的判斷
			if absf(err) <= MAX_ERR_SEC:
				_errors.append(err)
		Phase.RESULT:
			if _too_few:
				_start()
			else:
				_test_tap()


## 確認頁的試按：用目前的設定（song_beat，已扣延遲）量早晚，只顯示不改設定
func _test_tap() -> void:
	var b := Conductor.song_beat
	var err := (b - roundf(b)) * Conductor.sec_per_beat / maxf(Conductor.rate, 0.01)
	_hit = 1.0
	_hit_err = err
	if absf(err) <= MAX_ERR_SEC:
		_tests.append(err)
		if _tests.size() > 8:
			_tests.pop_front()


## 試按的平均（秒）
func _test_mean() -> float:
	if _tests.is_empty():
		return 0.0
	var t := 0.0
	for e in _tests:
		t += e
	return t / float(_tests.size())


## 照試按的平均修正：平均按晚（正）＝畫面／判定太早 → 延遲加大
func _apply_tests() -> void:
	if _tests.size() < 3:
		return
	_nudge(_test_mean() * 1000.0)
	_tests.clear()


func _nudge(ms: float) -> void:
	_result_ms = clampf(_result_ms + ms, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
	GameState.set_audio_offset_ms(_result_ms, false)
	GameState.play_sfx("pluck", GameState.next_note(), -8.0)


func _commit() -> void:
	_committed = true
	GameState.set_audio_offset_ms(_result_ms)
	GameState.calibration_done = true
	GameState.save_settings()
	GameState.play_sfx("pluck", 12.0, -6.0)
	closed.emit()
	queue_free()


func _skip() -> void:
	GameState.calibration_done = true
	GameState.save_settings()
	closed.emit()
	queue_free()


# ---------------------------------------------------------------- 輸入

func _on_gui_input(event: InputEvent) -> void:
	if _age < INPUT_GRACE:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _phase == Phase.RESULT and not _too_few:
			if _again_rect().has_point(mb.position):
				_start()
			elif _ok_rect().has_point(mb.position):
				_commit()
			elif _minus_rect().has_point(mb.position):
				_nudge(-NUDGE_MS)
			elif _plus_rect().has_point(mb.position):
				_nudge(NUDGE_MS)
			elif _fix_rect().has_point(mb.position):
				_apply_tests()
			else:
				_test_tap()
			return
		_tap()
		return
	var st := event as InputEventScreenTouch
	## 觸控會再模擬成滑鼠點擊（上面處理），這裡只處理沒有模擬滑鼠的情況
	if st and st.pressed and not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true):
		_tap()


func _process(delta: float) -> void:
	_hit = move_toward(_hit, 0.0, delta * 4.0)
	## 自己追拍子（不用 Conductor.beat：那是含延遲設定的拍子）
	## 鼓聲用提示音時計（和遊戲裡的提示音一樣提早一點點），按鍵量測照 _raw_beat
	var rb := floori(Conductor.calib_cue_beat)
	if rb != _last_beat:
		_on_beat(rb)
	_age += delta
	_ping = move_toward(_ping, 0.0, delta * 3.0)
	_view.queue_redraw()
	if Engine.get_process_frames() == _opened_frame or _age < INPUT_GRACE:
		return
	if Input.is_action_just_pressed("back"):
		_skip()
		return
	var checking := _phase == Phase.RESULT and not _too_few
	## 確認頁：Enter 完成；空白鍵是試按（不是確定）
	if checking and Input.is_action_just_pressed("confirm"):
		_commit()
		return
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("confirm"):
		_tap()
		return
	if _phase == Phase.RESULT:
		if Input.is_action_just_pressed("restart"):
			_start()
		elif checking:
			if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
				_nudge(-NUDGE_MS)
			elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder"):
				_nudge(NUDGE_MS)
			elif Input.is_action_just_pressed("up"):
				_apply_tests()


# ---------------------------------------------------------------- 畫面

func _again_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 - 250, size.y - 96, 220, 60)


func _ok_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 + 30, size.y - 96, 220, 60)


## 確認頁：延遲 −／＋ 按鈕和「照試按修正」
func _minus_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 - 300, size.y * 0.5 + 92, 190, 52)


func _plus_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 + 110, size.y * 0.5 + 92, 190, 52)


func _fix_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 + 170, size.y * 0.5 + 172, 130, 40)


func _on_view_draw() -> void:
	var size := _view.size
	var c := size * 0.5
	_view.draw_rect(Rect2(Vector2.ZERO, size), UiKit.NIGHT)
	var drum := c + Vector2(0, -40)
	match _phase:
		Phase.INTRO:
			_draw_drum(drum, 1.0, 0.0)
			_line(c.y + 110, "聽到鼓聲時，按空白鍵", 30, UiKit.TEXT)
			_draw_speaker(Vector2(c.x + 150, drum.y - 40))
			_line(c.y + 150, "也可以點一下畫面", 18, UiKit.MUTED)
			_draw_key_prompt(c.y + 210, "空白鍵", "開始")
			if first_run:
				_line(size.y - 74, "先校正一次，節奏會比較準。之後可以在主選單按 O 再校正", 15, UiKit.MUTED)
			_line(size.y - 40, "Esc 跳過", 15, UiKit.MUTED)
		Phase.COUNT_IN:
			var left: int = clampi(_start_beat + COUNT_IN_BEATS - floori(_raw_beat()), 1, COUNT_IN_BEATS)
			if _raw_beat() < float(_start_beat):
				left = COUNT_IN_BEATS
			_draw_drum(drum, 0.55, 0.0)
			var p := Conductor.pulse(6.0)
			var n := str(left)
			var f := UiKit.title_font()
			var fs := int(120 + 30 * p)
			var w := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_view.draw_string(f, Vector2(c.x - w * 0.5, drum.y + fs * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.YELLOW, 0.9))
			_line(c.y + 110, "先聽，還不要按", 30, UiKit.TEXT)
		Phase.TAPPING:
			## 這時候畫面不跟拍子動：只有按下去的那一刻鼓會彈，才量得到耳朵的時間
			_draw_drum(drum, 1.0, _hit)
			_line(c.y + 110, "跟著鼓聲按", 30, UiKit.TEXT)
			_draw_progress(c.y + 160)
		Phase.RESULT:
			if _too_few:
				_draw_drum(drum, 0.55, 0.0)
				_line(c.y + 110, "沒有對到幾下，再試一次", 30, UiKit.TEXT)
				_draw_key_prompt(c.y + 190, "空白鍵", "再試一次")
				_line(size.y - 40, "Esc 跳過", 15, UiKit.MUTED)
			else:
				_draw_check_page(c, drum)


## 確認頁：球落到鼓上（畫面拍子）和鼓聲（聲音拍子）是不是同時；不同時就 −／＋ 調，或跟著鼓按幾下自動修正
func _draw_check_page(c: Vector2, drum: Vector2) -> void:
	var size := _view.size
	_line(c.y - 290, "確認一下：球落到鼓上的那一刻，剛好聽到鼓聲嗎？", 24, UiKit.TEXT)
	_line(c.y - 258, _verdict(), 16, UiKit.MUTED)
	## 鼓＋落下的球（用 song_beat：已扣延遲的畫面拍子）
	var b := Conductor.song_beat
	var f := fposmod(b, 1.0)
	var land := 1.0 - minf(f * 6.0, 1.0)
	_draw_drum(drum + Vector2(0, 20), 1.0, maxf(_hit, land * 0.6))
	var top := drum.y + 20 - 74.0
	var ball_y := top - 100.0 * 4.0 * f * (1.0 - f) - 14.0
	_view.draw_circle(Vector2(drum.x, ball_y), 14.0, UiKit.YELLOW)
	_view.draw_arc(Vector2(drum.x, ball_y), 14.0, 0.0, TAU, 24, UiKit.INK, 2.5, true)
	## −／＋ 和目前數值
	UiKit.solid_button(_view, _minus_rect(), "← 球太晚", UiKit.TEXT, UiKit.LINE, 18)
	UiKit.solid_button(_view, _plus_rect(), "球太早 →", UiKit.TEXT, UiKit.LINE, 18)
	UiKit.text(_view, Vector2(c.x - 100, c.y + 128), 200, "%+.0f ms" % _result_ms, 26, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, UiKit.display_font(700))
	## 試按：最近 8 下落在早／晚哪邊
	var bar := Rect2(c.x - 300, c.y + 190, 440, 6)
	_view.draw_rect(bar, Color(UiKit.LINE, 0.9))
	var mid := bar.position.x + bar.size.x * 0.5
	_view.draw_line(Vector2(mid, bar.position.y - 10), Vector2(mid, bar.end.y + 10), UiKit.TEXT, 2.0)
	UiKit.text(_view, Vector2(bar.position.x, bar.position.y - 12), -1, "早", 14, UiKit.MUTED)
	UiKit.text(_view, Vector2(bar.end.x - 16, bar.position.y - 12), -1, "晚", 14, UiKit.MUTED)
	for e in _tests:
		var x := clampf(mid + e / MAX_ERR_SEC * bar.size.x * 0.5, bar.position.x, bar.end.x)
		_view.draw_circle(Vector2(x, bar.get_center().y), 6.0, UiKit.CYAN)
	var hint := "跟著鼓聲按空白鍵（或點鼓）試幾下"
	if _tests.size() >= 3:
		var m := _test_mean() * 1000.0
		hint = "你平均按得剛好" if absf(m) < 15.0 else ("你平均按晚 %d ms" % roundi(m) if m > 0.0 else "你平均按早 %d ms" % roundi(-m))
	UiKit.text(_view, Vector2(bar.position.x, bar.position.y + 32), -1, hint, 15, UiKit.TEXT)
	if _tests.size() >= 3:
		UiKit.solid_button(_view, _fix_rect(), "↑ 照這個修正", UiKit.CYAN, Color("2A8C97"), 15)
	UiKit.solid_button(_view, _again_rect(), "R　重新測", UiKit.TEXT, UiKit.LINE, 18)
	UiKit.solid_button(_view, _ok_rect(), "Enter　完成", UiKit.PINK, UiKit.PINK_DARK, 18)
	_line(size.y - 18, "Esc 取消（用原本的設定）", 13, UiKit.MUTED)


## 結果一句話：不講毫秒，講「快／慢」
func _verdict() -> String:
	var ms := _result_ms
	if absf(ms) < 15.0:
		return "你的聲音幾乎沒有延遲"
	if ms > 0.0:
		return "你的聲音大約慢了 %d 毫秒，已經幫你對齊" % roundi(ms)
	return "你的聲音大約快了 %d 毫秒，已經幫你對齊" % roundi(-ms)


func _line(y: float, s: String, size: int, col: Color) -> void:
	UiKit.text(_view, Vector2(0, y), _view.size.x, s, size, col, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))


## 鼓（assets/ui/drum.png 手繪圖）；hit > 0 時鼓往下壓一點、上面擴一圈
const DRUM_TEX := preload("res://assets/ui/drum.png")


func _draw_drum(at: Vector2, alpha: float, hit: float) -> void:
	var w := 210.0
	var h := w * float(DRUM_TEX.get_height()) / float(DRUM_TEX.get_width())
	var squash := 1.0 - 0.12 * hit
	var stretch := 1.0 + 0.05 * hit
	var size := Vector2(w * stretch, h * squash)
	## 底部固定，壓下去是往下扁
	var rect := Rect2(Vector2(at.x - size.x * 0.5, at.y + h * 0.5 - size.y), size)
	_view.draw_texture_rect(DRUM_TEX, rect, false, Color(1, 1, 1, alpha))
	if hit > 0.0:
		var r := 110.0 + (1.0 - hit) * 60.0
		var col := Color(0.55, 1.0, 0.7) if absf(_hit_err) <= 0.04 else UiKit.YELLOW
		_view.draw_arc(Vector2(at.x, rect.position.y + h * 0.35), r, PI, TAU, 40, Color(col, hit), 4.0, true)


## 小喇叭＋聲波：鼓響的時候亮一下，提醒「現在應該聽得到聲音」
func _draw_speaker(at: Vector2) -> void:
	var col := Color(UiKit.YELLOW, 0.5 + 0.5 * _ping)
	_view.draw_colored_polygon(PackedVector2Array([at + Vector2(-14, -8), at + Vector2(-6, -8), at + Vector2(4, -18),
		at + Vector2(4, 18), at + Vector2(-6, 8), at + Vector2(-14, 8)]), col)
	for i in 2:
		_view.draw_arc(at + Vector2(6, 0), 12.0 + i * 9.0, -0.8, 0.8, 12, Color(col, col.a * (1.0 - i * 0.35) * (0.4 + 0.6 * _ping)), 3.0, true)


func _draw_check(at: Vector2) -> void:
	_view.draw_circle(at, 70.0, Color(UiKit.PINK, 0.95))
	_view.draw_polyline(PackedVector2Array([at + Vector2(-30, 2), at + Vector2(-8, 24), at + Vector2(34, -22)]), UiKit.TEXT, 12.0, true)


## 8 個點：按到一下亮一個
func _draw_progress(y: float) -> void:
	var gap := 30.0
	var x0 := _view.size.x * 0.5 - gap * (TAP_BEATS - 1) * 0.5
	for i in TAP_BEATS:
		var on := i < _errors.size()
		_view.draw_circle(Vector2(x0 + i * gap, y), 9.0 if on else 6.0, Color(UiKit.YELLOW if on else UiKit.LINE, 1.0 if on else 0.8))


func _draw_key_prompt(y: float, key: String, label: String) -> void:
	var kw := UiKit.width_of(key, 16) + 28.0
	var lw := UiKit.width_of(label, 20)
	var x := _view.size.x * 0.5 - (kw + 12.0 + lw) * 0.5
	var key_rect := Rect2(x, y - 22, kw, 40)
	UiKit.solid_button(_view, key_rect, key, UiKit.TEXT, UiKit.LINE, 16)
	UiKit.text(_view, Vector2(x + kw + 12.0, y + 6), -1, label, 20, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
