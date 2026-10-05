class_name BeatHopper
extends Area2D
## 每一拍跳一下的甲蟲，在出生點左右來回巡邏。打不倒，只能抓準牠的節奏跳過去。

var hop_height: float = 26.0
var step_px: float = 20.0

var _home: Vector2
var _facing: float = 1.0
var _land_squash: float = 0.0


func setup(feet_pos: Vector2) -> void:
	_home = feet_pos
	position = feet_pos


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	z_index = 5
	add_to_group("enemy")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(34, 28)
	shape.shape = r
	shape.position = Vector2(0, -14)
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var step := floori(b)
	var hop_t := clampf((b - step) / 0.45, 0.0, 1.0)
	var cur := _patrol(step)
	var nxt := _patrol(step + 1)
	if nxt != cur:
		_facing = signf(nxt - cur)
	var x := lerpf(cur, nxt, smoothstep(0.0, 1.0, hop_t))
	var y := -sin(hop_t * PI) * hop_height
	var since_land := (b - step) - 0.45
	_land_squash = exp(-since_land * 10.0) if since_land >= 0.0 else 0.0
	position = _home + Vector2(x * step_px, y)
	queue_redraw()


func _patrol(step: int) -> float:
	var t := posmod(step, 8)
	return float(t if t <= 4 else 8 - t) - 2.0


func is_harmful() -> bool:
	return true


func _draw() -> void:
	var scale_v := Vector2(1.0 + _land_squash * 0.25, 1.0 - _land_squash * 0.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_v.x * _facing, scale_v.y))
	var shell := GameState.color("edge").lerp(Color(1.0, 0.45, 0.25), 0.55)
	var body := Color(0.08, 0.07, 0.1)
	draw_rect(Rect2(-14, -6, 4, 6), body)
	draw_rect(Rect2(10, -6, 4, 6), body)
	draw_circle(Vector2(0, -14), 15.0, body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-17, -12), Vector2(-10, -28), Vector2(8, -30), Vector2(16, -16), Vector2(6, -10)]), shell)
	draw_circle(Vector2(10, -12), 3.5, Color.WHITE)
	draw_circle(Vector2(11, -12), 1.8, Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
