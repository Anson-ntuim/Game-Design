extends Node2D
## 選關畫面：左右選關、上下換造型（只有一個造型時不顯示）、Q／E 換判定難度、Enter／跳躍開始，H／Tab 打開機關說明（mechanic_guide.gd），
## 顯示每關的說明、難度、地形縮圖與最佳紀錄。

const MAIN_SCENE := "res://scenes/main.tscn"
const CARD_SIZE := Vector2(440, 272)
const CARD_GAP := 40.0
var _selected: int = 0
var _view: Control
var _camera: Camera2D
var _bump: float = 0.0
var _skin_bump: float = 0.0
var _diff_bump: float = 0.0
var _slide: float = 0.0
var _fade: float = 0.0
var _starting: bool = false
var _guide: MechanicGuide


func _ready() -> void:
	Engine.time_scale = 1.0
	_selected = clampi(GameState.level_index, 0, LevelData.LEVELS.size() - 1)
	_slide = _selected
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
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_view)
	_view.draw.connect(_on_view_draw)
	for i in LevelData.LEVELS.size():
		UiKit.minimap(i)

	GameState.reset_stats()
	Conductor.start()


func _process(delta: float) -> void:
	_camera.position.x += 40.0 * delta
	_bump = move_toward(_bump, 0.0, delta * 4.0)
	_skin_bump = move_toward(_skin_bump, 0.0, delta * 4.0)
	_diff_bump = move_toward(_diff_bump, 0.0, delta * 4.0)
	_slide = lerpf(_slide, float(_selected), 1.0 - exp(-12.0 * delta))
	_view.queue_redraw()
	if _starting or is_instance_valid(_guide):
		return
	if Input.is_action_just_pressed("guide"):
		_open_guide()
		return

	var skin_step := 0
	if GameState.SKINS.size() < 2:
		pass
	elif Input.is_action_just_pressed("up"):
		skin_step = -1
	elif Input.is_action_just_pressed("down"):
		skin_step = 1
	if skin_step != 0:
		GameState.set_skin(GameState.skin + skin_step)
		_skin_bump = 1.0
		GameState.play_sfx("pluck", GameState.next_note() + 12.0, -6.0)

	var diff_step := 0
	if Input.is_action_just_pressed("easier"):
		diff_step = -1
	elif Input.is_action_just_pressed("harder"):
		diff_step = 1
	if diff_step != 0:
		var d := clampi(GameState.difficulty + diff_step, 0, GameState.DIFFICULTIES.size() - 1)
		if d != GameState.difficulty:
			GameState.set_difficulty(d)
			_diff_bump = 1.0
			GameState.play_sfx("pluck", GameState.next_note() + 7.0, -6.0)

	var step := 0
	if Input.is_action_just_pressed("move_left"):
		step = -1
	elif Input.is_action_just_pressed("move_right"):
		step = 1
	if step != 0:
		var next := clampi(_selected + step, 0, LevelData.LEVELS.size() - 1)
		if next != _selected:
			_selected = next
			_bump = 1.0
			GameState.play_sfx("pluck", GameState.next_note(), -6.0)
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"):
		_start(_selected)


## 數字鍵 1、2… 直接開始該關
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _starting or is_instance_valid(_guide):
		return
	var idx := key.physical_keycode - KEY_1
	if idx >= 0 and idx < LevelData.LEVELS.size():
		_selected = idx
		_start(idx)


func _open_guide() -> void:
	_guide = MechanicGuide.new()
	add_child(_guide)
	GameState.play_sfx("pluck", GameState.next_note() + 7.0, -6.0)


func _start(idx: int) -> void:
	_starting = true
	GameState.level_index = idx
	GameState.play_sfx("cue", 0.0, -4.0)
	var tw := create_tween()
	tw.tween_property(self, "_fade", 1.0, 0.35)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MAIN_SCENE))


