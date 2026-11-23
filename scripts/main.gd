extends Node2D
## 主場景：依 LevelData 建出整個關卡，負責鏡頭、存檔點、死亡重生與過關。

const TILE := LevelData.TILE
const SELECT_SCENE := "res://scenes/home.tscn"

var player: Player
var camera: Camera2D
var hud: Hud
var level_size: Vector2 = Vector2.ZERO
var spawn_point: Vector2 = Vector2.ZERO

var _hints: Array[Dictionary] = []
## 和 _hints 一一對應的標準節奏（見 level_data.gd）
var _plans: Array = []
var _patterns: Dictionary = {}
var _level_name: String = ""
var _stage: bool = false
var _wave: SoundWave
var _checkpoints: Array[Checkpoint] = []
var _flags: Array[CueFlag] = []
var _rest_zones: Array[RestZone] = []
var _blind_zones: Array[BlindZone] = []
## 玩家所在區塊要求的速度；在下一個小節頭才真的換速，拍子才不會亂
var _tempo_target: float = 120.0
## 玩家所在區塊的重力；走進區塊立刻強制轉換（和 bpm 一樣寫在 chunk 上）
var _gravity_target: float = 2400.0
var _gravity_applied: float = 2400.0
## 區塊內更細的重力帶（空中穿越邊界時切換）；有的話優先於 hint.gravity
var _gravity_zones: Array[Dictionary] = []
var _level_time: float = 0.0
var _completed: bool = false
var _shake: float = 0.0
var _look_x: float = 0.0
var _player_prev := Vector2.ZERO
var _player_curr := Vector2.ZERO
var _zoom_punch: float = 0.0
var _camera_ground_y: float = 0.0
var _score_cue_slot: int = -99999
var _tempo_pad_mode: bool = false
var _checkpoint_tempo_bpm: float = 120.0
## 各段落建議重生點
var _section_spawns: Array[Vector2] = []
var _section_index: int = 0


func _ready() -> void:
	Engine.time_scale = 1.0
	# 角色與機關先更新，鏡頭最後才追蹤物理解算後的位置。
	process_physics_priority = 10
	add_to_group("main")
	var bg := Background.new()
	add_child(bg)
	_build_level()
	_collect_cullable()
	_camera_ground_y = spawn_point.y
	bg.level_height = level_size.y
	bg.stage = _stage
	bg.profile = String(LevelData.level_info(GameState.level_index).get("background_profile", ""))

	player = Player.new()
	player.position = spawn_point
	player.kill_y = level_size.y + 120.0
	add_child(player)
	player.died.connect(_on_player_died)
	player.damaged.connect(_on_player_damaged)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level_size.x)
	camera.limit_bottom = int(level_size.y)
	camera.position = spawn_point
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	hud.player = player
	hud.tempo_mode = _tempo_pad_mode
	add_child(hud)
	add_child(TouchControls.new())

	GameState.reset_stats()
	Conductor.measure.connect(_on_measure)
	## 自訂音樂若已在播（剛過關進下一關），從頭重播會打斷曲子
	var restart_music := not (Conductor.custom_music and Conductor.is_music_playing())
	Conductor.start(true, restart_music)
	var start_sec := clampi(GameState.start_section, 0, maxi(0, _hints.size() - 1))
	GameState.start_section = 0
	if start_sec > 0:
		_warp_to_section(start_sec, true)


## 記下最近兩個物理步的角色位置，畫面更新時依插值比例取中間點（2D 沒有現成的插值變換可讀）
func _physics_process(_delta: float) -> void:
	_player_prev = _player_curr
	_player_curr = player.global_position


