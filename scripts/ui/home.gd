extends Node2D
## 主選單與選關（照設計稿「Heart Beat UI 改版提案」的主選單、選擇關卡兩個畫面）。
##   主選單：大標題、角色、四個按鈕（開始遊戲＝接續上次的關、選擇關卡、自訂音樂、設定）。
##   選擇關卡：關卡卡片沿著一條路線排、右邊是選中那關的詳細資料、判定難度和開始按鈕。
##   設定：用暫停選單同一個面板（PauseMenu），左邊換成返回、延遲校正、機關說明、關卡設計台。
## 從遊戲裡「回選關」會直接進到選擇關卡（GameState 的 meta "home_screen"）。

const MAIN_SCENE := "res://scenes/main.tscn"
const CHART_SCENE := "res://scenes/chart_studio.tscn"
## 關卡卡片的場景縮圖：背景主題 → 天空、近景兩層
const THUMBS := {
	"calm_city": ["res://assets/themes/heartbeat_city/bg/sky.png", "res://assets/themes/heartbeat_city/bg/city_near.png"],
	"sakura_park": ["res://assets/themes/sakura_park/bg/sky.png", "res://assets/themes/sakura_park/bg/park_near.png"],
	"music_festival": ["res://assets/themes/music_festival/bg/sky.png", "res://assets/themes/music_festival/bg/festival_near.png"],
}
const THEME_NAMES := {"calm_city": "月夜城市", "sakura_park": "櫻花公園", "music_festival": "音樂祭"}
const MENU_ITEMS := ["開始遊戲", "選擇關卡", "自訂音樂", "設定"]
const NEXT_UP := "天花板尖刺、雷射：即將推出"

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


func _ready() -> void:
	Engine.time_scale = 1.0
	_selected = clampi(GameState.level_index, 0, maxi(0, LevelData.LEVELS.size() - 1))
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


func _process(delta: float) -> void:
	_camera.position.x += 28.0 * delta
	_input_lock = maxf(0.0, _input_lock - delta)
	_bump = move_toward(_bump, 0.0, delta * 4.0)
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
		or is_instance_valid(_settings)


## 「開始遊戲」接續的關卡：還沒通關的第一關，全破就是上次玩的那關
func _continue_level() -> int:
	for i in LevelData.LEVELS.size():
		if not GameState.records.has(i):
			return i
	return clampi(GameState.level_index, 0, LevelData.LEVELS.size() - 1)


