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
const TAP_BEATS := 8
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
	Conductor.beat.connect(_on_beat)
	## 校正時把背景音樂壓低，鼓聲才聽得清楚
	_duck_before = Conductor.duck_target
	Conductor.duck_target = 0.85


func _exit_tree() -> void:
	if Conductor.beat.is_connected(_on_beat):
		Conductor.beat.disconnect(_on_beat)
	Conductor.duck_target = _duck_before
	if not _committed:
		GameState.set_audio_offset_ms(_saved_ms, true)


# ---------------------------------------------------------------- 流程

func _start() -> void:
	_phase = Phase.COUNT_IN
	_errors.clear()
	_too_few = false
	## 量測時用原本的設定當基準，量完再一次算好新的值
	GameState.set_audio_offset_ms(_saved_ms, false)
	_start_beat = ceili(Conductor.song_beat)
	GameState.play_sfx("pluck", 7.0, -6.0)


func _on_beat(beat_index: int) -> void:
	if beat_index == _last_beat:
		return
	_last_beat = beat_index
	if _phase == Phase.INTRO or _phase == Phase.RESULT:
		return
	if beat_index < _start_beat:
		return
	var step := beat_index - _start_beat
	if step < COUNT_IN_BEATS + TAP_BEATS:
		## 鼓聲：每小節第一下高一點
		var down := step % 4 == 0
		GameState.play_sfx("cue", 7.0 if down else 0.0, -4.0 if down else -7.0)
	if step == COUNT_IN_BEATS:
		_phase = Phase.TAPPING
	elif step >= COUNT_IN_BEATS + TAP_BEATS:
		_finish()


func _finish() -> void:
	_phase = Phase.RESULT
	if _errors.size() < MIN_TAPS:
		_too_few = true
		_result_ms = _saved_ms
		GameState.play_sfx("miss", 0.0, -6.0)
		return
	var sorted := _errors.duplicate()
	sorted.sort()
	var mid: float = sorted[sorted.size() / 2]
	## 按得晚（正）＝聲音比時鐘晚 → 延遲加大
	_result_ms = clampf(_saved_ms + mid * 1000.0, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
	GameState.set_audio_offset_ms(_result_ms, false)
	GameState.play_sfx("cue", 12.0, -4.0)


func _tap() -> void:
	match _phase:
		Phase.INTRO:
			_start()
		Phase.TAPPING:
			var beat := Conductor.song_beat
			var err := (beat - roundf(beat)) * Conductor.sec_per_beat / maxf(Conductor.rate, 0.01)
			_hit = 1.0
			_hit_err = err
			if absf(err) <= MAX_ERR_SEC:
				_errors.append(err)
				GameState.play_sfx("pluck", GameState.next_note() + 12.0, -8.0)
		Phase.RESULT:
			if _too_few:
				_start()
			else:
				_commit()


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
		if _phase == Phase.RESULT and not _too_few and _again_rect().has_point(mb.position):
			_start()
			return
		_tap()
		return
	var st := event as InputEventScreenTouch
	if st and st.pressed:
		_tap()


func _process(delta: float) -> void:
	_hit = move_toward(_hit, 0.0, delta * 4.0)
	_age += delta
	_view.queue_redraw()
	if Engine.get_process_frames() == _opened_frame or _age < INPUT_GRACE:
		return
	if Input.is_action_just_pressed("back"):
		_skip()
		return
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("confirm"):
		_tap()
		return
	if _phase == Phase.RESULT:
		if Input.is_action_just_pressed("restart"):
			_start()
		elif not _too_few:
			var step := 0.0
			if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
				step = -NUDGE_MS
			elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder"):
				step = NUDGE_MS
			if step != 0.0:
				_result_ms = clampf(_result_ms + step, GameState.AUDIO_OFFSET_MIN, GameState.AUDIO_OFFSET_MAX)
				GameState.set_audio_offset_ms(_result_ms, false)
				GameState.play_sfx("pluck", GameState.next_note(), -8.0)


# ---------------------------------------------------------------- 畫面

func _again_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 - 250, size.y * 0.5 + 170, 220, 64)


func _ok_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 + 30, size.y * 0.5 + 170, 220, 64)


func _on_view_draw() -> void:
	var size := _view.size
	var c := size * 0.5
	_view.draw_rect(Rect2(Vector2.ZERO, size), UiKit.NIGHT)
	var drum := c + Vector2(0, -40)
	match _phase:
		Phase.INTRO:
			_draw_drum(drum, 1.0, 0.0)
			_line(c.y + 110, "聽到鼓聲時，按空白鍵", 30, UiKit.TEXT)
			_line(c.y + 150, "也可以點一下畫面", 18, UiKit.MUTED)
			_draw_key_prompt(c.y + 210, "空白鍵", "開始")
			if first_run:
				_line(size.y - 74, "先校正一次，節奏會比較準。之後可以在主選單按 O 再校正", 15, UiKit.MUTED)
			_line(size.y - 40, "Esc 跳過", 15, UiKit.MUTED)
		Phase.COUNT_IN:
			var left: int = clampi(_start_beat + COUNT_IN_BEATS - floori(Conductor.song_beat), 1, COUNT_IN_BEATS)
			if Conductor.song_beat < float(_start_beat):
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
				_draw_check(drum)
				_line(c.y + 100, "好了！", 34, UiKit.TEXT)
				_line(c.y + 140, _verdict(), 18, UiKit.MUTED)
				UiKit.solid_button(_view, _again_rect(), "R　再測一次", UiKit.CYAN, Color("2A8C97"), 18)
				UiKit.solid_button(_view, _ok_rect(), "空白鍵　開始玩", UiKit.PINK, UiKit.PINK_DARK, 18)
				_line(size.y - 40, "覺得還是不準？ ← 提早一點　→ 延後一點", 15, UiKit.MUTED)


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