## 鏡頭每個畫面更新一次（不是每個物理步），追的是物理插值後的角色位置：
## 螢幕更新率和 120 物理頻率對不上時（144Hz、網頁）不會一幀不動一幀跳兩步。
## 前視距離跟水平速度走、慢慢變化，不再跟面向（轉身、蹬牆時不會左右甩）。
func _update_camera(delta: float) -> void:
	var view := get_viewport_rect().size / camera.zoom
	var player_pos: Vector2 = _player_prev.lerp(_player_curr, Engine.get_physics_interpolation_fraction())
	if _player_curr.distance_to(player.global_position) > 1.0:
		## 物理步之外被移動（重生、跳段）：直接用現在位置
		_player_prev = player.global_position
		_player_curr = player.global_position
		player_pos = player.global_position
	_look_x = lerpf(_look_x, clampf(player.velocity.x * 0.2, -60.0, 60.0), 1.0 - exp(-2.0 * delta))
	var target: Vector2 = player_pos + Vector2(_look_x, -30.0)
	if level_size.y > LevelData.HEIGHT * TILE:
		# 以最近落腳高度為基準，小跳保留下方地形；持續攀升才移動視野。
		if player.is_on_floor():
			_camera_ground_y = player.global_position.y
		target.y = clampf(_camera_ground_y + 20.0,
			player.global_position.y - view.y * 0.10, player.global_position.y + view.y * 0.12)
		target.y += clampf(player.velocity.y * 0.08, 0.0, 50.0)
	elif player.velocity.y > 500.0:
		target.y += 90.0
	var rate := 7.0
	var flag := _watching_flag()
	if flag:
		var focus: Variant = flag.camera_focus()
		if focus != null:
			target = focus + Vector2(120.0, 20.0 if level_size.y > LevelData.HEIGHT * TILE else -30.0)
			rate = 5.0
		else:
			rate = 3.0
	target.x = clampf(target.x, view.x * 0.5, maxf(view.x * 0.5, level_size.x - view.x * 0.5))
	target.y = clampf(target.y, view.y * 0.5, maxf(view.y * 0.5, level_size.y - view.y * 0.5))
	var y_rate := rate
	if not flag and level_size.y > LevelData.HEIGHT * TILE:
		y_rate = 5.0 if target.y < camera.position.y else 10.0
	camera.position.x = lerpf(camera.position.x, target.x, 1.0 - exp(-rate * delta))
	camera.position.y = lerpf(camera.position.y, target.y, 1.0 - exp(-y_rate * delta))
	if not flag and level_size.y > LevelData.HEIGHT * TILE:
		# 平滑追蹤仍有硬性安全範圍，連續接跳也不會把角色推到提示卡後面。
		camera.position.y = clampf(camera.position.y,
			player.global_position.y - view.y * 0.28, player.global_position.y + view.y * 0.18)
		camera.position.y = clampf(camera.position.y, view.y * 0.5, maxf(view.y * 0.5, level_size.y - view.y * 0.5))

	_shake = move_toward(_shake, 0.0, 40.0 * delta)
	## 畫面晃動預設關（設定裡可開）；開的時候也只用 35% 的平滑擺動，不用每幀亂跳的雜訊
	var amt := _shake * GameState.shake_amount()
	if amt > 0.05:
		camera.offset = Vector2(sin(_level_time * 37.0), cos(_level_time * 29.0)) * amt
	else:
		camera.offset = Vector2.ZERO
	_zoom_punch = move_toward(_zoom_punch, 0.0, 3.0 * delta)
	## 素材主題不用鏡頭 zoom punch：zoom 會整層縮放，遠城／近城看起來像被水平抽動
	if GameState.theme_is_procedural() and GameState.screen_shake:
		var punch := 0.025 * _zoom_punch * (0.4 + GameState.groove) * GameState.anim_amount()
		var z := 1.0 + punch
		camera.zoom = Vector2(z, z)
	else:
		camera.zoom = Vector2.ONE


func _process(delta: float) -> void:
	_update_camera(delta)
	_cull_offscreen()
	_watch_frame_rate(delta)
	if not _completed:
		_level_time += delta
	var hint := ""
	var subdivision_cue := false
	var section_duck := 0.0
	var px := player.global_position.x
	for i in _hints.size():
		var h: Dictionary = _hints[i]
		if px >= float(h["from"]) and px < float(h["to"]):
			_section_index = i
			hint = h["text"]
			subdivision_cue = bool(h.get("subdivision_cue", false))
			section_duck = float(h.get("music_duck", 0.0))
			_tempo_target = float(h["bpm"])
			_gravity_target = float(h.get("gravity", 2400))
			player.kill_y = float(h.get("kill_y", level_size.y + 120.0))
			break
	_gravity_target = _gravity_at_x(px)
	_apply_section_gravity()
	var watching := _watching_flag() != null
	hud.set_hint("" if _completed or watching else hint)
	hud.set_watching(watching)
	hud.set_gravity(player.gravity if player else _gravity_applied)

	var b := Conductor.song_beat
	## 節拍提示音用聲音時計（和音樂對齊）
	var cue_slot := floori(Conductor.cue_beat * 2.0)
	if cue_slot != _score_cue_slot:
		_score_cue_slot = cue_slot
		if subdivision_cue and not _completed and not watching and not player.control_locked:
			GameState.play_cue("block", 12.0 if posmod(cue_slot, 2) else 0.0, -15.0 if posmod(cue_slot, 2) else -19.0)
	var dark := 0.0
	for z in _blind_zones:
		dark = maxf(dark, z.darkness(b, px))
	hud.set_dark(0.0 if _completed or player.control_locked else dark)
	var duck := section_duck
	for z in _rest_zones:
		if z.contains(px) and z.resting(b):
			duck = 1.0
	Conductor.duck_target = duck

	var quality_step := 0
	if Input.is_action_just_pressed("quality_down"):
		quality_step = -1
	elif Input.is_action_just_pressed("quality_up"):
		quality_step = 1
	if quality_step != 0:
		var q := clampi(GameState.quality + quality_step, 0, GameState.QUALITIES.size() - 1)
		if q != GameState.quality:
			GameState.set_quality(q)
			hud.show_message("畫質　%s" % String(GameState.QUALITIES[q]["name"]), 1.2)

	if Input.is_action_just_pressed("back"):
		if _completed:
			GameState.set_meta("home_screen", "levels")
			get_tree().change_scene_to_file(SELECT_SCENE)
		else:
			_open_pause()
	elif Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	elif _completed and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump")):
		if GameState.level_index + 1 < LevelData.visible_count():
			GameState.level_index += 1
			get_tree().reload_current_scene()
		else:
			GameState.set_meta("home_screen", "levels")
			get_tree().change_scene_to_file(SELECT_SCENE)


