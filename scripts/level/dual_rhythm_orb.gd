class_name DualRhythmOrb
extends Area2D
## 雙節奏音符：同一顆同時顯示三拍與四拍的跳躍點，任一侧亮起時按跳即可（自由難度則隨時可用）。

const RADIUS := 24.0
const COLOR3 := Color(1.0, 0.55, 0.85)
const COLOR4 := Color(0.45, 0.92, 1.0)

var notes3: String = "x..x.."
var notes4: String = "x......."
var tone: float = 12.0
var _used3: bool = false
var _used4: bool = false
var _burst: float = 0.0
var _last_cue3: int = -9999
var _last_cue4: int = -9999


func setup(center: Vector2, triplet: String, quadruple: String, semitones: float = 12.0) -> void:
	position = center
	notes3 = triplet
	notes4 = quadruple
	tone = semitones


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	z_index = 6
	add_to_group("rhythm_orb")
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS + 4.0
	shape.shape = c
	add_child(shape)


func _slot_in(notes: String, b: float) -> int:
	if GameState.free_rhythm():
		return 0 if notes.contains("x") else -1
	var spb := Conductor.sec_per_beat
	var n := notes.length()
	var s0 := floori(b * 2.0)
	for s: int in [s0, s0 + 1, s0 - 1, s0 + 2]:
		if notes[posmod(s, n)] != "x":
			continue
		if GameState.in_window((b - s * 0.5) * spb):
			return s
	return -1


func is_ready() -> bool:
	if GameState.free_rhythm():
		return not (_used3 and _used4)
	var s3 := _slot_in(notes3, Conductor.song_beat)
	var s4 := _slot_in(notes4, Conductor.song_beat)
	if s3 != -1 and not _used3:
		return true
	if s4 != -1 and not _used4:
		return true
	return false


func consume() -> void:
	var b := Conductor.song_beat
	var s3 := _slot_in(notes3, b)
	var s4 := _slot_in(notes4, b)
	if s3 != -1 and not _used3:
		_used3 = true
	elif s4 != -1 and not _used4:
		_used4 = true
	elif GameState.free_rhythm():
		_used3 = true
		_used4 = true
	_burst = 1.0


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var s := floori(b * 2.0)
	if s != _last_cue3 and notes3[posmod(s, notes3.length())] == "x":
		_last_cue3 = s
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("cue", tone, -12.0)
	if s != _last_cue4 and notes4[posmod(s, notes4.length())] == "x":
		_last_cue4 = s
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("cue", tone + 3.0, -14.0)
	var p := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if p and p.is_on_floor() and global_position.distance_to(p.global_position) < 120.0:
		_used3 = false
		_used4 = false


func _process(delta: float) -> void:
	_burst = maxf(0.0, _burst - delta * 3.0)
	queue_redraw()


func _lit3() -> bool:
	if _used3:
		return false
	if GameState.free_rhythm():
		return true
	return _slot_in(notes3, Conductor.song_beat) != -1


func _lit4() -> bool:
	if _used4:
		return false
	if GameState.free_rhythm():
		return true
	return _slot_in(notes4, Conductor.song_beat) != -1


func _draw() -> void:
	var l3 := _lit3()
	var l4 := _lit4()
	if l3:
		draw_arc(Vector2(-7, 0), RADIUS, 0.0, TAU, 36, Color(COLOR3, 0.35), 4.0, true)
	if l4:
		draw_arc(Vector2(7, 0), RADIUS, 0.0, TAU, 36, Color(COLOR4, 0.35), 4.0, true)
	var core := Color(0.85, 0.82, 0.95, 0.55)
	if l3 or l4:
		core = COLOR3.lerp(COLOR4, 0.5)
	draw_circle(Vector2.ZERO, RADIUS * 0.55, core)
	draw_line(Vector2(-2, -8), Vector2(-2, 4), Color(0.08, 0.06, 0.1, 0.85), 2.0)
	draw_circle(Vector2(-5, 5), 3.5, Color(0.08, 0.06, 0.1, 0.85))
	if _burst > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + (1.0 - _burst) * 28.0, 0.0, TAU, 40, Color(1, 1, 1, _burst), 3.0, true)
