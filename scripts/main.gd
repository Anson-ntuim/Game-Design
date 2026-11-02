extends Node2D
## 主場景：依 LevelData 建出整個關卡，負責鏡頭、存檔點、死亡重生與過關。

const TILE := LevelData.TILE
const SELECT_SCENE := "res://scenes/level_select.tscn"

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
var _zoom_punch: float = 0.0
var _camera_ground_y: float = 0.0
var _score_cue_slot: int = -99999
var _tempo_pad_mode: bool = false
var _checkpoint_tempo_bpm: float = 120.0


func _ready() -> void:
	Engine.time_scale = 1.0
	# 角色與機關先更新，鏡頭最後才追蹤物理解算後的位置。
	process_physics_priority = 10
	add_to_group("main")
	var bg := Background.new()
	add_child(bg)
	_build_level()
	_camera_ground_y = spawn_point.y
	bg.level_height = level_size.y
	bg.stage = _stage

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
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	hud.player = player
	hud.tempo_mode = _tempo_pad_mode
	add_child(hud)

	GameState.reset_stats()
	Conductor.measure.connect(_on_measure)
	Conductor.start()
	hud.show_message(_level_name, 2.0)


func _physics_process(delta: float) -> void:
	var view := get_viewport_rect().size / camera.zoom
	var target := player.global_position + Vector2(player.facing * 70.0, -30.0)
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
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	_zoom_punch = move_toward(_zoom_punch, 0.0, 3.0 * delta)
	var z := 1.0 + 0.025 * _zoom_punch * (0.4 + GameState.groove)
	camera.zoom = Vector2(z, z)


func _process(delta: float) -> void:
	if not _completed:
		_level_time += delta
	var hint := ""
	var subdivision_cue := false
	var section_duck := 0.0
	var px := player.global_position.x
	for h in _hints:
		if px >= float(h["from"]) and px < float(h["to"]):
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
	var cue_slot := floori(b * 2.0)
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

	if Input.is_action_just_pressed("back"):
		get_tree().change_scene_to_file(SELECT_SCENE)
	elif Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	elif _completed and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump")):
		if GameState.level_index + 1 < LevelData.LEVELS.size():
			GameState.level_index += 1
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file(SELECT_SCENE)


## 數字鍵 1、2… 直接切換關卡
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var idx := key.physical_keycode - KEY_1
	if idx >= 0 and idx < LevelData.LEVELS.size():
		GameState.level_index = idx
		get_tree().reload_current_scene()


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
	var actual_target := _tempo_target / Conductor.REFERENCE_BPM * Conductor.bpm
	if absf(now - actual_target) > 0.5 and not _completed:
		Conductor.set_rate(_tempo_target / Conductor.REFERENCE_BPM)
		hud.show_message(("加速！" if actual_target > now else "減速") + "　BPM %d" % roundi(actual_target), 1.6)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func show_message(text: String, duration: float = 2.0) -> void:
	if hud:
		hud.show_message(text, duration)


func _on_tempo_pad_triggered(bpm: float) -> void:
	set_world_tempo(bpm)


func set_world_tempo(bpm: float, announce: bool = true) -> void:
	if not _tempo_pad_mode or _completed:
		return
	var multiplier := clampf(bpm / Conductor.REFERENCE_BPM, 0.6, 1.4)
	var actual_bpm := Conductor.bpm * multiplier
	var changed := absf(Conductor.current_bpm - actual_bpm) > 0.5
	var accelerating := actual_bpm > Conductor.current_bpm
	Conductor.set_rate(multiplier)
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
	_shake = 12.0


func _on_player_died() -> void:
	GameState.deaths += 1
	if _wave:
		_wave.reset()
	hud.fade(0.9)
	var section := 0
	for i in _hints.size():
		if player.death_pos.x >= float(_hints[i]["from"]):
			section = i
	var tip := {}
	if GameState.level_index == 0:
		tip = DeathCoach.advise(player, _plans[section] if section < _plans.size() else [])
	if tip.is_empty():
		hud.show_message("回到長椅……", 1.2)
	else:
		hud.show_message(String(tip["title"]), 1.4)
		hud.show_tip(String(tip["detail"]))
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void:
		if _tempo_pad_mode:
			set_world_tempo(_checkpoint_tempo_bpm, false)
		player.respawn_at(player.checkpoint_position)
		camera.position = player.global_position
		_camera_ground_y = player.global_position.y)


func _on_checkpoint_activated(cp: Checkpoint) -> void:
	if _tempo_pad_mode:
		_checkpoint_tempo_bpm = Conductor.REFERENCE_BPM * Conductor._base_rate
	for other in _checkpoints:
		if other != cp:
			other.active = false
	hud.show_message("存檔點", 1.5)


func _on_goal_reached() -> void:
	_completed = true
	player.control_locked = true
	if _wave:
		_wave.stop()
	var new_record := GameState.record_clear(GameState.level_index, _level_time, GameState.deaths)
	var best: Dictionary = GameState.records[GameState.level_index]
	hud.show_results({
		"time": _level_time, "deaths": GameState.deaths, "judge": GameState.DIFFICULTIES[GameState.difficulty]["name"],
		"new_record": new_record, "best_time": float(best["time"]), "best_deaths": int(best["deaths"]),
		"has_next": GameState.level_index + 1 < LevelData.LEVELS.size(),
	})


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
	for o: Dictionary in data["orbs"]:
		var orb := RhythmOrb.new()
		orb.setup(o["pos"], o["notes"], o["tone"], int(o.get("subdiv", 2)))
		add_child(orb)
	for o: Dictionary in data["rings"]:
		var ring := DashRing.new()
		ring.setup(o["pos"], o["notes"], o["tone"])
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

	var solid: Array[PackedByteArray] = []
	for y in height:
		var row := PackedByteArray()
		row.resize(width)
		for x in width:
			match grid[y][x]:
				"#": row[x] = 1
				"%": row[x] = 2
				_: row[x] = 0
		solid.append(row)

	_build_terrain(solid, width, height)
	var wave_trigger := -1.0
	var wave_end := INF

	for y in height:
		var line := grid[y]
		var x := 0
		while x < width:
			var c := line[x]
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
		for g: Dictionary in data["ghosts"]:
			if f.position.x >= float(g["from"]) and f.position.x < float(g["to"]):
				f.ghost = g["points"]

	if wave_trigger >= 0.0:
		_wave = SoundWave.new()
		_wave.setup(wave_trigger, wave_trigger - 10.0 * TILE, wave_end, level_size.y)
		_wave.armed.connect(_on_wave_armed)
		add_child(_wave)


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

	for r in _merge_rects(solid, width, height, 1):
		var world := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		_add_box(body, world)
		view.fill_rects.append(world)
	for r in _merge_rects(solid, width, height, 2):
		var world := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		_add_box(slick_body, world)
		view.fill_rects.append(world)
		view.slick_rects.append(world)
	_add_box(body, Rect2(-TILE, -TILE * 10, TILE, level_size.y + TILE * 10))
	_add_box(body, Rect2(level_size.x, -TILE * 10, TILE, level_size.y + TILE * 10))

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
