class_name TempoPad
extends Node2D
## 接觸地板才生效，空中飛過不切速；離開後可以再次踩踏。

signal triggered(bpm: float)

var target_bpm: float = 120.0
var width: float = 144.0
var _standing: bool = false
var _flash: float = 0.0


func setup(center: Vector2, bpm: float, pad_width: float = 144.0) -> void:
	position = center
	target_bpm = bpm
	width = pad_width


func _ready() -> void:
	z_index = 4
	add_to_group("tempo_pad")


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var on_pad := false
	if player and not player.control_locked and not player.watching:
		var feet := player.global_position + Vector2(0, Player.BODY_SIZE.y * 0.5)
		on_pad = player.is_on_floor() and absf(feet.y - global_position.y) < 8.0 \
			and absf(feet.x - global_position.x) < width * 0.5
	if on_pad and not _standing:
		_flash = 1.0
		triggered.emit(target_bpm)
	_standing = on_pad


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var color := Color(1.0, 0.58, 0.25) if target_bpm > 120 else Color(0.35, 0.8, 1.0)
	if is_equal_approx(target_bpm, 120.0):
		color = Color(0.6, 1.0, 0.72)
	var active := absf(Conductor.current_bpm - target_bpm) < 0.5
	draw_rect(Rect2(-width * 0.5, -7, width, 7), color.lightened(_flash * 0.5))
	draw_rect(Rect2(-width * 0.5, 0, width, 9), Color(color, 0.35))
	for i in 5:
		var x := -width * 0.5 + (i + 0.5) * width / 5
		draw_line(Vector2(x - 5, -15), Vector2(x, -10), Color(color, 0.8), 2)
		draw_line(Vector2(x, -10), Vector2(x + 5, -15), Color(color, 0.8), 2)
	var label := "%d BPM" % roundi(target_bpm)
	UiKit.pill(self, Vector2(-UiKit.width_of(label, 14) * 0.5 - 12, -86), label, color, UiKit.INK, 14)
	if active:
		draw_line(Vector2(-width * 0.5, -2), Vector2(width * 0.5, -2), Color.WHITE, 2)
