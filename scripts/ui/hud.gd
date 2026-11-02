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
const CONTROLS_A := [[["←", "→"], "移動"], [["空白鍵"], "跳"], [["C"], "衝刺"], [["F"], "自動跑／停"]]
const CONTROLS_B := [[["↑"], "看示範"], [["R"], "重來"], [["Esc"], "選關"]]
const TIP_TIME := 6.0
const TIP_COLOR := Color(1.0, 0.45, 0.5)

var player: Player
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


## 左上：關卡編號、名稱和整關縮圖，亮起的部分是已經跑過的距離
func _draw_progress(safe: Rect2, edge: Color, lift: float) -> void:
	var box := Rect2(safe.position.x, safe.position.y - lift, 380, 72)
	UiKit.panel(_view, box, edge)
	var idx := GameState.level_index
	var parts := UiKit.split_name(String(LevelData.LEVELS[idx]["name"]))
	var pw := UiKit.pill(_view, box.position + Vector2(14, 10), "%02d" % (idx + 1), edge, UiKit.INK, 13)
	UiKit.text(_view, box.position + Vector2(22 + pw, 28), box.size.x - pw - 40, parts[1], 17, Color.WHITE)
	var info := UiKit.minimap(idx)
	var progress := 0.0
	if player:
		progress = clampf(player.global_position.x / (float(info["cols"]) * LevelData.TILE), 0.0, 1.0)
	var strip := Rect2(box.position + Vector2(14, 42), Vector2(box.size.x - 28, 20))
	UiKit.draw_minimap(_view, idx, strip, edge, 1.0, progress)
	var px := strip.position.x + strip.size.x * progress
	var p := Conductor.pulse(8.0)
	_view.draw_circle(Vector2(px, strip.get_center().y), 7.0 + p * 3.0, Color(edge, 0.35))
	_view.draw_circle(Vector2(px, strip.get_center().y), 4.5, Color.WHITE)


## 右上：死亡次數、判定、律動條；輕重力時多一條浮力度
func _draw_stats(safe: Rect2, edge: Color, lift: float) -> void:
	var lit_g := UiKit.gravity_lightness(_gravity)
	var box_h := 72.0 + (28.0 if lit_g > 0.02 else 0.0)
	var box := Rect2(safe.end.x - 260, safe.position.y - lift, 260, box_h)
	UiKit.panel(_view, box, edge, 0.6 * _death_bump)
	var p := box.position
	UiKit.text(_view, p + Vector2(16, 30), -1, "死亡", 13, Color(1, 1, 1, 0.6))
	var s := 1.0 + 0.4 * _death_bump
	_view.draw_set_transform(p + Vector2(52, 31), 0.0, Vector2(s, s))
	UiKit.bold_text(_view, Vector2.ZERO, -1, str(GameState.deaths), 22,
		Color.WHITE.lerp(Color(1.0, 0.45, 0.5), _death_bump), Color(edge, 0.6))
	_view.draw_set_transform(Vector2.ZERO)
	var judge := String(GameState.DIFFICULTIES[GameState.difficulty]["name"])
	var jw := UiKit.width_of(judge, 13) + 24.0
	UiKit.text(_view, Vector2(box.end.x - jw - 52, p.y + 30), -1, "判定", 13, Color(1, 1, 1, 0.6))
	UiKit.pill(_view, Vector2(box.end.x - jw - 14, p.y + 12), judge, Color(edge, 0.9), UiKit.INK, 13)

	UiKit.text(_view, p + Vector2(16, 60), -1, "律動", 13, Color(1, 1, 1, 0.6))
	var segs := 12
	var x0 := p.x + 56.0
	var seg_w := (box.end.x - 16.0 - x0 - (segs - 1) * 3.0) / segs
	var lit := GameState.groove * segs
	for i in segs:
		var r := Rect2(x0 + i * (seg_w + 3.0), p.y + 50, seg_w, 10)
		var k := clampf(lit - i, 0.0, 1.0)
		_view.draw_rect(r, Color(1, 1, 1, 0.1))
		if k > 0.0:
			_view.draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), edge.lerp(UiKit.GOLD, float(i) / segs))
	if lit_g > 0.02:
		var glabel := UiKit.gravity_label(_gravity)
		var gcol := UiKit.FLOAT.lerp(Color(0.75, 0.95, 1.0), lit_g)
		UiKit.pill(_view, Vector2(p.x + 14, p.y + 68), glabel, Color(gcol, 0.95), UiKit.INK, 12)
		var bar := Rect2(p.x + 70, p.y + 74, box.size.x - 86, 10)
		_view.draw_rect(bar, Color(1, 1, 1, 0.08))
		_view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * lit_g, bar.size.y)), Color(gcol, 0.85))
		_view.draw_rect(bar, Color(gcol, 0.35), false, 1.0)