## 數字鍵 1、2… 直接切換關卡
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F3:
		GameState.show_fps = not GameState.show_fps
		return
	var idx := key.physical_keycode - KEY_1
	if idx >= 0 and idx < LevelData.visible_count():
		GameState.level_index = idx
		get_tree().reload_current_scene()


## 暫停選單：整棵場景樹和節奏時鐘一起停
var _pause: PauseMenu = null


func _open_pause() -> void:
	if _pause != null:
		return
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.chosen.connect(_on_pause_chosen)
	Conductor.set_paused(true)
	get_tree().paused = true


func _on_pause_chosen(action: String) -> void:
	_close_pause()
	if action == "回到長椅":
		if not player.control_locked:
			_do_respawn(player.checkpoint_position)
	elif action == "從頭再來":
		get_tree().reload_current_scene()
	elif action == "回選關":
		GameState.set_meta("home_screen", "levels")
		get_tree().change_scene_to_file(SELECT_SCENE)


func _close_pause() -> void:
	if _pause == null:
		return
	_pause.queue_free()
	_pause = null
	get_tree().paused = false
	Conductor.set_paused(false)


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false
	Conductor.set_paused(false)


## 正在示範中的起跳旗（沒有就回傳 null）
func _watching_flag() -> CueFlag:
	for f in _flags:
		if f.state == CueFlag.State.WATCH:
			return f
	return null


func _on_measure(_m: int) -> void:
	_zoom_punch = 1.0
	if _tempo_pad_mode:
		return
	var now := Conductor.current_bpm
	var new_rate := Conductor.rate_for_world_bpm(_tempo_target)
	var actual_target := Conductor.bpm * new_rate
	if absf(now - actual_target) > 0.5 and not _completed:
		Conductor.set_rate(new_rate)
		hud.show_message(("加速！" if actual_target > now else "減速") + "　BPM %d" % roundi(actual_target), 1.6)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 打中音符／環／鞦韆放手：碎片＋評價字＋角色閃白；perfect 再加亮音（鏡頭不動，不會有停住的感覺）
func hit_feedback(at: Vector2, grade: String, dir: Vector2, tint: Color = Color(1.0, 0.78, 0.35)) -> void:
	HitFx.spawn(self, at, "burst", grade, tint)
	GameState.add_combo()
	if grade == "perfect":
		GameState.perfects += 1
		GameState.play_sfx("pluck", GameState.next_note() + 24.0, -12.0)
		player.flash(0.12)
	else:
		GameState.goods += 1
		player.flash(0.05)




func show_message(text: String, duration: float = 2.0) -> void:
	if hud:
		hud.show_message(text, duration)


func _on_tempo_pad_triggered(bpm: float) -> void:
	set_world_tempo(bpm)


func set_world_tempo(bpm: float, announce: bool = true) -> void:
	if not _tempo_pad_mode or _completed:
		return
	var new_rate := Conductor.rate_for_world_bpm(bpm)
	var actual_bpm := Conductor.bpm * new_rate
	var changed := absf(Conductor.current_bpm - actual_bpm) > 0.5
	var accelerating := actual_bpm > Conductor.current_bpm
	Conductor.set_rate(new_rate)
	if announce and changed:
		GameState.play_sfx("cue", 7.0 if accelerating else -5.0, -7.0)
		hud.show_message(("加速！" if accelerating else "減速") + "　%d BPM" % roundi(actual_bpm), 1.5)


func _apply_section_gravity() -> void:
	if _completed or not player:
		return
	player.apply_gravity_mode(_gravity_target)
	if absf(_gravity_applied - _gravity_target) < 0.5:
		return
	var was := _gravity_applied
	_gravity_applied = _gravity_target
	## 只有從輕變回正常才提示「恢復」，避免進關／同檔區塊重進時洗版
	if absf(_gravity_target - 2400.0) < 0.5:
		if was < 2399.0:
			hud.show_message("重力恢復", 1.2)
		return
	hud.show_message("%s　%s" % [_gravity_label(_gravity_target), _gravity_tip(_gravity_target)], 1.8)


func _gravity_label(strength: float) -> String:
	if strength < 2400.0:
		return "輕重力"
	return "正常"


func _gravity_tip(strength: float) -> String:
	if strength < 2400.0:
		return "滯空變長，該衝的拍還是要準"
	return ""


func _on_wave_armed(_start_beat: float) -> void:
	hud.show_message("音浪來了！跟著節奏一路衝到底", 2.2)


func _on_player_damaged() -> void:
	_shake = 6.0


