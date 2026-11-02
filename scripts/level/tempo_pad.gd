class_name TempoPad
extends Node2D
## 全高度變速線，步行、跳躍或衝刺穿越都會切速；保留類名以相容既有關卡資料。

signal triggered(bpm: float)

var target_bpm: float = 120.0
var width: float = 144.0
var _standing: bool = false
var world_bottom: float = 800.0
var _previous_position := Vector2.ZERO
var _has_previous: bool = false
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
	if not player or player.control_locked or player.watching:
		_standing = false
		_has_previous = false
		return
	var current := player.global_position
	var near_line := absf(current.x - global_position.x) <= Player.BODY_SIZE.x * 0.5 + 4.0
	# 掃過 X 座標也算穿越，避免高速衝刺跳過窄觸發帶。重生／測試瞬移不掃過沿途所有線。
	var crossed := _has_previous and current.distance_to(_previous_position) < 128.0 		and (_previous_position.x - global_position.x) * (current.x - global_position.x) < 0.0
	if not _standing and (near_line or crossed):
		_flash = 1.0
		triggered.emit(target_bpm)
	_standing = near_line
	_previous_position = current
	_has_previous = true


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var color := Color(1.0, 0.58, 0.25) if target_bpm > 120 else Color(0.35, 0.8, 1.0)
	if is_equal_approx(target_bpm, 120.0):
		color = Color(0.6, 1.0, 0.72)
	var active := absf(Conductor.current_bpm - target_bpm) < 0.5
	var top := -global_position.y - 128.0
	var bottom := world_bottom - global_position.y + 128.0
	var camera := get_viewport().get_camera_2d()
	if camera:
		var half_view := get_viewport_rect().size.y / camera.zoom.y * 0.5
		top = minf(top, camera.get_screen_center_position().y - half_view - global_position.y - 128.0)
		bottom = maxf(bottom, camera.get_screen_center_position().y + half_view - global_position.y + 128.0)
	var height := bottom - top
	draw_rect(Rect2(-9, top, 18, height), Color(color, 0.07 + _flash * 0.15))
	draw_line(Vector2(0, top), Vector2(0, bottom), color.lightened(_flash * 0.5), 4.0)
	for y in range(int(top), int(bottom), 96):
		draw_polyline(PackedVector2Array([Vector2(-8, y - 7), Vector2(1, y), Vector2(-8, y + 7)]),
			Color(color, 0.65), 2.0, true)
	var label := "→ %d BPM" % roundi(target_bpm)
	UiKit.pill(self, Vector2(16, -86), label, color, UiKit.INK, 14)
	if active:
		draw_line(Vector2(0, top), Vector2(0, bottom), Color(1, 1, 1, 0.5), 1.0)
