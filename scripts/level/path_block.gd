class_name PathBlock
extends StaticBody2D
## 需先啟動對應重力／道路機關才會消失的擋路牆。

var unlock_id: String = "a"
var size: Vector2 = Vector2(40, 120)


func setup(top_left: Vector2, wh: Vector2, id: String) -> void:
	position = top_left
	size = wh
	unlock_id = id


func _ready() -> void:
	collision_layer = Player.LAYER_WORLD
	collision_mask = 0
	z_index = 3
	add_to_group("solid_ground")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	shape.position = size * 0.5
	add_child(shape)
	set_process(true)


func _process(_delta: float) -> void:
	var open := GameState.is_path_unlock(unlock_id)
	collision_layer = 0 if open else Player.LAYER_WORLD
	visible = not open
	queue_redraw()


func _draw() -> void:
	var edge := GameState.color("edge")
	draw_rect(Rect2(Vector2.ZERO, size), Color(edge, 0.35))
	draw_rect(Rect2(size * 0.5 - Vector2(2, 0), Vector2(4, size.y)), Color(edge, 0.85))
