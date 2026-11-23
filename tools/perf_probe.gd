extends SceneTree
## 效能量測（要開視窗，不能 headless）：godot --path . -s tools/perf_probe.gd -- 3 5 6
## q=0／1／2 指定畫質（不存檔）。每關跑 12 秒（自動前進，跳不過坑會一直重生，鏡頭會在段落間移動），印出平均／最低幀率和每幀 CPU 時間。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var levels: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("q="):
			root.get_node("GameState").set_quality(int(a.substr(2)), false)
		elif a.is_valid_int():
			levels.append(int(a) - 1)
	if levels.is_empty():
		levels = [0]
	for idx in levels:
		var gs := root.get_node("GameState")
		gs.persist_enabled = false
		gs.level_index = idx
		gs.reset_stats()
		change_scene_to_file("res://scenes/main.tscn")
		await create_timer(2.0).timeout
		var frames := 0
		var worst := 0.0
		var proc := 0.0
		var phys := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < 12000000:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, float(now - last) / 1000.0)
			last = now
			frames += 1
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var secs := float(Time.get_ticks_usec() - t0) / 1000000.0
		print("Level %02d: avg %.1f fps, worst frame %.1f ms, process %.2f ms, physics %.2f ms, nodes %d, draw calls %d" % [
			idx + 1, frames / secs, worst, proc / frames * 1000.0, phys / frames * 1000.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	quit()