func _draw_controls(safe: Rect2, edge: Color, lift: float) -> void:
	var y0 := safe.end.y + lift
	if player and player.auto_running:
		var tip := "旗子前等候 GO…" if player and player.auto_flag_wait else "自動前進中　旗子前會停等 GO　F 停止"
		UiKit.pill(_view, Vector2(safe.position.x, y0 - 80), tip, edge, UiKit.INK, 12)
	UiKit.key_hints(_view, safe.position.x, y0 - 42, CONTROLS_A, edge, 0.5, HORIZONTAL_ALIGNMENT_LEFT, 12)
	UiKit.key_hints(_view, safe.position.x, y0 - 12, CONTROLS_B, edge, 0.5, HORIZONTAL_ALIGNMENT_LEFT, 12)


func _draw_bars(size: Vector2, edge: Color) -> void:
	var h := 64.0 * ease(_bars, -2.0)
	_view.draw_rect(Rect2(0, 0, size.x, h), Color(0, 0, 0, 0.88))
	_view.draw_rect(Rect2(0, size.y - h, size.x, h), Color(0, 0, 0, 0.88))
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
	var full := String(LevelData.LEVELS[GameState.level_index]["name"])
	if _message == full:
		var parts := UiKit.split_name(full)
		text = parts[1]
		font_size = 50
		var tag := "STAGE %02d　%s" % [GameState.level_index + 1, parts[0]]
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


## 提示用 "\n" 分成兩行：第一行是標題、第二行是操作說明。
## 太寬的行會縮小字級，背景框跟著最寬的一行，但不超出安全區
func _draw_hint(safe: Rect2, edge: Color) -> void:
	var lines := _hint.split("\n", false, 1)
	var sizes: Array[int] = [24, 17]
	if lines.size() == 1:
		sizes = [19]
	var font := UiKit.font()
	var max_w := safe.size.x - 56.0
	var widest := 0.0
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sizes[i]).x
		if w > max_w:
			sizes[i] = maxi(12, floori(sizes[i] * max_w / w))
			w = font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sizes[i]).x
		widest = maxf(widest, w)
	var box_w := minf(safe.size.x, widest + 64.0)
	var top := safe.position.y + 86.0 - 8.0 * (1.0 - ease(_hint_alpha, -2.0))
	var baselines: Array[float] = []
	var y := top + 6.0
	for s in sizes:
		y += s + 9.0
		baselines.append(y)
	var box := Rect2(safe.get_center().x - box_w * 0.5, top, box_w, y - top + 14.0)
	var a := _hint_alpha
	UiKit.panel(_view, box, edge, 0.3, a, 10.0)
	for i in lines.size():
		var title := i == 0 and lines.size() > 1
		var col := Color(UiKit.GOLD, a) if title else Color(1, 1, 1, 0.92 * a)
		UiKit.text(_view, Vector2(0, baselines[i]), safe.end.x + safe.position.x, lines[i], sizes[i], col, HORIZONTAL_ALIGNMENT_CENTER)


