extends Node2D
## 主選單與選關（照設計稿「Heart Beat UI 改版提案」的主選單、選擇關卡兩個畫面）。
##   主選單：大標題、角色、四個按鈕（開始遊戲＝接續上次的關、選擇關卡、自訂音樂、設定）。
##   選擇關卡：關卡卡片沿著一條路線排、右邊是選中那關的詳細資料、判定難度和開始按鈕。
##   設定：用暫停選單同一個面板（PauseMenu），左邊換成返回、延遲校正、機關說明。
## 從遊戲裡「回選關」會直接進到選擇關卡（GameState 的 meta "home_screen"）。

const MAIN_SCENE := "res://scenes/main.tscn"
## 關卡卡片的場景縮圖：背景主題 → 天空、近景兩層
const THUMBS := {
	"calm_city": ["res://assets/themes/heartbeat_city/bg/sky.png", "res://assets/themes/heartbeat_city/bg/city_near.png"],
	"sakura_park": ["res://assets/themes/sakura_park/bg/sky.png", "res://assets/themes/sakura_park/bg/park_near.png"],
	"music_festival": ["res://assets/themes/music_festival/bg/sky.png", "res://assets/themes/music_festival/bg/festival_near.png"],
	## 和關卡內背景（scripts/level/background.gd）用同一組圖層
	"rainy_street": ["res://assets/themes/rainy_street/bg/sky_base.png", "res://assets/themes/rainy_street/bg/city_far.png",
		"res://assets/themes/rainy_street/bg/street_mid.png", "res://assets/themes/rainy_street/bg/promenade_near.png"],
	"broken_memory": ["res://assets/themes/broken_memory/bg/sky.png", "res://assets/themes/broken_memory/bg/city.png",
		"res://assets/themes/broken_memory/bg/bridge.png"],
}
const MENU_ITEMS := ["開始遊戲", "選擇關卡", "自訂音樂", "設定"]

enum Screen { MAIN, LEVELS }

static var _thumb_cache: Dictionary = {}

var _screen: Screen = Screen.MAIN
var _menu_row: int = 0
var _selected: int = 0
var _view: Control
var _camera: Camera2D
var _fade: float = 1.0
var _fade_out: float = 0.0
var _bump: float = 0.0
var _input_lock: float = 0.35
var _starting: bool = false
var _guide: MechanicGuide
var _calibrator: LatencyCalibrator
var _music_setup: MusicSetup
var _settings: PauseMenu
var _quality_picker: QualityPicker
var _skin_bump: float = 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	_selected = clampi(GameState.level_index, 0, maxi(0, LevelData.visible_count() - 1))
	GameState.level_index = _selected
	if String(GameState.get_meta("home_screen", "")) == "levels":
		_screen = Screen.LEVELS
	GameState.set_meta("home_screen", "")

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

	GameState.reset_stats()
	Conductor.start(false, not (Conductor.custom_music and Conductor.is_music_playing()))
	var tw := create_tween()
	tw.tween_property(self, "_fade", 0.0, 0.6).set_ease(Tween.EASE_OUT)
	## 第一次開遊戲：先做聲音延遲校正
	## 第一次開遊戲：先做聲音延遲校正，接著選畫面品質
	if not GameState.calibration_done:
		_open_calibrator()
		_calibrator.first_run = true
		_calibrator.closed.connect(_open_quality_picker)


func _process(delta: float) -> void:
	_camera.position.x += 28.0 * delta
	_input_lock = maxf(0.0, _input_lock - delta)
	_bump = move_toward(_bump, 0.0, delta * 4.0)
	_skin_bump = move_toward(_skin_bump, 0.0, delta * 4.0)
	_view.queue_redraw()
	if _fade_out > 0.0:
		_fade_out = minf(1.0, _fade_out + delta * 2.4)
		if _fade_out >= 1.0 and _starting:
			get_tree().change_scene_to_file(MAIN_SCENE)
		return
	if _starting or _fade > 0.05 or _input_lock > 0.0 or _overlay_open():
		return
	if Input.is_action_just_pressed("guide"):
		_open_guide()
	elif Input.is_action_just_pressed("calibrate"):
		_open_calibrator()
	elif Input.is_action_just_pressed("music_setup"):
		_open_music_setup()
	elif _screen == Screen.MAIN:
		_handle_main()
	else:
		_handle_levels()


