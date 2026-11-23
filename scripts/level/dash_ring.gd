class_name DashRing
extends Area2D
## 衝刺環：只在節奏型的 x 拍亮起。在亮起的那一拍按衝刺、並在這次衝刺中穿過它，
## 衝刺冷卻會立刻清零、空中衝刺補回，衝刺結束時還會往上輕彈維持高度。
## 關卡上有兩種寫法，不要鎖死成「穿環後一定再衝」：
##   引導環 — 環標出該衝的拍，穿過去就落地（J→R）；補能是順便的，這句用不到。
##   補能連環 — 連穿多環維持空中衝刺，最後常再接一下普通衝刺過坑（J→R→R→D）。
## 判定看的是「按下衝刺的時間」；每個 x 只能用一次；
## 外圈會在亮起前一拍往內縮，縮到環上就是該按的時機。

const RADIUS := 26.0
const COLOR := Color(0.45, 0.95, 1.0)
## 衝刺環本體（手繪蠟筆圖：青色圈＋兩個箭頭，中間透明）
const RING_TEX := preload("res://assets/ui/dash_ring.png")

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
	if GameState.free_rhythm():
		return 0 if notes.contains("x") and _used_slot == -9999 else -1
	var spb := Conductor.sec_per_beat
	var n := notes.length()
	var s0 := floori(beat * 2.0)
	for s: int in [s0, s0 + 1, s0 - 1, s0 + 2]:
		if notes[posmod(s, n)] != "x":
			continue
		if GameState.in_window((beat - s * 0.5) * spb):
			return s
	return -1


## 在 dash_beat 按下的衝刺能不能觸發這個環
func accepts(dash_beat: float) -> bool:
	if quiet and not _awake:
		return false
	var s := _slot_at(dash_beat)
	return s != -1 and s != _used_slot


## 回傳衝刺時離 x 格幾秒（負的是提早），給打擊評價用
func consume(dash_beat: float) -> float:
	var s := _slot_at(dash_beat)
	_used_slot = s
	_burst = 1.0
	if s == -1 or GameState.free_rhythm():
		return 0.0
	return (dash_beat - s * 0.5) * Conductor.sec_per_beat


func _physics_process(_delta: float) -> void:
	_update_awake()
	if GameState.free_rhythm():
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and p.is_on_floor():
			_used_slot = -9999
	var s := floori(Conductor.audio_beat * 2.0)
	if s != _last_cue_slot and notes[posmod(s, notes.length())] == "x":
		_last_cue_slot = s
		if BeatPattern.near_player(self, 700.0) and (_awake or not quiet):
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
	## 每一拍整個環彈一下（醒著的時候），看得出拍子在哪
	if _awake or not quiet:
		var bounce := 1.0 + 0.14 * Conductor.pulse(9.0) * maxf(GameState.anim_amount(), 0.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(bounce, bounce))
	var slot := _slot_at(Conductor.song_beat)
	var lit := slot != -1 and slot != _used_slot and (_awake or not quiet)
	var used := slot != -1 and slot == _used_slot
	var until := _beats_to_next()
	if until < 1.0 and (_awake or not quiet):
		var t := 1.0 - until
		draw_arc(Vector2.ZERO, lerpf(RADIUS * 3.0, RADIUS, t * t), 0.0, TAU, 48, Color(COLOR, 0.25 + 0.6 * t), 2.5, true)
	if lit:
		draw_circle(Vector2.ZERO, RADIUS + 8.0, Color(COLOR, 0.2))
	## 亮著原色、沒亮變暗、用過變灰半透明
	var tint := Color(1, 1, 1, 1) if lit else Color(0.5, 0.55, 0.65, 0.7)
	if used:
		tint = Color(0.6, 0.6, 0.65, 0.4)
	var rs := (RADIUS + 4.0) * 2.0
	draw_texture_rect(RING_TEX, Rect2(Vector2(-rs * 0.5, -rs * 0.5), Vector2(rs, rs)), false, tint)
	if _burst > 0.0:
		var r := RADIUS + (1.0 - _burst) * 40.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, _burst), 3.0, true)
		for i in 8:
			var d := Vector2.RIGHT.rotated(i * TAU / 8.0)
			draw_line(d * (r - 6.0), d * (r + 6.0), Color(COLOR, _burst), 2.5)


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
