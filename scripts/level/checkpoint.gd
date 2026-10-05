class_name Checkpoint
extends Area2D
## 長椅存檔點：碰到就設定重生點，倒下後會回到最後坐過的長椅。

signal activated(checkpoint: Checkpoint)

var active: bool = false


func setup(feet_pos: Vector2) -> void:
	position = feet_pos


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	z_index = 3
	add_to_group("checkpoint")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(60, 60)
	shape.shape = r
	shape.position = Vector2(0, -30)
	add_child(shape)


func _process(_delta: float) -> void:
	queue_redraw()


func activate(player: Player) -> void:
	player.checkpoint_position = global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5 - 1.0)
	if not active:
		active = true
		activated.emit(self)


func _draw() -> void:
	var wood := Color(0.55, 0.45, 0.35)
	var glow := GameState.color("edge")
	if active:
		var p := Conductor.pulse(5.0)
		draw_circle(Vector2(0, -24), 34.0 + p * 6.0, Color(glow, 0.12 + p * 0.12))
	draw_rect(Rect2(-26, -18, 52, 6), wood)
	draw_rect(Rect2(-26, -34, 52, 5), wood)
	draw_rect(Rect2(-22, -18, 4, 18), wood.darkened(0.3))
	draw_rect(Rect2(18, -18, 4, 18), wood.darkened(0.3))
	draw_rect(Rect2(-22, -34, 3, 16), wood.darkened(0.2))
	draw_rect(Rect2(19, -34, 3, 16), wood.darkened(0.2))
