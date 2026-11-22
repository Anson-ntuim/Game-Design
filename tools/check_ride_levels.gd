extends SceneTree
## 試作關（彈簧床／盪鞦韆／礦車）自動遊玩：每段從長椅出發，用「完美玩家」的按法走到下一段。
## Godot --headless --path . --fixed-fps 120 --script res://tools/check_ride_levels.gd
## 另外測：彈簧床不按維持段數、鞦韆亂放手到不了對岸、礦車不跳會撞尖刺、不攻擊會撞木箱、亂敲會鎖住。

const FIRST_RIDE_LEVEL := 6

var failures := 0
var checks := 0
var conductor: Node
var frame_clock := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("  ok  ", label)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var save_path := "user://save.cfg"
	var had_save := FileAccess.file_exists(save_path)
	var saved_bytes := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	conductor = root.get_node("Conductor")
	conductor.restore_builtin_music()
	var levels = load("res://scripts/level/level_data.gd")
	check(levels.LEVELS.size() == FIRST_RIDE_LEVEL + 4, "Four ride levels registered (incl. mixed)")
	var swing_level: Dictionary = levels.build(FIRST_RIDE_LEVEL + 1)
	var periods := []
	for chunk: Dictionary in levels.LEVELS[FIRST_RIDE_LEVEL + 1]["chunks"]:
		for sw: Array in chunk.get("swings", []):
			periods.append(float(sw[3]))
	check(periods.min() >= 4.0, "Swings take at least 4 beats per round trip %s" % [periods])
	for index in range(FIRST_RIDE_LEVEL, FIRST_RIDE_LEVEL + 4):
		await _play_level(index)
	await _negative_tests()
	if had_save:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		f.store_buffer(saved_bytes)
		f.close()
	elif FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	conductor.stop()
	for audio: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await process_frame
	OS.delay_msec(100)
	print("Ride levels: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _load_level(index: int) -> Node:
	root.get_node("GameState").level_index = index
	var level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.set_process(false)
	conductor.set_process(false)
	conductor._player.stop()
	await process_frame
	return level


func _tick() -> void:
	frame_clock += 1
	conductor._anchor_position = frame_clock / 120.0
	conductor._anchor_usec = Time.get_ticks_usec()
	conductor._running = true


func _set_action(action: String, pressed: bool) -> void:
	if Input.is_action_pressed(action) == pressed:
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for a in ["move_right", "move_left", "jump", "dash"]:
		Input.action_release(a)


## 依目前搭乘的機關決定這一幀要不要按跳（完美玩家）
func _bot_jump(player: Node, state: Dictionary) -> bool:
	var b: float = conductor.song_beat
	var ride: Node = player.ride
	if ride != null and ride.is_in_group("trampoline"):
		var land: float = ride._next_beat if ride._waiting else ride._bounce_start + ride._bounce_len
		if b >= land - 0.02 and float(state.get("pressed_for", -1.0)) != land:
			state["pressed_for"] = land
			return true
		return false
	if ride != null and ride.is_in_group("swing"):
		var peak: float = ride.next_peak(b - 0.02)
		if b >= peak - 0.01 and float(state.get("pressed_for", -1.0)) != peak:
			state["pressed_for"] = peak
			return true
		return false
	if ride != null and ride.is_in_group("mine_rail"):
		if not ride.is_moving():
			return false
		var local: float = b - ride._start_beat
		var presses: Array[float] = []
		for k: float in ride.spikes:
			presses.append(k - 0.5)
		for g: Array in ride.gaps:
			presses.append((float(g[0]) + float(g[1])) * 0.5 - 0.5)
		for pb: float in presses:
			var key := "%s:%f" % [ride.get_instance_id(), pb]
			if local >= pb and local < pb + 0.2 and not state.has(key):
				state[key] = true
				return true
		return false
	## 鞦韆關：走到高台邊緣，等座椅盪回來（往後到頂前 0.3~0.5 拍）再長按起跳去抓
	if _at_swing_edge(player, state):
		var sw: Node = state["first_swing"]
		var frac := fposmod(b - float(sw.offset), float(sw.period))
		var back := float(sw.period) * 0.5
		if frac >= back * 0.5 and frac <= back * 0.6:
			state["hold_until"] = frame_clock + 40
			return true
	return false


func _at_swing_edge(player: Node, state: Dictionary) -> bool:
	if state.get("jump_edges", []).is_empty() or not player.is_on_floor():
		return false
	for edge: float in state["jump_edges"]:
		if player.global_position.x >= edge - 14.0 and player.global_position.x < edge + 20.0:
			return true
	return false


## 礦車上的攻擊（衝刺鍵）：木箱前 0.2 拍
func _bot_dash(player: Node, state: Dictionary) -> bool:
	var ride: Node = player.ride
	if ride == null or not ride.is_in_group("mine_rail") or not ride.is_moving():
		return false
	var local: float = conductor.song_beat - ride._start_beat
	var presses: Array[float] = []
	for k: float in ride.crates:
		presses.append(k - 0.2)
	for pb: float in presses:
		var key := "dash%s:%f" % [ride.get_instance_id(), pb]
		if local >= pb and local < pb + 0.2 and not state.has(key):
			state[key] = true
			return true
	return false


func _play_level(index: int) -> void:
	var level = await _load_level(index)
	var player = level.player
	var hints: Array = level._hints
	print("Level %02d: %d sections" % [index + 1, hints.size()])
	for i in range(1, hints.size() - 1):
		var title := String(hints[i]["text"]).split("\n")[0]
		var start: Vector2 = level._section_spawns[i]
		player.respawn_at(start)
		player.checkpoint_position = start
		player.kill_y = float(hints[i]["kill_y"])
		level.camera.position = start
		var target_x := float(hints[i]["to"]) + 80.0
		var state := {"jump_edges": _swing_edges(level, i), "first_swing": _first_swing(level, i)}
		var reached := false
		var died := false
		for f in 60 * 40:
			_tick()
			var press := _bot_jump(player, state)
			var hold := frame_clock < int(state.get("hold_until", -1))
			_set_action("jump", press or hold)
			_set_action("dash", _bot_dash(player, state))
			var wait := _at_swing_edge(player, state) and frame_clock >= int(state.get("hold_until", -1))
			_set_action("move_right", (player.ride == null and not wait) or (player.ride != null and player.ride.is_in_group("trampoline")))
			var was_ride = player.ride
			await physics_frame
			if OS.get_cmdline_user_args().has("--trace") and was_ride != player.ride:
				print("    beat %.2f ride %s -> %s pos %s vel %s" % [conductor.song_beat, was_ride, player.ride, player.global_position, player.velocity])
			_maybe_shot(level, player, index, i, f, state)
			if player.control_locked:
				died = not level._completed
				reached = level._completed
				break
			if player.global_position.x >= target_x and player.is_on_floor():
				reached = true
				break
		_release_all()
		await physics_frame
		if died:
			print("    died at ", player.death_pos, " beat ", player.death_beat, " source ", player.death_source)
		check(reached, "Level %02d section %d「%s」passable (pos %s)" % [index + 1, i, title, player.global_position])
		if player.control_locked and not level._completed:
			player.respawn_at(start)
	level.queue_free()
	await process_frame


func _first_swing(level: Node, section: int) -> Node:
	var h: Dictionary = level._hints[section]
	for sw: Node in get_nodes_in_group("swing"):
		if sw.global_position.x >= float(h["from"]) and sw.global_position.x <= float(h["to"]):
			return sw
	return null


## 鞦韆段：每座鞦韆前高台的右緣 x（px）
func _swing_edges(level: Node, section: int) -> Array:
	var out := []
	var h: Dictionary = level._hints[section]
	for sw: Node in get_nodes_in_group("swing"):
		if sw.global_position.x < float(h["from"]) or sw.global_position.x > float(h["to"]):
			continue
		## 只有第一座需要從地面起跳；後面的在空中抓
		if out.is_empty():
			out.append(sw.global_position.x - 3.5 * 40.0)
	return out


func _negative_tests() -> void:
	## 彈簧床：一直不按 → 停在第 0 段，上不了第 13 列高台
	var level = await _load_level(FIRST_RIDE_LEVEL)
	var player = level.player
	var h: Dictionary = level._hints[1]
	player.respawn_at(level._section_spawns[1])
	var max_tier := 0
	var top := INF
	for f in 60 * 8:
		_tick()
		_set_action("move_right", true)
		await physics_frame
		for tr: Node in get_nodes_in_group("trampoline"):
			max_tier = maxi(max_tier, tr.tier())
		top = minf(top, player.global_position.y)
	_release_all()
	check(max_tier == 0, "Trampoline stays at tier 0 without presses")
	check(top < level._section_spawns[1].y - 20.0, "Trampoline keeps bouncing on its own")
	check(player.global_position.x < float(h["from"]) + 13 * 40.0, "Trampoline ledge unreachable without presses")
	level.queue_free()
	await process_frame

	## 鞦韆：抓住後在「往後到頂」的拍放手 → 掉進坑
	level = await _load_level(FIRST_RIDE_LEVEL + 1)
	player = level.player
	player.respawn_at(level._section_spawns[1])
	player.kill_y = float(level._hints[1]["kill_y"])
	var edge: float = _swing_edges(level, 1)[0]
	var hold_until := -1
	var released := false
	var died := false
	for f in 60 * 20:
		_tick()
		var press := false
		if player.ride == null and player.is_on_floor() and player.global_position.x >= edge - 14.0:
			hold_until = frame_clock + 40
			press = true
		if player.ride != null and player.ride.is_in_group("swing") and not released:
			var sw = player.ride
			var back_peak: float = sw.next_peak(conductor.song_beat) - sw.period * 0.5
			if absf(conductor.song_beat - back_peak) < 0.02 or conductor.song_beat - back_peak > 0.0 and conductor.song_beat - back_peak < 0.05:
				press = true
				released = true
		_set_action("jump", press or frame_clock < hold_until)
		_set_action("move_right", player.ride == null and not released)
		await physics_frame
		if player.control_locked:
			died = true
			break
		if released and player.is_on_floor():
			break
	_release_all()
	var far_platform := float(level._hints[1]["from"]) + 21 * 40.0
	print("    back-swing release: died=%s pos=%s" % [died, player.global_position])
	check(released and (died or player.global_position.x < far_platform), "Swing: releasing on the back swing falls short")
	level.queue_free()
	await process_frame

	## 礦車：上車後不按 → 撞到第一個尖刺
	level = await _load_level(FIRST_RIDE_LEVEL + 2)
	player = level.player
	player.respawn_at(level._section_spawns[1])
	died = false
	var rode := false
	for f in 60 * 20:
		_tick()
		_set_action("move_right", player.ride == null and not rode)
		await physics_frame
		rode = rode or (player.ride != null and player.ride.is_in_group("mine_rail"))
		if player.control_locked:
			died = true
			break
	_release_all()
	check(rode and died and player.death_source != null and player.death_source.is_in_group("hazard"), "Minecart: not jumping hits the first spike")
	level.queue_free()
	await process_frame

	## 礦車：衝刺段只跳不衝刺 → 撞上木箱
	level = await _load_level(FIRST_RIDE_LEVEL + 2)
	player = level.player
	var dash_section := 3
	player.respawn_at(level._section_spawns[dash_section])
	died = false
	rode = false
	for f in 60 * 20:
		_tick()
		_set_action("move_right", player.ride == null and not rode)
		await physics_frame
		rode = rode or (player.ride != null and player.ride.is_in_group("mine_rail"))
		if player.control_locked:
			died = true
			break
	_release_all()
	check(rode and died and player.death_source != null and player.death_source.is_in_group("mine_rail"),
		"Minecart: crates kill without an attack")
	level.queue_free()
	await process_frame

	## 礦車：一直亂敲 → 揮空後鎖一拍，還是會撞上木箱
	level = await _load_level(FIRST_RIDE_LEVEL + 2)
	player = level.player
	player.respawn_at(level._section_spawns[dash_section])
	died = false
	rode = false
	var n := 0
	for f in 60 * 20:
		_tick()
		n += 1
		_set_action("move_right", player.ride == null and not rode)
		_set_action("dash", rode and n % 20 < 2)
		await physics_frame
		rode = rode or (player.ride != null and player.ride.is_in_group("mine_rail"))
		if player.control_locked:
			died = true
			break
	_release_all()
	check(rode and died, "Minecart: spamming attack gets locked out and hits a crate")
	level.queue_free()
	await process_frame

	## 彈簧床：沒人站上去時床面每拍也會沉一下
	level = await _load_level(FIRST_RIDE_LEVEL)
	var sagged := 0
	for f in 120 * 3:
		_tick()
		await physics_frame
		await process_frame
		for tr: Node in get_nodes_in_group("trampoline"):
			if tr._sag > 0.5:
				sagged += 1
				break
	check(sagged > 0, "Trampoline pulses on the beat with nobody on it")
	level.queue_free()
	await process_frame


## 加上 `-- --shots <資料夾>`（不要 --headless）會在幾個時刻存截圖：段落開頭、礦車攻擊中、彈床升到第 2 段
func _maybe_shot(level: Node, player: Node, index: int, section: int, f: int, state: Dictionary) -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--shots")
	if at < 0 or at + 1 >= args.size():
		return
	var tag := ""
	var ride: Node = player.ride
	if f == 45:
		tag = "start"
	elif ride != null and ride.is_in_group("mine_rail") and ride._attacking(conductor.song_beat) \
			and conductor.song_beat - float(ride._attack_at) > 0.1:
		tag = "attack"
	elif ride != null and ride.is_in_group("trampoline") and ride.tier() >= 1:
		tag = "bounce"
	if tag == "" or state.has("shot_" + tag):
		return
	state["shot_" + tag] = true
	RenderingServer.force_draw(false)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/level%02d_s%d_%s.png" % [args[at + 1], index + 1, section, tag])
