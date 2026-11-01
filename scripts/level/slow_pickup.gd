class_name SlowPickup
extends Area2D
## 減速瓶：撿起後存進玩家背包，按 V 使用，暫時把音樂與物理放慢。

const COLOR := Color(0.55, 0.75, 1.0)

var _collected: bool = false
var _bob: float = 0.0


func setup(center: Vector2) -> void:
	position = center


func _ready() -> void:
	collision_layer = Player.LAYER_TRIGGER
	collision_mask = 2
	monitoring = true
	z_index = 5
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 18.0
	shape.shape = c
	add_child(shape)
	body_entered.connect(_on_body)


func _on_body(body: Node2D) -> void:
	if _collected:
		return
	var p := body as Player
	if p == null:
		return
	_collected = true
	p.slow_charges += 1
	GameState.play_sfx("pluck", GameState.next_note() + 7.0, -4.0)
	queue_free()


func _process(delta: float) -> void:
	_bob += delta
	queue_redraw()


func _draw() -> void:
	var y := sin(_bob * 4.0) * 4.0
	draw_circle(Vector2(0, y), 16.0, Color(COLOR, 0.25))
	draw_circle(Vector2(0, y - 2), 14.0, COLOR)
	draw_rect(Rect2(-5, y + 6, 10, 8), Color(COLOR.darkened(0.2)))
	draw_string(ThemeDB.fallback_font, Vector2(-4, y + 4), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
