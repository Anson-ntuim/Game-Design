class_name PauseMenu
extends CanvasLayer
## 暫停選單（設計稿「暫停／設定」）：左邊繼續／回到長椅／從頭再來／回選關，右邊直接調設定。
## 開著的時候整個遊戲（物理、節奏時鐘、音樂）都停住；這一層本身 PROCESS_MODE_ALWAYS 才收得到按鍵。
## ↑↓ 選項目、←→ 調整、Enter／空白鍵確定、Esc 等於第一個動作（繼續／返回）。滑鼠也可以直接點。
## 主選單的「設定」也用這一個面板（actions、settings、title 換掉就好）。

## 選了左邊哪個動作（文字就是按鈕上的字）
signal chosen(action: String)

var actions: Array = ["繼續", "回到長椅", "從頭再來", "回選關"]
var settings: Array = ["music", "sfx", "shake", "auto", "judge"]
var title: String = "暫停"
const SETTING_LABEL := {"music": "音樂音量", "sfx": "音效音量", "shake": "畫面晃動", "auto": "自動前進",
	"judge": "判定難度", "quality": "畫質", "skin": "角色造型"}

var _view: Control
var _row: int = 0
var _open_t: float = 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_view)
	_view.draw.connect(_on_draw)
	_view.gui_input.connect(_on_gui_input)


func _rows() -> int:
	return actions.size() + settings.size()


func _process(delta: float) -> void:
	_open_t = minf(1.0, _open_t + delta * 6.0)
	if Input.is_action_just_pressed("back"):
		chosen.emit(String(actions[0]))
		return
	if Input.is_action_just_pressed("up"):
		_row = posmod(_row - 1, _rows())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("down"):
		_row = posmod(_row + 1, _rows())
		GameState.play_sfx("pluck", 3.0, -10.0)
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
		_adjust(-1)
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder"):
		_adjust(1)
	elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_activate()
	_view.queue_redraw()


func _activate() -> void:
	if _row < actions.size():
		chosen.emit(String(actions[_row]))
	else:
		_adjust(1)


func _adjust(step: int) -> void:
	if _row < actions.size():
		return
	match settings[_row - actions.size()]:
		"music":
			GameState.set_music_volume(GameState.music_volume + 0.1 * step)
		"sfx":
			GameState.set_sfx_volume(GameState.sfx_volume + 0.1 * step)
		"shake":
			GameState.set_screen_shake(not GameState.screen_shake)
		"auto":
			GameState.set_auto_run(not GameState.auto_run)
		"judge":
			GameState.set_difficulty(clampi(GameState.difficulty + step, 0, GameState.DIFFICULTIES.size() - 1))
		"quality":
			GameState.set_quality(clampi(GameState.quality + step, 0, GameState.QUALITIES.size() - 1))
		"skin":
			GameState.set_skin(GameState.skin + step)
	GameState.play_sfx("pluck", 6.0, -8.0)


func _action_rect(i: int) -> Rect2:
	return Rect2(96, 210 + i * 70.0, 300, 58 if i > 0 else 64)


func _setting_rect(i: int) -> Rect2:
	var panel := _panel_rect()
	var step := minf(78.0, (panel.size.y - 110.0) / maxf(1.0, settings.size()))
	return Rect2(panel.position.x + 28, panel.position.y + 86 + i * step, panel.size.x - 56, step - 12.0)


func _panel_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x - 96 - 640, 96, 640, 528)


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in actions.size():
		if _action_rect(i).has_point(mb.position):
			_row = i
			_activate()
			return
	for i in settings.size():
		var r := _setting_rect(i)
		if r.has_point(mb.position):
			_row = actions.size() + i
			if settings[i] == "skin":
				## 直接點哪一隻就換哪一隻
				var right := Rect2(r.position.x + 190, r.position.y, r.size.x - 210, r.size.y)
				var n := GameState.SKINS.size()
				var k := clampi(int((mb.position.x - right.position.x) / (right.size.x / n)), 0, n - 1)
				GameState.set_skin(k)
				GameState.play_sfx("pluck", 6.0, -8.0)
				return
			_adjust(-1 if mb.position.x < r.get_center().x and settings[i] in ["music", "sfx", "judge", "quality"] else 1)
			return


