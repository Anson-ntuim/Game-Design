class_name DashRing
extends Area2D
## 衝刺環：只在節奏型的 x 拍亮起。在亮起的那一拍按衝刺、並在這次衝刺中穿過它，
## 衝刺冷卻會立刻清零、空中衝刺補回，衝刺結束時還會往上輕彈維持高度，下一拍就能再衝。
## 判定看的是「按下衝刺的時間」，所以早半拍衝過去也不算。每個 x 只能用一次；
## 外圈會在亮起前一拍往內縮，縮到環上就是該按的時機。

const RADIUS := 26.0
const COLOR := Color(0.45, 0.95, 1.0)

var notes: String = "x......."
var tone: float = 19.0
var _used_slot: int = -9999
var _burst: float = 0.0
var _last_cue_slot: int = -9999


func setup(center: Vector2, pattern: String, semitones: float = 19.0) -> void:
	position = center
	notes = pattern
	tone = semitones


func _ready() -> void:
	collision_layer = Player.LAYER_TRIGGER
	collision_mask = 0
	monitoring = false
	z_index = 6
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	shape.shape = c
	add_child(shape)


## beat 落在哪個 x 格的判定窗內（沒有回傳 -1）。格編號 = 從第 0 拍起算的半拍數
func _slot_at(beat: float) -> int:
	var spb := Conductor.sec_per_beat
	var n := notes.length()
	var s0 := floori(beat * 2.0)
	for s: int in [s0, s0 + 1, s0 - 1]:
		if notes[posmod(s, n)] != "x":
			continue
		if GameState.in_window((beat - s * 0.5) * spb):
			return s
	return -1


## 在 dash_beat 按下的衝刺能不能觸發這個環
func accepts(dash_beat: float) -> bool:
	var s := _slot_at(dash_beat)
	return s != -1 and s != _used_slot


func consume(dash_beat: float) -> void:
	_used_slot = _slot_at(dash_beat)
	_burst = 1.0


func _physics_process(_delta: float) -> void:
	var s := floori(Conductor.song_beat * 2.0)
	if s != _last_cue_slot and notes[posmod(s, notes.length())] == "x":
		_last_cue_slot = s
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("cue", tone, -12.0)


func _process(delta: float) -> void:
	_burst = maxf(0.0, _burst - delta * 2.5)
	queue_redraw()


func _beats_to_next() -> float:
	var b := Conductor.song_beat
	var n := notes.length()
	var s := ceili(b * 2.0)
	for i in n:
		if notes[posmod(s + i, n)] == "x":
			return (s + i) * 0.5 - b
	return INF


func _draw() -> void:
	var slot := _slot_at(Conductor.song_beat)
	var lit := slot != -1 and slot != _used_slot
	var used := slot != -1 and slot == _used_slot
	var hoop := COLOR if lit else Color(COLOR.darkened(0.5), 0.6)
	if used:
		hoop = Color(0.5, 0.5, 0.55, 0.4)
	var until := _beats_to_next()
	if until < 1.0:
		var t := 1.0 - until
		draw_arc(Vector2.ZERO, lerpf(RADIUS * 3.0, RADIUS, t * t), 0.0, TAU, 48, Color(COLOR, 0.25 + 0.6 * t), 2.5, true)
	if lit:
		draw_circle(Vector2.ZERO, RADIUS + 8.0, Color(COLOR, 0.2))
	draw_circle(Vector2.ZERO, RADIUS - 3.0, Color(0.06, 0.08, 0.14, 0.55))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, hoop, 5.0, true)
	draw_arc(Vector2.ZERO, RADIUS - 5.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5 if lit else 0.15), 1.5, true)
	var chevron := Color(1, 1, 1, 0.9) if lit else Color(hoop, 0.7)
	for i in 2:
		var tip := Vector2(-2.0 + i * 9.0, 0.0)
		draw_polyline(PackedVector2Array([tip + Vector2(-7, -8), tip, tip + Vector2(-7, 8)]), chevron, 3.0, true)
	if _burst > 0.0:
		var r := RADIUS + (1.0 - _burst) * 40.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, _burst), 3.0, true)
		for i in 8:
			var d := Vector2.RIGHT.rotated(i * TAU / 8.0)
			draw_line(d * (r - 6.0), d * (r + 6.0), Color(COLOR, _burst), 2.5)
