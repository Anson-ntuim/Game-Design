class_name Player
extends CharacterBody2D
## 節奏跑酷角色控制器。
## 預設自動往右跑（F 可切換成手動）；跳躍高度固定，平地上起跳後剛好 JUMP_BEATS 拍落地，
## 不管按多久都一樣，玩家只要決定「哪一拍跳」。固定距離衝刺、蹬牆跳。
## 沒有常駐二段跳，空中要再跳只能靠關卡裡的節奏音符。
## 物理和 tools/sim_player.py 一致（關卡地形由它模擬產生），改數值要兩邊一起改。
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
## 固定跳躍：高度（px）與一般重力下的滯空拍數。重力「標稱值」2400 = 1 拍、1000（輕重力）= 2 拍，高度不變
const JUMP_HEIGHT := 140.0
const JUMP_BEATS := 1.0
const NOMINAL_NORMAL := 2400.0
const NOMINAL_LIGHT := 1000.0
## 一拍的世界時間（世界和音樂一起變速）
const WORLD_SPB := 0.5
## 標稱重力（關卡資料、重力區用的數字）；實際物理用 eff_gravity()
@export var gravity: float = 2400.0
@export var coyote_time: float = 0.08
@export var jump_buffer_time: float = 0.1

@export_group("Wall")
## 不能貼牆滑、蹬牆跳（碰到牆就照常往下掉）
@export var can_wall_jump: bool = false
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
## 自動往右跑（預設開，GameState.auto_run）。按住方向鍵只會暫時改方向，放開就繼續自動跑；F 切換自動／手動。
var auto_running: bool = false
## 自動跑時在旗子前等候 3、2、1、GO（由 CueFlag 開關）
var auto_flag_wait: bool = false
## 剛重生：下一面旗子一定停下來完整倒數（至少 CueFlag.REST_BEATS 拍），不會一出生就直接衝進段落
var rest_after_respawn: bool = false
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
## 搭乘中的機關（彈簧床、盪鞦韆、礦車）：搭乘期間由機關的 ride_step(player, delta) 決定位置，
## 機關呼叫 end_ride() 放開角色並給一個初速。
var ride: Node = null
var ride_pose: String = "apex_0"
var _ride_cooldown: float = 0.0
## 從機關被拋出去時保留的水平速度，落地、碰牆、衝刺或再次起跳就結束
var _launch_active: bool = false
var _launch_vx: float = 0.0
## 被拋出去期間用的重力（0 = 一般）：彈簧床的拋物線要剛好一拍到最高點，重力和一般跳不同
var _launch_gravity: float = 0.0
## 高音符（飄）：重力減半，飛兩拍才回到原高度；落地、衝刺、再跳就恢復
var _orb_float: float = 1.0
## 打中時角色閃白一下（秒）
var _flash_t: float = 0.0
## 上一次踩拍的拍號
var _step_beat: int = -99999
## 低畫質時略過不變的重畫（節點位移仍由引擎帶動）
var _draw_key: String = ""


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
	auto_running = GameState.auto_run


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if control_locked:
		auto_running = false
		velocity = Vector2.ZERO
		_update_visuals(delta)
		return

	if ride != null:
		if is_instance_valid(ride):
			ride.call("ride_step", self, delta)
		else:
			ride = null
		_after_move(delta)
		return

	var on_floor := is_on_floor()
	var input_x := _input_dir()

	if on_floor:
		_coyote = coyote_time
		_air_dash = true
		## 剛被彈出去的那一幀，is_on_floor 還是上車前的舊值：往上飛的時候不算落地
		if velocity.y >= 0.0:
			_launch_active = false
			_orb_float = 1.0
		if not _was_on_floor:
			_on_landed()
	_was_on_floor = on_floor

	_wall_dir = 0 if on_floor else _detect_wall()
	if can_wall_jump and _wall_dir != 0:
		_air_dash = true
		_launch_active = false

	if Input.is_action_just_pressed("jump") and not watching:
		_jump_buffer = jump_buffer_time
	if Input.is_action_just_pressed("dash") and not watching:
		_try_dash(input_x, on_floor)
	if Input.is_action_just_pressed("use_item") and not watching:
		_try_slow_item()

	if _dash_timer > 0.0:
		velocity = Vector2(_dash_dir * dash_speed, 0.0)
		_append_trail()
		_check_rings()
		move_and_slide()
		for i in get_slide_collision_count():
			var gate := get_slide_collision(i).get_collider() as Node
			if gate and gate.has_method("reject"):
				gate.call("reject")
				GameState.break_combo()
				if gate is BeatGate:
					last_miss = {"what": "gate", "beat": _dash_beat, "off": BeatPattern.offset((gate as BeatGate).notes, _dash_beat)}
		_after_move(delta)
		return

	# 水平：沒有加速度，放開方向鍵立刻停下（HK 的招牌手感）
	if _wall_push_timer > 0.0:
		velocity.x = _wall_push_dir * run_speed
	elif _launch_active:
		## 被拋出去的弧線固定，往反方向按只會煞車一半，避免一放手就失去距離
		velocity.x = _launch_vx
		if input_x != 0 and signf(input_x) != signf(_launch_vx):
			velocity.x = _launch_vx * 0.5
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
	# 垂直：跳躍是固定拋物線（放開跳鍵不會切短）；只有節拍鼓有一小段等速上升
	_tick_gravity_blend(delta)
	if _jumping:
		_jump_elapsed += delta
		if _jump_elapsed < _jump_max_current:
			velocity.y = -_jump_speed_current
		else:
			_jumping = false
	else:
		velocity.y = minf(velocity.y + eff_gravity() * _orb_float * delta, max_fall_speed())

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
	## 在地上跑的時候每一拍踩一下（壓扁再彈回），腳步跟著拍子
	var beat_i := floori(Conductor.song_beat)
	if beat_i != _step_beat:
		_step_beat = beat_i
		if is_on_floor() and absf(velocity.x) > 10.0 and _dash_timer <= 0.0 and ride == null:
			_set_squash(Vector2(1.14, 0.88))
	_flash_t = maxf(0.0, _flash_t - delta)
	var glow := clampf(_flash_t / 0.12, 0.0, 1.0)
	modulate = Color(1, 1, 1).lerp(Color(1.9, 1.85, 1.6), glow)
	_land_timer = maxf(0.0, _land_timer - delta)
	_drum_timer = maxf(0.0, _drum_timer - delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_stop_timer = maxf(0.0, _stop_timer - delta)
	_start_timer = maxf(0.0, _start_timer - delta)
	_ride_cooldown = maxf(0.0, _ride_cooldown - delta)
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
		## 看示範時暫停自動跑（不改 auto_running，看完會接著自動跑）
		auto_flag_wait = false
		var dx := watch_x - global_position.x
		return 0 if absf(dx) < 4.0 else (1 if dx > 0.0 else -1)
	if auto_flag_wait:
		var dx := watch_x - global_position.x
		return 0 if absf(dx) < 4.0 else (1 if dx > 0.0 else -1)
	var x := Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("auto_run"):
		auto_running = not auto_running
		GameState.set_auto_run(auto_running)
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
	_begin_jump(0.0, 0.0, false, "ground")


## 站在節拍鼓上時，鼓點一響就被彈高（由 BeatPad 呼叫）
func launch_from_pad(pad: Node) -> bool:
	if control_locked or _dash_timer > 0.0 or not is_on_floor() or _floor_pad() != pad:
		return false
	GameState.play_sfx("pluck", GameState.next_note() - 12.0)
	GameState.play_sfx("cue", 0.0, -8.0)
	_begin_jump(beat_pad_speed, beat_pad_time, false, "pad")
	return true


## 機關能不能接手角色（剛被拋出去的短時間內不會又被同一個機關抓回去）
func can_ride() -> bool:
	return ride == null and not control_locked and not watching and _ride_cooldown <= 0.0 and _dash_timer <= 0.0


func begin_ride(node: Node, pose: String = "apex_0") -> void:
	ride = node
	ride_pose = pose
	velocity = Vector2.ZERO
	## 抓住機關就恢復一般重力（大音符的飄浮不會帶到鞦韆放手之後）
	_orb_float = 1.0
	_jumping = false
	_jump_cancelable = false
	_jump_buffer = 0.0
	_launch_active = false
	_wall_push_timer = 0.0
	_air_dash = true
	_trail.clear()
	_set_squash(Vector2(1.2, 0.85))


## 機關放開角色。carry = true 時，launch.x 會一路保持到落地（拋物線固定，關卡才算得準）
func end_ride(launch: Vector2, carry: bool = true, launch_gravity: float = 0.0) -> void:
	_launch_gravity = launch_gravity
	ride = null
	_ride_cooldown = 0.25
	velocity = launch
	_launch_active = carry and absf(launch.x) > 1.0
	_launch_vx = launch.x
	if absf(launch.x) > 1.0:
		facing = 1 if launch.x > 0.0 else -1
	_jumping = false
	_jump_cancelable = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_was_on_floor = false
	if launch.y < -1.0:
		_set_squash(Vector2(0.8, 1.25))


## 搭乘機關用：目前的左右輸入（含自動跑）
func ride_input_x() -> int:
	return _input_dir()


func fail_feedback() -> void:
	GameState.break_combo()
	_fail_puff = 0.35


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
	var dt := 0.0
	if orb.has_method("consume"):
		var r: Variant = orb.call("consume")
		if r is float:
			dt = r
	_hit_feedback((orb as Node2D).global_position, GameState.judge(dt), Vector2(0, -1))
	var note := GameState.next_note() + 12.0
	GameState.play_sfx("pluck", note)
	_wing_timer = 0.3
	_drum_timer = DRUM_POSE_TIME
	_air_dash = true
	_begin_jump(0.0, 0.0, false, "orb")
	## 高音符：一樣的起跳速度、重力減半 → 高兩倍、兩拍才落回原高度；低音符：速度減半 → 很矮、半拍就落回來
	match String(orb.get("jump_kind")):
		"high":
			_orb_float = 0.5
		"low":
			velocity.y *= 0.5


## 碰著還沒亮（或已用過）的音符按跳：出聲提示按錯拍
func _orb_miss_feedback() -> void:
	for area in _hurtbox.get_overlapping_areas():
		if area is RhythmOrb:
			GameState.break_combo()
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
			var dt := ring.consume(_dash_beat)
			_hit_feedback(ring.global_position, GameState.judge(dt), Vector2(_dash_dir, 0), Color(0.45, 0.9, 1.0))
			_ring_hit = ring
			GameState.play_sfx("pluck", GameState.next_note() + 12.0)
			_dash_cooldown_timer = 0.0
			_air_dash = true
			## 往上輕彈是為了連續穿環維持高度；重重力時關掉，手感才會真的「往下沉」
			_ring_pop = _gravity_strength < 3000.0
			_wing_timer = 0.3
		elif not _ring_missed:
			_ring_missed = true
			GameState.break_combo()
			GameState.play_sfx("miss", 0.0, -6.0)
			_fail_puff = 0.35
			last_miss = {"what": "ring", "beat": _dash_beat, "off": BeatPattern.offset(ring.notes, _dash_beat)}


## 地面、音符、蹬牆跳都是同一條固定拋物線（speed／max_time 不使用）；
## 節拍鼓（kind = "pad"）才用 speed 等速上升 max_time 秒
func _begin_jump(speed: float, max_time: float, cancelable: bool, kind: String) -> void:
	_launch_active = false
	_orb_float = 1.0
	_jump_elapsed = 0.0
	_hold_note = INF
	last_jump = {"beat": Conductor.song_beat, "x": global_position.x, "kind": kind, "long": true, "held": 0.0}
	_jump_cancelable = false
	if kind == "pad":
		_jumping = true
		_jump_speed_current = speed
		_jump_max_current = max_time
		velocity.y = -speed
	else:
		_jumping = false
		velocity.y = -fixed_jump_speed()
	_jump_buffer = 0.0
	_coyote = 0.0
	_set_squash(Vector2(0.75, 1.3))


## 標稱重力 → 平地跳躍滯空幾拍（2400 → 1 拍、1000 → 2 拍，中間線性；和 sim_player.jump_beats 相同）
func jump_beats() -> float:
	var t := (NOMINAL_NORMAL - _gravity_strength) / (NOMINAL_NORMAL - NOMINAL_LIGHT)
	return JUMP_BEATS * (1.0 + clampf(t, 0.0, 1.0))


func eff_gravity() -> float:
	if _launch_active and _launch_gravity > 0.0:
		return _launch_gravity
	var air := jump_beats() * WORLD_SPB
	return 8.0 * JUMP_HEIGHT / (air * air)


func fixed_jump_speed() -> float:
	return sqrt(2.0 * eff_gravity() * JUMP_HEIGHT)


## 落下最快就是一般重力起跳的初速（拋物線上下對稱）
static func max_fall_speed() -> float:
	var air := JUMP_BEATS * WORLD_SPB
	return 4.0 * JUMP_HEIGHT / air


func _wall_jump() -> void:
	var note := GameState.next_note()
	GameState.play_sfx("pluck", note)
	_wall_push_dir = -_wall_dir
	_wall_push_timer = wall_jump_push_time
	facing = _wall_push_dir
	_begin_jump(0.0, 0.0, false, "wall")
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
	_orb_float = 1.0
	_dash_cooldown_timer = dash_cooldown
	_dash_beat = Conductor.song_beat
	recent_dashes.append(_dash_beat)
	if recent_dashes.size() > 8:
		recent_dashes.pop_front()
	_ring_hit = null
	_ring_missed = false
	_launch_active = false
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
	_set_squash(Vector2(1.3, 0.75))
	_jump_cancelable = false
	## 低畫質略過落地過渡幀，少換貼圖
	_land_timer = LAND_POSE_TIME if pose_frames() > 1 else 0.0
	_drum_timer = 0.0
	_stop_timer = 0.0
	_start_timer = 0.0


func _set_squash(target: Vector2) -> void:
	var amount := GameState.anim_amount()
	if amount < 0.2:
		_squash = Vector2.ONE
		return
	_squash = Vector2.ONE.lerp(target, amount)


func _append_trail() -> void:
	var cap := GameState.quality_int("player_trail", 7)
	if cap <= 0:
		return
	## 中畫質隔幀採樣，減少陣列與重畫
	if cap <= 3 and Engine.get_physics_frames() % 2 == 1:
		return
	_trail.append(global_position)
	while _trail.size() > cap:
		_trail.remove_at(0)


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
	## 瞬移：不要從死掉的位置插值滑過來
	reset_physics_interpolation()
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
	auto_running = GameState.auto_run
	rest_after_respawn = true


func _reset_motion() -> void:
	auto_running = false
	auto_flag_wait = false
	ride = null
	_launch_active = false
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
	var anim := GameState.anim_amount()
	if anim < 0.2:
		_squash = Vector2.ONE
	else:
		_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	var frames := pose_frames()
	if _dash_timer <= 0.0:
		# 空中也要更新：邊跑邊跳落地不算起跑，原地跳起來落地也不算停步
		var running := absf(velocity.x) > 10.0
		if frames > 1 and is_on_floor() and _was_on_floor and running != _was_running:
			if running:
				_start_timer = START_POSE_TIME
				_stop_timer = 0.0
			else:
				_stop_timer = STOP_POSE_TIME
				_start_timer = 0.0
		_was_running = running
	var trail_cap := GameState.quality_int("player_trail", 7)
	if _dash_timer <= 0.0 and not _trail.is_empty():
		_trail.remove_at(0)
	while _trail.size() > trail_cap:
		_trail.remove_at(0)

	## 低畫質姿態幾乎不動：只在狀態改變時重畫，省掉每幀貼圖切換
	var blink := _invincible_timer > 0.0 and fmod(_invincible_timer, 0.12) < 0.06
	var key := "%s|%d|%d|%.2f|%.2f|%d|%d" % [
		_pose() if GameState.skin_frame("idle_0") != null else "static",
		facing, _trail.size(), _squash.x, _squash.y,
		1 if blink else 0,
		1 if (_wing_timer > 0.0 or _fail_puff > 0.0) else 0,
	]
	if frames <= 1 and anim < 0.25 and key == _draw_key \
			and _squash.distance_squared_to(Vector2.ONE) < 0.0004 \
			and _trail.is_empty() and _wing_timer <= 0.0 and _fail_puff <= 0.0:
		return
	_draw_key = key
	queue_redraw()


func _draw() -> void:
	var animated := GameState.skin_frame("idle_0") != null
	var anim := GameState.anim_amount()
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

	if _wing_timer > 0.0 and anim >= 0.25:
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
		var juice := anim
		var b := Conductor.song_beat
		if _dash_timer > 0.0:
			tilt = 0.35 * juice
		elif not is_on_floor():
			tilt = clampf(velocity.y / max_fall_speed(), -1.0, 1.0) * 0.18 * juice
		elif absf(velocity.x) > 10.0:
			feet.y -= absf(sin(b * TAU)) * 4.0 * juice
			tilt = (0.1 + sin(b * TAU) * 0.06) * juice
		elif juice >= 0.25:
			var pulse := Conductor.pulse(6.0) * juice
			s *= Vector2(1.0 + 0.04 * pulse, 1.0 - 0.06 * pulse)
		draw_skin(self, GameState.skin, feet, Vector2(s.x * facing, s.y), tilt * facing, Color(1, 1, 1, alpha))

	if _fail_puff > 0.0 and anim >= 0.25:
		var t := 1.0 - _fail_puff / 0.35
		var puffs := 3 if anim >= 0.75 else 1
		for i in puffs:
			var px := (i - (puffs - 1) * 0.5) * 12.0
			draw_circle(Vector2(px, 22.0 + t * 10.0), 5.0 * (1.0 - t) + 2.0, Color(0.6, 0.6, 0.65, 0.7 * (1.0 - t)))


## 有動作幀的造型這一刻要用哪一幀
func _pose() -> String:
	if _hurt_timer > 0.0:
		return "hurt_0"
	if ride != null:
		return ride_pose
	if _dash_timer > 0.0:
		if pose_frames() <= 1:
			return "dash_1"
		if dash_time - _dash_timer < DASH_EDGE_TIME:
			return "dash_0"
		return "dash_2" if _dash_timer < DASH_EDGE_TIME else "dash_1"
	if is_on_floor():
		var moving := absf(velocity.x) > 10.0
		# 剛碰到地面的這一幀 _on_landed 還沒跑（下一個物理幀才偵測）
		if not _was_on_floor:
			return "land_0" if pose_frames() > 1 else ("run_0" if moving else "idle_0")
		if _land_timer > 0.0 and pose_frames() > 1:
			var step := floori((LAND_POSE_TIME - _land_timer) / LAND_STEP)
			if step < (2 if moving else 3):
				return "land_%d" % step
		if _stop_timer > 0.0 and pose_frames() > 1:
			return "stop_0" if _stop_timer > STOP_POSE_TIME * 0.5 else "stop_1"
		if _start_timer > 0.0 and pose_frames() > 1:
			return "start_0"
		if moving:
			return run_pose(Conductor.song_beat)
		return idle_pose(Conductor.song_beat)
	if _wall_sliding:
		return "wall_0"
	if _drum_timer > 0.0:
		if pose_frames() <= 1:
			return "orb_1"
		return "orb_0" if _drum_timer > DRUM_POSE_TIME - DRUM_WINDUP else "orb_1"
	if absf(velocity.y) < APEX_SPEED:
		return "apex_0"
	return "jump_0" if velocity.y < 0.0 else "fall_0"


## 依畫質決定跑／待機循環要播幾幀（低＝定格、中＝2、高＝6）
static func pose_frames() -> int:
	return clampi(GameState.quality_int("player_frames", 6), 1, 6)


## 一拍跑完一輪（高畫質 6 幀）；低畫質定格 run_0，中畫質兩幀交替
static func run_pose(beat: float) -> String:
	var n := pose_frames()
	if n <= 1:
		return "run_0"
	return "run_%d" % mini(floori(fposmod(beat, 1.0) * float(n)), n - 1)


## 一拍原地律動；幀數隨畫質縮減
static func idle_pose(beat: float) -> String:
	var n := pose_frames()
	if n <= 1:
		return "idle_0"
	return "idle_%d" % mini(floori(fposmod(beat, 1.0) * float(n)), n - 1)


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


## 打擊回饋交給 main（特效、鏡頭）；在測試場景沒有 main 就什麼都不做
func _hit_feedback(at: Vector2, grade: String, dir: Vector2, tint: Color = Color(1.0, 0.78, 0.35)) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("hit_feedback"):
		main.call("hit_feedback", at, grade, dir, tint)


## 角色閃白 sec 秒
func flash(sec: float) -> void:
	_flash_t = maxf(_flash_t, sec)
