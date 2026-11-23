class_name Trampoline
extends StaticBody2D
## 彈簧床：沒人的時候床面也跟著拍子一直彈（每拍一沉、提示圈每拍縮一次），看得出節奏。
## 一碰到床面（走上去或從空中落下）馬上被彈起，第一下只到下一個整拍，之後每一次都在整拍落回床面。
## 落回床面的那一拍按跳（判定窗同音符），下一下就彈高一段；不按就維持同樣高度一直自動彈。
## 四段高度與滯空：1.5 → 3.5 格各 1 拍，7 → 10 格各 2 拍（越高越慢，節奏是 1、1、2、2）。
## 彈跳時仍可左右移動；移出床面就照當下的垂直速度掉出去，落到旁邊的高台就算抵達。
## 床面在這一格的頂端；整格是實心的，玩家可以從旁邊走上去。
##
## 連段模式（need > 0，正式版關卡用）：站上去就停在床中間（自動跑不會把人帶走），
## 每次落床那一拍按跳就升一段；升到第 need 段就把人往前彈出去、飛上對面的高台。
## 任何一次落床那一拍按跳都會升一段（不限哪一拍）；沒按到就維持同一段再彈一次。
## 飛出去之後空中的衝刺環、音符每一拍都亮，晚幾拍飛出去也接得上；下一段的起跳旗會重新對拍。

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
## 連段模式要按幾次（0 = 一般模式：不按維持高度、走出床面離開）
var need: int = 0
## 連段模式：這一拍落床沒按準，等判定窗過了還沒補按就掉下去
var _pending_fail: float = INF
## 連段模式沒按準：讓這個人穿過床面掉下去（掉到床面下方夠遠才恢復碰撞）
var _dropping: Player = null

var _rider: Player = null
var _waiting: bool = false
var _next_beat: float = 0.0
var _bounce_start: float = 0.0
var _bounce_len: float = 1.0
## 這一下的高度（第一下依剩下的時間縮放，之後就是 TIERS[_tier].h）
var _bounce_h: float = 60.0
var _idle_tick: int = -99999
var _tier: int = 0
## 剛落地那一拍判定前的段數（晚按時用來補判）
var _tier_before: int = 0
var _landing_judged: bool = true
var _h_display: float = 0.0
var _last_press: float = -INF
var _sag: float = 0.0
var _flash: float = 0.0


## 彈簧床圖；BED_CAP = 左右兩端（腳）佔圖寬的比例，中間那段拉長填滿寬度
const BED_TEX := preload("res://assets/ui/trampoline_strip.png")
const BED_CAP := 0.06

func setup(top_left: Vector2, w: float, tile_size: float = 40.0, need_presses: int = 0, _press_phase: float = -1.0) -> void:
	position = top_left
	width = w
	tile = tile_size
	need = need_presses


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
	if _dropping != null:
		if not is_instance_valid(_dropping) or _dropping.global_position.y > global_position.y + 80.0 \
				or _dropping.control_locked:
			if is_instance_valid(_dropping):
				_dropping.remove_collision_exception_with(self)
			_dropping = null
		return
	if _rider != null and (not is_instance_valid(_rider) or _rider.ride != self):
		_release_rider()
	if _rider != null:
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or not p.can_ride():
		return
	var feet_y := p.global_position.y + Player.BODY_SIZE.y * 0.5
	## 站在床上，或從空中往下掉、腳快碰到床面
	var landing := not p.is_on_floor() and p.velocity.y >= 0.0 and feet_y >= global_position.y - 10.0 and feet_y <= global_position.y + 6.0
	if not landing and (not p.is_on_floor() or absf(feet_y - global_position.y) > 6.0):
		return
	if p.global_position.x < global_position.x or p.global_position.x > global_position.x + width:
		return
	_board(p)


func _board(p: Player) -> void:
	_rider = p
	p.begin_ride(self, "land_1")
	p.add_collision_exception_with(self)
	var b := Conductor.song_beat
	## 床一直在彈：碰到就馬上彈起，落在下一個整拍（太近就再下一拍）
	var land := ceilf(b)
	if land - b < 0.35:
		land += 1.0
	_next_beat = land
	_waiting = false
	_bounce_start = b
	_bounce_len = land - b
	_bounce_h = float(TIERS[0]["h"]) * _bounce_len * _bounce_len
	_tier = 0
	_tier_before = 0
	_h_display = _bounce_h
	_landing_judged = true
	_last_press = -INF
	_pending_fail = INF
	_sag = 1.0
	_rider.call("_set_squash", Vector2(1.3, 0.72))
	GameState.play_sfx("pluck", GameState.next_note() - 12.0, -7.0)


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
	_bounce_h = float(TIERS[_tier]["h"])
	_waiting = false
	_sag = 1.0
	_rider.call("_set_squash", Vector2(1.3, 0.72))
	GameState.play_sfx("pluck", GameState.next_note() - 12.0 + _tier * 5.0, -7.0)


func p_fail_hint() -> void:
	if _rider != null:
		_rider.fail_feedback()
	GameState.play_sfx("miss", 0.0, -8.0)


func _on_tier_up() -> void:
	_flash = 1.0
	_pending_fail = INF
	GameState.play_cue("cue", 12.0 + _tier * 4.0, -5.0)


