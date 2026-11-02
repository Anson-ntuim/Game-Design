class_name Player
extends CharacterBody2D
## 仿 Hollow Knight 的角色控制器。
## 重點：沒有加速度的水平移動、按住越久跳越高、放開跳躍鍵立即停止上升、
## 固定距離衝刺、蹬牆跳。沒有常駐二段跳，空中要再跳只能靠關卡裡的節奏音符。
##
## 角色本身不判定按鍵時機，節奏完全來自關卡：
##   節奏音符只在亮起的那一拍能用、光牆只在特定拍打開、節拍鼓在鼓點上把人彈高。
## 沒有血量：碰到任何傷害就倒下，回到最後坐過的長椅。

signal died
signal damaged

const LAYER_WORLD := 1
const LAYER_HAZARD := 4
const LAYER_ENEMY := 8
const LAYER_TRIGGER := 16
const LAYER_GATE := 32
const BODY_SIZE := Vector2(24, 44)
## 圖片造型在遊戲裡的高度（腳底到頭頂）
const SKIN_HEIGHT := 60.0
## 動作幀：落地（land_0～2 各 LAND_STEP 秒，邊跑邊落地只播前兩張）、音符二段跳揮鼓棒（前 DRUM_WINDUP 秒舉棒）、
## 倒下、停步（stop_0、stop_1 各一半）、起跑各維持幾秒
const LAND_STEP := 0.06
const LAND_POSE_TIME := LAND_STEP * 3.0
const DRUM_POSE_TIME := 0.3
const DRUM_WINDUP := 0.07
const HURT_POSE_TIME := 0.5
const STOP_POSE_TIME := 0.14
const START_POSE_TIME := 0.08
## 衝刺頭尾各幾秒用 dash_0／dash_2，中間 dash_1
const DASH_EDGE_TIME := 0.05
## 空中上下速度小於這個值（px/s）算跳到最高點
const APEX_SPEED := 150.0

@export_group("Run")
@export var run_speed: float = 310.0

@export_group("Jump")
## 按住跳躍時維持的固定上升速度
@export var jump_speed: float = 560.0
## 最短跳躍時間（輕點跳躍的高度）
@export var jump_min_time: float = 0.08
## 最長可維持上升的時間（按住到底的高度）
@export var jump_max_time: float = 0.2
## 按住超過這個時間就算長按：之後放開也會跳到最高（tools/sim_player.py 的 JUMP_COMMIT 要一起改）
@export var jump_commit_time: float = 0.22
@export var gravity: float = 2400.0
@export var max_fall_speed: float = 760.0
@export var coyote_time: float = 0.08
@export var jump_buffer_time: float = 0.1

@export_group("Rhythm Orb")
@export var orb_jump_speed: float = 560.0
@export var orb_jump_max_time: float = 0.18

@export_group("Wall")
@export var can_wall_jump: bool = true
@export var wall_slide_speed: float = 160.0
## 蹬牆後強制往外推、暫時無法控制水平方向的時間
@export var wall_jump_push_time: float = 0.12

@export_group("Dash")
@export var dash_speed: float = 850.0
@export var dash_time: float = 0.2
@export var dash_cooldown: float = 0.55
## 穿過衝刺環的那次衝刺結束時往上彈的速度（讓連續每拍衝刺維持同一個高度）
@export var ring_pop_speed: float = 360.0

@export_group("Beat Pad")
@export var beat_pad_speed: float = 950.0
@export var beat_pad_time: float = 0.2

var facing: int = 1
## F 切換自動往右跑；手動方向輸入、死亡和示範會取消。
var auto_running: bool = false
## 自動跑時在旗子前等候 3、2、1、GO（由 CueFlag 開關）
var auto_flag_wait: bool = false
var control_locked: bool = false
## 看起跳旗示範的期間不能操作（重力等物理照常），會自己走到旗子下（watch_x）站好
var watching: bool = false
var watch_x: float = 0.0
var checkpoint_position: Vector2
var kill_y: float = 100000.0
var slow_charges: int = 0
var _gravity_strength: float = 2400.0
var _gravity_target: float = 2400.0
## 走進輕重力區時柔順過渡；回到正常則較快，避免落地還飄

