extends SceneTree
## 實際 CharacterBody2D 回放第四／六關，包含升高後的接縫、長椅與鏡頭。
## Godot --headless --path . --fixed-fps 120 --script res://tools/check_climbing_levels.gd
## 延後載入主場景，讓 autoload 先完成註冊；失敗必定回傳非零。

var failures := 0
var checks := 0
var conductor: Node


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	# 終點會呼叫正式成績存檔；測試結束後還原原始檔案，避免留下自動回放成績。
	var save_path := "user://save.cfg"
	var had_save := FileAccess.file_exists(save_path)
	var saved_bytes := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	conductor = root.get_node("Conductor")
	var levels = load("res://scripts/level/level_data.gd")
	for index: int in [0, 1, 2, 4]:
		check(levels.build(index)["height"] == 20, "Existing flat level height changed")
	for index: int in [3, 5]:
		if await _replay_level(index) != true:
			failures += 1
			push_error("Stage %d replay aborted" % (index + 1))
	if had_save:
		var save_file := FileAccess.open(save_path, FileAccess.WRITE)
		if save_file:
			save_file.store_buffer(saved_bytes)
			save_file.close()
		else:
			check(false, "Could not restore saved records")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	conductor.stop()
	for audio: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await process_frame
	await process_frame
	# 等音訊混音執行緒釋放短音效的播放參照，避免快速 headless 結束時誤報洩漏。
	OS.delay_msec(100)
	print("Climbing levels: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _replay_level(index: int) -> bool:
	root.get_node("GameState").level_index = index
	var data_script = load("res://scripts/level/level_data.gd")
	var data: Dictionary = data_script.build(index)
	var chunks: Array = data_script.LEVELS[index]["chunks"]
	var level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.set_process(false)
	conductor.set_process(false)
	conductor._player.stop()
	for flag in level._flags:
		flag.set_physics_process(false)
	var player = level.player
	player.set_physics_process(false)
	check(data["height"] > 20, "Tall map bounds")
	check(level.camera.limit_bottom == data["height"] * 40, "Camera uses tall map bounds")
	var visual_count := 0
	for node: Node in level.get_children():
		if node.get_script() != load("res://scripts/level/gravity_zone.gd"):
			continue
		visual_count += 1
		if node.show_left_boundary:
			check(not is_equal_approx(level._gravity_at_x(node.from_x - 1), level._gravity_at_x(node.from_x + 1)),
				"Gravity line without a real transition at left edge")
		if node.show_right_boundary:
			check(not is_equal_approx(level._gravity_at_x(node.to_x - 1), level._gravity_at_x(node.to_x + 1)),
				"Gravity line without a real transition at right edge")
	check(visual_count == (2 if index == 3 else 3), "Continuous light gravity was not merged")
	if index == 5:
		var score_sections := 0
		for hint: Dictionary in data["hints"]:
			if float(hint.get("score_beats", 0)) > 0:
				score_sections += 1
		check(score_sections == 8, "New score must have eight complete sections")
		for flag in level._flags:
			check(flag.demo.length() >= 64, "Full score demo was truncated")
			check(flag.go_beat() - flag.start_beat > flag.ghost_end(), "GO starts before full demo finishes")
	for ghost: Dictionary in data["ghosts"]:
		var within_map := true
		for point: Vector2 in ghost["points"]:
			within_map = within_map and point.y >= 0.0 and point.y < level.level_size.y
		check(within_map, "Raised demonstration escaped map bounds")
	for i in chunks.size():
		var chunk: Dictionary = chunks[i]
		var plan: Array = chunk.get("plan", [])
		if plan.is_empty():
			continue
		var hint: Dictionary = data["hints"][i]
		var section_name: String = chunk["hint"].split("\n")[0]
		var row := int(chunk.get("row_offset", 0))
		player.respawn_at(Vector2(float(hint["from"]) + 140.0, (row + 16) * 40.0 - 22.01))
		player.apply_gravity_mode(float(chunk.get("gravity", 2400)))
		player.kill_y = hint["kill_y"]
		level.camera.position = player.position
		var target_x := float(hint["to"]) + 6.5 * 40.0
		if i == chunks.size() - 2:
			target_x = float(hint["to"]) + 7.5 * 40.0
		var next_row := int(chunks[i + 1].get("row_offset", 0))
		var next_floor := (next_row + 16) * 40.0 - 22.0
		var reached := false
		var pending: Array[Dictionary] = []
		var framed := true
		var lower_view := true
		Input.action_press("move_right")
		player.set_physics_process(true)
		for frame in range(-30, maxi(1100, roundi(float(chunk.get("score_beats", 0)) * 60.0) + 600)):
			await physics_frame
			for item: Dictionary in pending:
				var delay := 4 if item["kind"] == "ring" else 2
				if frame != int(item["frame"]) + delay:
					continue
				if item["kind"] in ["ground", "orb"]:
					check(player.last_jump.get("kind", "") == item["kind"] and absf(float(player.last_jump.get("beat", -999)) - float(item["frame"]) / 60.0) < 0.06,
						"Stage %d %s beat %.1f: expected %s, got %s" % [index + 1, section_name, float(item["frame"]) / 60.0, item["kind"], player.last_jump])
				else:
					check(player._dash_timer > 0.0 and absf(player._dash_beat - float(item["frame"]) / 60.0) < 0.06,
						"Dash did not trigger: %s at %.1f" % [section_name, float(item["frame"]) / 60.0])
					if item["kind"] == "ring":
						check(player._ring_hit != null, "Ring was not consumed: %s at %.1f" % [section_name, float(item["frame"]) / 60.0])

			conductor._anchor_position = frame / 120.0
			conductor._anchor_usec = Time.get_ticks_usec()
			conductor._running = true
			var jump_held := false
			var dash_pressed := false
			var expected_jump := ""
			var expected_dash := ""
			for j in plan.size():
				var step: Array = plan[j]
				var start := roundi(float(step[0]) * 60.0)
				var act: String = step[1]
				if act in ["L", "T", "O", "o"]:
					var duration := 4 if act in ["T", "o"] else 60
					for k in range(j + 1, plan.size()):
						if plan[k][1] in ["L", "T", "O", "o"]:
							duration = mini(duration, roundi(float(plan[k][0]) * 60.0) - start - 1)
							break
					jump_held = jump_held or (frame >= start and frame < start + duration)
					if frame == start:
						expected_jump = "orb" if act in ["O", "o"] else "ground"
				elif frame == start:
					dash_pressed = true
					expected_dash = "ring" if act == "R" else "dash"
			_set_action("jump", jump_held)
			_set_action("dash", dash_pressed)
			await process_frame
			if expected_jump != "":
				pending.append({"frame": frame, "kind": expected_jump})
			if expected_dash != "":
				pending.append({"frame": frame, "kind": expected_dash})
			var current_screen: Vector2 = player.get_global_transform_with_canvas().origin
			framed = framed and current_screen.y > 70.0 and current_screen.y < level.get_viewport_rect().size.y - 30.0
			if frame >= 0 and not player.is_on_floor():
				var camera_bottom: float = level.camera.get_screen_center_position().y + 360.0
				if camera_bottom < level.level_size.y - 5.0:
					lower_view = lower_view and current_screen.y < 500.0

			if player.control_locked:
				if not level._completed:
					print("REPLAY_DEATH beat=", frame / 60.0, " source=", player.death_source, " position=", player.death_pos)
				if level._completed:
					reached = true
				break
			if player.position.x >= target_x:
				reached = true
				break
		Input.action_release("move_right")
		Input.action_release("jump")
		Input.action_release("dash")
		player.set_physics_process(false)
		check(framed, "Camera lost player during traversal: " + section_name)
		check(lower_view, "Camera hid lower landing space: " + section_name)
		check(reached, "Stage %d %s did not reach next rest / goal; position %s" % [index + 1, section_name, player.position])
		if i == chunks.size() - 2:
			check(level._completed, "Final goal did not trigger completion")
		check(absf(player.position.y - next_floor) < 2.0, "Raised section seam has wrong height: " + section_name)
		var screen: Vector2 = player.get_global_transform_with_canvas().origin
		var view: Vector2 = level.get_viewport_rect().size
		check(screen.y > 140.0 and screen.y < view.y - 70.0, "Camera lost player at raised landing: " + section_name)
		if i + 2 < chunks.size():
			check(absf(player.checkpoint_position.y - next_floor) < 2.0, "Raised checkpoint not activated: " + section_name)
		print("Stage %d %s: reached=%s, player=%s, camera=%s" % [index + 1, section_name, reached, player.position, level.camera.position])
		if not reached:
			break
		if i == chunks.size() - 4:
			var checkpoint: Vector2 = player.checkpoint_position
			player.kill()
			for frame in 120:
				await process_frame
			check(not player.control_locked and player.position.distance_to(checkpoint) < 0.1,
				"Death did not respawn at raised checkpoint")
	level.queue_free()
	await process_frame
	await process_frame
	Engine.time_scale = 1.0
	return true


func _set_action(action: String, pressed: bool) -> void:
	if Input.is_action_pressed(action) == pressed:
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
