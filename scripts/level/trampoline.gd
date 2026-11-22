class_name Trampoline
extends StaticBody2D
## 彈簧床：站上去就會跟著拍子自動彈跳，每一次都在整拍落回床面。
## 落回床面的那一拍按跳（判定窗同音符），下一下就彈高一段；不按就維持同樣高度一直自動彈。
## 四段高度與滯空：1.5 → 3.5 格各 1 拍，7 → 10 格各 2 拍（越高越慢，節奏是 1、1、2、2）。
## 彈跳時仍可左右移動；移出床面就照當下的垂直速度掉出去，落到旁邊的高台就算抵達。
## 床面在這一格的頂端；整格是實心的，玩家可以從旁邊走上去。

## 各段：h = 彈起的高度（px）、beats = 一次彈跳佔幾拍
const TIERS: Array[Dictionary] = [
	{"h": 60.0, "beats": 1.0},
	{"h": 140.0, "beats": 1.0},
	{"h": 280.0, "beats": 2.0},
	{"h": 400.0, "beats": 2.0},
]
const COLOR := Color(1.0, 0.55, 0.78)
const FRAME := Color(0.22, 0.17, 0.3)

var width: float = 160.0
var tile: float = 40.0

var _rider: Player = null
var _waiting: bool = false
var _next_beat: float = 0.0
var _bounce_start: float = 0.0
var _bounce_len: float = 1.0
var _tier: int = 0
## 剛落地那一拍判定前的段數（晚按時用來補判）
var _tier_before: int = 0
var _landing_judged: bool = true
var _h_display: float = 0.0
var _last_press: float = -INF
var _sag: float = 0.0
var _flash: float = 0.0


func setup(top_left: Vector2, w: float, tile_size: float = 40.0) -> void:
	position = top_left
	width = w
	tile = tile_size


func _ready() -> void:
	collision_layer = Player.LAYER_WORLD
	collision_mask = 0
	z_index = 3
	add_to_group("trampoline")
	add_to_group("no_cling")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, tile)
	shape.shape = r
	shape.position = Vector2(width * 0.5, tile * 0.5)
	add_child(shape)


func tier() -> int:
	return _tier


func is_riding(p: Node) -> bool:
	return _rider != null and _rider == p


func _physics_process(_delta: float) -> void:
	if _rider != null and (not is_instance_valid(_rider) or _rider.ride != self):
		_release_rider()
	if _rider != null:
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or not p.can_ride() or not p.is_on_floor():
		return
	var feet_y := p.global_position.y + Player.BODY_SIZE.y * 0.5
	if absf(feet_y - global_position.y) > 6.0:
		return
	if p.global_position.x < global_position.x or p.global_position.x > global_position.x + width:
		return
	_board(p)


func _board(p: Player) -> void:
	_rider = p
	p.begin_ride(self, "land_1")
	p.add_collision_exception_with(self)
	var b := Conductor.song_beat
	_next_beat = ceilf(b)
	if _next_beat - b < 0.05:
		_next_beat += 1.0
	_waiting = true
	_tier = 0
	_tier_before = 0
	_h_display = 0.0
	_landing_judged = true
	_last_press = -INF
	_sag = 1.0
	GameState.play_sfx("block", 0.0, -10.0)


func _release_rider() -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.remove_collision_exception_with(self)
	_rider = null
	_waiting = false


func _judged(press_beat: float, boundary: float) -> bool:
	if press_beat == -INF:
		return false
	return GameState.in_window((press_beat - boundary) * Conductor.sec_per_beat)


## 在 boundary（整拍）落回床面，決定下一下的段數並開始彈
func _start_bounce(boundary: float, _first: bool) -> void:
	_tier_before = _tier
	var ok := _judged(_last_press, boundary)
	if ok:
		_tier = mini(_tier + 1, TIERS.size() - 1)
		_on_tier_up()
	_landing_judged = ok
	_bounce_start = boundary
	_bounce_len = float(TIERS[_tier]["beats"])
	_waiting = false
	_sag = 1.0
	_rider.call("_set_squash", Vector2(1.3, 0.72))
	GameState.play_sfx("pluck", GameState.next_note() - 12.0 + _tier * 5.0, -7.0)


func _on_tier_up() -> void:
	_flash = 1.0
	GameState.play_cue("cue", 12.0 + _tier * 4.0, -5.0)


