class_name GravitySwitch
extends Area2D
## 重力／道路機關：站在旁邊按 ↑ 切換，解鎖對應 id 的擋路牆並提示重力段落。

signal toggled(unlock_id: String, on: bool)

var unlock_id: String = "a"
var label: String = "切換重力"
var _on: bool = false
var _flash: float = 0.0


func setup(center: Vector2, id: String, hint: String = "") -> void:
	position = center
	unlock_id = id
	if hint != "":
		label = hint


func _ready() -> void:
	collision_layer = Player.LAYER_TRIGGER
	collision_mask = 0
	monitoring = false
	z_index = 4
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(48, 64)
	shape.shape = box
	shape.position = Vector2(0, -32)
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or p.control_locked or p.watching:
		return
	if global_position.distance_to(p.global_position) > 56.0:
		return
	if Input.is_action_just_pressed("up"):
		_on = not _on
		_flash = 1.0
		GameState.set_path_unlock(unlock_id, _on)
		toggled.emit(unlock_id, _on)
		GameState.play_sfx("cue", 0.0 if _on else -5.0, -6.0)
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("show_message"):
			main.call("show_message", label + ("　已開啟" if _on else "　已關閉"), 1.8)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var edge := GameState.color("edge")
	var base := edge.lerp(Color.WHITE, 0.25 + 0.35 * _flash)
	draw_rect(Rect2(-20, -48, 40, 48), Color(base, 0.35 if _on else 0.18))
	draw_rect(Rect2(-4, -52, 8, 12), Color(base, 0.9))
	draw_circle(Vector2(0, -18), 10.0, Color(1, 0.85, 0.35, 0.95 if _on else 0.45))
	if _on:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(edge, 0.35 + 0.4 * _flash), 2.0, true)