func _on_player_died() -> void:
	GameState.break_combo()
	GameState.deaths += 1
	if _wave:
		_wave.reset()
	hud.fade(0.9)
	var section := 0
	for i in _hints.size():
		if player.death_pos.x >= float(_hints[i]["from"]):
			section = i
	## 同一段倒下太多次：這段的旗子亮出「看示範」提示
	_section_deaths[section] = int(_section_deaths.get(section, 0)) + 1
	if int(_section_deaths[section]) >= DEMO_HINT_DEATHS:
		_offer_demo(section)
	var tip := {}
	if GameState.level_index == 0:
		tip = DeathCoach.advise(player, _plans[section] if section < _plans.size() else [])
	## 只有第一關（教學）倒下會說明原因；其他關不跳文字
	if not tip.is_empty():
		hud.show_message(String(tip["title"]), 1.4)
		hud.show_tip(String(tip["detail"]))
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void:
		if _tempo_pad_mode:
			set_world_tempo(_checkpoint_tempo_bpm, false)
		## 一律在長椅出現，下一面旗子會停下來倒數（rest_after_respawn）；
		## 不再等某一拍才出現：音樂時鐘如果往回跳，那一拍永遠不會到，角色會一直卡在黑畫面
		_do_respawn(player.checkpoint_position))


## 同一段倒下幾次後提示可以看示範
const DEMO_HINT_DEATHS := 3
var _section_deaths: Dictionary = {}


func _offer_demo(section: int) -> void:
	if section >= _hints.size():
		return
	var h: Dictionary = _hints[section]
	for f in _flags:
		if f.position.x >= float(h["from"]) and f.position.x < float(h["to"]) and f.has_demo() and not f.offer_demo:
			f.offer_demo = true
			var how := "點畫面上方的「看示範」" if TouchControls.wanted() else "在旗子前按 ↑"
			hud.show_message("卡在這段了嗎？%s看示範" % how, 2.8)


## 觸控用：角色正站在一面有「看示範」提示的旗子前（可以按看示範）
func demo_offer_ready() -> bool:
	for f in _flags:
		if f.offer_demo and f.state == CueFlag.State.FREE and f.call("_at_flag", player):
			return true
	return false


## HUD 用：目前段落在「有連招的段落」裡是第幾段、共幾段、標題
func hud_section_info() -> Dictionary:
	var timed: Array[int] = []
	for i in _plans.size():
		if not (_plans[i] as Array).is_empty():
			timed.append(i)
	var cur := -1
	for k in timed.size():
		if timed[k] <= _section_index:
			cur = k
	var title := ""
	if _section_index < _hints.size():
		title = String(_hints[_section_index]["text"]).split("\n")[0]
	return {"index": cur, "total": timed.size(), "title": title}


func _do_respawn(pos: Vector2) -> void:
	player.respawn_at(pos)
	camera.position = player.global_position
	_camera_ground_y = player.global_position.y


func _on_checkpoint_activated(cp: Checkpoint) -> void:
	if _tempo_pad_mode:
		_checkpoint_tempo_bpm = Conductor.REFERENCE_BPM * Conductor._base_rate
	for other in _checkpoints:
		if other != cp:
			other.active = false


func _on_goal_reached() -> void:
	_completed = true
	player.control_locked = true
	if _wave:
		_wave.stop()
	var new_record := GameState.record_clear(GameState.level_index, _level_time, GameState.deaths,
		GameState.perfects, GameState.goods, GameState.max_combo)
	var best: Dictionary = GameState.records[GameState.level_index]
	hud.show_results({
		"time": _level_time, "deaths": GameState.deaths, "judge": GameState.DIFFICULTIES[GameState.difficulty]["name"],
		"perfects": GameState.perfects, "goods": GameState.goods,
		"max_combo": GameState.max_combo, "best_combo": int(best.get("combo", 0)),
		"score": GameState.rank_score(GameState.perfects, GameState.goods, GameState.deaths),
		"best_score": float(best.get("score", 0.0)),
		"new_record": new_record, "best_time": float(best["time"]), "best_deaths": int(best["deaths"]),
		"has_next": GameState.level_index + 1 < LevelData.visible_count(),
	})


func _warp_to_section(index: int, silent: bool = false) -> void:
	if _hints.is_empty() or not player:
		return
	var i := clampi(index, 0, _hints.size() - 1)
	_section_index = i
	var target := spawn_point
	if i < _section_spawns.size():
		target = _section_spawns[i]
	var h: Dictionary = _hints[i]
	player.respawn_at(target)
	player.checkpoint_position = target
	camera.position = target
	_camera_ground_y = target.y
	_gravity_applied = -1.0
	_gravity_target = float(h.get("gravity", 2400.0))
	_apply_section_gravity()
	player.kill_y = float(h.get("kill_y", level_size.y + 120.0))
	if _tempo_pad_mode:
		_checkpoint_tempo_bpm = float(h.get("bpm", 120.0))
		set_world_tempo(_checkpoint_tempo_bpm, false)
	var title := String(h.get("text", "")).split("\n")[0]
	if silent:
		hud.show_message("%s\nDEV → %s" % [_level_name, title], 2.2)
	else:
		hud.show_message("DEV %d／%d　%s" % [i + 1, _hints.size(), title], 1.4)
		GameState.play_sfx("cue", 5.0, -8.0)