func _on_draw() -> void:
	var size := _view.size
	var k := ease(_open_t, -2.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, 0.78 * k))
	UiKit.text(_view, Vector2(96, 176), -1, title, 44, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.8))
	for i in actions.size():
		var r := _action_rect(i)
		var on := _row == i
		if i == 0 or on:
			UiKit.solid_button(_view, r, actions[i], UiKit.PINK if i == 0 else UiKit.CYAN,
				UiKit.PINK_DARK if i == 0 else Color("2A8C97"), 21 if i == 0 else 19, k)
		else:
			UiKit.panel(_view, r, UiKit.LINE, 0.0, k, 10.0, Color(UiKit.NIGHT, 0.85))
			UiKit.text(_view, Vector2(r.position.x + 24, r.position.y + r.size.y * 0.5 + 7), -1, actions[i], 19, Color(UiKit.TEXT, k))
		if on and i == 0:
			_view.draw_rect(Rect2(r.position.x - 14, r.position.y + 14, 5, r.size.y - 28), Color(UiKit.YELLOW, k))

	var panel := _panel_rect()
	UiKit.panel(_view, panel, UiKit.LINE, 0.0, k, 18.0, Color(UiKit.CARD, 0.98))
	UiKit.text(_view, panel.position + Vector2(28, 52), -1, "設定", 22, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
	for i in settings.size():
		var id: String = settings[i]
		var r := _setting_rect(i)
		var on := _row == actions.size() + i
		UiKit.panel(_view, r, UiKit.PINK, 1.0 if on else 0.0, k, 10.0, Color(UiKit.NIGHT, 0.9))
		var cy := r.get_center().y
		UiKit.text(_view, Vector2(r.position.x + 20, cy + 7), -1, SETTING_LABEL[id], 18, Color(UiKit.TEXT, k))
		var right := Rect2(r.position.x + 190, r.position.y, r.size.x - 210, r.size.y)
		match id:
			"music", "sfx":
				var v: float = GameState.music_volume if id == "music" else GameState.sfx_volume
				var col := UiKit.PINK if id == "music" else UiKit.CYAN
				var bar := Rect2(right.position.x, right.get_center().y - 3, right.size.x - 70, 6)
				_view.draw_rect(bar, Color(UiKit.LINE, k))
				_view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * v, bar.size.y)), Color(col, k))
				var knob := Vector2(bar.position.x + bar.size.x * v, bar.get_center().y)
				_view.draw_circle(knob, 13.0, Color(col, k))
				_view.draw_circle(knob, 9.0, Color(UiKit.TEXT, k))
				UiKit.text(_view, Vector2(bar.end.x + 12, cy + 8), 58, "%d%%" % roundi(v * 100.0), 18, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_RIGHT, UiKit.display_font(700))
			"shake", "auto":
				var value: bool = GameState.screen_shake if id == "shake" else GameState.auto_run
				var sw := Rect2(right.end.x - 64, right.get_center().y - 18, 64, 36)
				var st := StyleBoxFlat.new()
				st.anti_aliasing = true
				st.set_corner_radius_all(18)
				st.bg_color = Color(UiKit.PINK if value else UiKit.LINE, k)
				_view.draw_style_box(st, sw)
				_view.draw_circle(Vector2(sw.end.x - 18 if value else sw.position.x + 18, sw.get_center().y), 14.0, Color(UiKit.TEXT, k))
				var note := ("開" if value else "關")
				if id == "auto":
					note = "只管跳和衝刺" if value else "方向鍵手動移動"
				UiKit.text(_view, Vector2(right.position.x, cy + 6), right.size.x - 80, note, 15, Color(UiKit.MUTED, k))
			"quality", "skin":
				var names: Array = []
				var cur := 0
				if id == "quality":
					for q in GameState.QUALITIES:
						names.append(String(q["name"]))
					cur = GameState.quality
				else:
					## 每個造型一格，目前用的那格亮起來（原本只畫目前那一個，看起來像只剩一隻角色）
					for sk in GameState.SKINS:
						names.append(String(sk["name"]))
					cur = GameState.skin
				var nq := names.size()
				var sq := (right.size.x - 6.0 * (nq - 1)) / nq
				for d in nq:
					var sr2 := Rect2(right.position.x + d * (sq + 6.0), cy - 18, sq, 36)
					var sel2 := d == cur
					var st3 := StyleBoxFlat.new()
					st3.anti_aliasing = true
					st3.set_corner_radius_all(12)
					st3.bg_color = Color(UiKit.PINK if sel2 else UiKit.CARD, k)
					st3.set_border_width_all(2)
					st3.border_color = Color(UiKit.PINK if sel2 else UiKit.LINE, k)
					_view.draw_style_box(st3, sr2)
					UiKit.text(_view, Vector2(sr2.position.x, sr2.position.y + 25), sr2.size.x, String(names[d]),
						15, Color(UiKit.INK if sel2 else UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_CENTER)
			"judge":
				var n := GameState.DIFFICULTIES.size()
				var seg := (right.size.x - 6.0 * (n - 1)) / n
				for d in n:
					var sr := Rect2(right.position.x + d * (seg + 6.0), cy - 18, seg, 36)
					var sel := d == GameState.difficulty
					var st2 := StyleBoxFlat.new()
					st2.anti_aliasing = true
					st2.set_corner_radius_all(12)
					st2.bg_color = Color(UiKit.PINK if sel else UiKit.CARD, k)
					st2.set_border_width_all(2)
					st2.border_color = Color(UiKit.PINK if sel else UiKit.LINE, k)
					_view.draw_style_box(st2, sr)
					UiKit.text(_view, Vector2(sr.position.x, sr.position.y + 25), sr.size.x,
						String(GameState.DIFFICULTIES[d]["name"]), 15, Color(UiKit.INK if sel else UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.key_hints(_view, size.x * 0.5, size.y - 52, [[["↑", "↓"], "選擇"], [["←", "→"], "調整"], [["Enter"], "確定"], [["Esc"], String(actions[0])]], UiKit.LINE, k)
