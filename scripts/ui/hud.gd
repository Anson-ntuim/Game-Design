class_name Hud
extends CanvasLayer
## 介面：關卡進度、死亡次數與律動條、節拍指示條、區塊提示、倒下的提示卡、示範時的上下黑邊、盲拍的黑幕、淡出與結算畫面。

const DARK_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size;
uniform vec2 center;
uniform float radius = 70.0;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV * rect_size, center);
	COLOR = vec4(0.0, 0.0, 0.02, amount * 0.97 * smoothstep(radius, radius * 2.2, d));
}
"
const CONTROLS_A := [[["空白鍵"], "跳"], [["C", "Shift"], "衝刺"], [["F"], "自動／手動"], [["←", "→"], "手動移動"]]
const CONTROLS_B := [[["↑"], "看示範"], [["[", "]"], "畫質"], [["R"], "重來"], [["Esc"], "暫停"]]
const TIP_TIME := 6.0
const TIP_COLOR := Color(1.0, 0.45, 0.5)
const SAKURA_ROSE := Color("e6a0b7")
const SAKURA_CREAM := Color("ffe0ad")
const SAKURA_MINT := Color("bfe8d2")
const FESTIVAL_PINK := Color("ff61d5")
const FESTIVAL_CYAN := Color("66e7ff")
const FESTIVAL_GOLD := Color("ffe19a")

var player: Player
var tempo_mode: bool = false
var _gravity: float = 2400.0

var _view: Control
var _message: String = ""
var _message_timer: float = 0.0
var _message_duration: float = 1.0
var _hint: String = ""
var _hint_alpha: float = 0.0
var _fade: float = 0.0
var _results: Dictionary = {}
var _results_t: float = 0.0
var _watching: bool = false
var _bars: float = 0.0
var _dark_rect: ColorRect
var _dark: float = 0.0
var _dark_target: float = 0.0
var _deaths_shown: int = 0
var _death_bump: float = 0.0
## 倒下後的提示卡：一句指令（太短、太長、太早、太晚才有）
var _tip: String = ""
var _tip_timer: float = 0.0


func _ready() -> void:
	layer = 10
	_dark_rect = ColorRect.new()
	_dark_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = DARK_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_dark_rect.material = mat
	_dark_rect.visible = false
	add_child(_dark_rect)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_on_view_draw)
	UiKit.minimap(GameState.level_index)
	_deaths_shown = GameState.deaths


func _process(delta: float) -> void:
	_message_timer = maxf(0.0, _message_timer - delta)
	_tip_timer = maxf(0.0, _tip_timer - delta)
	_hint_alpha = move_toward(_hint_alpha, 1.0 if _hint != "" else 0.0, delta * 3.0)
	_bars = move_toward(_bars, 1.0 if _watching else 0.0, delta * 3.0)
	_dark = move_toward(_dark, _dark_target, delta * 20.0)
	if not _results.is_empty():
		_results_t += delta
	if GameState.deaths != _deaths_shown:
		_deaths_shown = GameState.deaths
		_death_bump = 1.0
	_death_bump = move_toward(_death_bump, 0.0, delta * 2.5)
	_dark_rect.visible = _dark > 0.0
	if _dark_rect.visible:
		var mat := _dark_rect.material as ShaderMaterial
		mat.set_shader_parameter("rect_size", _dark_rect.size)
		mat.set_shader_parameter("amount", _dark)
		if player:
			mat.set_shader_parameter("center", player.get_global_transform_with_canvas().origin)
	_view.queue_redraw()


## 盲拍：0 = 全亮、1 = 全暗（角色周圍留一圈微光）
func set_dark(amount: float) -> void:
	_dark_target = amount


func set_gravity(strength: float) -> void:
	_gravity = strength


func set_hint(text: String) -> void:
	if text != _hint:
		_hint = text
		_hint_alpha = 0.0


## 看起跳旗示範的期間畫面上下出現黑邊
func set_watching(on: bool) -> void:
	_watching = on


func show_message(text: String, duration: float = 2.0) -> void:
	_message = text
	_message_timer = duration
	_message_duration = duration


func show_tip(text: String) -> void:
	_tip = text
	_tip_timer = TIP_TIME


## data：time、deaths、judge、new_record、best_time、best_deaths、has_next
func show_results(data: Dictionary) -> void:
	_results = data
	_results_t = 0.0