func _compute_section_spawns(grid: Array[String], width: int, height: int) -> void:
	_section_spawns.clear()
	for hi in _hints.size():
		var h: Dictionary = _hints[hi]
		var x0 := clampi(int(float(h["from"]) / TILE), 0, maxi(0, width - 1))
		var x1 := clampi(int(float(h["to"]) / TILE), x0 + 1, width)
		var found := Vector2.ZERO
		var has := false
		for x in range(x0, x1):
			for y in range(height):
				if x >= grid[y].length():
					continue
				var c := grid[y][x]
				if c == "C" or c == "P":
					var feet := Vector2(x * TILE + TILE * 0.5, (y + 1) * TILE)
					found = feet - Vector2(0, Player.BODY_SIZE.y * 0.5 + 1.0)
					has = true
					break
			if has:
				break
		if not has:
			var x := mini(x0 + 3, x1 - 1)
			for y in range(height):
				if x < grid[y].length() and (grid[y][x] == "#" or grid[y][x] == "%"):
					var feet := Vector2(x * TILE + TILE * 0.5, y * TILE)
					found = feet - Vector2(0, Player.BODY_SIZE.y * 0.5 + 1.0)
					has = true
					break
		_section_spawns.append(found if has else spawn_point)


func _build_level() -> void:
	var data := LevelData.build(GameState.level_index)
	var grid: Array[String] = data["grid"]
	var width: int = data["width"]
	var height: int = data["height"]
	_hints = data["hints"]
	_plans = data["plans"]
	_patterns = data["patterns"]
	_level_name = data["name"]
	_stage = data["stage"]
	_tempo_pad_mode = data["tempo_stage"]
	_gravity_zones = data["gravity_zones"]
	level_size = Vector2(width * TILE, height * TILE)
	for spec: Dictionary in data["tempo_pads"]:
		var pad := TempoPad.new()
		pad.setup(spec["pos"], spec["bpm"], spec["width"])
		pad.world_bottom = level_size.y
		pad.triggered.connect(_on_tempo_pad_triggered)
		add_child(pad)
	for t: Dictionary in data["trampolines"]:
		var tr := Trampoline.new()
		tr.setup(t["top_left"], t["width"], TILE, int(t.get("need", 0)), float(t.get("phase", -1.0)))
		add_child(tr)
	for pos: Vector2 in data.get("showcases", []):
		var show := OrbShowcase.new()
		show.position = pos
		add_child(show)
	for s: Dictionary in data["swings"]:
		var sw := SwingRope.new()
		sw.setup(s["anchor"], s["length"], s["period"], s["dir"], s["offset"])
		add_child(sw)
	for r: Dictionary in data["rails"]:
		var rail := MineRail.new()
		rail.setup(r["points"], r["speed"], r["spikes"], r["gaps"], r["beams"], r["marks"], r["crates"])
		add_child(rail)
	for o: Dictionary in data["orbs"]:
		var orb := RhythmOrb.new()
		orb.setup(o["pos"], o["notes"], o["tone"], int(o.get("subdiv", 2)))
		orb.quiet = bool(o.get("quiet", false))
		orb.jump_kind = String(o.get("kind", ""))
		add_child(orb)
	for o: Dictionary in data["rings"]:
		var ring := DashRing.new()
		ring.setup(o["pos"], o["notes"], o["tone"])
		ring.quiet = bool(o.get("quiet", false))
		add_child(ring)
	# 相鄰同重力的區塊合成一片光幕，只有實際重力改變才畫邊線。
	var spans := _gravity_visual_spans()
	for i in spans.size():
		var span: Dictionary = spans[i]
		if float(span["gravity"]) >= 2400.0:
			continue
		var zone := GravityZone.new()
		zone.setup(float(span["from"]), float(span["to"]), float(span["gravity"]))
		zone.zone_height = level_size.y
		zone.show_left_boundary = i > 0
		zone.show_right_boundary = i + 1 < spans.size() and float(spans[i + 1]["gravity"]) >= 2400.0
		add_child(zone)

	_build_terrain(_solid_grid(grid, width, height), width, height)
	var wave_trigger := -1.0
	var wave_end := INF

	for y in height:
		var line := grid[y]
		var x := 0
		while x < width:
			var c := line[x]
			## 空白和實心地形佔了地圖的絕大多數，直接跳過（重玩時重建關卡才不會頓）
			if c == " " or c == "#" or c == "%":
				x += 1
				continue
			var top_left := Vector2(x * TILE, y * TILE)
			var feet := Vector2((x + 0.5) * TILE, (y + 1) * TILE)
			var run := 1
			var pat: Dictionary = _patterns.get(c, {})
			if c in "ABMmJ=" or pat.get("kind") == "platform":
				while x + run < width and line[x + run] == c:
					run += 1
			if not pat.is_empty():
				_add_pattern_tile(pat, grid, x, y, run)
			match c:
				"J":
					var pad := BeatPad.new()
					pad.setup(top_left, run * TILE, TILE)
					add_child(pad)
				"|":
					if y == 0 or grid[y - 1][x] != "|":
						var tall := 1
						while y + tall < height and grid[y + tall][x] == "|":
							tall += 1
						var gate := BeatGate.new()
						gate.setup(top_left, TILE, maxf(tall * TILE, level_size.y + 128.0 - top_left.y))
						add_child(gate)
				"P":
					spawn_point = feet - Vector2(0, Player.BODY_SIZE.y * 0.5 + 1.0)
				"A", "B":
					var bp := BeatPlatform.new()
					bp.setup(top_left, run * TILE, 0 if c == "A" else 1)
					add_child(bp)
				"M", "m":
					var mv := BeatMover.new()
					mv.setup(top_left, run * TILE, Vector2(LevelData.MOVER_TRAVEL_TILES * TILE, 0), 0 if c == "M" else 1)
					add_child(mv)
				"=":
					_add_one_way(top_left, run * TILE)
				"^":
					var sp := Spike.new()
					sp.setup(top_left, TILE)
					add_child(sp)
				"!", "?":
					var bs := BeatSpike.new()
					bs.setup(top_left, TILE, 0 if c == "!" else 1)
					add_child(bs)
				"E":
					var en := BeatHopper.new()
					en.setup(feet)
					add_child(en)
				"C":
					var cp := Checkpoint.new()
					cp.setup(feet)
					cp.activated.connect(_on_checkpoint_activated)
					_checkpoints.append(cp)
					add_child(cp)
				"G":
					var goal := Goal.new()
					goal.setup(feet)
					goal.reached.connect(_on_goal_reached)
					add_child(goal)
				"W":
					wave_trigger = top_left.x
				"Y":
					wave_end = top_left.x
			x += run

	for f in _flags:
		for h in _hints:
			if f.position.x >= float(h["from"]) and f.position.x < float(h["to"]):
				f.section_from = float(h["from"])
				f.section_to = float(h["to"])
				## 自動前進時旗子插在起跑點旁邊，倒數就在角色頭上
				if GameState.auto_run:
					f.position.x = f.section_from + CueFlag.START_X + CueFlag.BESIDE_PLAYER
		for g: Dictionary in data["ghosts"]:
			if f.position.x >= float(g["from"]) and f.position.x < float(g["to"]):
				f.ghost = g["points"]

	if wave_trigger >= 0.0:
		_wave = SoundWave.new()
		_wave.setup(wave_trigger, wave_trigger - 10.0 * TILE, wave_end, level_size.y)
		_wave.armed.connect(_on_wave_armed)
		add_child(_wave)
	_compute_section_spawns(grid, width, height)


