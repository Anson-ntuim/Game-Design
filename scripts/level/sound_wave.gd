class_name SoundWave
extends Node2D
## 音浪：玩家經過觸發點後，在下一個循環開頭從後方湧出，每一拍往前推進一段，被追上就直接倒下。
## 追到 end_x 就停住（終點前的舞台），玩家倒下後會重置，回到觸發點才會再次出現。

signal armed(start_beat: float)

const SPEED := 140.0
const LEAD_BEATS := 2.0
const CYCLE_BEATS := 8.0
const COLOR := Color(1.0, 0.35, 0.6)

var trigger_x: float = 0.0
var spawn_x: float = 0.0
var end_x: float = 0.0
var height: float = 800.0
var is_armed: bool = false
var stopped: bool = false
var start_beat: float = 0.0
var front: float = -INF
var _last_measure: int = -1


func setup(trigger: float, spawn: float, end: float, level_height: float) -> void:
	trigger_x = trigger
	spawn_x = spawn
	end_x = end
	height = level_height


func _ready() -> void:
	z_index = 20


func reset() -> void:
	is_armed = false
	stopped = false
	front = -INF


func stop() -> void:
	stopped = true


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null:
		return
	if not is_armed:
		if p.global_position.x > trigger_x and not p.control_locked:
			is_armed = true
			start_beat = ceilf((b + LEAD_BEATS) / CYCLE_BEATS) * CYCLE_BEATS
			armed.emit(start_beat)
			GameState.play_sfx("rumble", 0.0, -6.0)
		return
	if stopped:
		return
	var t := b - start_beat
	if t < 0.0:
		front = -INF
		return
	var step := floorf(t)
	front = minf(end_x, spawn_x + SPEED * (step + smoothstep(0.0, 0.35, t - step)))
	var m := floori(b / 4.0)
	if m != _last_measure:
		_last_measure = m
		if absf(p.global_position.x - front) < 900.0:
			GameState.play_sfx("rumble", 0.0, -12.0)
	if not p.control_locked and p.global_position.x - Player.BODY_SIZE.x * 0.5 < front:
		p.kill()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if front == -INF:
		return
	var b := Conductor.song_beat
	var pulse := Conductor.pulse(6.0)
	var edge := GameState.color("edge")
	var pts := PackedVector2Array()
	var back := front - 2400.0
	pts.append(Vector2(back, -200))
	var n := 40
	for i in n + 1:
		var y := -200.0 + (height + 400.0) * i / n
		var wobble := sin(y * 0.025 + b * TAU) * (10.0 + 14.0 * pulse) + sin(y * 0.07 - b * 9.0) * 5.0
		pts.append(Vector2(front + wobble, y))
	pts.append(Vector2(back, height + 200))
	draw_colored_polygon(pts, Color(0.05, 0.02, 0.08, 0.82))
	var edge_line := PackedVector2Array()
	for i in range(1, n + 2):
		edge_line.append(pts[i])
	draw_polyline(edge_line, Color(COLOR.lerp(edge, 0.3), 0.9), 6.0 + 4.0 * pulse)
	draw_polyline(edge_line, Color(1, 1, 1, 0.7), 2.0)
	for i in 14:
		var x := front - 30.0 - i * 26.0
		var bar := (0.3 + 0.7 * absf(sin(i * 1.9 + floorf(b * 2.0) * 1.3))) * (0.5 + 0.5 * pulse)
		var bh := height * 0.45 * bar
		draw_rect(Rect2(x - 8, height * 0.5 - bh * 0.5, 16, bh), Color(COLOR, 0.18 + 0.2 * pulse))
