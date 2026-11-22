extends SceneTree
## 正式版關卡自動遊玩（加 -- --archive 改測封存的舊第 1～5 關）：開著自動前進，每段跑到旗子前等 GO，再照關卡產生器的標準節奏（chunk["plan"]）按跳／衝刺。
## 跳躍是固定高度，所以只在拍子上「點一下」；確認每段都能跑到下一段、而且旗子起跑和模擬對得上。
## Godot --headless --path . --fixed-fps 120 --script res://tools/check_all_levels.gd [-- --level 2] [-- --trace]


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


func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var save_path := "user://save.cfg"
	var had_save := FileAccess.file_exists(save_path)
	var saved_bytes := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	conductor = root.get_node("Conductor")
	conductor.restore_builtin_music()
	var state := root.get_node("GameState")
	state.auto_run = true
	var only := -1
	var at := _args().find("--level")
	if at >= 0 and at + 1 < _args().size():
		only = int(_args()[at + 1]) - 1
	var levels = load("res://scripts/level/level_data.gd")
	var indices := range(levels.LEVELS.size())
	if _args().has("--archive"):
		indices = range(levels.LEVELS.size(), levels.LEVELS.size() + 5)
	for index: int in indices:
		if only >= 0 and index != only:
			continue
		if _args().has("--flow"):
			await _flow_level(index)
		else:
			await _play_level(index)
			if not _args().has("--archive"):
				await _cheat_level(index)
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
	print("All levels: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


var song_clock := 0.0


## 模擬真實時間一幀 1/120 秒：歌曲位置照播放速率（變速線會改 rate）前進
func _tick() -> void:
	frame_clock += 1
	song_clock += float(conductor.rate) / 120.0
	conductor._anchor_position = song_clock
	conductor._anchor_usec = Time.get_ticks_usec()
	conductor._running = true


func _set_action(action: String, pressed: bool) -> void:
	if Input.is_action_pressed(action) == pressed:
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _flag_for(level: Node, hint: Dictionary) -> Node:
	for f: Node in level._flags:
		if f.position.x >= float(hint["from"]) and f.position.x <= float(hint["to"]):
			return f
	return null


func _cheat_level(index: int) -> void:
	await _play_level(index, true)


func _play_level(index: int, cheat := false) -> void:
	root.get_node("GameState").level_index = index
	var data_script = load("res://scripts/level/level_data.gd")
	var chunks: Array = data_script.level_info(index)["chunks"]
	var level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.set_process(false)
	conductor.set_process(false)
	conductor._player.stop()
	await process_frame
	var player = level.player
	var hints: Array = level._hints
	print("Level %02d: %d chunks" % [index + 1, chunks.size()])
	for i in chunks.size():
		var chunk: Dictionary = chunks[i]
		var plan: Array = chunk.get("plan", [])
		if plan.is_empty():
			continue
		var hint: Dictionary = hints[i]
		var title := String(chunk["hint"]).split("\n")[0]
		var expect_pass := false
		if cheat and not chunk.get("trampolines", []).is_empty():
			## 彈簧床漏按最後一下、下一次落床再補按：不會死，晚一點飛出去也到得了
			var last: Array = plan[-1]
			var tier_beats := [1.0, 1.0, 2.0, 2.0]
			var need := int(chunk["trampolines"][0][3])
			plan = plan.slice(0, plan.size() - 1)
			plan.append([float(last[0]) + tier_beats[need - 1], "L", last[2]])
			expect_pass = true
		elif cheat:
			## 偷懶玩法：黃色音符全部不踩，改在第一顆音符前半拍空中衝刺一次
			var orbs := plan.filter(func(st: Array) -> bool: return String(st[1]) in ["O", "o"])
			if orbs.is_empty():
				continue
			var cut := float(orbs[0][0])
			plan = plan.filter(func(st: Array) -> bool: return float(st[0]) < cut)
			plan.append([cut - 0.5, "D", 0])
		var row := int(chunk.get("row_offset", 0))
		var start := Vector2(float(hint["from"]) + 40.0, (row + 16) * 40.0 - 22.01)
		player.respawn_at(start)
		player.checkpoint_position = start
		player.apply_gravity_mode(float(chunk.get("gravity", 2400)))
		player.kill_y = float(hint["kill_y"])
		level.camera.position = start
		var flag: Node = _flag_for(level, hint)
		for fl: Node in level._flags:
			fl._clear_auto_wait(player)
			fl._auto_can_stop = true
		var target_x := float(hint["to"]) + 2.0 * 40.0
		var base := INF
		var reached := false
		var died := false
		var presses: Array[Dictionary] = []
		var waited := false
		var sync0: float = flag.last_sync_beat if flag != null else -INF
		for f in 120 * 60:
			_tick()
			var b: float = conductor.song_beat
			if base == INF:
				if flag != null and flag._auto_waiting:
					waited = true
					base = float(flag._auto_go_at)
					print("    wait at flag: %.2f beats" % (base - 1.0 - b))
				elif flag != null and flag.last_sync_beat != sync0:
					## 調速後剛好在 GO 拍跑到，直接通過
					waited = true
					base = float(flag.last_sync_beat)
					print("    passed the flag without stopping")
				elif flag == null and player.global_position.x >= float(hint["from"]) + 140.0:
					base = b + 0.5
				if base != INF:
					for step: Array in plan:
						presses.append({"beat": base + float(step[0]), "act": String(step[1]), "done": false})
			var jump := false
			var dash := false
			for pr: Dictionary in presses:
				if not pr["done"] and b >= float(pr["beat"]) - 0.004:
					pr["done"] = true
					if String(pr["act"]) in ["D", "R"]:
						dash = true
					else:
						jump = true
			_set_action("jump", jump)
			_set_action("dash", dash)
			await physics_frame
			if _args().has("--trace") and (jump or dash):
				print("    beat %.2f %s pos %s vel %s floor %s" % [b, "J" if jump else "D", player.global_position, player.velocity, player.is_on_floor()])
			if player.control_locked:
				died = not level._completed
				reached = level._completed
				break
			if player.global_position.x >= target_x and player.is_on_floor():
				reached = true
				break
		_set_action("jump", false)
		_set_action("dash", false)
		await physics_frame
		if died:
			print("    died at %s beat %.2f (plan base %.2f) source %s" % [player.death_pos, player.death_beat, base, player.death_source])
		if cheat and expect_pass and not reached:
			print("    stuck: ride=%s vel=%s floor=%s auto_wait=%s locked=%s target=%.0f" % [player.ride, player.velocity, player.is_on_floor(), player.auto_flag_wait, player.control_locked, target_x])
		if cheat and expect_pass:
			check(reached, "Level %02d「%s」missed press can be retried on the next landing (pos %s)" % [index + 1, title, player.global_position])
		elif cheat:
			check(not reached, "Level %02d「%s」cannot be skipped with one jump + dash (pos %s)" % [index + 1, title, player.global_position])
		else:
			check(flag == null or waited, "Level %02d「%s」flag releases the player on the beat" % [index + 1, title])
			check(reached, "Level %02d「%s」passable with auto-run (pos %s)" % [index + 1, title, player.global_position])
		if player.control_locked and not level._completed:
			player.respawn_at(start)
		if level._completed:
			break
	level.queue_free()
	await process_frame
	await process_frame


## 一口氣從關卡開頭跑到終點（不在每段重生）：每面旗子放行時（停下倒數或直接通過）照那段的標準節奏按，
## 統計在旗子前停了幾拍。無縫接軌做對的話，除了第一面旗子以外都應該直接通過。
func _flow_level(index: int) -> void:
	root.get_node("GameState").level_index = index
	var data_script = load("res://scripts/level/level_data.gd")
	var chunks: Array = data_script.level_info(index)["chunks"]
	var level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.set_process(false)
	conductor.set_process(false)
	conductor._player.stop()
	await process_frame
	var player = level.player
	var hints: Array = level._hints
	var seen: Dictionary = {}
	var presses: Array[Dictionary] = []
	var waits: Array[String] = []
	var wait_frames := 0
	var died := false
	for f in 120 * 400:
		_tick()
		var b: float = conductor.song_beat
		for flag: Node in level._flags:
			var sync: float = flag.last_sync_beat
			if sync == -INF or seen.get(flag, -INF) == sync:
				continue
			seen[flag] = sync
			for i in hints.size():
				if flag.position.x >= float(hints[i]["from"]) and flag.position.x < float(hints[i]["to"]):
					for step: Array in chunks[i].get("plan", []):
						presses.append({"beat": sync + float(step[0]), "act": String(step[1]), "done": false})
					waits.append("%s %.2f 拍" % [String(chunks[i]["hint"]).split("\n")[0], wait_frames / 60.0])
			wait_frames = 0
		var jump := false
		var dash := false
		for pr: Dictionary in presses:
			if not pr["done"] and b >= float(pr["beat"]) - 0.004:
				pr["done"] = true
				if String(pr["act"]) in ["D", "R"]:
					dash = true
				else:
					jump = true
		## 間奏平地的小坑：跑到起跳點就跳
		if player.is_on_floor():
			for i in hints.size():
				for hx in chunks[i].get("hops", []):
					var wx := float(hints[i]["from"]) + float(hx)
					var key := "hop%d:%d" % [i, hx]
					if absf(player.global_position.x - wx) < 3.0 and not seen.has(key):
						seen[key] = true
						jump = true
		## --respawn：第三面旗子放行後，跑到下一塊長椅平地時倒下一次，看重生後能不能直接接上下一面旗子
		if _args().has("--respawn") and seen.size() >= 3 and not seen.has("killed") and player.is_on_floor():
			for i in hints.size():
				if String(chunks[i]["hint"]).begins_with("長椅") or String(chunks[i]["hint"]).begins_with("間奏"):
					var h: Dictionary = hints[i]
					if player.global_position.x > float(h["from"]) + 20.0 and player.global_position.x < float(h["from"]) + 60.0:
						seen["killed"] = true
						player.kill()
		## 被光柱擋住（自動跑卻停在原地）：下一個正拍光柱打開時衝刺
		if player.is_on_floor() and player.auto_running and not player.auto_flag_wait and absf(player.velocity.x) < 1.0 \
				and b - floorf(b) < 0.01 and player._dash_cooldown_timer <= 0.0:
			dash = true
		## --mistake：每段長椅平地中間誤按一次衝刺，看調速能不能拉回來、不用停下
		if _args().has("--mistake") and player.is_on_floor() and player.ride == null:
			for i in hints.size():
				var h: Dictionary = hints[i]
				var mid := (float(h["from"]) + float(h["to"])) * 0.5
				if String(h["text"]).begins_with("長椅") and absf(player.global_position.x - mid) < 6.0 and not seen.has("dash%d" % i):
					seen["dash%d" % i] = true
					dash = true
		_set_action("jump", jump)
		_set_action("dash", dash)
		await physics_frame
		if player.auto_flag_wait:
			wait_frames += 1
		if player.control_locked and not (seen.has("killed") and not seen.has("respawned")):
			died = not level._completed
			break
		if seen.has("killed") and not seen.has("respawned") and not player.control_locked:
			seen["respawned"] = true
			print("    respawned at %s beat %.2f" % [player.global_position, b])
	_set_action("jump", false)
	_set_action("dash", false)
	print("  flag stops: ", ", ".join(waits))
	if died:
		print("    died at %s beat %.2f source %s" % [player.death_pos, player.death_beat, player.death_source])
	check(level._completed, "Level %02d played straight through to the goal" % [index + 1])
	## 停不到 0.35 拍（關卡產生器刻意讓人早到一點點）算是無縫；誤按衝刺時允許多停，但要能跑完
	var stops := 0
	for k in range(1, waits.size()):
		if float(waits[k].split(" ")[-2]) > 0.35:
			stops += 1
	if not _args().has("--mistake"):
		check(stops == 0, "Level %02d: only the first flag makes you wait (%d extra stops)" % [index + 1, stops])
	level.queue_free()
	await process_frame
	await process_frame