## 與實際角色套用同一套優先序，避免視覺邊界與重力切換不一致。
func _gravity_at_x(x: float) -> float:
	for zone: Dictionary in _gravity_zones:
		if x >= float(zone["from"]) and x < float(zone["to"]):
			return float(zone["gravity"])
	for hint: Dictionary in _hints:
		if x >= float(hint["from"]) and x < float(hint["to"]):
			return float(hint.get("gravity", 2400.0))
	return 2400.0


func _gravity_visual_spans() -> Array[Dictionary]:
	var edges: Array[float] = [0.0, level_size.x]
	for span: Dictionary in _hints + _gravity_zones:
		for key: String in ["from", "to"]:
			var x := float(span[key])
			if not edges.has(x):
				edges.append(x)
	edges.sort()
	var spans: Array[Dictionary] = []
	for i in range(edges.size() - 1):
		var gravity := _gravity_at_x((edges[i] + edges[i + 1]) * 0.5)
		if not spans.is_empty() and is_equal_approx(float(spans[-1]["gravity"]), gravity):
			spans[-1]["to"] = edges[i + 1]
		else:
			spans.append({"from": edges[i], "to": edges[i + 1], "gravity": gravity})
	return spans


func _add_pattern_tile(pat: Dictionary, grid: Array[String], x: int, y: int, run: int) -> void:
	var top_left := Vector2(x * TILE, y * TILE)
	var notes: String = pat["notes"]
	match pat["kind"]:
		"spike", "ceiling":
			var sp := PatternSpike.new()
			sp.setup(top_left, TILE, notes, pat["kind"] == "ceiling")
			add_child(sp)
		"flag":
			var flag := CueFlag.new()
			flag.setup(top_left + Vector2(TILE * 0.5, TILE), pat.get("demo", ""))
			flag.cycle_beats = float(pat.get("cycle", CueFlag.CYCLE_BEATS))
			flag.demo_sub = int(pat.get("demo_sub", 2))
			flag.phase8 = float(pat.get("phase", -1.0))
			_flags.append(flag)
			add_child(flag)
		"platform":
			var pf := PatternPlatform.new()
			pf.setup(top_left, run * TILE, notes, float(pat.get("tone", 0)))
			add_child(pf)
		"piston", "lift":
			var c := grid[y][x]
			if (x > 0 and grid[y][x - 1] == c) or (y > 0 and grid[y - 1][x] == c):
				return
			var w := 1
			while x + w < grid[y].length() and grid[y][x + w] == c:
				w += 1
			var h := 1
			while y + h < grid.size() and grid[y + h][x] == c:
				h += 1
			if pat["kind"] == "piston":
				var piston := PatternPiston.new()
				piston.setup(top_left, Vector2(w, h) * TILE, notes)
				add_child(piston)
			else:
				var lift := PatternLift.new()
				lift.setup(top_left + Vector2(0, h * TILE), w * TILE, h * TILE, notes, float(pat.get("tone", 0)))
				add_child(lift)
		"laser":
			var c := grid[y][x]
			var above := y > 0 and grid[y - 1][x] == c
			var below := y + 1 < grid.size() and grid[y + 1][x] == c
			if above or below:
				if above:
					return
				var h := 1
				while y + h < grid.size() and grid[y + h][x] == c:
					h += 1
				var laser := PatternLaser.new()
				laser.setup(top_left + Vector2(TILE * 0.5, 0), h * TILE, true, notes)
				add_child(laser)
			else:
				if x > 0 and grid[y][x - 1] == c:
					return
				var w := 1
				while x + w < grid[y].length() and grid[y][x + w] == c:
					w += 1
				var laser := PatternLaser.new()
				laser.setup(top_left + Vector2(0, TILE * 0.5), w * TILE, false, notes)
				add_child(laser)
		"rest":
			var zone := RestZone.new()
			zone.setup(x * TILE, (x + int(pat["cols"])) * TILE, 16 * TILE, notes, bool(pat.get("strict", true)))
			_rest_zones.append(zone)
			add_child(zone)
		"blind":
			var zone := BlindZone.new()
			zone.setup(x * TILE, (x + int(pat["cols"])) * TILE, 16 * TILE, notes, bool(pat.get("strobe", false)))
			_blind_zones.append(zone)
			add_child(zone)
		"gate":
			var c := grid[y][x]
			if y > 0 and grid[y - 1][x] == c:
				return
			var tall := 1
			while y + tall < grid.size() and grid[y + tall][x] == c:
				tall += 1
			var gate := BeatGate.new()
			gate.setup(top_left, TILE, maxf(tall * TILE, level_size.y + 128.0 - top_left.y), notes)
			add_child(gate)


