class_name GravityZone
extends Node2D
## 重力段落的視覺提示（實際重力由 main 依區塊 gravity 強制套用）。
## 輕重力：淡藍上浮粒子；重重力：琥珀下沉粒子。

const LIGHT := 1200.0
const HEAVY := 3600.0
const NORMAL := 2400.0

var from_x: float = 0.0
var to_x: float = 0.0
var gravity_strength: float = NORMAL
var _phase: float = 0.0


func setup(x0: float, x1: float, strength: float, _inverted: bool = false) -> void:
	from_x = x0
	to_x = x1
	gravity_strength = strength
	position = Vector2(x0, 0.0)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var w := to_x - from_x
	if w <= 0.0 or absf(gravity_strength - NORMAL) < 1.0:
		return
	var light := gravity_strength < NORMAL
	var col := Color(0.45, 0.85, 1.0, 0.08) if light else Color(1.0, 0.55, 0.25, 0.08)
	draw_rect(Rect2(0, -40, w, 900), col)
	var edge := Color(0.55, 0.9, 1.0, 0.55) if light else Color(1.0, 0.65, 0.3, 0.55)
	draw_line(Vector2(0, 0), Vector2(0, 800), edge, 2.0)
	draw_line(Vector2(w, 0), Vector2(w, 800), edge, 2.0)
	var n := maxi(4, int(w / 70.0))
	for i in n:
		var x := (i + 0.5) * w / n
		var t := fposmod(_phase * (0.7 if light else 1.1) + i * 0.37, 1.0)
		var y := lerpf(720.0, 80.0, t) if light else lerpf(80.0, 720.0, t)
		var a := 0.15 + 0.35 * sin(t * PI)
		draw_circle(Vector2(x, y), 3.0 + (2.0 if light else 0.0), Color(edge, a))
