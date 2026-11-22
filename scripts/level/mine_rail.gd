class_name MineRail
extends Node2D
## 礦車軌道：走進起點的礦車就會上車，下一個整拍（至少隔半拍）發車。
## 礦車沿軌道等速前進，位置只由拍子決定：第 k 拍一定在「起點 + k × 速度」的地方，
## 所以障礙物用「第幾拍」來擺，軌道本身就是譜面。
##   按跳：礦車連人一起跳 1 拍（約 2.2 格高、前進 speed 格）。
##   spikes：軌道上的尖刺（拍），要在前半拍起跳。軌道上會畫黃色箭頭標出按的位置。
##   gaps：軌道斷掉的範圍 [起拍, 終拍]，長度不超過 0.9 拍，經過時必須在空中。
##   beams：低樑（拍），經過時不能在空中（休止）。
## 到終點時把人往前拋出去，落到下一段地面。
## 節點本身放在原點，points 用世界座標。

enum State { IDLE, WAIT, RIDING, DONE, CRASH }

const CART_W := 58.0
const CART_H := 26.0
const JUMP_BEATS := 1.0
const JUMP_H := 88.0
const BEAM_HALF := 10.0
## 一拍的世界時間（世界和音樂一起變速，換算成 px/s 用這個）
const WORLD_SPB := 0.5
const RAIL := Color(0.75, 0.78, 0.86)
const WOOD := Color(0.45, 0.3, 0.22)
const CART := Color(0.42, 0.62, 0.9)
const PRESS := Color(1.0, 0.86, 0.3)
const HAZARD := Color(1.0, 0.32, 0.42)

var points := PackedVector2Array()
var speed_px: float = 160.0
var spikes: Array[float] = []
var gaps: Array = []
var beams: Array[float] = []
var show_marks: bool = true

var _cum: Array[float] = []
var _total: float = 0.0
var _state: State = State.IDLE
var _rider: Player = null
var _start_beat: float = 0.0
var _jump_start: float = -INF
var _cart_pos := Vector2.ZERO
var _cart_off: float = 0.0
var _crash_vel := Vector2.ZERO
var _reset_at: float = INF
var _last_tick: int = -99999


func setup(world_points: PackedVector2Array, speed_tiles_per_beat: float, spike_beats: Array = [],
		gap_ranges: Array = [], beam_beats: Array = [], marks: bool = true) -> void:
	points = world_points
	speed_px = speed_tiles_per_beat * LevelData.TILE
	for s in spike_beats:
		spikes.append(float(s))
	gaps = gap_ranges.duplicate(true)
	for bm in beam_beats:
		beams.append(float(bm))
	show_marks = marks


func _ready() -> void:
	## 畫在角色前面，看起來像坐在車廂裡
	z_index = 11
	add_to_group("mine_rail")
	_cum = [0.0]
	for i in range(1, points.size()):
		_cum.append(_cum[-1] + points[i - 1].distance_to(points[i]))
	_total = _cum[-1]
	_cart_pos = points[0]
	for k: float in spikes:
		var p := point_at(k * speed_px)
		var sp := Spike.new()
		sp.setup(p - Vector2(LevelData.TILE * 0.5, LevelData.TILE), LevelData.TILE)
		add_child(sp)


func point_at(dist: float) -> Vector2:
	var d := clampf(dist, 0.0, _total)
	for i in range(1, points.size()):
		if d <= _cum[i] or i == points.size() - 1:
			var seg := _cum[i] - _cum[i - 1]
			var t := 0.0 if seg <= 0.0 else (d - _cum[i - 1]) / seg
			return points[i - 1].lerp(points[i], clampf(t, 0.0, 1.0))
	return points[-1]


func beats_long() -> float:
	return _total / speed_px


func is_moving() -> bool:
	return _state == State.RIDING


func is_riding(p: Node) -> bool:
	return _rider != null and _rider == p


func _in_gap(beat_pos: float) -> bool:
	for g: Array in gaps:
		if beat_pos >= float(g[0]) and beat_pos <= float(g[1]):
			return true
	return false


func _reset_cart() -> void:
	_state = State.IDLE
	_rider = null
	_cart_pos = points[0]
	_cart_off = 0.0
	_jump_start = -INF
	_reset_at = INF


func _physics_process(delta: float) -> void:
	var b := Conductor.song_beat
	if _state == State.CRASH:
		_crash_vel.y += 2400.0 * delta
		_cart_pos += _crash_vel * delta
	if (_state == State.CRASH or _state == State.DONE) and b >= _reset_at:
		_reset_cart()
	if _rider != null and (not is_instance_valid(_rider) or _rider.ride != self):
		## 被尖刺、低樑打倒或其他原因離開：礦車翻落，稍後回到起點
		_rider = null
		if _state == State.WAIT or _state == State.RIDING:
			_crash(b)
	if _state != State.IDLE:
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or not p.can_ride():
		return
	var c := points[0] + Vector2(0.0, -CART_H * 0.5)
	var d := p.global_position - c
	if absf(d.x) < CART_W * 0.5 + 6.0 and d.y > -60.0 and d.y < 30.0:
		_board(p, b)


func _board(p: Player, b: float) -> void:
	_rider = p
	_state = State.WAIT
	_start_beat = ceilf(b + 0.5)
	_jump_start = -INF
	_last_tick = floori(b)
	p.begin_ride(self, "idle_0")
	p.facing = 1
	GameState.play_sfx("block", -5.0, -8.0)


func _crash(b: float) -> void:
	_state = State.CRASH
	_crash_vel = Vector2(speed_px / WORLD_SPB * 0.4, -200.0)
	_reset_at = b + 3.0