## 連段模式：升到第 need 段 → 往前彈出去（高度就是這一段的高度，往前跟跑步一樣快）
## 拋物線和這一段在床上的彈跳一樣：高度 h、整段 beats 拍，所以剛好在出發後半段（正拍）到最高點，
## 空中的衝刺環、音符可以放在正拍上（tools/campaign.py 照同一條拋物線擺）
func _launch(p: Player) -> void:
	var h := float(TIERS[_tier]["h"])
	var air := float(TIERS[_tier]["beats"]) * Player.WORLD_SPB
	var g := 8.0 * h / (air * air)
	var vy := 4.0 * h / air
	_release_rider()
	p.facing = 1
	p.end_ride(Vector2(p.run_speed, -vy), true, g)
	GameState.play_cue("cue", 24.0, -4.0)



func ride_step(p: Player, delta: float) -> void:
	var b := Conductor.song_beat
	if Input.is_action_just_pressed("jump"):
		_last_press = b
		## 晚一點按（落地後的判定窗內）也算，補升一段
		if not _waiting and not _landing_judged and _judged(b, _bounce_start):
			_landing_judged = true
			_tier = mini(_tier_before + 1, TIERS.size() - 1)
			_bounce_len = float(TIERS[_tier]["beats"])
			_bounce_h = float(TIERS[_tier]["h"])
			_on_tier_up()
			_pending_fail = INF
		elif not _waiting and (b - _bounce_start) > 0.25 and (_bounce_start + _bounce_len - b) > 0.25:
			p.fail_feedback()

	if _waiting:
		if b >= _next_beat:
			_start_bounce(_next_beat, true)
	elif b >= _bounce_start + _bounce_len:
		_start_bounce(_bounce_start + _bounce_len, false)

	if need > 0:
		if _tier >= need and _landing_judged:
			_launch(p)
			return

	var target_h := 0.0 if _waiting else _bounce_h
	_h_display = lerpf(_h_display, target_h, 1.0 - exp(-30.0 * delta))
	var t := 0.0 if _waiting else clampf((b - _bounce_start) / _bounce_len, 0.0, 1.0)
	var lift := 4.0 * _h_display * t * (1.0 - t)
	var target_y := global_position.y - lift - Player.BODY_SIZE.y * 0.5 - 1.0

	var dir := 0 if need > 0 else p.ride_input_x()
	if need > 0:
		## 連段模式：停在床中間
		var cx := global_position.x + width * 0.5
		p.move_and_collide(Vector2((cx - p.global_position.x) * minf(1.0, 12.0 * delta), 0.0))
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
	## 沒人在床上也每拍沉一下
	var tick := floori(Conductor.song_beat)
	if tick != _idle_tick:
		_idle_tick = tick
		if _rider == null:
			_sag = maxf(_sag, 0.7)
	_sag = maxf(0.0, _sag - delta * 5.0)
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var lit := _rider != null
	## 彈簧床（手繪圖切三段：左腳、中間拉長、右腳）；有人落下時整張往下壓一點
	var sag_x := width * 0.5
	if lit:
		sag_x = clampf(_rider.global_position.x - global_position.x, 12.0, width - 12.0)
	var sag := 6.0 * _sag
	var th := 26.0
	var ks := th / float(BED_TEX.get_height())
	var cap_src := float(BED_TEX.get_width()) * BED_CAP
	var cap_w := cap_src * ks
	var src_h := float(BED_TEX.get_height())
	var y0 := sag
	var hh := th - sag * 0.5
	draw_texture_rect_region(BED_TEX, Rect2(0, y0, cap_w, hh), Rect2(0, 0, cap_src, src_h))
	draw_texture_rect_region(BED_TEX, Rect2(cap_w, y0, maxf(0.0, width - cap_w * 2.0), hh),
		Rect2(cap_src, 0, float(BED_TEX.get_width()) - cap_src * 2.0, src_h))
	draw_texture_rect_region(BED_TEX, Rect2(width - cap_w, y0, cap_w, hh),
		Rect2(float(BED_TEX.get_width()) - cap_src, 0, cap_src, src_h))
	## 段數燈：四顆
	var cx := width * 0.5
	## 連段模式只畫要按的次數（need 顆），一般模式畫四段
	var lights := need if need > 0 else TIERS.size()
	for i in lights:
		var on := lit and (i < _tier if need > 0 else i <= _tier) and not _waiting
		var pc := Vector2(cx + (i - (lights - 1) * 0.5) * 14.0, tile * 0.82)
		var off_col := Color(0.1, 0.08, 0.16, 0.85)
		if not lit and i == 0:
			off_col = off_col.lerp(COLOR, 0.25 + 0.5 * _sag)
		draw_circle(pc, 5.0, Color(COLOR, 0.95) if on else off_col)
		if on and _flash > 0.0:
			draw_circle(pc, 5.0 + _flash * 6.0, Color(COLOR, _flash * 0.5))
	## 下一次落床的提示圈：一拍內從大縮到床面；沒人時每拍都縮一次
	var land := ceilf(Conductor.song_beat)
	if lit:
		land = _next_beat if _waiting else _bounce_start + _bounce_len
	var until := land - Conductor.song_beat
	if until <= 1.0 and until >= 0.0:
		var k := 1.0 - until
		var r := lerpf(46.0, 14.0, k * k)
		var a := (0.25 + 0.6 * k) if lit else (0.12 + 0.3 * k)
		draw_arc(Vector2(sag_x, 2.0), r, PI, TAU, 24, Color(1, 1, 1, a), 2.5, true)
	if _flash > 0.0:
		draw_rect(Rect2(0, -2, width, 6), Color(1, 1, 1, _flash * 0.4))