func _overlay_open() -> bool:
	return is_instance_valid(_guide) or is_instance_valid(_calibrator) or is_instance_valid(_music_setup) \
		or is_instance_valid(_settings) or is_instance_valid(_quality_picker)


## 「開始遊戲」接續的關卡：還沒通關的第一關，全破就是上次玩的那關
func _continue_level() -> int:
	for i in LevelData.visible_count():
		if not GameState.records.has(i):
			return i
	return clampi(GameState.level_index, 0, LevelData.visible_count() - 1)


func _open_quality_picker() -> void:
	_quality_picker = QualityPicker.new()
	add_child.call_deferred(_quality_picker)


## 主畫面換角色（← → 或點角色兩邊的箭頭）
func _change_skin(step: int) -> void:
	GameState.set_skin(GameState.skin + step)
	_skin_bump = 1.0
	GameState.play_sfx("pluck", 7.0 + step * 2.0, -6.0)


func _skin_center() -> Vector2:
	var size := _view.size
	return Vector2(size.x - 330, size.y - 70)


func _skin_arrow_rect(dir: int) -> Rect2:
	var c := _skin_center() + Vector2(dir * 215.0, -200.0)
	return Rect2(c - Vector2(30, 30), Vector2(60, 60))


func _handle_main() -> void:
	if Input.is_action_just_pressed("move_left"):
		_change_skin(-1)
		return
	if Input.is_action_just_pressed("move_right"):
		_change_skin(1)
		return
	if Input.is_action_just_pressed("up"):
		_menu_row = posmod(_menu_row - 1, MENU_ITEMS.size())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("down"):
		_menu_row = posmod(_menu_row + 1, MENU_ITEMS.size())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_activate_menu(_menu_row)


func _activate_menu(i: int) -> void:
	match i:
		0:
			_start_level(_continue_level())
		1:
			_screen = Screen.LEVELS
			_input_lock = 0.15
			GameState.play_sfx("pluck", 7.0, -6.0)
		2:
			_open_music_setup()
		3:
			_open_settings()


func _handle_levels() -> void:
	if Input.is_action_just_pressed("back"):
		_screen = Screen.MAIN
		_input_lock = 0.15
		GameState.play_sfx("pluck", 2.0, -8.0)
		return
	var step := 0
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("up"):
		step = -1
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("down"):
		step = 1
	if step != 0:
		var next := clampi(_selected + step, 0, LevelData.visible_count() - 1)
		if next != _selected:
			_selected = next
			_bump = 1.0
			GameState.play_sfx("pluck", GameState.next_note(), -6.0)
	if Input.is_action_just_pressed("easier") or Input.is_action_just_pressed("harder"):
		var d := GameState.difficulty + (-1 if Input.is_action_just_pressed("easier") else 1)
		GameState.set_difficulty(clampi(d, 0, GameState.DIFFICULTIES.size() - 1))
		GameState.play_sfx("pluck", 7.0, -8.0)
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_start_level(_selected)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _starting or _overlay_open() or key == null or not key.pressed or key.echo:
		return
	var digit := key.physical_keycode - KEY_1
	if _screen == Screen.LEVELS and digit >= 0 and digit < LevelData.visible_count():
		_selected = digit
		_start_level(digit)


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
	if is_instance_valid(_music_setup) and _music_setup.is_inside_tree():
		return
	_music_setup = MusicSetup.new()
	_music_setup.closed.connect(func() -> void:
		_input_lock = 0.2
		_music_setup = null)
	_music_setup.tree_exited.connect(func() -> void:
		_music_setup = null
		_input_lock = maxf(_input_lock, 0.15))
	add_child(_music_setup)
	GameState.play_sfx("pluck", 7.0, -6.0)


