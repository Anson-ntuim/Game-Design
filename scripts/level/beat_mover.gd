class_name BeatMover
extends AnimatableBody2D
## 每一拍「喀」地往前移動一步的平台，走完一半循環後折返。

const THICKNESS := 16.0

var start_pos: Vector2
var travel: Vector2 = Vector2(240, 0)
var cycle_beats: float = 8.0
var phase: int = 0
var size: Vector2 = Vector2(120, THICKNESS)


func setup(top_left: Vector2, width: float, travel_px: Vector2, phase_group: int) -> void:
	start_pos = top_left
	size = Vector2(width, THICKNESS)
	travel = travel_px
	phase = phase_group
	position = top_left


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	shape.shape = r
	shape.position = size * 0.5
	shape.one_way_collision = true
	add_child(shape)
	position = _pos_at(Conductor.song_beat)


func _physics_process(_delta: float) -> void:
	position = _pos_at(Conductor.song_beat)
	queue_redraw()


func _pos_at(b: float) -> Vector2:
	var local := fposmod(b + phase * cycle_beats * 0.5, cycle_beats)
	var step := floorf(local)
	var progress := step + smoothstep(0.0, 0.4, local - step)
	var half := cycle_beats * 0.5
	var t := progress / half if progress <= half else (cycle_beats - progress) / half
	return start_pos + travel * t


func _draw() -> void:
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(9.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.94, 1.0))
	draw_rect(Rect2(0, 0, size.x, 4), edge.lerp(Color.WHITE, pulse))
	for i in 3:
		var cx := size.x * (0.25 + 0.25 * i)
		draw_circle(Vector2(cx, size.y * 0.6), 3.0, Color(edge, 0.4 + 0.6 * pulse))