## 下方中央、節拍條上面：倒下的提示卡，從下面滑上來，最後半秒淡出
func _draw_tip(safe: Rect2) -> void:
	var t := TIP_TIME - _tip_timer
	var a := minf(1.0, _tip_timer * 2.0) * minf(1.0, t * 4.0)
	var rise := 16.0 * (1.0 - ease(minf(1.0, t * 4.0), -2.0))
	var label := "提示"
	var pw := UiKit.width_of(label, 13) + 24.0
	var box_w := pw + 12.0 + UiKit.width_of(_tip, 17) + 44.0
	var box := Rect2(safe.get_center().x - box_w * 0.5, safe.end.y - 126.0 + rise, box_w, 50.0)
	UiKit.panel(_view, box, TIP_COLOR, 0.35, a, 10.0)
	var x := box.position.x + 22.0
	var y := box.position.y + 32.0
	UiKit.pill(_view, Vector2(x, y - 18.0), label, Color(TIP_COLOR, a), UiKit.INK, 13)
	UiKit.text(_view, Vector2(x + pw + 12.0, y), -1, _tip, 17, Color(1, 1, 1, a))


## 下方中央：拍點從兩側往中間收，收到中央的鼓就是拍點
func _draw_beat_bar(safe: Rect2, edge: Color) -> void:
	var center := Vector2(safe.get_center().x, safe.end.y - 6.0)
	var reach := 250.0
	for side: float in [-1.0, 1.0]:
		_view.draw_polygon(PackedVector2Array([center + Vector2(side * 20, -1.5), center + Vector2(side * reach, -1.5),
			center + Vector2(side * reach, 1.5), center + Vector2(side * 20, 1.5)]),
			PackedColorArray([Color(1, 1, 1, 0.3), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.3)]))
	var b := Conductor.song_beat
	var base := floori(b)
	for k in range(0, 4):
		var nb := base + k
		var dt := float(nb) - b
		if dt < -0.12 or dt > reach / 90.0:
			continue
		var dx := dt * 90.0
		var downbeat := posmod(nb, Conductor.beats_per_measure) == 0
		var h := 26.0 if downbeat else 14.0
		var a := clampf(1.0 - dt * 90.0 / reach, 0.0, 1.0)
		var col := Color(UiKit.GOLD if downbeat else edge.lerp(Color.WHITE, 0.3), a)
		for side: float in [-1.0, 1.0]:
			var x := center.x + side * (dx + 22.0)
			_view.draw_rect(Rect2(x - 2.5, center.y - h * 0.5 + 2.5, 5.0, h - 5.0), col)
			_view.draw_circle(Vector2(x, center.y - h * 0.5 + 2.5), 2.5, col)
			_view.draw_circle(Vector2(x, center.y + h * 0.5 - 2.5), 2.5, col)
	var p := Conductor.pulse(8.0)
	_view.draw_circle(center, 22.0 + p * 8.0, Color(edge, 0.15 + 0.15 * p))
	_view.draw_arc(center, 16.0, 0.0, TAU, 32, Color(edge, 0.9), 2.5, true)
	_view.draw_circle(center, 9.0 + p * 4.0, edge.lerp(Color.WHITE, p))