## 設定：和遊戲中暫停同一個面板
func _open_settings() -> void:
	_settings = PauseMenu.new()
	_settings.title = "設定"
	var acts: Array = ["返回", "延遲校正", "機關說明"]
	if not OS.has_feature("web"):
		acts.append("離開遊戲")
	_settings.actions = acts
	_settings.settings = ["music", "sfx", "quality", "skin", "shake", "judge"]
	add_child(_settings)
	_settings.chosen.connect(_on_settings_chosen)
	GameState.play_sfx("pluck", 7.0, -6.0)


func _on_settings_chosen(action: String) -> void:
	_settings.queue_free()
	_settings = null
	_input_lock = 0.2
	if action == "延遲校正":
		_open_calibrator()
	elif action == "機關說明":
		_open_guide()
	elif action == "離開遊戲":
		get_tree().quit()


# ---------------------------------------------------------------- 滑鼠

func _menu_rect(i: int) -> Rect2:
	if i == 0:
		return Rect2(88, 352, 380, 76)
	return Rect2(88, 442 + (i - 1) * 74.0, 380, 60)


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or _overlay_open() or _starting:
		return
	if _screen == Screen.MAIN:
		for dir: int in [-1, 1]:
			if _skin_arrow_rect(dir).has_point(mb.position):
				_change_skin(dir)
				return
		var sc := _skin_center()
		if Rect2(sc.x - 140, sc.y - 420, 280, 430).has_point(mb.position):
			_change_skin(1)
			return
		for i in MENU_ITEMS.size():
			if _menu_rect(i).has_point(mb.position):
				_menu_row = i
				_activate_menu(i)
				return
		return
	if Rect2(64, 48, 48, 48).has_point(mb.position):
		_screen = Screen.MAIN
		return
	for c: Dictionary in _card_layout():
		if (c["rect"] as Rect2).has_point(mb.position):
			if int(c["index"]) == _selected:
				_start_level(_selected)
			else:
				_selected = int(c["index"])
				_bump = 1.0
			return
	var panel := _detail_rect()
	var n := GameState.DIFFICULTIES.size()
	for d in n:
		if _difficulty_rect(panel, d, n).has_point(mb.position):
			GameState.set_difficulty(d)
			return
	if _start_rect(panel).has_point(mb.position):
		_start_level(_selected)


# ---------------------------------------------------------------- 畫面

func _on_view_draw() -> void:
	var size := _view.size
	if _screen == Screen.MAIN:
		_draw_main(size)
	else:
		_draw_levels(size)
	if _fade > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, _fade))
	if _fade_out > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, _fade_out))