func _on_view_draw() -> void:
	var size := _view.size
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(6.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.16))
	var shade := size.y * 0.36
	_view.draw_polygon(PackedVector2Array([Vector2(0, size.y - shade), Vector2(size.x, size.y - shade), size, Vector2(0, size.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]))

	_draw_logo(Vector2(size.x * 0.5, 104), edge)

	var center_y := 332.0
	for i in LevelData.LEVELS.size():
		var offset := (i - _slide) * (CARD_SIZE.x + CARD_GAP)
		if absf(offset) < size.x * 0.5 + CARD_SIZE.x:
			_draw_card(i, Vector2(size.x * 0.5 + offset, center_y), i == _selected, edge, pulse)
	_draw_arrows(Vector2(size.x * 0.5, center_y), edge, pulse)
	_draw_dots(Vector2(size.x * 0.5, center_y + 168), edge)

	_draw_skin_picker(Rect2(size.x * 0.5 - 336, 526, 324, 108), edge, pulse)
	_draw_difficulty_picker(Rect2(size.x * 0.5 + 12, 526, 324, 108), edge, pulse)

	var hints := [[["←", "→"], "選關"], [["Q", "E"], "判定"],
		[["Enter"], "開始"], [["H"], "機關說明"], [["1~%d" % LevelData.LEVELS.size()], "直接進入"]]
	if GameState.SKINS.size() > 1:
		hints.insert(1, [["↑", "↓"], "造型"])
	UiKit.key_hints(_view, size.x * 0.5, size.y - 44, hints, edge, 0.9)

	if _fade > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))


## 標題字每拍從左到右彈一波（像心跳傳過去），右上掛著 DEMO 標籤
func _draw_logo(c: Vector2, edge: Color) -> void:
	var logo := GameState.GAME_TITLE
	var f := UiKit.title_font()
	var font_size := 72
	var gap := 3.0
	var widths: Array[float] = []
	var total := 0.0
	for ch in logo:
		var w := UiKit.width_of(ch, font_size, f) if ch != " " else font_size * 0.32
		widths.append(w)
		total += w + gap
	total -= gap
	var b := Conductor.song_beat
	var frac := fposmod(b, 1.0)
	var x := c.x - total * 0.5 - 36.0
	var start_x := x
	for i in logo.length():
		var d := frac - i * 0.045
		var k := sin(clampf(d * 3.0, 0.0, 1.0) * PI) if d >= 0.0 else 0.0
		var tilt := deg_to_rad(-4.0 if i % 2 == 0 else 3.0) * (0.4 + k)
		var col := Color.WHITE.lerp(edge.lerp(Color.WHITE, 0.3), 0.6 * k)
		_view.draw_set_transform(Vector2(x + widths[i] * 0.5, c.y - k * 12.0), tilt)
		if logo[i] != " ":
			UiKit.bold_text(_view, Vector2(-widths[i] * 0.5, 0), -1, logo[i], font_size, col, edge)
		x += widths[i] + gap
	_view.draw_set_transform(Vector2(x + 10, c.y - 62), deg_to_rad(-8.0))
	UiKit.pill(_view, Vector2.ZERO, "DEMO", edge, UiKit.INK, 18)
	_view.draw_set_transform(Vector2.ZERO)
	for side: float in [-1.0, 1.0]:
		var bob := sin(b * PI + side) * 6.0
		var nx := start_x - 52.0 if side < 0.0 else x + 92.0
		UiKit.text(_view, Vector2(nx, c.y - 20 + bob), -1, "♪" if side < 0.0 else "♫", 34, Color(edge, 0.75))

	var sub := "選擇關卡"
	var tw := UiKit.width_of(sub, 18)
	UiKit.text(_view, Vector2(c.x - tw * 0.5, c.y + 42), -1, sub, 18, Color(edge.lerp(Color.WHITE, 0.3), 0.95))
	var beat := 0.4 + 0.6 * Conductor.pulse(6.0)
	for side: float in [-1.0, 1.0]:
		var a := c.x + side * (tw * 0.5 + 14.0)
		var y := c.y + 36.0
		var trace := PackedVector2Array()
		for p: Vector2 in [Vector2(0, 0), Vector2(26, 0), Vector2(32, -5), Vector2(38, 0), Vector2(44, 0),
				Vector2(49, 8), Vector2(55, -18), Vector2(61, 10), Vector2(66, 0), Vector2(96, 0)]:
			trace.append(Vector2(a + side * p.x, y + p.y * beat))
		_view.draw_polyline(trace, Color(edge, 0.75), 2.0, true)
		_view.draw_circle(trace[trace.size() - 1] + Vector2(side * 6.0, 0), 3.0, Color(edge, 0.9))


