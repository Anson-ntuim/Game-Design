class_name BeatPad
extends StaticBody2D
## 節拍鼓：每一拍鼓點響起時，站在上面的人會被彈得非常高；其餘時間就是普通地面。

var size: Vector2 = Vector2(80, 40)
var _launch_flash: float = 0.0
var _last_beat: int = -1


func setup(top_left: Vector2, width: float, height: float) -> void:
	position = top_left
	size = Vector2(width, height)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	add_to_group("solid_ground")
	add_to_group("beat_pad")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	shape.shape = r
	shape.position = size * 0.5
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var b := floori(Conductor.song_beat)
	if b == _last_beat:
		return
	_last_beat = b
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and p.launch_from_pad(self):
		_launch_flash = 1.0


func _process(delta: float) -> void:
	_launch_flash = maxf(0.0, _launch_flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var p := Conductor.pulse(7.0)
	var gold := Color(1.0, 0.8, 0.3)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.14, 0.12))
	draw_rect(Rect2(4, 8, size.x - 8, size.y - 8), Color(0.35, 0.2, 0.14))
	var skin := Color(1.0, 0.95, 0.85).lerp(gold, 0.4 + 0.6 * p)
	draw_rect(Rect2(0, 0, size.x, 8), skin)
	for i in 3:
		var y := -10.0 - i * 14.0 - p * 6.0
		var a := (0.25 + 0.6 * p) * (1.0 - i * 0.28)
		var cx := size.x * 0.5
		draw_polyline(PackedVector2Array([Vector2(cx - 12, y + 8), Vector2(cx, y), Vector2(cx + 12, y + 8)]),
			Color(gold, a), 3.0, true)
	if _launch_flash > 0.0:
		var r := 20.0 + (1.0 - _launch_flash) * 60.0
		draw_arc(Vector2(size.x * 0.5, 0), r, PI, TAU, 24, Color(gold, _launch_flash), 4.0, true)