func _round(r: Rect2, fill: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(int(radius))
	st.bg_color = fill
	if bw > 0:
		st.set_border_width_all(bw)
		st.border_color = border
	_view.draw_style_box(st, r)


func _chip(pos: Vector2, label: String, dot: Color = Color(0, 0, 0, 0)) -> float:
	var w := UiKit.width_of(label, 15) + 32.0 + (16.0 if dot.a > 0.0 else 0.0)
	var r := Rect2(pos, Vector2(w, 40))
	_round(r, Color(UiKit.NIGHT, 0.82), 20, UiKit.LINE, 2)
	var x := pos.x + 16
	if dot.a > 0.0:
		_view.draw_circle(Vector2(x + 4, pos.y + 20), 4.0, dot)
		x += 16
	UiKit.text(_view, Vector2(x, pos.y + 26), -1, label, 15, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
	return w


func _draw_main(size: Vector2) -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.078, 0.039, 0.173, 0.55))
	## 四顆節拍點（跟著拍子亮）
	var beat := posmod(floori(Conductor.song_beat), 4)
	var dots := [UiKit.PINK, UiKit.CYAN, UiKit.YELLOW, Color(UiKit.TEXT, 0.4)]
	for i in 4:
		_view.draw_circle(Vector2(93 + i * 16, 104), 5.0 + (1.5 if i == beat else 0.0), dots[i])
	## 大標題：粉色錯位陰影
	var f := UiKit.title_font()
	_view.draw_string(f, Vector2(94, 218), GameState.GAME_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 112, UiKit.PINK)
	_view.draw_string(f, Vector2(88, 212), GameState.GAME_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 112, UiKit.TEXT)

	## 角色（右下）：兩邊箭頭可以換，下面是名字
	var bob := sin(Conductor.song_beat * PI) * 4.0
	var sc := _skin_center()
	var pop := 1.0 + 0.12 * ease(_skin_bump, 0.5)
	_view.draw_circle(sc + Vector2(0, -150), 190.0, Color(UiKit.PINK, 0.10 + 0.06 * Conductor.pulse(6.0)))
	Player.draw_skin(_view, GameState.skin, Vector2(sc.x, sc.y + bob), Vector2(7.0, 7.0) * pop, 0.0,
		Color.WHITE, Player.idle_pose(Conductor.song_beat))
	_view.draw_set_transform(Vector2.ZERO)
	for dir: int in [-1, 1]:
		var ar := _skin_arrow_rect(dir)
		_view.draw_circle(ar.get_center(), 30.0, Color(UiKit.PINK, 0.95))
		_view.draw_arc(ar.get_center(), 30.0, 0.0, TAU, 32, UiKit.TEXT, 3.0, true)
		UiKit.text(_view, Vector2(ar.position.x, ar.get_center().y + 13), ar.size.x, "‹" if dir < 0 else "›", 40, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.9))
	var skin_name := String(GameState.SKINS[GameState.skin]["name"])
	var nw := UiKit.width_of(skin_name, 22) + 56.0
	var nr := Rect2(sc.x - nw * 0.5, sc.y + 8.0, nw, 44.0)
	_round(nr, Color(UiKit.NIGHT, 0.9), 22, UiKit.PINK, 3)
	UiKit.text(_view, Vector2(nr.position.x, nr.position.y + 30), nr.size.x, skin_name, 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.8))

	## 四個按鈕
	var cont := _continue_level()
	for i in MENU_ITEMS.size():
		var r := _menu_rect(i)
		var on := i == _menu_row
		if i == 0:
			UiKit.solid_button(_view, r, "", UiKit.PINK, UiKit.PINK_DARK, 28)
			UiKit.text(_view, Vector2(r.position.x + 28, r.get_center().y + 10), -1, MENU_ITEMS[0], 27, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.25))
			UiKit.text(_view, Vector2(r.end.x - 150, r.get_center().y + 7), 124, "繼續 %s ›" % LevelData.level_code(cont), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.font(0.15))
		else:
			_round(r, Color(UiKit.CARD if on else UiKit.NIGHT, 0.86), 18, UiKit.PINK if on else UiKit.LINE, 2)
			UiKit.text(_view, Vector2(r.position.x + 28, r.get_center().y + 8), -1, MENU_ITEMS[i], 21, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.15))
		if on:
			_round(Rect2(r.position.x - 16, r.position.y + 14, 5, r.size.y - 28), UiKit.YELLOW, 2)

	## 右上：延遲、目前音樂
	var music := "♪ %s · %d BPM" % [UiKit.safe_text(Conductor.track_name), roundi(Conductor.bpm)]
	var mw := UiKit.width_of(music, 15) + 32.0
	_chip(Vector2(size.x - 88 - mw, 72), music)
	var off := "延遲 %+.0f ms" % GameState.audio_offset_ms
	var ow := UiKit.width_of(off, 15) + 48.0
	_chip(Vector2(size.x - 88 - mw - 10 - ow, 72), off, UiKit.CYAN)

	## 左下操作說明
	var x := 88.0
	for pair: Array in [["↑ ↓", "選擇"], ["← →", "換角色"], ["Enter", "確定"], ["H", "機關說明"], ["O", "延遲校正"]]:
		UiKit.text(_view, Vector2(x, size.y - 40), -1, pair[0], 15, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
		x += UiKit.width_of(pair[0], 15) + 10
		UiKit.text(_view, Vector2(x, size.y - 40), -1, pair[1], 15, UiKit.MUTED)
		x += UiKit.width_of(pair[1], 15) + 26


## 卡片排法：最多同時看三張，選中的那張大一點、往上提
func _card_layout() -> Array[Dictionary]:
	var n := LevelData.visible_count()
	var first := clampi(_selected - 1, 0, maxi(0, n - 3))
	var out: Array[Dictionary] = []
	for k in range(first, mini(n, first + 3)):
		var slot := k - first
		var sel := k == _selected
		var w := 250.0 if sel else 230.0
		var h := 330.0 if sel else 300.0
		var x := 64.0 + slot * 275.0 + (0.0 if sel else 10.0)
		var y := 140.0 if sel else 180.0
		out.append({"index": k, "rect": Rect2(x, y, w, h), "selected": sel})
	return out


func _detail_rect() -> Rect2:
	return Rect2(_view.size.x - 64 - 360, 140, 360, 520)


func _difficulty_rect(panel: Rect2, d: int, n: int) -> Rect2:
	var w := (panel.size.x - 56.0 - 6.0 * (n - 1)) / n
	return Rect2(panel.position.x + 28 + d * (w + 6.0), panel.position.y + 290, w, 44)


func _start_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position.x + 28, panel.end.y - 100, panel.size.x - 56, 72)