## 倒下時給提示用（death_coach.gd 讀）
## 最近一次起跳：beat、x、kind（ground／orb／wall／pad）、long（有沒有變成大跳）、held（按了幾秒）
var last_jump: Dictionary = {}
## 最近一次按錯拍：what（orb／ring／gate）、beat、off（離最近的 x 拍幾拍，負的是早）
var last_miss: Dictionary = {}
## 最近幾次按下衝刺的拍子、在空中按跳卻沒碰著亮起音符的拍子
var recent_dashes: Array[float] = []
var recent_air_presses: Array[float] = []
## 碰到的機關（掉坑是 null）
var death_source: Node = null
var death_beat: float = 0.0
var death_pos: Vector2 = Vector2.ZERO

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jumping: bool = false
var _jump_elapsed: float = 0.0
var _jump_speed_current: float = 0.0
var _jump_max_current: float = 0.0
var _jump_cancelable: bool = false
## 這次跳躍彈出的音高；按住超過輕點的時間就接上延音，讓「長」聽得出來（INF = 不接）
var _hold_note: float = INF
var _air_dash: bool = true
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: int = 1
var _dash_beat: float = -99.0
var _ring_pop: bool = false
var _ring_hit: DashRing = null
var _ring_missed: bool = false
## 這次衝刺按在拍子上、可以穿過的光牆（衝刺結束時恢復碰撞）
var _gate_pass: Array[BeatGate] = []
var _wall_dir: int = 0
var _wall_sliding: bool = false
var _wall_push_timer: float = 0.0
var _wall_push_dir: int = 0
var _invincible_timer: float = 0.0
var _was_on_floor: bool = true
var _squash: Vector2 = Vector2.ONE
var _trail: Array[Vector2] = []
var _wing_timer: float = 0.0
var _fail_puff: float = 0.0
var _land_timer: float = 0.0
var _drum_timer: float = 0.0
var _hurt_timer: float = 0.0
var _stop_timer: float = 0.0
var _start_timer: float = 0.0
var _was_running: bool = false
var _hurtbox: Area2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = LAYER_WORLD | LAYER_GATE
	floor_snap_length = 8.0
	z_index = 10

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY_SIZE
	col.shape = rect
	add_child(col)

	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = LAYER_HAZARD | LAYER_ENEMY | LAYER_TRIGGER
	_hurtbox.monitorable = false
	var hcol := CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = BODY_SIZE - Vector2(6, 6)
	hcol.shape = hrect
	_hurtbox.add_child(hcol)
	add_child(_hurtbox)

	checkpoint_position = position
	_gravity_strength = gravity


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if control_locked:
		auto_running = false
		velocity = Vector2.ZERO
		_update_visuals(delta)
		return

	var on_floor := is_on_floor()
	var input_x := _input_dir()

	if on_floor:
		_coyote = coyote_time
		_air_dash = true
		if not _was_on_floor:
			_on_landed()
	_was_on_floor = on_floor

	_wall_dir = 0 if on_floor else _detect_wall()
	if can_wall_jump and _wall_dir != 0:
		_air_dash = true

	if Input.is_action_just_pressed("jump") and not watching:
		_jump_buffer = jump_buffer_time
	if Input.is_action_just_pressed("dash") and not watching:
		_try_dash(input_x, on_floor)
	if Input.is_action_just_pressed("use_item") and not watching:
		_try_slow_item()

	if _dash_timer > 0.0:
		velocity = Vector2(_dash_dir * dash_speed, 0.0)
		_trail.append(global_position)
		_check_rings()
		move_and_slide()
		for i in get_slide_collision_count():
			var gate := get_slide_collision(i).get_collider() as Node
			if gate and gate.has_method("reject"):
				gate.call("reject")
				if gate is BeatGate:
					last_miss = {"what": "gate", "beat": _dash_beat, "off": BeatPattern.offset((gate as BeatGate).notes, _dash_beat)}
		_after_move(delta)
		return

	# 水平：沒有加速度，放開方向鍵立刻停下（HK 的招牌手感）
	if _wall_push_timer > 0.0:
		velocity.x = _wall_push_dir * run_speed
	else:
		velocity.x = input_x * run_speed
		if input_x != 0:
			facing = input_x

	_wall_sliding = can_wall_jump and _wall_dir != 0 and input_x == _wall_dir \
		and velocity.y > 0.0
	if _wall_sliding:
		facing = -_wall_dir

	if _jump_buffer > 0.0:
		if on_floor or _coyote > 0.0:
			_ground_jump()
		elif can_wall_jump and _wall_dir != 0:
			_wall_jump()
		else:
			var orb := _ready_orb()
			if orb:
				_orb_jump(orb)
			elif Input.is_action_just_pressed("jump"):
				_orb_miss_feedback()
				recent_air_presses.append(Conductor.song_beat)
				if recent_air_presses.size() > 8:
					recent_air_presses.pop_front()
	# 垂直：按住期間維持固定上升速度，放開就把上升速度歸零；按滿 jump_commit_time 就一定跳到最高
	var jump_held := Input.is_action_pressed("jump")
	# 等速上升（jump_max_time）結束後還在往上的期間也要計時，門檻可以比 jump_max_time 長
	if _jumping or _jump_cancelable:
		_jump_elapsed += delta
		if jump_held and _jump_cancelable:
			last_jump["held"] = _jump_elapsed
			if _jump_elapsed >= jump_commit_time:
				_jump_cancelable = false
				last_jump["long"] = true
				if _hold_note != INF:
					GameState.play_sfx("hold", _hold_note, -9.0)
	_tick_gravity_blend(delta)
	if _jumping:
		var holding := jump_held or not _jump_cancelable
		if _jump_elapsed < jump_min_time or (holding and _jump_elapsed < _jump_max_current):
			velocity.y = -_jump_speed_current
		else:
			_jumping = false
			if not holding:
				velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + _gravity_strength * delta, max_fall_speed)
		if _jump_cancelable and velocity.y < 0.0 and not jump_held:
			velocity.y = 0.0
		if velocity.y >= 0.0:
			_jump_cancelable = false

	if _wall_sliding:
		velocity.y = minf(velocity.y, wall_slide_speed)

	move_and_slide()

	if is_on_ceiling() and velocity.y <= 0.0:
		_jumping = false
		_jump_cancelable = false
		velocity.y = 0.0

	_after_move(delta)