## 把相鄰的同種實心格子合併成大矩形，減少碰撞接縫並加速繪製。
## solid 的值：0 空、1 一般地形、2 光滑牆
func _build_terrain(solid: Array[PackedByteArray], width: int, height: int) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("solid_ground")
	add_child(body)
	var slick_body := StaticBody2D.new()
	slick_body.collision_layer = 1
	slick_body.collision_mask = 0
	slick_body.add_to_group("solid_ground")
	slick_body.add_to_group("no_cling")
	add_child(slick_body)
	var view := TerrainView.new()
	view.tile = TILE
	add_child(view)

	## 同一關重玩時，合併好的地形方塊和邊線直接沿用上次算好的結果
	var key := GameState.level_index
	var cached: Dictionary = _terrain_cache.get(key, {})
	if cached.is_empty():
		cached = {"solid": _merge_rects(solid, width, height, 1), "slick": _merge_rects(solid, width, height, 2)}
	for r: Rect2i in cached["solid"]:
		var world := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		_add_box(body, world)
		view.fill_rects.append(world)
	for r: Rect2i in cached["slick"]:
		var world := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		_add_box(slick_body, world)
		view.fill_rects.append(world)
		view.slick_rects.append(world)
	_add_box(body, Rect2(-TILE, -TILE * 10, TILE, level_size.y + TILE * 10))
	_add_box(body, Rect2(level_size.x, -TILE * 10, TILE, level_size.y + TILE * 10))
	## 直的螢幕（手機直拿）看得到關卡底下：碰到底的地面往下畫長一點，不要露出下面是空的（只畫，不加碰撞）
	var bottom := float(height) * TILE
	for i in view.fill_rects.size():
		var r: Rect2 = view.fill_rects[i]
		if r.end.y >= bottom - 1.0:
			r.size.y += TILE * 60.0
			view.fill_rects[i] = r

	if cached.has("top"):
		view.top_edges = cached["top"].duplicate()
		view.side_edges = cached["side"].duplicate()
		return
	for y in height:
		var x := 0
		while x < width:
			if solid[y][x] != 0 and (y == 0 or solid[y - 1][x] == 0):
				var x0 := x
				while x < width and solid[y][x] != 0 and (y == 0 or solid[y - 1][x] == 0):
					x += 1
				view.top_edges.append(Rect2(x0 * TILE, y * TILE, (x - x0) * TILE, TILE))
			else:
				x += 1
	for x in width:
		for side in [-1, 1]:
			var nx: int = x + side
			var y := 0
			while y < height:
				if solid[y][x] != 0 and nx >= 0 and nx < width and solid[y][nx] == 0:
					var y0 := y
					while y < height and solid[y][x] != 0 and solid[y][nx] == 0:
						y += 1
					var ex := x * TILE if side < 0 else (x + 1) * TILE - 3
					view.side_edges.append(Rect2(ex, y0 * TILE, 3, (y - y0) * TILE))
				else:
					y += 1

	cached["top"] = view.top_edges.duplicate()
	cached["side"] = view.side_edges.duplicate()
	_terrain_cache[key] = cached