func ride_step(p: Player, _delta: float) -> void:
	var b := Conductor.song_beat
	if _state == State.WAIT and b >= _start_beat:
		_state = State.RIDING
		GameState.play_cue("cue", 7.0, -6.0)
	var s := 0.0 if _state == State.WAIT else (b - _start_beat) * speed_px
	## 快落回軌道時就能再按（連續兩拍的障礙要能接著跳）
	if _state == State.RIDING and Input.is_action_just_pressed("jump") and b - _jump_start >= JUMP_BEATS * 0.85:
		_jump_start = b
		GameState.play_sfx("pluck", GameState.next_note(), -6.0)
	var jt := (b - _jump_start) / JUMP_BEATS
	_cart_off = 4.0 * JUMP_H * jt * (1.0 - jt) if jt >= 0.0 and jt <= 1.0 else 0.0

	## 行進中每拍輕敲，讓人跟得上
	var tick := floori(b)
	if _state == State.RIDING and tick != _last_tick:
		_last_tick = tick
		GameState.play_cue("cue", 0.0, -16.0)

	if s >= _total:
		_cart_pos = points[-1]
		_cart_off = 0.0
		_state = State.DONE
		_reset_at = b + 3.0
		_rider = null
		GameState.play_cue("cue", 19.0, -5.0)
		p.end_ride(Vector2(speed_px / WORLD_SPB, -560.0))
		return

	var rail_pt := point_at(s)
	_cart_pos = rail_pt + Vector2(0.0, -_cart_off)
	p.global_position = _cart_pos + Vector2(0.0, -8.0 - Player.BODY_SIZE.y * 0.5)
	p.ride_pose = "idle_0" if _cart_off < 4.0 else ("jump_0" if jt < 0.4 else ("apex_0" if jt < 0.6 else "fall_0"))

	if _state != State.RIDING:
		return
	var beat_pos := s / speed_px
	if _cart_off < 6.0 and _in_gap(beat_pos):
		p.kill(self)
		return
	for bm: float in beams:
		if absf(beat_pos - bm) * speed_px < BEAM_HALF + CART_W * 0.3 and _cart_off > 18.0:
			p.kill(self)
			return


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	## 軌道：每半拍一根枕木，斷掉的地方不畫
	var step := speed_px * 0.5
	var n := int(_total / step)
	for i in n + 1:
		var bp := i * 0.5
		if _in_gap(bp):
			continue
		var p := point_at(i * step)
		draw_line(p + Vector2(-9, 3), p + Vector2(9, 3), WOOD, 5.0)
		if i % 2 == 0 and show_marks:
			draw_line(p + Vector2(0, 6), p + Vector2(0, 14), Color(1, 1, 1, 0.25), 2.0)
	var seg_pts := PackedVector2Array()
	var samples := maxi(2, int(_total / 8.0))
	for i in samples + 1:
		var d := _total * float(i) / float(samples)
		var bp := d / speed_px
		if _in_gap(bp):
			if seg_pts.size() >= 2:
				draw_polyline(seg_pts, RAIL, 3.0, true)
			seg_pts = PackedVector2Array()
			continue
		seg_pts.append(point_at(d) + Vector2(0, -1))
	if seg_pts.size() >= 2:
		draw_polyline(seg_pts, RAIL, 3.0, true)

	## 低樑
	for bm: float in beams:
		var p := point_at(bm * speed_px)
		var top := p + Vector2(-BEAM_HALF, -150.0)
		draw_rect(Rect2(top, Vector2(BEAM_HALF * 2.0, 82.0)), WOOD.darkened(0.2))
		for k in 4:
			var y := top.y + 46.0 + k * 9.0
			draw_line(Vector2(top.x, y), Vector2(top.x + BEAM_HALF * 2.0, y + 6.0), HAZARD, 3.0)

	## 起跳提示（黃色箭頭）：尖刺前半拍、斷軌置中
	if show_marks:
		var presses: Array[float] = []
		for k: float in spikes:
			presses.append(k - 0.5)
		for g: Array in gaps:
			presses.append((float(g[0]) + float(g[1])) * 0.5 - 0.5)
		var now := 0.0
		if _state == State.RIDING:
			now = Conductor.song_beat - _start_beat
		for pb: float in presses:
			var p := point_at(pb * speed_px) + Vector2(0, -18)
			var a := 0.85 if _state != State.RIDING or pb > now - 0.2 else 0.25
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(7, 0), p + Vector2(0, -10)]), Color(PRESS, a))

	## 礦車
	var c := _cart_pos
	if _state == State.IDLE:
		draw_circle(c + Vector2(0, -CART_H * 0.5), 44.0, Color(PRESS, 0.08 + 0.06 * Conductor.pulse(6.0)))
	var body := PackedVector2Array([
		c + Vector2(-CART_W * 0.5, -CART_H), c + Vector2(CART_W * 0.5, -CART_H),
		c + Vector2(CART_W * 0.4, -4.0), c + Vector2(-CART_W * 0.4, -4.0)])
	draw_colored_polygon(body, CART)
	draw_polyline(PackedVector2Array([body[0], body[1]]), CART.lightened(0.35), 3.0)
	draw_line(c + Vector2(-CART_W * 0.3, -CART_H * 0.55), c + Vector2(CART_W * 0.3, -CART_H * 0.55), CART.darkened(0.3), 2.0)
	for wx: float in [-CART_W * 0.26, CART_W * 0.26]:
		draw_circle(c + Vector2(wx, -3.0), 6.0, Color(0.15, 0.13, 0.2))
		draw_circle(c + Vector2(wx, -3.0), 2.5, RAIL)