func fade(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_fade", 1.0, duration * 0.4)
	tw.tween_interval(duration * 0.2)
	tw.tween_property(self, "_fade", 0.0, duration * 0.4)


func _on_view_draw() -> void:
	var size := _view.size
	var safe := UiKit.safe_rect(size)
	var edge := GameState.color("edge")
	if _sakura_park_style():
		edge = SAKURA_ROSE
	elif _music_festival_style():
		edge = FESTIVAL_PINK
	var done := not _results.is_empty()
	var lift := 110.0 * ease(_bars, -2.0)
	if not done and lift < 109.0:
		_draw_progress(safe, edge, lift)
		_draw_stats(safe, edge, lift)
		_draw_controls(safe, edge, lift)
	if _bars > 0.0:
		_draw_bars(size, edge)
	_draw_beat_bar(safe, edge)

	if _message_timer > 0.0 and not done:
		_draw_message(size, edge)
	if _hint != "" and _hint_alpha > 0.0:
		_draw_hint(safe, edge)
	if _tip_timer > 0.0 and not done and not _watching:
		_draw_tip(safe)
	if done:
		_draw_results(size, edge)

	if _fade > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))


func _soft_city_style() -> bool:
	return GameState.level_index == 0 and String(GameState.current_theme().get("id", "")) == "heartbeat_city"


func _sakura_park_style() -> bool:
	if GameState.level_index < 0 or GameState.level_index >= LevelData.LEVELS.size():
		return false
	return String(LevelData.level_info(GameState.level_index).get("background_profile", "")) == "sakura_park"


func _music_festival_style() -> bool:
	if GameState.level_index < 0 or GameState.level_index >= LevelData.LEVELS.size():
		return false
	return String(LevelData.level_info(GameState.level_index).get("background_profile", "")) == "music_festival"


## 左上：關卡編號和整關縮圖，亮起的部分是已經跑過的距離
## 左上：關卡編號 + 目前段落名 + 一排小格（第幾段／共幾段）
func _draw_progress(safe: Rect2, _edge: Color, lift: float) -> void:
	var main := get_tree().get_first_node_in_group("main")
	var info: Dictionary = main.call("hud_section_info") if main else {"index": -1, "total": 0, "title": ""}
	var title := UiKit.safe_text(String(info["title"]))
	var total := int(info["total"])
	var seg_w := 18.0
	var segs_w := total * (seg_w + 4.0)
	var title_w := UiKit.width_of(title, 15)
	var box := Rect2(safe.position.x, safe.position.y - lift, 64.0 + maxf(title_w, segs_w) + 18.0, 54.0)
	_capsule(box, Color(UiKit.NIGHT, 0.8))
	var chip := Rect2(box.position + Vector2(8, 8), Vector2(42, 38))
	_capsule(chip, UiKit.PINK)
	_view.draw_string(UiKit.display_font(700), Vector2(chip.position.x, chip.get_center().y + 7), LevelData.level_code(GameState.level_index),
		HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 18, UiKit.INK)
	UiKit.text(_view, box.position + Vector2(62, 24), -1, title, 15, UiKit.TEXT)
	var cur := int(info["index"])
	for i in total:
		var col := Color(1, 1, 1, 0.25)
		if i < cur:
			col = UiKit.PINK
		elif i == cur:
			col = UiKit.YELLOW
		var r := Rect2(box.position.x + 62 + i * (seg_w + 4.0), box.position.y + 34, seg_w, 5)
		_capsule(r, col)