## 卡片在原點畫好再整張縮放，沒選中的縮小變暗
func _draw_card(i: int, center: Vector2, selected: bool, edge: Color, pulse: float) -> void:
	var info: Dictionary = LevelData.LEVELS[i]
	var s := 1.04 + 0.015 * pulse + 0.04 * _bump if selected else 0.9
	var alpha := 1.0 if selected else 0.45
	_view.draw_set_transform(center, 0.0, Vector2(s, s))
	var r := Rect2(-CARD_SIZE * 0.5, CARD_SIZE)
	UiKit.panel(_view, r, edge if selected else Color(0.8, 0.85, 1.0), 0.6 + 0.4 * pulse if selected else 0.0,
		1.0 if selected else 0.75, 18.0)
	var x := r.position.x + 24.0
	var y := r.position.y
	var w := r.size.x - 48.0

	UiKit.text(_view, Vector2(x + 2, y + 32), -1, "STAGE", 12, Color(edge, 0.9 * alpha))
	UiKit.bold_text(_view, Vector2(x, y + 82), -1, "%02d" % (i + 1), 46, Color(1, 1, 1, alpha), edge)
	var parts := UiKit.split_name(String(info["name"]))
	UiKit.text(_view, Vector2(x + 96, y + 40), -1, parts[0], 14, Color(1, 1, 1, 0.6 * alpha))
	UiKit.text(_view, Vector2(x + 96, y + 76), w - 170, parts[1], 30, Color(1, 1, 1, alpha))
	var stars := int(info.get("stars", 1))
	UiKit.notes(_view, Vector2(r.end.x - 24 - 3 * 17, y + 40), stars, 3, Color(UiKit.GOLD, alpha), 22)
	_view.draw_line(Vector2(x, y + 100), Vector2(r.end.x - 24, y + 100), Color(edge, 0.35 * alpha), 1.0)

	_view.draw_multiline_string(UiKit.font(), Vector2(x, y + 126), String(info.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT,
		w, 15, 2, Color(1, 1, 1, 0.82 * alpha))
	UiKit.draw_minimap(_view, i, Rect2(x, y + 170, w, 40), edge, alpha)

	var rec: Dictionary = GameState.records.get(i, {})
	var fy := r.end.y - 34.0
	if rec.is_empty():
		UiKit.text(_view, Vector2(x, fy + 17), -1, "尚未通關", 15, Color(1, 1, 1, 0.5 * alpha))
	else:
		var pw := UiKit.pill(_view, Vector2(x, fy), "最佳", Color(UiKit.GOLD, alpha), UiKit.INK, 12)
		UiKit.text(_view, Vector2(x + pw + 8, fy + 17), -1, "%.1f 秒　死亡最少 %d 次" % [float(rec["time"]), int(rec["deaths"])],
			15, Color(UiKit.GOLD, alpha))
	if selected:
		UiKit.key_hints(_view, r.end.x - 24, fy - 1, [[["Enter"], "開始"]], edge, 0.6 + 0.4 * pulse, HORIZONTAL_ALIGNMENT_RIGHT)
	_view.draw_set_transform(Vector2.ZERO)


func _draw_arrows(c: Vector2, edge: Color, pulse: float) -> void:
	var nudge := 4.0 * pulse
	var half := CARD_SIZE.x * 0.5 + 22.0
	if _selected > 0:
		var p := c + Vector2(-half - nudge, 0)
		_view.draw_colored_polygon(PackedVector2Array([p + Vector2(6, -14), p + Vector2(-8, 0), p + Vector2(6, 14)]), Color(edge, 0.9))
	if _selected < LevelData.LEVELS.size() - 1:
		var p := c + Vector2(half + nudge, 0)
		_view.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -14), p + Vector2(8, 0), p + Vector2(-6, 14)]), Color(edge, 0.9))


func _draw_dots(c: Vector2, edge: Color) -> void:
	var n := LevelData.LEVELS.size()
	var total := (n - 1) * 16.0 + 18.0
	var x := c.x - total * 0.5
	for i in n:
		var on := i == _selected
		var w := 26.0 if on else 8.0
		var r := Rect2(x, c.y - 4, w, 8)
		_view.draw_rect(Rect2(r.position + Vector2(4, 0), r.size - Vector2(8, 0)), Color(edge, 1.0) if on else Color(1, 1, 1, 0.3))
		_view.draw_circle(r.position + Vector2(4, 4), 4.0, Color(edge, 1.0) if on else Color(1, 1, 1, 0.3))
		_view.draw_circle(Vector2(r.end.x - 4, r.position.y + 4), 4.0, Color(edge, 1.0) if on else Color(1, 1, 1, 0.3))
		x += w + 8.0


