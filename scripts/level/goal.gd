class_name Goal
extends Area2D
## 關卡終點之門。

signal reached

var _done: bool = false


func setup(feet_pos: Vector2) -> void:
	position = feet_pos


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	z_index = 3
	add_to_group("goal")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(50, 110)
	shape.shape = r
	shape.position = Vector2(0, -55)
	add_child(shape)


func _process(_delta: float) -> void:
	queue_redraw()


func reach(_player: Player) -> void:
	if _done:
		return
	_done = true
	reached.emit()


func _draw() -> void:
	var glow := GameState.color("edge")
	var p := Conductor.pulse(4.0)
	draw_rect(Rect2(-30, -120, 60, 120), Color(glow, 0.12 + 0.18 * p))
	draw_rect(Rect2(-22, -110, 44, 110), Color(1, 1, 1, 0.15 + 0.25 * p))
	draw_rect(Rect2(-34, -126, 8, 126), Color(0.9, 0.92, 1.0))
	draw_rect(Rect2(26, -126, 8, 126), Color(0.9, 0.92, 1.0))
	draw_rect(Rect2(-38, -132, 76, 10), Color(0.9, 0.92, 1.0))
	for i in 5:
		var y := -20.0 - fposmod(Conductor.song_beat * 30.0 + i * 22.0, 110.0)
		draw_circle(Vector2(sin(i * 2.3) * 12.0, y), 2.5, Color(1, 1, 1, 0.8))
