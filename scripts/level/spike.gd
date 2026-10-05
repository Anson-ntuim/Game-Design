class_name Spike
extends Area2D
## 固定尖刺。

const HAZARD_COLOR := Color(1.0, 0.32, 0.42)

var tile: float = 40.0


func setup(top_left: Vector2, tile_size: float) -> void:
	position = top_left
	tile = tile_size


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	z_index = 2
	add_to_group("hazard")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(tile - 8.0, tile * 0.55)
	shape.shape = r
	shape.position = Vector2(tile * 0.5, tile - r.size.y * 0.5)
	add_child(shape)


func is_harmful() -> bool:
	return true


func _draw() -> void:
	draw_spikes(self, tile, 1.0, HAZARD_COLOR)


static func draw_spikes(canvas: CanvasItem, tile_size: float, height: float, color: Color) -> void:
	if height <= 0.01:
		return
	var w := tile_size / 3.0
	var tip_h := tile_size * 0.8 * height
	for i in 3:
		var x := i * w
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x + 1, tile_size), Vector2(x + w * 0.5, tile_size - tip_h), Vector2(x + w - 1, tile_size)]), color)
		canvas.draw_line(Vector2(x + w * 0.5, tile_size - tip_h), Vector2(x + w * 0.5, tile_size - tip_h * 0.6),
			Color(1, 1, 1, 0.6), 1.5)