func _handle_main() -> void:
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
		var next := clampi(_selected + step, 0, LevelData.LEVELS.size() - 1)
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
	if _screen == Screen.LEVELS and digit >= 0 and digit < LevelData.LEVELS.size():
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
	_settings.subtitle = "SETTINGS"
	var acts: Array = ["返回", "延遲校正", "機關說明", "關卡設計台"]
	if not OS.has_feature("web"):
		acts.append("離開遊戲")
	_settings.actions = acts
	_settings.settings = ["music", "sfx", "quality", "skin", "shake", "auto", "judge"]
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
	elif action == "關卡設計台":
		get_tree().change_scene_to_file(CHART_SCENE)
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
	## RHYTHM RUNNER ＋ 四顆節拍點
	var beat := posmod(floori(Conductor.song_beat), 4)
	var dots := [UiKit.PINK, UiKit.CYAN, UiKit.YELLOW, Color(UiKit.TEXT, 0.4)]
	for i in 4:
		_view.draw_circle(Vector2(93 + i * 16, 104), 5.0 + (1.5 if i == beat else 0.0), dots[i])
	UiKit.text(_view, Vector2(166, 110), -1, "RHYTHM RUNNER", 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(600))
	## 大標題：粉色錯位陰影
	var f := UiKit.title_font()
	_view.draw_string(f, Vector2(94, 218), GameState.GAME_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 112, UiKit.PINK)
	_view.draw_string(f, Vector2(88, 212), GameState.GAME_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 112, UiKit.TEXT)
	UiKit.text(_view, Vector2(88, 262), -1, "跟著拍子跑，一拍一跳", 22, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))

	## 角色（右下）
	var bob := sin(Conductor.song_beat * PI) * 4.0
	Player.draw_skin(_view, GameState.skin, Vector2(size.x - 330, size.y - 70 + bob), Vector2(7.0, 7.0), 0.0,
		Color.WHITE, Player.idle_pose(Conductor.song_beat))
	_view.draw_set_transform(Vector2.ZERO)

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
	for pair: Array in [["↑ ↓", "選擇"], ["Enter", "確定"], ["H", "機關說明"], ["O", "延遲校正"]]:
		UiKit.text(_view, Vector2(x, size.y - 40), -1, pair[0], 15, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
		x += UiKit.width_of(pair[0], 15) + 10
		UiKit.text(_view, Vector2(x, size.y - 40), -1, pair[1], 15, UiKit.MUTED)
		x += UiKit.width_of(pair[1], 15) + 26


## 卡片排法：最多同時看三張，選中的那張大一點、往上提
func _card_layout() -> Array[Dictionary]:
	var n := LevelData.LEVELS.size()
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


func _plan_sections(i: int) -> int:
	var n := 0
	for chunk: Dictionary in LevelData.level_info(i)["chunks"]:
		if not (chunk.get("plan", []) as Array).is_empty():
			n += 1
	return n


func _draw_levels(size: Vector2) -> void:
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, 0.88))
	## 標題列
	var back := Rect2(64, 48, 48, 48)
	_round(back, Color(UiKit.NIGHT, 0.0), 14, UiKit.LINE, 2)
	UiKit.text(_view, Vector2(back.position.x, back.position.y + 33), back.size.x, "‹", 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.8))
	UiKit.text(_view, Vector2(128, 84), -1, "選擇關卡", 36, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.9))
	UiKit.text(_view, Vector2(128 + UiKit.width_of("選擇關卡", 36) + 16, 82), -1, "每一關加入一樣新東西，再和學過的混在一起", 16, UiKit.MUTED)

	## 路線虛線
	var y_line := 390.0
	var xx := 104.0
	while xx < 780.0:
		_view.draw_line(Vector2(xx, y_line), Vector2(xx + 6, y_line), UiKit.LINE, 4.0)
		xx += 14.0
	for c: Dictionary in _card_layout():
		_draw_card(int(c["index"]), c["rect"], bool(c["selected"]))
	## 下一關預告
	var next := Rect2(204, 560, 520, 90)
	var dash := StyleBoxFlat.new()
	dash.bg_color = Color(0, 0, 0, 0)
	_round(next, Color(UiKit.NIGHT, 0.4), 22, UiKit.LINE, 3)
	UiKit.text(_view, Vector2(next.position.x, next.get_center().y + 8), next.size.x,
		"%02d　%s" % [LevelData.LEVELS.size() + 1, NEXT_UP], 16, Color("A598D1"), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))

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
	var thumb := Rect2(lr.position + Vector2(12, 12), Vector2(lr.size.x - 24, 128 if selected else 116))
	_draw_thumb(String(info.get("background_profile", "calm_city")), thumb)
	var x := lr.position.x + 16
	var y := thumb.end.y
	_view.draw_string(UiKit.title_font(), Vector2(x, y + 46), LevelData.level_code(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 40 if selected else 34, UiKit.TEXT)
	var rec: Dictionary = GameState.records.get(i, {})
	if not rec.is_empty():
		UiKit.text(_view, Vector2(lr.end.x - 96, y + 38), 80, "已通關", 14, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.font(0.6))
	UiKit.text(_view, Vector2(x, y + 78), -1, String(info.get("desc", "")), 20 if selected else 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.8))
	var tx := x
	var ty := y + 92
	var tags: Array = info.get("tags", [])
	if selected:
		var nw := UiKit.width_of("新", 12) + 20.0
		_round(Rect2(tx, ty, nw, 24), UiKit.PINK, 10)
		UiKit.text(_view, Vector2(tx, ty + 17), nw, "新", 12, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.8))
		tx += nw + 6
	for t: String in tags:
		var tw := UiKit.width_of(t, 12) + 20.0
		if tx + tw > lr.end.x - 12:
			tx = x
			ty += 30
		## 標籤太多就不畫到最下面那行紀錄上
		if ty + 24 > lr.end.y - 34:
			break
		_round(Rect2(tx, ty, tw, 24), Color("3B2A6B"), 10)
		UiKit.text(_view, Vector2(tx, ty + 17), tw, t, 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
		tx += tw + 6
	var line := "尚未通關" if rec.is_empty() else "最佳 %s · 倒下 %d" % [_fmt_time(float(rec["time"])), int(rec["deaths"])]
	UiKit.text(_view, Vector2(x, lr.end.y - 16), -1, line, 13, UiKit.CYAN if not rec.is_empty() else UiKit.MUTED)
	_view.draw_set_transform(Vector2.ZERO)


func _draw_detail(panel: Rect2) -> void:
	_round(panel, UiKit.CARD, 24, UiKit.LINE, 3)
	var i := _selected
	var info := LevelData.level_info(i)
	var p := panel.position
	UiKit.text(_view, p + Vector2(28, 44), -1, "STAGE %s" % LevelData.level_code(i), 14, UiKit.PINK, HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(600))
	UiKit.text(_view, p + Vector2(28, 84), panel.size.x - 56, String(info.get("desc", "")), 30, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.9))
	var theme := String(THEME_NAMES.get(String(info.get("background_profile", "")), ""))
	UiKit.text(_view, p + Vector2(28, 114), -1, "%s · %d 段" % [theme, _plan_sections(i)], 15, UiKit.MUTED)
	var rec: Dictionary = GameState.records.get(i, {})
	var tiles := [
		["最佳時間", _fmt_time(float(rec["time"])) if not rec.is_empty() else "—"],
		["最少倒下", str(int(rec["deaths"])) if not rec.is_empty() else "—"],
		["新機關", str((info.get("tags", []) as Array).size())],
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
	var dd: Dictionary = GameState.DIFFICULTIES[GameState.difficulty]
	var sub := "音符、衝刺環、光柱隨時可用，不用對拍" if GameState.free_rhythm() else \
		"早 %d 幀／晚 %d 幀內按下都算準" % [int(dd["early"]), int(dd["late"])]
	UiKit.text(_view, p + Vector2(28, 362), panel.size.x - 56, sub, 13, UiKit.MUTED)
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
