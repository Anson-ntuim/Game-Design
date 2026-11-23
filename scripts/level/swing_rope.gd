class_name SwingRope
extends Node2D
## 盪鞦韆：座椅跟著拍子擺盪，角度只由 Conductor.song_beat 決定，永遠不會脫拍。
## 在空中碰到座椅就會抓住；按跳放手。
##   在「往前擺到最高」的那一拍放手（判定窗同音符）→ 固定的大拋物線，飛得又高又遠。
##   其他時間放手 → 只帶著座椅當下的速度掉下去，通常到不了對岸。
## period = 來回一趟幾拍（預設 4 = 每小節往前盪到頂一次；8 = 慢鞦韆）；
## offset = 往前到頂的拍子位移（相鄰鞦韆錯開半趟就能接力）。

const SEAT_HALF := 22.0
const GRAB_RADIUS := 44.0
## 碰到繩子任何一段都算抓住，之後在 GRAB_BLEND 秒內滑到座椅上
const ROPE_GRAB := 30.0
const GRAB_BLEND := 0.15
## 完美放手的初速（px/s，世界時間）。玩家重力改成固定跳躍的 4480 後，初速乘 √(4480/2400)，
## 飛行路線和原本 2400 重力時完全一樣（只是快一點），落點不用重算
const LAUNCH_VX := 574.0
const LAUNCH_VY := 1120.0
const ROPE := Color(0.93, 0.86, 0.74)
const SEAT := Color(0.98, 0.62, 0.36)
const GLOW := Color(1.0, 0.9, 0.45)

var length: float = 160.0
var period: float = 4.0
var offset: float = 0.0
var dir: int = 1
var amplitude: float = deg_to_rad(55.0)

var _rider: Player = null
var _grab_offset := Vector2.ZERO
var _blend: float = 0.0
var _flash: float = 0.0
var _last_tick: int = -99999


func setup(anchor: Vector2, rope_length: float, period_beats: float = 4.0, forward: int = 1,
		phase_offset: float = 0.0, amplitude_deg: float = 55.0) -> void:
	position = anchor
	length = rope_length
	period = maxf(period_beats, 0.5)
	dir = 1 if forward >= 0 else -1
	offset = phase_offset
	amplitude = deg_to_rad(amplitude_deg)


func _ready() -> void:
	z_index = 5
	add_to_group("swing")


func angle_at(beat: float) -> float:
	return dir * amplitude * cos(TAU * (beat - offset) / period)


func seat_at(beat: float) -> Vector2:
	var a := angle_at(beat)
	return global_position + Vector2(sin(a), cos(a)) * length


## 離 beat 最近的「往前到頂」拍
func nearest_peak(beat: float) -> float:
	return offset + period * roundf((beat - offset) / period)


func next_peak(beat: float) -> float:
	return offset + period * ceilf((beat - offset) / period)


func is_riding(p: Node) -> bool:
	return _rider != null and _rider == p


func _rider_pos(beat: float) -> Vector2:
	return seat_at(beat) + Vector2(0.0, -Player.BODY_SIZE.y * 0.5 + 4.0)


func _physics_process(_delta: float) -> void:
	if _rider != null and (not is_instance_valid(_rider) or _rider.ride != self):
		_rider = null
	if _rider != null:
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or not p.can_ride() or p.is_on_floor():
		return
	var seat := seat_at(Conductor.song_beat)
	var pc := p.global_position
	var on_rope := Geometry2D.get_closest_point_to_segment(pc, global_position + (seat - global_position) * 0.35, seat).distance_to(pc) <= ROPE_GRAB
	if pc.distance_to(seat + Vector2(0, -8)) <= GRAB_RADIUS or on_rope:
		_rider = p
		_grab_offset = pc - _rider_pos(Conductor.song_beat)
		_blend = 1.0
		p.begin_ride(self, "apex_0")
		p.facing = dir
		_last_tick = floori(Conductor.song_beat)
		GameState.play_sfx("block", 4.0, -9.0)