## 地形方塊和邊線的計算結果（關卡編號 → 結果），跨場景保留：重玩同一關不用再掃一次整張地圖
static var _terrain_cache: Dictionary = {}
static var _solid_cache: Dictionary = {}


func _solid_grid(grid: Array[String], width: int, height: int) -> Array[PackedByteArray]:
	var key := GameState.level_index
	if _solid_cache.has(key):
		return _solid_cache[key]
	var solid: Array[PackedByteArray] = []
	for y in height:
		var row := PackedByteArray()
		row.resize(width)
		var line := grid[y]
		for x in width:
			var c := line[x]
			row[x] = 1 if c == "#" else (2 if c == "%" else 0)
		solid.append(row)
	_solid_cache[key] = solid
	return solid

func _merge_rects(solid: Array[PackedByteArray], width: int, height: int, value: int) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var open: Dictionary = {}
	for y in height:
		var next_open: Dictionary = {}
		var x := 0
		while x < width:
			if solid[y][x] != value:
				x += 1
				continue
			var x0 := x
			while x < width and solid[y][x] == value:
				x += 1
			var key := Vector2i(x0, x - 1)
			if open.has(key):
				var r: Rect2i = open[key]
				r.size.y += 1
				next_open[key] = r
			else:
				next_open[key] = Rect2i(x0, y, x - x0, 1)
		for key in open:
			if not next_open.has(key):
				rects.append(open[key])
		open = next_open
	for key in open:
		rects.append(open[key])
	return rects


func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)


func _add_one_way(top_left: Vector2, width: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("solid_ground")
	body.position = top_left
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, 16)
	shape.shape = box
	shape.position = box.size * 0.5
	shape.one_way_collision = true
	body.add_child(shape)
	add_child(body)
	var view := TerrainView.new()
	view.fill_rects.append(Rect2(top_left, box.size))
	view.top_edges.append(Rect2(top_left, Vector2(width, TILE)))
	add_child(view)


# ---------------------------------------------------------------- 效能
## 離鏡頭很遠的機關先隱藏：隱藏的節點不重畫（_draw 不跑），碰撞和節奏邏輯照常運作。
## 只收「畫的東西都在自己位置附近」的機關；起跳旗（示範角色會跑很遠）、雷射、軌道等大範圍的不收。
const CULL_MARGIN := 900.0
var _cullable: Array[Node2D] = []


func _collect_cullable() -> void:
	_cullable.clear()
	for c in get_children():
		if c is RhythmOrb or c is DashRing or c is SwingRope or c is Trampoline or c is Checkpoint \
				or c is BeatPlatform or c is PatternPlatform or c is BeatSpike or c is PatternSpike \
				or c is BeatGate or c is BeatHopper or c is BeatMover or c is PatternLift or c is PatternPiston \
				or c is SlowPickup:
			_cullable.append(c as Node2D)


func _cull_offscreen() -> void:
	if camera == null:
		return
	var half := get_viewport_rect().size.x * 0.5 / camera.zoom.x + CULL_MARGIN
	var cx := camera.get_screen_center_position().x
	for n in _cullable:
		if is_instance_valid(n):
			n.visible = absf(n.global_position.x - cx) < half


## 自動降畫質：關卡中連續幾秒平均幀率太低（低階手機、網頁），自動降一級畫質並提示一次
const LOW_FPS := 40.0
var _fps_avg: float = 60.0
var _fps_low_time: float = 0.0
var _fps_grace: float = 3.0


func _watch_frame_rate(delta: float) -> void:
	## 視窗不在前景時系統會降頻，不算
	if delta <= 0.0 or get_tree().paused or not DisplayServer.window_is_focused():
		return
	## 剛進關卡、讀檔的頭幾秒不算
	if _fps_grace > 0.0:
		_fps_grace -= delta
		return
	_fps_avg = lerpf(_fps_avg, 1.0 / delta, 0.05)
	if _fps_avg < LOW_FPS and GameState.quality > 0:
		_fps_low_time += delta
		if _fps_low_time > 4.0:
			_fps_low_time = 0.0
			_fps_avg = 60.0
			_fps_grace = 3.0
			GameState.set_quality(GameState.quality - 1)
			show_message("畫面有點卡，自動把畫質降成「%s」" % String(GameState.QUALITIES[GameState.quality]["name"]), 2.4)
	else:
		_fps_low_time = maxf(0.0, _fps_low_time - delta)
