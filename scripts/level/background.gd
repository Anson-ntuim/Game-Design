class_name Background
extends Node2D
## 多層視差背景：天空漸層、隨拍脈動的月亮、等化器光柱、遺跡剪影、漂浮光點。
## 顏色取自 Game 色盤，所以每個音樂段落都會換一種氛圍。

var level_height: float = 800.0
## 舞台模式：從畫面底部打上來、跟著節拍擺動的聚光燈
var stage: bool = false


func _ready() -> void:
	z_index = -100


func _process(_delta: float) -> void:
	queue_redraw()


func _hash(i: int) -> float:
	return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center := cam.get_screen_center_position()
	var size := get_viewport_rect().size / cam.zoom + Vector2(40, 40)
	var tl := center - size * 0.5
	var b := Conductor.song_beat
	var pulse := Conductor.pulse(6.0)
	var groove := GameState.groove
	var edge := GameState.color("edge")

	var top := GameState.color("bg_top")
	var bottom := GameState.color("bg_bottom")
	draw_polygon(
		PackedVector2Array([tl, tl + Vector2(size.x, 0), tl + size, tl + Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	var moon := tl + Vector2(size.x * 0.74, size.y * 0.26)
	var moon_r := 62.0 + pulse * (6.0 + 10.0 * groove)
	for i in 4:
		draw_circle(moon, moon_r + 18.0 * (i + 1) + pulse * 8.0, Color(edge, 0.05 + 0.03 * pulse))
	draw_circle(moon, moon_r, top.lerp(Color.WHITE, 0.82))

	if stage:
		_draw_spotlights(tl, size, b, pulse, edge)
	_draw_equalizer(tl, size, center, b, pulse, groove)
	_draw_ruins(tl, size, center, pulse)
	_draw_motes(tl, size, center, b, pulse, groove)


func _draw_equalizer(tl: Vector2, size: Vector2, center: Vector2, b: float, pulse: float, groove: float) -> void:
	var factor := 0.15
	var spacing := 46.0
	var shift := center.x * (1.0 - factor)
	var first := floori((tl.x - shift) / spacing) - 1
	var last := ceili((tl.x + size.x - shift) / spacing) + 1
	var far := GameState.color("far")
	var eighth := floori(b * 2.0)
	var base_y := tl.y + size.y * 0.8
	for i in range(first, last):
		var x := i * spacing + shift
		var v := 0.25 + 0.75 * absf(sin(i * 1.7 + eighth * 2.3))
		var h := (70.0 + 170.0 * v) * (0.45 + 0.55 * pulse) * (0.8 + 0.5 * groove)
		draw_rect(Rect2(x, base_y - h, spacing * 0.62, h), Color(far, 0.55))
		draw_rect(Rect2(x, base_y - h, spacing * 0.62, 4), Color(far.lerp(Color.WHITE, 0.4), 0.7))


func _draw_spotlights(tl: Vector2, size: Vector2, b: float, pulse: float, edge: Color) -> void:
	var count := 5
	var downbeat := posmod(floori(b), Conductor.beats_per_measure) == 0
	for i in count:
		var base := tl + Vector2(size.x * (i + 0.5) / count, size.y + 30.0)
		var sway := sin(b * PI * 0.5 + i * 1.3) * 0.45 * (1.0 if i % 2 == 0 else -1.0)
		var dir := Vector2(sin(sway), -cos(sway))
		var length := size.y * 1.5
		var spread := 0.11
		var tip_l := base + dir.rotated(-spread) * length
		var tip_r := base + dir.rotated(spread) * length
		var hue_shift := Color.from_hsv(fposmod(edge.h + i * 0.13, 1.0), 0.55, 1.0)
		var a := 0.05 + 0.07 * pulse + (0.06 * pulse if downbeat else 0.0)
		draw_colored_polygon(PackedVector2Array([base, tip_l, tip_r]),
			Color(hue_shift, a))
		draw_colored_polygon(PackedVector2Array([base, base + dir.rotated(-spread * 0.4) * length, base + dir.rotated(spread * 0.4) * length]),
			Color(hue_shift, a * 0.8))


func _draw_ruins(tl: Vector2, size: Vector2, center: Vector2, pulse: float) -> void:
	var factor := 0.45
	var spacing := 170.0
	var shift := center.x * (1.0 - factor)
	var y_shift := (center.y - level_height * 0.5) * 0.3
	var first := floori((tl.x - shift) / spacing) - 1
	var last := ceili((tl.x + size.x - shift) / spacing) + 1
	var mid := GameState.color("mid")
	var edge := GameState.color("edge")
	var base_y := tl.y + size.y + 20.0 - y_shift
	for i in range(first, last):
		var x := i * spacing + shift + _hash(i) * 60.0
		var w := 40.0 + _hash(i + 50) * 60.0
		var h := 160.0 + _hash(i + 99) * 260.0
		draw_rect(Rect2(x, base_y - h, w, h + 400.0), mid)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 6, base_y - h), Vector2(x + w * 0.5, base_y - h - 26.0), Vector2(x + w + 6, base_y - h)]), mid)
		var lit := posmod(i + floori(Conductor.song_beat), 3) == 0
		var a := (0.25 + 0.75 * pulse) if lit else 0.12
		draw_rect(Rect2(x + w * 0.5 - 3.0, base_y - h + 30.0, 6, 10), Color(edge, a))


func _draw_motes(tl: Vector2, size: Vector2, center: Vector2, b: float, pulse: float, groove: float) -> void:
	var factor := 0.8
	var shift := center.x * (1.0 - factor)
	var count := 36 + int(groove * 30.0)
	var edge := GameState.color("edge")
	for i in count:
		var span := size.x + 200.0
		var lx := fposmod(_hash(i) * 3000.0 - (tl.x - shift), span)
		var x := tl.x + lx - 100.0
		var y := tl.y + fposmod(_hash(i + 300) * size.y - b * (12.0 + _hash(i + 7) * 20.0), size.y)
		var r := 1.5 + _hash(i + 11) * 2.0 + pulse * 1.5
		draw_circle(Vector2(x, y), r, Color(edge.lerp(Color.WHITE, 0.5), 0.25 + 0.45 * pulse))