## 右上：倒下次數（愛心）＋判定難度；輕重力時多一顆「輕重力」膠囊
func _draw_stats(safe: Rect2, _edge: Color, lift: float) -> void:
	var judge := String(GameState.DIFFICULTIES[GameState.difficulty]["name"])
	var deaths := str(GameState.deaths)
	var w := 30.0 + UiKit.width_of("倒下", 15) + 8.0 + UiKit.width_of(deaths, 20) + 18.0
	var box := Rect2(safe.end.x - w, safe.position.y - lift, w, 46)
	_capsule(box, Color(UiKit.NIGHT, 0.8))
	var s := 1.0 + 0.35 * _death_bump
	var heart := box.position + Vector2(22, 23)
	_view.draw_set_transform(heart, 0.0, Vector2(s, s))
	_draw_heart(Vector2.ZERO, 8.0, UiKit.PINK.lerp(Color.WHITE, _death_bump * 0.5))
	_view.draw_set_transform(Vector2.ZERO)
	UiKit.text(_view, box.position + Vector2(38, 29), -1, "倒下", 15, UiKit.TEXT)
	UiKit.text(_view, box.position + Vector2(46 + UiKit.width_of("倒下", 15), 30), -1, deaths, 20, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(700))
	var jw := UiKit.width_of(judge, 13) + 24.0
	var jbox := Rect2(box.position.x - jw - 8, box.position.y + 8, jw, 30)
	_capsule(jbox, Color(UiKit.NIGHT, 0.8))
	UiKit.text(_view, Vector2(jbox.position.x, jbox.position.y + 20), jw, judge, 13, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var lit_g := UiKit.gravity_lightness(_gravity)
	if lit_g > 0.02:
		var glabel := UiKit.gravity_label(_gravity)
		var gw := UiKit.width_of(glabel, 13) + 26.0
		var g := Rect2(safe.end.x - gw, box.end.y + 8, gw, 28)
		_capsule(g, Color(UiKit.CYAN, 0.9))
		UiKit.text(_view, Vector2(g.position.x, g.position.y + 19), gw, glabel, 13, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)


## 左下：狀態膠囊（旗子前等候、手動模式、變速）＋第一關才顯示的按鍵說明
func _draw_controls(safe: Rect2, _edge: Color, lift: float) -> void:
	var y0 := safe.end.y + lift
	var status := ""
	if player and player.auto_running and player.auto_flag_wait:
		status = "旗子前等候，數到 0 自動出發"
	elif player and not player.auto_running and not player.control_locked and not GameState.auto_run:
		status = "手動移動中　F 切回自動前進"
	elif tempo_mode or Conductor.custom_music:
		status = "%d BPM" % roundi(Conductor.current_bpm)
	if status != "":
		var sw := UiKit.width_of(status, 13) + 28.0
		var r := Rect2(safe.position.x, y0 - 176, sw, 30)
		_capsule(r, Color(UiKit.NIGHT, 0.8))
		UiKit.text(_view, Vector2(r.position.x, r.position.y + 20), sw, status, 13, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	if GameState.level_index == 0:
		## 節拍軌在下方中央，按鍵說明放在它上面一點的左側
		UiKit.key_hints(_view, safe.position.x, y0 - 136, CONTROLS_A, UiKit.LINE, 0.75, HORIZONTAL_ALIGNMENT_LEFT, 12)
		UiKit.key_hints(_view, safe.position.x, y0 - 106, CONTROLS_B, UiKit.LINE, 0.75, HORIZONTAL_ALIGNMENT_LEFT, 12)


func _capsule(r: Rect2, fill: Color) -> void:
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(int(r.size.y * 0.5))
	st.bg_color = fill
	_view.draw_style_box(st, r)


func _draw_heart(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * r / 16.0)
	_view.draw_colored_polygon(pts, col)


func _draw_bars(size: Vector2, edge: Color) -> void:
	var h := 64.0 * ease(_bars, -2.0)
	var bar_fill := Color(0, 0, 0, 0.88)
	if _sakura_park_style():
		bar_fill = Color(0.12, 0.045, 0.14, 0.88)
	elif _music_festival_style():
		bar_fill = Color(0.025, 0.015, 0.11, 0.90)
	_view.draw_rect(Rect2(0, 0, size.x, h), bar_fill)
	_view.draw_rect(Rect2(0, size.y - h, size.x, h), bar_fill)
	_view.draw_line(Vector2(0, h), Vector2(size.x, h), Color(edge, 0.5 * _bars), 2.0)
	_view.draw_line(Vector2(0, size.y - h), Vector2(size.x, size.y - h), Color(edge, 0.5 * _bars), 2.0)
	var a := clampf(_bars * 2.0 - 1.0, 0.0, 1.0)
	if a <= 0.0:
		return
	var label := "看一遍節奏，旗子倒數 3、2、1 後換你跑"
	var pw := UiKit.width_of("示範中", 14) + 25.0
	var total := pw + 12.0 + UiKit.width_of(label, 17)
	var x := size.x * 0.5 - total * 0.5
	var y := h - 32.0
	var blink := 0.6 + 0.4 * Conductor.pulse(6.0)
	UiKit.pill(_view, Vector2(x, y - 18), "示範中", Color(edge, a * blink), UiKit.INK, 14)
	UiKit.text(_view, Vector2(x + pw + 12, y), -1, label, 17, Color(1, 1, 1, 0.9 * a))


## 訊息出現時先放大一點再縮回，兩側的線往外拉開
func _draw_message(size: Vector2, edge: Color) -> void:
	var a := minf(1.0, _message_timer * 2.0)
	var t := _message_duration - _message_timer
	var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - t * 6.0)
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	var font_size := 42
	var text := _message
	var code := LevelData.level_code(GameState.level_index)
	if _message == code or _message == String(LevelData.level_info(GameState.level_index).get("name", "")):
		text = code
		font_size = 56
		var tag := "STAGE"
		var tw := UiKit.width_of(tag, 15) + 26.0
		UiKit.pill(_view, Vector2(c.x - tw * 0.5, c.y - font_size * 0.64 - 40), tag, Color(edge, a), UiKit.INK, 15)
	var w := UiKit.width_of(text, font_size, UiKit.title_font())
	_view.draw_set_transform(c, 0.0, Vector2(pop, pop))
	UiKit.bold_text(_view, Vector2(-w * 0.5, font_size * 0.36), -1, text, font_size, Color(1, 1, 1, a), edge)
	_view.draw_set_transform(Vector2.ZERO)
	var spread := ease(minf(1.0, t * 3.0), -2.0)
	for side: float in [-1.0, 1.0]:
		var x0 := c.x + side * (w * 0.5 + 24.0)
		_view.draw_line(Vector2(x0, c.y), Vector2(x0 + side * 120.0 * spread, c.y), Color(edge, 0.8 * a), 3.0)
		_view.draw_circle(Vector2(x0 + side * (120.0 * spread + 8.0), c.y), 4.0, Color(edge, a))


## 上方中央：段落提示卡。第一行是黃色「段落名」膠囊，第二行是怎麼按
func _draw_hint(safe: Rect2, _edge: Color) -> void:
	var lines := _hint.split("\n", false, 1)
	var title := lines[0] if lines.size() > 1 else "提示"
	var body := lines[1] if lines.size() > 1 else lines[0]
	var size := 16
	var tw := UiKit.width_of(title, 13) + 22.0
	var max_body := safe.size.x - 240.0
	var bw := UiKit.width_of(body, size)
	if bw > max_body:
		size = maxi(12, floori(size * max_body / bw))
		bw = UiKit.width_of(body, size)
	var w := 20.0 + tw + 12.0 + bw + 22.0
	var a := _hint_alpha
	var top := safe.position.y + 78.0 - 8.0 * (1.0 - ease(a, -2.0))
	var box := Rect2(safe.get_center().x - w * 0.5, top, w, 48)
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(18)
	st.bg_color = Color(UiKit.NIGHT, 0.82 * a)
	_view.draw_style_box(st, box)
	var chip := Rect2(box.position + Vector2(16, 11), Vector2(tw, 26))
	st.set_corner_radius_all(10)
	st.bg_color = Color(UiKit.YELLOW, a)
	_view.draw_style_box(st, chip)
	UiKit.text(_view, Vector2(chip.position.x, chip.position.y + 18), tw, title, 13, Color(UiKit.INK, a), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
	UiKit.text(_view, Vector2(chip.end.x + 12, box.position.y + 30), -1, body, size, Color(UiKit.TEXT, a))


## 倒下後的提示：跟段落提示同樣的卡，粉色膠囊，在節拍軌上方
func _draw_tip(safe: Rect2) -> void:
	var t := TIP_TIME - _tip_timer
	var a := minf(1.0, _tip_timer * 2.0) * minf(1.0, t * 4.0)
	var rise := 16.0 * (1.0 - ease(minf(1.0, t * 4.0), -2.0))
	var label := "提示"
	var tw := UiKit.width_of(label, 13) + 22.0
	var w := 20.0 + tw + 12.0 + UiKit.width_of(_tip, 16) + 22.0
	var box := Rect2(safe.get_center().x - w * 0.5, safe.end.y - 150.0 + rise, w, 48.0)
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(18)
	st.bg_color = Color(UiKit.NIGHT, 0.86 * a)
	_view.draw_style_box(st, box)
	var chip := Rect2(box.position + Vector2(16, 11), Vector2(tw, 26))
	st.set_corner_radius_all(10)
	st.bg_color = Color(UiKit.PINK, a)
	_view.draw_style_box(st, chip)
	UiKit.text(_view, Vector2(chip.position.x, chip.position.y + 18), tw, label, 13, Color(UiKit.INK, a), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
	UiKit.text(_view, Vector2(chip.end.x + 12, box.position.y + 30), -1, _tip, 16, Color(UiKit.TEXT, a))


## 下方中央：節拍軌。拍線從右往左流到判定圈，接下來要按的動作（跳／音符／衝）也一起流過來，
## 流到圈上那一刻就是該按的時機（取代原本看不懂的「律動」條）
const TRACK_W := 760.0
const TRACK_H := 74.0
const TRACK_PX_PER_BEAT := 60.0
const TRACK_HIT_X := 112.0


func _draw_beat_bar(safe: Rect2, _edge: Color) -> void:
	var lane := Rect2(safe.get_center().x - TRACK_W * 0.5, safe.end.y - TRACK_H + 2.0, TRACK_W, TRACK_H)
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(int(TRACK_H * 0.5))
	st.bg_color = Color(UiKit.NIGHT, 0.82)
	_view.draw_style_box(st, lane)
	var mid := lane.get_center().y
	var hit_x := lane.position.x + TRACK_HIT_X
	_view.draw_line(Vector2(lane.position.x + 30, mid), Vector2(lane.end.x - 30, mid), Color(UiKit.LINE, 1.0), 2.0)
	var b := Conductor.song_beat
	var max_dt := (lane.end.x - 40.0 - hit_x) / TRACK_PX_PER_BEAT
	for k in range(floori(b), ceili(b + max_dt) + 1):
		var x := hit_x + (float(k) - b) * TRACK_PX_PER_BEAT
		if x < lane.position.x + 34.0 or x > lane.end.x - 34.0:
			continue
		var bar := posmod(k, 4) == 0
		var h := 30.0 if bar else 14.0
		_view.draw_line(Vector2(x, mid - h * 0.5), Vector2(x, mid + h * 0.5), Color(1, 1, 1, 0.6 if bar else 0.3), 2.0)
	var p := Conductor.pulse(8.0)
	_view.draw_arc(Vector2(hit_x, mid), 24.0 + p * 3.0, 0.0, TAU, 40, UiKit.PINK, 4.0, true)
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return
	for ev: Dictionary in main.call("track_events"):
		var dt := float(ev["beat"]) - b
		if dt < -0.35 or dt > max_dt:
			continue
		var x := hit_x + dt * TRACK_PX_PER_BEAT
		var act := String(ev["act"])
		var col := UiKit.PINK
		var label := "跳"
		if act in ["O", "o"]:
			col = UiKit.YELLOW
			label = "♪"
		elif act in ["D", "R"]:
			col = UiKit.CYAN
			label = "衝"
		var a := 1.0 if dt >= 0.0 else clampf(1.0 + dt / 0.35, 0.0, 1.0)
		_view.draw_circle(Vector2(x, mid), 18.0, Color(col, a))
		_view.draw_string(UiKit.font(0.6), Vector2(x - 18.0, mid + 6.0), label, HORIZONTAL_ALIGNMENT_CENTER, 36.0, 15, Color(UiKit.INK, a))


## 結算：左邊大字 CLEAR!，右邊成績卡（評等、時間、倒下、最佳紀錄），下方三個按鍵
func _draw_results(size: Vector2, edge: Color) -> void:
	var k := ease(minf(1.0, _results_t * 2.2), -2.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.NIGHT, 0.72 * k))
	_draw_confetti(size, edge, k)
	var pulse := Conductor.pulse(6.0)
	var left := Vector2(96, 150 + (1.0 - k) * 30.0)
	UiKit.text(_view, left, -1, "STAGE %s" % LevelData.level_code(GameState.level_index), 18, Color(UiKit.MUTED, k), HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(600))
	var head := "CLEAR!"
	var hs := 1.0 + 0.03 * pulse
	_view.draw_set_transform(left + Vector2(0, 100), 0.0, Vector2(hs, hs))
	_view.draw_string(UiKit.title_font(), Vector2(6, 6), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Color(UiKit.PINK, k))
	_view.draw_string(UiKit.title_font(), Vector2.ZERO, head, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Color(UiKit.TEXT, k))
	_view.draw_set_transform(Vector2.ZERO)

	var box := Rect2(size.x - 96 - 520, 90 + (1.0 - k) * 60.0, 520, 520)
	UiKit.panel(_view, box, UiKit.PINK, 0.0, k, 18.0, Color(UiKit.CARD, 0.97))
	var p := box.position
	var deaths := int(_results["deaths"])
	var grade := "S" if deaths == 0 else ("A" if deaths <= 2 else ("B" if deaths <= 5 else "C"))
	var g := Rect2(p + Vector2(32, 32), Vector2(120, 120))
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(30)
	st.bg_color = Color(UiKit.PINK, k)
	_view.draw_style_box(st, g)
	_view.draw_string(UiKit.title_font(), Vector2(g.position.x, g.position.y + 88), grade, HORIZONTAL_ALIGNMENT_CENTER, g.size.x, 80, Color(UiKit.INK, k))
	UiKit.text(_view, p + Vector2(180, 64), -1, "評等依倒下次數", 15, Color(UiKit.MUTED, k))
	UiKit.text(_view, p + Vector2(180, 112), -1, "判定　" + String(_results["judge"]), 24, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, UiKit.font(0.6))
	if _results["new_record"]:
		var tag := Rect2(p + Vector2(180, 126), Vector2(UiKit.width_of("新紀錄", 13) + 22.0, 26))
		st.set_corner_radius_all(10)
		st.bg_color = Color(UiKit.YELLOW, k)
		_view.draw_style_box(st, tag)
		UiKit.text(_view, Vector2(tag.position.x, tag.position.y + 18), tag.size.x, "新紀錄", 13, Color(UiKit.INK, k), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))

	var tiles := [
		["通關時間", "%.1f 秒" % float(_results["time"]), UiKit.CYAN],
		["倒下次數", str(deaths), UiKit.PINK],
		["最佳時間", "%.1f 秒" % float(_results["best_time"]), UiKit.YELLOW],
	]
	var tw := (box.size.x - 64.0 - 20.0) / 3.0
	for i in 3:
		var r := Rect2(p.x + 32.0 + i * (tw + 10.0), p.y + 184, tw, 96)
		st.set_corner_radius_all(16)
		st.bg_color = Color(UiKit.NIGHT, k)
		_view.draw_style_box(st, r)
		UiKit.text(_view, r.position + Vector2(14, 30), -1, tiles[i][0], 14, Color(tiles[i][2], k))
		UiKit.text(_view, r.position + Vector2(14, 72), -1, tiles[i][1], 26, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, UiKit.display_font(700))
	UiKit.text(_view, p + Vector2(32, 324), box.size.x - 64, "最少倒下　%d 次" % int(_results["best_deaths"]), 17, Color(UiKit.MUTED, k))

	var bw := (box.size.x - 64.0 - 20.0) / 3.0
	var labels := ["Esc　選關", "R　再玩一次", ("Enter　下一關" if _results["has_next"] else "Enter　選關")]
	for i in 3:
		var r := Rect2(p.x + 32.0 + i * (bw + 10.0), box.end.y - 88, bw, 56)
		if i == 2:
			UiKit.solid_button(_view, r, labels[i], UiKit.PINK, UiKit.PINK_DARK, 17, k)
		else:
			UiKit.panel(_view, r, UiKit.LINE, 0.0, k, 10.0, Color(UiKit.NIGHT, 0.9))
			UiKit.text(_view, Vector2(r.position.x, r.position.y + 35), r.size.x, labels[i], 16, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_confetti(size: Vector2, edge: Color, k: float) -> void:
	var count := GameState.quality_int("confetti", 26)
	if count <= 0:
		return
	var f := UiKit.font()
	var glyphs := ["♪", "♫", "♩"]
	for i in count:
		var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var speed := 50.0 + 60.0 * fposmod(sin(i * 78.233) * 12345.678, 1.0)
		var x := seed_x * size.x + sin(_results_t * 1.5 + i) * 16.0
		var y := fposmod(_results_t * speed + i * 57.0, size.y + 60.0) - 30.0
		var col: Color = [edge, UiKit.GOLD, Color.WHITE][i % 3]
		_view.draw_string(f, Vector2(x, y), glyphs[i % 3], HORIZONTAL_ALIGNMENT_LEFT, -1, 18 + (i % 4) * 4, Color(col, 0.45 * k))