func _draw_levels(size: Vector2) -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, 0.88))
	## 標題列
	var back := Rect2(64, 48, 48, 48)
	_round(back, Color(UiKit.NIGHT, 0.0), 14, UiKit.LINE, 2)
	UiKit.text(_view, Vector2(back.position.x, back.position.y + 33), back.size.x, "‹", 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.8))
	UiKit.text(_view, Vector2(128, 84), -1, "選擇關卡", 36, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.9))

	## 路線虛線
	var y_line := 390.0
	var xx := 104.0
	while xx < 780.0:
		_view.draw_line(Vector2(xx, y_line), Vector2(xx + 6, y_line), UiKit.LINE, 4.0)
		xx += 14.0
	for c: Dictionary in _card_layout():
		_draw_card(int(c["index"]), c["rect"], bool(c["selected"]))

	_draw_detail(_detail_rect())
	## 底部操作說明
	var x := 64.0
	for pair: Array in [["← →", "選關"], ["Q E", "判定"], ["Enter", "開始"], ["Esc", "返回"]]:
		UiKit.text(_view, Vector2(x, size.y - 24), -1, pair[0], 14, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
		x += UiKit.width_of(pair[0], 14) + 8
		UiKit.text(_view, Vector2(x, size.y - 24), -1, pair[1], 14, UiKit.MUTED)
		x += UiKit.width_of(pair[1], 14) + 24


func _draw_card(i: int, r: Rect2, selected: bool) -> void:
	var info := LevelData.level_info(i)
	var s := 1.0 + 0.03 * _bump if selected else 1.0
	var c := r.get_center()
	_view.draw_set_transform(c, 0.0, Vector2(s, s))
	var lr := Rect2(-r.size * 0.5, r.size)
	if selected:
		var halo := StyleBoxFlat.new()
		halo.anti_aliasing = true
		halo.set_corner_radius_all(28)
		halo.bg_color = Color(UiKit.PINK, 0.18)
		_view.draw_style_box(halo, lr.grow(6))
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(22)
	st.bg_color = Color("2E1F5C") if selected else UiKit.CARD
	st.set_border_width_all(3)
	st.border_color = UiKit.PINK if selected else UiKit.LINE
	_view.draw_style_box(st, lr)
	## 卡片只放封面、編號、關名：封面撐滿上面，下面留編號和關名的位置
	var thumb := Rect2(lr.position + Vector2(12, 12), Vector2(lr.size.x - 24, lr.size.y - 24 - 96))
	_draw_thumb(String(info.get("background_profile", "calm_city")), thumb)
	var x := lr.position.x + 16
	var y := thumb.end.y
	_view.draw_string(UiKit.title_font(), Vector2(x, y + 46), LevelData.level_code(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 40 if selected else 34, UiKit.TEXT)
	var rec: Dictionary = GameState.records.get(i, {})
	## 過關後右上角放評等（沒有評等紀錄的舊存檔放一個勾）
	if not rec.is_empty():
		var mark := GameState.rank_of(float(rec["score"])) if rec.has("score") else "✓"
		var badge := Rect2(lr.end.x - 16 - 44, y + 10, 44, 44)
		_round(badge, UiKit.YELLOW, 14)
		_view.draw_string(UiKit.title_font(), Vector2(badge.position.x, badge.position.y + 34), mark, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 30, UiKit.INK)
	UiKit.text(_view, Vector2(x, y + 78), -1, String(info.get("desc", "")), 20 if selected else 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.8))
	_view.draw_set_transform(Vector2.ZERO)


func _draw_detail(panel: Rect2) -> void:
	_round(panel, UiKit.CARD, 24, UiKit.LINE, 3)
	var i := _selected
	var info := LevelData.level_info(i)
	var p := panel.position
	UiKit.text(_view, p + Vector2(28, 74), panel.size.x - 56, String(info.get("desc", "")), 32, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.9))
	var rec: Dictionary = GameState.records.get(i, {})
	var tiles := [
		["最佳時間", _fmt_time(float(rec["time"])) if not rec.is_empty() else "—"],
		["最少倒下", str(int(rec["deaths"])) if not rec.is_empty() else "—"],
		["最佳評等", GameState.rank_of(float(rec["score"])) if rec.has("score") else "—"],
	]
	var tw := (panel.size.x - 56.0 - 20.0) / 3.0
	for k in 3:
		var r := Rect2(p.x + 28 + k * (tw + 10), p.y + 140, tw, 78)
		_round(r, UiKit.NIGHT, 14)
		UiKit.text(_view, r.position + Vector2(12, 26), -1, tiles[k][0], 12, UiKit.MUTED)
		UiKit.text(_view, r.position + Vector2(12, 60), -1, tiles[k][1], 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(700))
	UiKit.text(_view, p + Vector2(28, 272), -1, "判定難度", 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
	var n := GameState.DIFFICULTIES.size()
	for d in n:
		var r := _difficulty_rect(panel, d, n)
		var on := d == GameState.difficulty
		_round(r, UiKit.PINK if on else Color(0, 0, 0, 0), 12, UiKit.PINK if on else UiKit.LINE, 2)
		UiKit.text(_view, Vector2(r.position.x, r.position.y + 29), r.size.x, String(GameState.DIFFICULTIES[d]["name"]), 15,
			UiKit.INK if on else UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
	UiKit.solid_button(_view, _start_rect(panel), "開始", UiKit.PINK, UiKit.PINK_DARK, 26)


func _fmt_time(sec: float) -> String:
	return "%d:%02d" % [floori(sec / 60.0), floori(fposmod(sec, 60.0))]


func _draw_thumb(profile: String, rect: Rect2) -> void:
	var paths: Array = THUMBS.get(profile, THUMBS["calm_city"])
	_round(rect, UiKit.NIGHT, 14)
	for k in paths.size():
		var path: String = paths[k]
		if not _thumb_cache.has(path):
			_thumb_cache[path] = load(path) if ResourceLoader.exists(path) else null
		var tex: Texture2D = _thumb_cache[path]
		if tex == null:
			continue
		var ts := tex.get_size()
		var aspect := rect.size.x / rect.size.y
		var src_h := ts.x / aspect
		var src := Rect2(0, 0 if k == 0 else maxf(0.0, ts.y - src_h), ts.x, minf(src_h, ts.y))
		_view.draw_texture_rect_region(tex, rect.grow(-2.0), src)