## 結算：面板從下方滑上來，三格數據、新紀錄標籤，背景飄著音符
func _draw_results(size: Vector2, edge: Color) -> void:
	var k := ease(minf(1.0, _results_t * 2.2), -2.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62 * k))
	_draw_confetti(size, edge, k)

	var box := Rect2(size.x * 0.5 - 310, size.y * 0.5 - 180 + (1.0 - k) * 60.0, 620, 350)
	UiKit.panel(_view, box, edge, 0.8, k, 20.0, Color(UiKit.PANEL, 0.94))
	var p := box.position
	var cx := box.get_center().x
	var pulse := Conductor.pulse(6.0)

	var head := "過關！"
	var hw := UiKit.width_of(head, 56, UiKit.title_font())
	var hs := 1.0 + 0.04 * pulse
	_view.draw_set_transform(Vector2(cx, p.y + 62), 0.0, Vector2(hs, hs))
	UiKit.bold_text(_view, Vector2(-hw * 0.5, 20), -1, head, 56, Color(UiKit.GOLD, k), edge)
	_view.draw_set_transform(Vector2.ZERO)
	var parts := UiKit.split_name(String(LevelData.LEVELS[GameState.level_index]["name"]))
	UiKit.text(_view, Vector2(p.x, p.y + 114), box.size.x, "STAGE %02d　%s　%s" % [GameState.level_index + 1, parts[0], parts[1]],
		15, Color(edge.lerp(Color.WHITE, 0.3), k), HORIZONTAL_ALIGNMENT_CENTER)

	var tiles := [
		["時間", "%.1f" % float(_results["time"]), "秒"],
		["死亡", str(int(_results["deaths"])), "次"],
		["判定", String(_results["judge"]), ""],
	]
	var gap := 14.0
	var tw := (box.size.x - 56.0 - gap * 2.0) / 3.0
	for i in 3:
		var r := Rect2(p.x + 28.0 + i * (tw + gap), p.y + 134, tw, 92)
		_view.draw_colored_polygon(UiKit.chamfer(r, 8.0), Color(1, 1, 1, 0.06 * k))
		_view.draw_rect(Rect2(r.position.x + 8, r.end.y - 3, r.size.x - 16, 3), Color(edge, 0.7 * k))
		UiKit.text(_view, r.position + Vector2(0, 28), r.size.x, tiles[i][0], 14, Color(1, 1, 1, 0.6 * k), HORIZONTAL_ALIGNMENT_CENTER)
		var value: String = tiles[i][1]
		var unit: String = tiles[i][2]
		var vw := UiKit.width_of(value, 32, UiKit.title_font())
		var uw := UiKit.width_of(unit, 15) + (4.0 if unit != "" else 0.0)
		var vx := r.get_center().x - (vw + uw) * 0.5
		UiKit.bold_text(_view, Vector2(vx, r.position.y + 72), -1, value, 32, Color(1, 1, 1, k), Color(edge, 0.5))
		if unit != "":
			UiKit.text(_view, Vector2(vx + vw + 4, r.position.y + 72), -1, unit, 15, Color(1, 1, 1, 0.7 * k))

	var best := "最佳 %.1f 秒　死亡最少 %d 次" % [float(_results["best_time"]), int(_results["best_deaths"])]
	var bw := UiKit.width_of(best, 16)
	var by := p.y + 262
	if _results["new_record"]:
		var tag := "新紀錄！"
		var tag_w := UiKit.width_of(tag, 14) + 25.0
		var x := cx - (tag_w + 10.0 + bw) * 0.5
		var s := 1.0 + 0.08 * pulse
		_view.draw_set_transform(Vector2(x + tag_w * 0.5, by - 6), deg_to_rad(-4.0), Vector2(s, s))
		UiKit.pill(_view, Vector2(-tag_w * 0.5, -12.5), tag, Color(UiKit.GOLD, k), UiKit.INK, 14)
		_view.draw_set_transform(Vector2.ZERO)
		UiKit.text(_view, Vector2(x + tag_w + 10, by), -1, best, 16, Color(UiKit.GOLD, k))
	else:
		UiKit.text(_view, Vector2(p.x, by), box.size.x, best, 16, Color(1, 1, 1, 0.75 * k), HORIZONTAL_ALIGNMENT_CENTER)

	_view.draw_line(Vector2(p.x + 28, p.y + 284), Vector2(box.end.x - 28, p.y + 284), Color(edge, 0.3 * k), 1.0)
	UiKit.key_hints(_view, cx, p.y + 302, [
		[["Enter"], "下一關" if _results["has_next"] else "回到選關"], [["R"], "再挑戰"], [["Esc"], "選關"],
	], edge, k)


func _draw_confetti(size: Vector2, edge: Color, k: float) -> void:
	var f := UiKit.font()
	var glyphs := ["♪", "♫", "♩"]
	for i in 26:
		var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var speed := 50.0 + 60.0 * fposmod(sin(i * 78.233) * 12345.678, 1.0)
		var x := seed_x * size.x + sin(_results_t * 1.5 + i) * 16.0
		var y := fposmod(_results_t * speed + i * 57.0, size.y + 60.0) - 30.0
		var col: Color = [edge, UiKit.GOLD, Color.WHITE][i % 3]
		_view.draw_string(f, Vector2(x, y), glyphs[i % 3], HORIZONTAL_ALIGNMENT_LEFT, -1, 18 + (i % 4) * 4, Color(col, 0.45 * k))
