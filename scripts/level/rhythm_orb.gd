class_name RhythmOrb
extends Area2D
## 節奏音符：取代常駐二段跳。只在節奏型的 x 拍亮起，
## 玩家在空中碰著亮起的音符時按跳，就能再跳一次並補回空中衝刺。
## 每個 x 只能用一次；外圈會在亮起前一拍往內縮，縮到音符上就是該按的時機。

const RADIUS := 22.0
const COLOR := Color(1.0, 0.78, 0.35)

var notes: String = "x......."
var tone: float = 12.0
var _used_slot: int = -9999
var _burst: float = 0.0
var _last_cue_slot: int = -9999


func setup(center: Vector2, pattern: String, semitones: float = 12.0) -> void:
	position = center
	notes = pattern
	tone = semitones


func _ready() -> void:
	collision_layer = Player.LAYER_TRIGGER
	collision_mask = 0
	monitoring = false
	z_index = 6
	add_to_group("rhythm_orb")
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	shape.shape = c
	add_child(shape)


## 目前落在判定窗內的 x 格編號（沒有回傳 -1）。格編號 = 從第 0 拍起算的半拍數
func _active_slot() -> int:
	if GameState.free_rhythm():
		return 0 if notes.contains("x") and _used_slot == -9999 else -1
	var b := Conductor.song_beat
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
	var s := _active_slot()
	return s != -1 and (GameState.free_rhythm() or s != _used_slot)


func consume() -> void:
	_used_slot = _active_slot()
	_burst = 1.0


func _physics_process(_delta: float) -> void:
	if GameState.free_rhythm():
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and p.is_on_floor():
			_used_slot = -9999
	var s := floori(Conductor.song_beat * 2.0)
	if s != _last_cue_slot and notes[posmod(s, notes.length())] == "x":
		_last_cue_slot = s
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("cue", tone, -12.0)


func _process(delta: float) -> void:
	_burst = maxf(0.0, _burst - delta * 3.0)
	queue_redraw()


## 距離下一個 x 格還有幾拍
func _beats_to_next() -> float:
	var b := Conductor.song_beat
	var n := notes.length()
	var s := ceili(b * 2.0)
	for i in n:
		if notes[posmod(s + i, n)] == "x":
			return (s + i) * 0.5 - b
	return INF


func _draw() -> void:
	var lit := is_ready()
	var slot := _active_slot()
	var core := COLOR if lit else Color(COLOR.darkened(0.55), 0.55)
	if slot != -1 and slot == _used_slot:
		core = Color(0.5, 0.5, 0.55, 0.4)
	var until := _beats_to_next()
	if until < 1.0:
		var t := 1.0 - until
		draw_arc(Vector2.ZERO, lerpf(RADIUS * 3.0, RADIUS, t), 0.0, TAU, 40, Color(COLOR, 0.25 + 0.6 * t), 2.5, true)
	if lit:
		draw_circle(Vector2.ZERO, RADIUS + 6.0, Color(COLOR, 0.25))
	draw_circle(Vector2.ZERO, RADIUS * 0.62, core)
	draw_arc(Vector2.ZERO, RADIUS * 0.62, 0.0, TAU, 32, Color(1, 1, 1, 0.8 if lit else 0.3), 2.0, true)
	draw_line(Vector2(3, -9), Vector2(3, 5), Color(0.1, 0.08, 0.05, 0.8), 2.0)
	draw_circle(Vector2(-1, 6), 4.0, Color(0.1, 0.08, 0.05, 0.8))
	if _burst > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + (1.0 - _burst) * 30.0, 0.0, TAU, 40, Color(1, 1, 1, _burst), 3.0, true)
