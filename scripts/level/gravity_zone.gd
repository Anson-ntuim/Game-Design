class_name GravityZone
extends Node2D
## 輕重力段落的視覺提示（實際重力由 main 依區塊 gravity 強制套用）。
## 第五關固定輕檔（1000）：藍幕＋上浮粒子；長椅外恢復正常。

const NORMAL := 2400.0
const LIGHT := 1000.0

var from_x: float = 0.0
var to_x: float = 0.0
var gravity_strength: float = NORMAL
var zone_height: float = 800.0
var show_left_boundary: bool = true
var show_right_boundary: bool = true
var _phase: float = 0.0


func setup(x0: float, x1: float, strength: float, _inverted: bool = false) -> void:
	from_x = x0
	to_x = x1
	gravity_strength = strength
	position = Vector2(x0, 0.0)


func _lightness() -> float:
	## 0 = 正常、1 = 輕重力滿檔（1000）
	return clampf((NORMAL - gravity_strength) / (NORMAL - LIGHT), 0.0, 1.0)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var w := to_x - from_x
	var lit := _lightness()
	if w <= 0.0 or lit <= 0.02:
		return
	var col := Color(0.35, 0.75, 1.0, 0.05 + 0.10 * lit)
	draw_rect(Rect2(0, -40, w, zone_height + 100), col)
	var edge := Color(0.55, 0.9, 1.0, 0.35 + 0.45 * lit)
	if show_left_boundary:
		draw_line(Vector2(0, 0), Vector2(0, zone_height), edge, 2.0 + lit)
	if show_right_boundary:
		draw_line(Vector2(w, 0), Vector2(w, zone_height), edge, 2.0 + lit)
	var n := maxi(4, int(w / 70.0)) * maxi(1, ceili(zone_height / 800.0))
	var speed := 0.55 + lit * 0.9
	for i in n:
		var x := (fposmod(i * 0.618, 1.0) + 0.5 / n) * w
		var t := fposmod(_phase * speed + i * 0.37, 1.0)
		var y := lerpf(zone_height - 80.0, 40.0, t)
		var a := 0.12 + 0.45 * lit * sin(t * PI)
		draw_circle(Vector2(x, y), 2.5 + 3.0 * lit, Color(edge, a))