func ride_step(p: Player, delta: float) -> void:
	var b := Conductor.song_beat
	var before := p.global_position
	_blend = maxf(0.0, _blend - delta / GRAB_BLEND)
	var target := _rider_pos(b) + _grab_offset * (_blend * _blend)
	p.global_position = target
	var vel := (target - before) / maxf(delta, 0.0001)
	p.facing = dir
	## 每拍輕敲一下；往前到頂那一拍是亮音，讓人數得出「再一拍」
	var tick := floori(b)
	if tick != _last_tick:
		_last_tick = tick
		var at_peak := absf(float(tick) - nearest_peak(float(tick))) < 0.01
		if at_peak:
			GameState.play_cue("cue", 16.0, -6.0)
		else:
			GameState.play_cue("cue", 4.0, -14.0)
	if not Input.is_action_just_pressed("jump"):
		return
	_rider = null
	var peak := nearest_peak(b)
	if GameState.in_window((b - peak) * Conductor.sec_per_beat):
		_flash = 1.0
		GameState.play_sfx("pluck", GameState.next_note(), -3.0)
		GameState.play_cue("cue", 19.0, -4.0)
		p.end_ride(Vector2(dir * LAUNCH_VX, -LAUNCH_VY))
		p._hit_feedback(p.global_position, GameState.judge((b - peak) * Conductor.sec_per_beat), Vector2(dir, -1).normalized(),
			Color(0.98, 0.62, 0.36))
	else:
		p.fail_feedback()
		GameState.play_sfx("pluck", GameState.next_note() - 12.0, -10.0)
		var weak := Vector2(clampf(vel.x, -p.run_speed, p.run_speed), clampf(vel.y, -380.0, 200.0))
		p.end_ride(weak)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var b := Conductor.song_beat
	## 擺盪軌跡與「往前到頂」的星星
	var arc_pts := PackedVector2Array()
	for i in 25:
		var a := lerpf(-amplitude, amplitude, float(i) / 24.0)
		arc_pts.append(Vector2(sin(a), cos(a)) * length)
	draw_polyline(arc_pts, Color(1, 1, 1, 0.12), 2.0, true)
	var peak_local := Vector2(sin(dir * amplitude), cos(dir * amplitude)) * length
	var until := next_peak(b) - b
	var near := clampf(1.0 - until, 0.0, 1.0)
	var star_r := 7.0 + near * 5.0
	_draw_star(peak_local + Vector2(dir * 26.0, -26.0), star_r, Color(GLOW, 0.35 + 0.6 * near))
	## 錨點與繩子
	draw_circle(Vector2.ZERO, 7.0, Color(0.25, 0.2, 0.3))
	draw_circle(Vector2.ZERO, 3.5, ROPE)
	var seat_local := seat_at(b) - global_position
	var side := Vector2(cos(angle_at(b)), -sin(angle_at(b))) * SEAT_HALF
	draw_line(Vector2.ZERO, seat_local - side, ROPE, 2.5, true)
	draw_line(Vector2.ZERO, seat_local + side, ROPE, 2.5, true)
	## 座椅
	var plank := PackedVector2Array([seat_local - side, seat_local + side])
	draw_polyline(plank, SEAT.darkened(0.35), 9.0, true)
	draw_polyline(plank, SEAT, 6.0, true)
	if _rider == null:
		draw_circle(seat_local, GRAB_RADIUS * 0.55, Color(GLOW, 0.08 + 0.12 * near))
	else:
		## 搭乘中：一拍內從大縮到座椅的提示圈，縮到底就是放手的時機
		if until <= 1.0:
			var r := lerpf(64.0, 18.0, near * near)
			draw_arc(seat_local + Vector2(0, -20), r, 0.0, TAU, 40, Color(GLOW, 0.25 + 0.65 * near), 3.0, true)
	if _flash > 0.0:
		draw_circle(seat_local, 20.0 + (1.0 - _flash) * 50.0, Color(GLOW, _flash * 0.35))


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, color)