## 造型列：角色站在小聚光燈上跟著拍子彈，換造型時跳一下
func _draw_skin_picker(box: Rect2, edge: Color, pulse: float) -> void:
	UiKit.panel(_view, box, edge, 0.5 * _skin_bump)
	var p := box.position
	var n := GameState.SKINS.size()
	UiKit.text(_view, p + Vector2(18, 26), -1, "造型" if n > 1 else "角色", 14, Color(edge, 0.9))
	if n > 1:
		UiKit.keycap(_view, Vector2(box.end.x - 70, p.y + 10), "↑", edge, 0.85)
		UiKit.keycap(_view, Vector2(box.end.x - 42, p.y + 10), "↓", edge, 0.85)

	var feet := p + Vector2(76, 98)
	var glow := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		glow.append(feet + Vector2(cos(a) * 46.0, sin(a) * 9.0))
	_view.draw_colored_polygon(glow, Color(edge, 0.18 + 0.12 * pulse))
	var hop := -sin(_skin_bump * PI) * 14.0
	var s := 1.5 * Vector2(1.0 + 0.04 * pulse, 1.0 - 0.06 * pulse)
	var pose := "jump_0" if _skin_bump > 0.3 else Player.idle_pose(Conductor.song_beat)
	Player.draw_skin(_view, GameState.skin, feet + Vector2(0, hop), s, 0.0, Color.WHITE, pose)

	var skin_name: String = GameState.SKINS[GameState.skin]["name"]
	UiKit.text(_view, p + Vector2(148, 66 if n > 1 else 72), box.size.x - 160, skin_name, 26, Color.WHITE)
	if n < 2:
		return
	for i in n:
		var on := i == GameState.skin
		_view.draw_circle(p + Vector2(154 + i * 16, 86), 4.0 if on else 3.0, Color(edge, 1.0) if on else Color(1, 1, 1, 0.3))
	UiKit.text(_view, p + Vector2(154 + n * 16, 91), -1, "%d / %d" % [GameState.skin + 1, n], 13, Color(1, 1, 1, 0.5))


## 判定難度列：選中的那格亮起，下面寫出判定窗是早／晚幾幀
func _draw_difficulty_picker(box: Rect2, edge: Color, pulse: float) -> void:
	UiKit.panel(_view, box, edge, 0.5 * _diff_bump)
	var p := box.position
	UiKit.text(_view, p + Vector2(18, 26), -1, "判定難度", 14, Color(edge, 0.9))
	UiKit.keycap(_view, Vector2(box.end.x - 70, p.y + 10), "Q", edge, 0.85)
	UiKit.keycap(_view, Vector2(box.end.x - 42, p.y + 10), "E", edge, 0.85)
	var n := GameState.DIFFICULTIES.size()
	var seg_w := (box.size.x - 36.0 - 6.0 * (n - 1)) / n
	for i in n:
		var on := i == GameState.difficulty
		var r := Rect2(p + Vector2(18.0 + i * (seg_w + 6.0), 42), Vector2(seg_w, 32))
		if on:
			r = r.grow(2.0 * _diff_bump)
			_view.draw_colored_polygon(UiKit.chamfer(r, 7.0), Color(edge, 0.85 + 0.15 * pulse))
		else:
			var loop := UiKit.chamfer(r, 7.0)
			_view.draw_colored_polygon(loop, Color(1, 1, 1, 0.06))
			loop.append(loop[0])
			_view.draw_polyline(loop, Color(1, 1, 1, 0.2), 1.0, true)
		_view.draw_string(UiKit.font(), Vector2(r.position.x, r.position.y + 22), String(GameState.DIFFICULTIES[i]["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, UiKit.INK if on else Color(1, 1, 1, 0.55))
	var d: Dictionary = GameState.DIFFICULTIES[GameState.difficulty]
	UiKit.text(_view, Vector2(p.x, box.end.y - 13), box.size.x, "早 %d 幀／晚 %d 幀內按下都算準（60fps）" % [int(d["early"]), int(d["late"])],
		13, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