func _after_move(delta: float) -> void:
	_check_hurtbox()
	if global_position.y > kill_y:
		kill()
	_update_visuals(delta)


func _tick_timers(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	_wall_push_timer = maxf(0.0, _wall_push_timer - delta)
	_invincible_timer = maxf(0.0, _invincible_timer - delta)
	_wing_timer = maxf(0.0, _wing_timer - delta)
	_fail_puff = maxf(0.0, _fail_puff - delta)
	_land_timer = maxf(0.0, _land_timer - delta)
	_drum_timer = maxf(0.0, _drum_timer - delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_stop_timer = maxf(0.0, _stop_timer - delta)
	_start_timer = maxf(0.0, _start_timer - delta)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			if _overlapping_gate():
				_dash_timer = 0.01
			else:
				var pop := _ring_pop
				_end_dash()
				if pop:
					## 輕重力時等比縮小上彈，避免連續穿環一路爬出螢幕
					var g_scale := sqrt(maxf(_gravity_strength, 1.0) / 2400.0)
					velocity.y = -ring_pop_speed * g_scale


func _end_dash() -> void:
	_dash_timer = 0.0
	_ring_pop = false
	collision_mask = LAYER_WORLD | LAYER_GATE
	velocity = Vector2.ZERO
	_close_gates()


func _open_gates() -> void:
	_close_gates()
	for g: BeatGate in get_tree().get_nodes_in_group("beat_gate"):
		if g.accepts(_dash_beat):
			add_collision_exception_with(g)
			_gate_pass.append(g)


func _close_gates() -> void:
	for g in _gate_pass:
		if is_instance_valid(g):
			remove_collision_exception_with(g)
	_gate_pass.clear()


func _overlapping_gate() -> bool:
	var shape := RectangleShape2D.new()
	shape.size = BODY_SIZE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = LAYER_GATE
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _input_dir() -> int:
	if watching:
		auto_running = false
		auto_flag_wait = false
		var dx := watch_x - global_position.x
		return 0 if absf(dx) < 4.0 else (1 if dx > 0.0 else -1)
	if auto_flag_wait:
		var dx := watch_x - global_position.x
		return 0 if absf(dx) < 4.0 else (1 if dx > 0.0 else -1)
	var x := Input.get_axis("move_left", "move_right")
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		auto_running = false
		auto_flag_wait = false
	elif Input.is_action_just_pressed("auto_run"):
		auto_running = not auto_running
		if not auto_running:
			auto_flag_wait = false
	if x > 0.3:
		return 1
	if x < -0.3:
		return -1
	return 1 if auto_running else 0


## 光滑牆（no_cling 群組）不能滑牆也不能蹬牆
func _detect_wall() -> int:
	for dir: int in [1, -1]:
		var col := move_and_collide(Vector2(dir * 3, 0), true)
		if col and absf(col.get_normal().x) > 0.7:
			var body := col.get_collider() as Node
			if body and not body.is_in_group("no_cling"):
				return dir
	return 0


func _floor_pad() -> Node:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.7:
			var body := col.get_collider() as Node
			if body and body.is_in_group("beat_pad"):
				return body
	return null


## 動作就是樂器：每次跳躍依序彈出目前和弦的音
func _ground_jump() -> void:
	var note := GameState.next_note()
	GameState.play_sfx("pluck", note)
	_begin_jump(jump_speed, jump_max_time, true, "ground")
	_hold_note = note


## 站在節拍鼓上時，鼓點一響就被彈高（由 BeatPad 呼叫）
func launch_from_pad(pad: Node) -> bool:
	if control_locked or _dash_timer > 0.0 or not is_on_floor() or _floor_pad() != pad:
		return false
	GameState.play_sfx("pluck", GameState.next_note() - 12.0)
	GameState.play_sfx("cue", 0.0, -8.0)
	_begin_jump(beat_pad_speed, beat_pad_time, false, "pad")
	return true


func _ready_orb() -> Node:
	for area in _hurtbox.get_overlapping_areas():
		if not area.is_in_group("rhythm_orb"):
			continue
		if area.has_method("is_ready") and area.call("is_ready"):
			return area
	return null


func apply_gravity_mode(strength: float, _inverted: bool = false) -> void:
	_gravity_target = strength


func _tick_gravity_blend(delta: float) -> void:
	if absf(_gravity_strength - _gravity_target) < 0.5:
		_gravity_strength = _gravity_target
		gravity = _gravity_strength
		return
	## 變輕慢一點（漂起來），變重快一點（腳立刻穩）
	var rate := 2.2 if _gravity_target < _gravity_strength else 5.5
	_gravity_strength = move_toward(_gravity_strength, _gravity_target, absf(_gravity_target - _gravity_strength) * rate * delta + 80.0 * delta)
	gravity = _gravity_strength


func _try_slow_item() -> void:
	if slow_charges <= 0:
		return
	slow_charges -= 1
	Conductor.apply_slow(0.55, 8.0)
	GameState.play_sfx("hold", GameState.next_note(), -5.0)
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("show_message"):
		main.call("show_message", "減速瓶　音樂與動作放慢 8 拍", 1.6)


## 節奏音符：在音符亮起的瞬間按跳，再跳一次並補回空中衝刺
func _orb_jump(orb: Node) -> void:
	if orb.has_method("consume"):
		orb.call("consume")
	var note := GameState.next_note() + 12.0
	GameState.play_sfx("pluck", note)
	_wing_timer = 0.3
	_drum_timer = DRUM_POSE_TIME
	_air_dash = true
	_begin_jump(orb_jump_speed, orb_jump_max_time, true, "orb")
	_hold_note = note


## 碰著還沒亮（或已用過）的音符按跳：出聲提示按錯拍
func _orb_miss_feedback() -> void:
	for area in _hurtbox.get_overlapping_areas():
		if area is RhythmOrb:
			GameState.play_sfx("miss", 0.0, -6.0)
			_fail_puff = 0.35
			var b := Conductor.song_beat
			last_miss = {"what": "orb", "beat": b, "off": BeatPattern.offset((area as RhythmOrb).notes, b)}
			return


## 衝刺中穿過衝刺環：按下衝刺的時間在環的拍子上，就清掉冷卻、補回空中衝刺，衝刺結束時往上彈
func _check_rings() -> void:
	for area in _hurtbox.get_overlapping_areas():
		var ring := area as DashRing
		if ring == null or ring == _ring_hit:
			continue
		if ring.accepts(_dash_beat):
			ring.consume(_dash_beat)
			_ring_hit = ring
			GameState.play_sfx("pluck", GameState.next_note() + 12.0)
			_dash_cooldown_timer = 0.0
			_air_dash = true
			## 往上輕彈是為了連續穿環維持高度；重重力時關掉，手感才會真的「往下沉」
			_ring_pop = _gravity_strength < 3000.0
			_wing_timer = 0.3
		elif not _ring_missed:
			_ring_missed = true
			GameState.play_sfx("miss", 0.0, -6.0)
			_fail_puff = 0.35
			last_miss = {"what": "ring", "beat": _dash_beat, "off": BeatPattern.offset(ring.notes, _dash_beat)}


func _begin_jump(speed: float, max_time: float, cancelable: bool, kind: String) -> void:
	_jumping = true
	_jump_elapsed = 0.0
	_hold_note = INF
	last_jump = {"beat": Conductor.song_beat, "x": global_position.x, "kind": kind, "long": not cancelable, "held": 0.0}
	_jump_speed_current = speed
	_jump_max_current = max_time
	_jump_cancelable = cancelable
	velocity.y = -speed
	_jump_buffer = 0.0
	_coyote = 0.0
	_squash = Vector2(0.75, 1.3)


func _wall_jump() -> void:
	var note := GameState.next_note()
	GameState.play_sfx("pluck", note)
	_wall_push_dir = -_wall_dir
	_wall_push_timer = wall_jump_push_time
	facing = _wall_push_dir
	_begin_jump(jump_speed, jump_max_time * 0.9, true, "wall")
	_hold_note = note
	velocity.x = _wall_push_dir * run_speed


func _try_dash(input_x: int, on_floor: bool) -> void:
	if _dash_cooldown_timer > 0.0:
		return
	if not on_floor and not _air_dash:
		return
	var dir := facing
	if _wall_dir != 0 and not on_floor:
		dir = -_wall_dir
	elif input_x != 0:
		dir = input_x
	GameState.play_sfx("clap")
	facing = dir
	_dash_dir = dir
	_dash_timer = dash_time
	_dash_cooldown_timer = dash_cooldown
	_dash_beat = Conductor.song_beat
	recent_dashes.append(_dash_beat)
	if recent_dashes.size() > 8:
		recent_dashes.pop_front()
	_ring_hit = null
	_ring_missed = false
	collision_mask = LAYER_WORLD
	_open_gates()
	if not on_floor:
		_air_dash = false
	_jumping = false
	_jump_cancelable = false
	_wall_push_timer = 0.0
	_trail.clear()


func _check_hurtbox() -> void:
	for area in _hurtbox.get_overlapping_areas():
		if area.is_in_group("checkpoint"):
			area.call("activate", self)
		elif area.is_in_group("goal"):
			area.call("reach", self)
		elif _invincible_timer <= 0.0 and area.has_method("is_harmful") and area.call("is_harmful"):
			kill(area)
			return


func _on_landed() -> void:
	_squash = Vector2(1.3, 0.75)
	_jump_cancelable = false
	_land_timer = LAND_POSE_TIME
	_drum_timer = 0.0
	_stop_timer = 0.0
	_start_timer = 0.0


## 碰到尖刺、活塞、雷射、掉坑或被音浪吞沒：直接倒下，由主場景送回長椅（source = 碰到的機關，掉坑是 null）
func kill(source: Node = null) -> void:
	if control_locked:
		return
	death_source = source
	death_beat = Conductor.song_beat
	death_pos = global_position
	damaged.emit()
	control_locked = true
	_reset_motion()
	_hurt_timer = HURT_POSE_TIME
	_hit_stop(0.08)
	died.emit()


func respawn_at(pos: Vector2) -> void:
	global_position = pos
	_gravity_strength = 2400.0
	apply_gravity_mode(2400.0)
	_reset_motion()
	_hurt_timer = 0.0
	_drum_timer = 0.0
	_stop_timer = 0.0
	_start_timer = 0.0
	_was_running = false
	_invincible_timer = 1.0
	control_locked = false
	watching = false


func _reset_motion() -> void:
	auto_running = false
	auto_flag_wait = false
	velocity = Vector2.ZERO
	_jumping = false
	_jump_cancelable = false
	_end_dash()
	_wall_push_timer = 0.0
	_trail.clear()


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void: Engine.time_scale = Conductor.world_rate)


func _update_visuals(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	if _dash_timer <= 0.0:
		# 空中也要更新：邊跑邊跳落地不算起跑，原地跳起來落地也不算停步
		var running := absf(velocity.x) > 10.0
		if is_on_floor() and _was_on_floor and running != _was_running:
			if running:
				_start_timer = START_POSE_TIME
				_stop_timer = 0.0
			else:
				_stop_timer = STOP_POSE_TIME
				_start_timer = 0.0
		_was_running = running
	if _dash_timer <= 0.0 and not _trail.is_empty():
		_trail.remove_at(0)
	while _trail.size() > 7:
		_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	var animated := GameState.skin_frame("idle_0") != null
	var feet := Vector2(0, BODY_SIZE.y * 0.5)
	for i in _trail.size():
		var p := to_local(_trail[i])
		var a := float(i + 1) / float(_trail.size() + 1) * 0.4
		if animated:
			draw_skin(self, GameState.skin, p + feet, Vector2(facing, 1.0), 0.0, Color(0.75, 0.9, 1.0, a), "dash_1")
		else:
			draw_skin(self, GameState.skin, p + feet, Vector2(facing, 1.0), 0.35 * facing, Color(0.75, 0.9, 1.0, a))

	var alpha := 1.0
	if _invincible_timer > 0.0 and fmod(_invincible_timer, 0.12) < 0.06:
		alpha = 0.3

	if _wing_timer > 0.0:
		var wa := _wing_timer / 0.3 * 0.7
		draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2(-18, 0), 16.0, Color(1, 1, 1, wa * 0.5))
		draw_circle(Vector2(18, 0), 16.0, Color(1, 1, 1, wa * 0.5))

	var s := _squash
	var tilt := 0.0
	if animated:
		var pose := _pose()
		var dir := _wall_dir if pose == "wall_0" else facing
		draw_skin(self, GameState.skin, feet, Vector2(s.x * dir, s.y), 0.0, Color(1, 1, 1, alpha), pose)
	else:
		# 圖片造型沒有動作幀：用拍點彈跳、跑步小跳、空中和衝刺的傾斜讓它動起來
		var b := Conductor.song_beat
		if _dash_timer > 0.0:
			tilt = 0.35
		elif not is_on_floor():
			tilt = clampf(velocity.y / max_fall_speed, -1.0, 1.0) * 0.18
		elif absf(velocity.x) > 10.0:
			feet.y -= absf(sin(b * TAU)) * 4.0
			tilt = 0.1 + sin(b * TAU) * 0.06
		else:
			var pulse := Conductor.pulse(6.0)
			s *= Vector2(1.0 + 0.04 * pulse, 1.0 - 0.06 * pulse)
		draw_skin(self, GameState.skin, feet, Vector2(s.x * facing, s.y), tilt * facing, Color(1, 1, 1, alpha))

	if _fail_puff > 0.0:
		var t := 1.0 - _fail_puff / 0.35
		for i in 3:
			var px := (i - 1) * 12.0
			draw_circle(Vector2(px, 22.0 + t * 10.0), 5.0 * (1.0 - t) + 2.0, Color(0.6, 0.6, 0.65, 0.7 * (1.0 - t)))


## 有動作幀的造型這一刻要用哪一幀
func _pose() -> String:
	if _hurt_timer > 0.0:
		return "hurt_0"
	if _dash_timer > 0.0:
		if dash_time - _dash_timer < DASH_EDGE_TIME:
			return "dash_0"
		return "dash_2" if _dash_timer < DASH_EDGE_TIME else "dash_1"
	if is_on_floor():
		var moving := absf(velocity.x) > 10.0
		# 剛碰到地面的這一幀 _on_landed 還沒跑（下一個物理幀才偵測）
		if not _was_on_floor:
			return "land_0"
		if _land_timer > 0.0:
			var step := floori((LAND_POSE_TIME - _land_timer) / LAND_STEP)
			if step < (2 if moving else 3):
				return "land_%d" % step
		if _stop_timer > 0.0:
			return "stop_0" if _stop_timer > STOP_POSE_TIME * 0.5 else "stop_1"
		if _start_timer > 0.0:
			return "start_0"
		if moving:
			return run_pose(Conductor.song_beat)
		return idle_pose(Conductor.song_beat)
	if _wall_sliding:
		return "wall_0"
	if _drum_timer > 0.0:
		return "orb_0" if _drum_timer > DRUM_POSE_TIME - DRUM_WINDUP else "orb_1"
	if absf(velocity.y) < APEX_SPEED:
		return "apex_0"
	return "jump_0" if velocity.y < 0.0 else "fall_0"


## 一拍跑完一輪 6 幀（左右各一步），第 0、3 幀腳著地，所以每半拍踩在拍子上
static func run_pose(beat: float) -> String:
	return "run_%d" % mini(floori(fposmod(beat, 1.0) * 6.0), 5)


## 一拍 6 張的原地律動：拍點那張蹲到最低、閉眼，之後站起、預備、再往下
static func idle_pose(beat: float) -> String:
	return "idle_%d" % mini(floori(fposmod(beat, 1.0) * 6.0), 5)


## 畫角色本體（腳底在 feet、面向右，body_scale.x 給負的就面向左）；選關畫面預覽也用這個。
## pose 是動作幀名稱，造型沒有這一幀時改畫靜態圖
static func draw_skin(ci: CanvasItem, index: int, feet: Vector2, body_scale: Vector2, tilt: float = 0.0,
		tint: Color = Color.WHITE, pose: String = "") -> void:
	ci.draw_set_transform(feet, tilt, body_scale)
	var frame := GameState.skin_frame(pose, index)
	if frame != null:
		var info: Dictionary = GameState.SKINS[GameState.skin if index < 0 else index]
		var k := SKIN_HEIGHT / float(info["frame_height"])
		var anchor: Vector2 = info["frame_anchor"]
		ci.draw_texture_rect(frame, Rect2(-anchor * k, frame.get_size() * k), false, tint)
	else:
		var tex := GameState.skin_texture(index)
		var w := SKIN_HEIGHT * tex.get_width() / float(tex.get_height())
		ci.draw_texture_rect(tex, Rect2(-w * 0.5, -SKIN_HEIGHT, w, SKIN_HEIGHT), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
