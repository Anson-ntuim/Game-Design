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


## 終點拱門（手繪蠟筆圖，中間是空的）：門洞裡的光和往上飄的光點由程式畫，跟著拍子亮
const DOOR_TEX := preload("res://assets/ui/goal_door.png")
const DOOR_H := 140.0


func _draw() -> void:
	var glow := GameState.color("edge")
	var p := Conductor.pulse(4.0)
	var w := DOOR_H * float(DOOR_TEX.get_width()) / float(DOOR_TEX.get_height())
	## 門洞裡的光（畫在拱門後面）
	draw_rect(Rect2(-w * 0.28, -DOOR_H * 0.78, w * 0.56, DOOR_H * 0.78), Color(glow, 0.14 + 0.2 * p))
	draw_rect(Rect2(-w * 0.2, -DOOR_H * 0.7, w * 0.4, DOOR_H * 0.7), Color(1, 1, 1, 0.15 + 0.25 * p))
	draw_texture_rect(DOOR_TEX, Rect2(-w * 0.5, -DOOR_H, w, DOOR_H), false)
	for i in 5:
		var y := -20.0 - fposmod(Conductor.song_beat * 30.0 + i * 22.0, 110.0)
		draw_circle(Vector2(sin(i * 2.3) * 12.0, y), 2.5, Color(1, 1, 1, 0.8))