func ride_step(p: Player, delta: float) -> void:
	var b := Conductor.song_beat
	if Input.is_action_just_pressed("jump"):
		_last_press = b
		## 晚一點按（落地後的判定窗內）也算，補升一段
		if not _waiting and not _landing_judged and _judged(b, _bounce_start):
			_landing_judged = true
			_tier = mini(_tier_before + 1, TIERS.size() - 1)
			_bounce_len = float(TIERS[_tier]["beats"])
			_on_tier_up()
		elif not _waiting and (b - _bounce_start) > 0.25 and (_bounce_start + _bounce_len - b) > 0.25:
			p.fail_feedback()

	if _waiting:
		if b >= _next_beat:
			_start_bounce(_next_beat, true)
	elif b >= _bounce_start + _bounce_len:
		_start_bounce(_bounce_start + _bounce_len, false)

	var target_h := 0.0 if _waiting else float(TIERS[_tier]["h"])
	_h_display = lerpf(_h_display, target_h, 1.0 - exp(-30.0 * delta))
	var t := 0.0 if _waiting else clampf((b - _bounce_start) / _bounce_len, 0.0, 1.0)
	var lift := 4.0 * _h_display * t * (1.0 - t)
	var target_y := global_position.y - lift - Player.BODY_SIZE.y * 0.5 - 1.0

	var dir := p.ride_input_x()
	if dir != 0:
		p.facing = dir
		p.move_and_collide(Vector2(dir * p.run_speed * delta, 0.0))
	var before_y := p.global_position.y
	var col := p.move_and_collide(Vector2(0.0, target_y - before_y))
	var vy := (p.global_position.y - before_y) / maxf(delta, 0.0001)
	p.ride_pose = "land_1" if _waiting or lift < 6.0 else ("jump_0" if t < 0.4 else ("apex_0" if t < 0.6 else "fall_0"))

	if col and col.get_normal().y < -0.7:
		## 往下時踩到旁邊的高台：抵達
		_release_rider()
		p.end_ride(Vector2.ZERO, false)
		return
	var x := p.global_position.x
	if x < global_position.x - 2.0 or x > global_position.x + width + 2.0:
		_release_rider()
		p.end_ride(Vector2(0.0, vy), false)


func _process(delta: float) -> void:
	_sag = maxf(0.0, _sag - delta * 5.0)
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var lit := _rider != null
	## 腳架與外框
	for lx: float in [10.0, width * 0.5, width - 10.0]:
		draw_line(Vector2(lx - 6, 8), Vector2(lx - 10, tile), FRAME, 5.0)
		draw_line(Vector2(lx + 6, 8), Vector2(lx + 10, tile), FRAME, 5.0)
	draw_rect(Rect2(0, 6, width, 8), FRAME)
	draw_rect(Rect2(0, 6, width, 3), FRAME.lightened(0.25))
	## 床面：有人落下時往下凹
	var sag_x := width * 0.5
	if lit:
		sag_x = clampf(_rider.global_position.x - global_position.x, 12.0, width - 12.0)
	var sag := 9.0 * _sag
	var pts := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var x := width * float(i) / float(n)
		var d := absf(x - sag_x) / maxf(width * 0.5, 1.0)
		pts.append(Vector2(x, 2.0 + sag * maxf(0.0, 1.0 - d * d * 3.0)))
	draw_polyline(pts, Color(COLOR, 0.95), 5.0, true)
	draw_polyline(pts, Color(1, 1, 1, 0.45), 1.5, true)
	## 彈簧
	for i in range(1, 6):
		var sx := width * float(i) / 6.0
		var top := pts[int(round(float(i) / 6.0 * n))].y + 2.0
		var zig := PackedVector2Array()
		for k in 5:
			zig.append(Vector2(sx + (3.0 if k % 2 == 0 else -3.0), lerpf(top, 6.0, float(k) / 4.0)))
		draw_polyline(zig, Color(0.8, 0.85, 0.95, 0.7), 1.5)
	## 段數燈：四顆
	var cx := width * 0.5
	for i in TIERS.size():
		var on := lit and i <= _tier and not _waiting
		var pc := Vector2(cx + (i - 1.5) * 14.0, tile * 0.62)
		draw_circle(pc, 5.0, Color(COLOR, 0.95) if on else Color(0.1, 0.08, 0.16, 0.85))
		if on and _flash > 0.0:
			draw_circle(pc, 5.0 + _flash * 6.0, Color(COLOR, _flash * 0.5))
	## 下一次落床的提示圈：一拍內從大縮到床面
	if lit:
		var land := _next_beat if _waiting else _bounce_start + _bounce_len
		var until := land - Conductor.song_beat
		if until <= 1.0 and until >= 0.0:
			var k := 1.0 - until
			var r := lerpf(46.0, 14.0, k * k)
			draw_arc(Vector2(sag_x, 2.0), r, PI, TAU, 24, Color(1, 1, 1, 0.25 + 0.6 * k), 2.5, true)
	if _flash > 0.0:
		draw_rect(Rect2(0, -2, width, 6), Color(1, 1, 1, _flash * 0.4))
