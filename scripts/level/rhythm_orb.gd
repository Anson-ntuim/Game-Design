class_name RhythmOrb
extends Area2D
## 節奏音符：取代常駐二段跳。只在節奏型的 x 格亮起，
## 玩家在空中碰著亮起的音符時按跳，就能再跳一次並補回空中衝刺。
## 每個 x 只能用一次；外圈會在亮起前一拍往內縮，縮到音符上就是該按的時機。
## subdiv：一拍切成幾格（2 = 八分音符／半拍；3 = 三連音，一格 = 1/3 拍）。

const RADIUS := 22.0
const COLOR := Color(1.0, 0.78, 0.35)

var notes: String = "x......."
var tone: float = 12.0
var subdiv: int = 2
## ""（一般）、"high"（大音符：跳更高，兩拍才落回原高度）、"low"（小音符：跳很矮，半拍就落回來）
var jump_kind: String = ""
var _used_slot: int = -9999
var _burst: float = 0.0
var _last_cue_slot: int = -9999


func setup(center: Vector2, pattern: String, semitones: float = 12.0, slots_per_beat: int = 2) -> void:
	position = center
	notes = pattern
	tone = semitones
	subdiv = maxi(1, slots_per_beat)


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


## 畫面大小倍率：大音符 1.6 倍、小音符 0.6 倍（碰撞範圍不變）
func size_scale() -> float:
	return 1.6 if jump_kind == "high" else 0.6 if jump_kind == "low" else 1.0


func _slot_beats(slot: int) -> float:
	return float(slot) / float(subdiv)


## 目前落在判定窗內的 x 格編號（沒有回傳 -1）
func _active_slot() -> int:
	if GameState.free_rhythm():
		return 0 if notes.contains("x") and _used_slot == -9999 else -1
	var b := Conductor.song_beat
	var spb := Conductor.sec_per_beat
	var n := notes.length()
	var s0 := floori(b * float(subdiv))
	for s: int in [s0, s0 + 1, s0 - 1, s0 + 2, s0 + 3, s0 - 2]:
		if notes[posmod(s, n)] != "x":
			continue
		if GameState.in_window((b - _slot_beats(s)) * spb):
			return s
	return -1


func is_ready() -> bool:
	if quiet and not _awake:
		return false
	var s := _active_slot()
	return s != -1 and (GameState.free_rhythm() or s != _used_slot)


func consume() -> void:
	_used_slot = _active_slot()
	_burst = 1.0


func _physics_process(_delta: float) -> void:
	_update_awake()
	if GameState.free_rhythm():
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and p.is_on_floor():
			_used_slot = -9999
	var s := floori(Conductor.song_beat * float(subdiv))
	if s != _last_cue_slot and notes[posmod(s, notes.length())] == "x":
		_last_cue_slot = s
		if BeatPattern.near_player(self, 700.0) and (_awake or not quiet):
			GameState.play_cue("cue", tone, -12.0)


func _process(delta: float) -> void:
	_burst = maxf(0.0, _burst - delta * 3.0)
	queue_redraw()


## 距離下一個 x 格還有幾拍
func _beats_to_next() -> float:
	var b := Conductor.song_beat
	var n := notes.length()
	var s := ceili(b * float(subdiv))
	for i in n:
		if notes[posmod(s + i, n)] == "x":
			return _slot_beats(s + i) - b
	return INF


func _draw() -> void:
	var lit := is_ready()
	var slot := _active_slot()
	## 大音符（跳得高）畫大、小音符（跳得矮）畫小；顏色一樣是黃色
	var base := COLOR
	var k := size_scale()
	var core := base if lit else Color(base.darkened(0.55), 0.55)
	if slot != -1 and slot == _used_slot:
		core = Color(0.5, 0.5, 0.55, 0.4)
	## 三連音用偏暖的外圈提示
	var ring_col := Color(1.0, 0.55, 0.4) if subdiv == 3 else base
	var until := _beats_to_next()
	if until < 1.0 and (_awake or not quiet):
		var t := 1.0 - until
		draw_arc(Vector2.ZERO, lerpf(RADIUS * 3.0, RADIUS, t) * k, 0.0, TAU, 40, Color(ring_col, 0.25 + 0.6 * t), 2.5, true)
	if lit:
		draw_circle(Vector2.ZERO, (RADIUS + 6.0) * k, Color(ring_col, 0.25))
	draw_circle(Vector2.ZERO, RADIUS * 0.62 * k, core)
	draw_arc(Vector2.ZERO, RADIUS * 0.62 * k, 0.0, TAU, 32, Color(1, 1, 1, 0.8 if lit else 0.3), 2.0, true)
	draw_line(Vector2(3, -9) * k, Vector2(3, 5) * k, Color(0.1, 0.08, 0.05, 0.8), 2.0 * k)
	draw_circle(Vector2(-1, 6) * k, 4.0 * k, Color(0.1, 0.08, 0.05, 0.8))
	if subdiv == 3:
		draw_string(ThemeDB.fallback_font, Vector2(-5, -RADIUS - 4), "3", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ring_col, 0.85))
	if _burst > 0.0:
		draw_arc(Vector2.ZERO, RADIUS * k + (1.0 - _burst) * 30.0, 0.0, TAU, 40, Color(1, 1, 1, _burst), 3.0, true)


## 安靜模式（彈簧床飛出去之後要踩的音符／環用）：平常只是暗暗的不閃不響，
## 在彈簧床上彈的時候也不動；真的被彈出去、飛在附近的空中才「醒來」開始跟拍子亮、外圈縮小；落地就再睡。
var quiet: bool = false
var _awake: bool = false


func _update_awake() -> void:
	if not quiet:
		_awake = true
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null:
		_awake = false
		return
	var near := absf(p.global_position.x - global_position.x) < 900.0
	var riding := p.ride != null and p.ride.is_in_group("trampoline")
	if riding or p.is_on_floor():
		_awake = false
	elif near:
		_awake = true

