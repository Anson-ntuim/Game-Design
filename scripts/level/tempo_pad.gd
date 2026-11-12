class_name TempoPad
extends Node2D
## 全高度變速線，步行、跳躍或衝刺穿越都會切速；保留類名以相容既有關卡資料。
## 顏色固定：橘＝加速、藍＝減速、綠＝回到原速（相對 120 BPM 基準）。

signal triggered(bpm: float)

## 加速線（橘）
const COLOR_SPEED_UP := Color("ff7a2e")
## 減速線（藍）
const COLOR_SLOW_DOWN := Color("3accff")
## 原速線（綠）
const COLOR_RESET := Color("66ffb0")

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


func line_color() -> Color:
	if is_equal_approx(target_bpm, Conductor.REFERENCE_BPM):
		return COLOR_RESET
	if target_bpm > Conductor.REFERENCE_BPM:
		return COLOR_SPEED_UP
	return COLOR_SLOW_DOWN


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if not player or player.control_locked or player.watching:
		_standing = false
		_has_previous = false
		return
	var current := player.global_position
	var near_line := absf(current.x - global_position.x) <= Player.BODY_SIZE.x * 0.5 + 4.0
	# 掃過 X 座標也算穿越，避免高速衝刺跳過窄觸發帶。重生／測試瞬移不掃過沿途所有線。
	var crossed := _has_previous and current.distance_to(_previous_position) < 128.0 \
		and (_previous_position.x - global_position.x) * (current.x - global_position.x) < 0.0
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
	var color := line_color()
	var multiplier := Conductor.rate_for_world_bpm(target_bpm)
	var actual_bpm := Conductor.bpm * multiplier
	var active := absf(Conductor.current_bpm - actual_bpm) < 0.5
	var top := -global_position.y - 128.0
	var bottom := world_bottom - global_position.y + 128.0
	var camera := get_viewport().get_camera_2d()
	if camera:
		var half_view := get_viewport_rect().size.y / camera.zoom.y * 0.5
		top = minf(top, camera.get_screen_center_position().y - half_view - global_position.y - 128.0)
		bottom = maxf(bottom, camera.get_screen_center_position().y + half_view - global_position.y + 128.0)
	var height := bottom - top
	## 閃爍只拉高透明度，色相維持固定
	draw_rect(Rect2(-9, top, 18, height), Color(color, 0.08 + _flash * 0.18))
	draw_line(Vector2(0, top), Vector2(0, bottom), Color(color, 0.85 + _flash * 0.15), 4.0)
	for y in range(int(top), int(bottom), 96):
		draw_polyline(PackedVector2Array([Vector2(-8, y - 7), Vector2(1, y), Vector2(-8, y + 7)]),
			Color(color, 0.7), 2.0, true)
	var label := "→ %.2f× · %d BPM" % [multiplier, roundi(actual_bpm)]
	UiKit.pill(self, Vector2(16, -86), label, color, UiKit.INK, 14)
	if active:
		draw_line(Vector2(0, top), Vector2(0, bottom), Color(1, 1, 1, 0.45), 1.0)
