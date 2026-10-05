class_name BeatSpike
extends Area2D
## 跟著拍子伸縮的尖刺：phase 0 在偶數拍伸出、phase 1 在奇數拍伸出。
## 伸出前半拍會先冒出尖端當作預告。

var tile: float = 40.0
var phase: int = 0
var _height: float = 0.0


func setup(top_left: Vector2, tile_size: float, phase_group: int) -> void:
	position = top_left
	tile = tile_size
	phase = phase_group


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	z_index = 2
	add_to_group("hazard")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(tile - 8.0, tile * 0.6)
	shape.shape = r
	shape.position = Vector2(tile * 0.5, tile - r.size.y * 0.5)
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var step := floori(b)
	var f := b - step
	if posmod(step, 2) == phase:
		_height = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.82, 1.0, f))
	else:
		_height = smoothstep(0.55, 1.0, f) * 0.18
	queue_redraw()


func is_harmful() -> bool:
	return _height > 0.5


func _draw() -> void:
	draw_rect(Rect2(2, tile - 5, tile - 4, 5), Color(Spike.HAZARD_COLOR, 0.35))
	var col := Spike.HAZARD_COLOR if _height > 0.5 else Spike.HAZARD_COLOR.lerp(Color.WHITE, 0.4)
	Spike.draw_spikes(self, tile, _height, col)
