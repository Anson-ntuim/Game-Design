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


## 尖刺圖（手繪：三根一排＋底座），高度跟著 height 伸縮；
## color 越接近白色（預告、還沒傷人）圖就越亮
const SPIKE_TEX := preload("res://assets/ui/spike.png")


static func draw_spikes(canvas: CanvasItem, tile_size: float, height: float, color: Color) -> void:
	if height <= 0.01:
		return
	var h := (tile_size * 0.8 + 4.0) * height
	var white := clampf((color.g - HAZARD_COLOR.g) / (1.0 - HAZARD_COLOR.g), 0.0, 1.0)
	var tint := Color(1, 1, 1).lerp(Color(1.7, 1.7, 1.7), white)
	canvas.draw_texture_rect(SPIKE_TEX, Rect2(0, tile_size - h, tile_size, h), false, tint)
