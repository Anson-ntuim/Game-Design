extends SceneTree
## Rendered camera-motion regression check. Run with a real renderer, not --headless:
## Godot --path . --fixed-fps 60 --script res://tools/check_background_motion.gd
## Add -- --baseline to measure without enforcing the regression threshold.

var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Background motion check requires a real renderer; omit --headless")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if await _measure() != true:
		failures += 1
		push_error("Background motion measurement aborted")
	print("Background motion: %d failures" % failures)
	quit(1 if failures else 0)


func _measure() -> bool:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	var conductor := root.get_node("Conductor")
	conductor.stop()
	conductor.set_process(false)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	# Load after autoload registration; compiling a base class at startup can
	# otherwise resolve GameState too early in a SceneTree --script runner.
	var bg = load("res://tools/background_motion_probe.gd").new()
	root.add_child(bg)
	var cases := {
		"walk": Vector2(240, 0),
		"dash": Vector2(850, 0),
		"vertical": Vector2(0, -360),
		"diagonal": Vector2(240, -360),
	}
	var baseline := OS.get_cmdline_user_args().has("--baseline")
	for quality in range(3):
		state.set_quality(quality, false)
		for label: String in cases:
			camera.position = Vector2(2000, 1000)
			camera.force_update_scroll()
			# Allow initial texture uploads/shader compilation and any scheduled redraw.
			for warmup in range(15):
				await process_frame
				await RenderingServer.frame_post_draw
			bg.draw_count = 0
			bg.draw_usec = 0
			var max_error := 0.0
			var max_jump := 0.0
			var previous := Vector2.ZERO
			var max_calls := 0
			for frame in range(60):
				await process_frame
				camera.position += Vector2(cases[label]) / 60.0
				camera.force_update_scroll()
				await RenderingServer.frame_post_draw
				# This point belongs to the cached draw list, so the canvas transform
				# also exposes the movement on frames when _draw was skipped.
				var screen_marker: Vector2 = bg.get_global_transform_with_canvas() * bg.marker_world
				var expected: Vector2 = root.get_visible_rect().size * 0.5 + Vector2(-300, -200)
				max_error = maxf(max_error, screen_marker.distance_to(expected))
				if frame > 0:
					max_jump = maxf(max_jump, screen_marker.distance_to(previous))
				previous = screen_marker
				max_calls = maxi(max_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var avg_draw_ms := float(bg.draw_usec) / maxf(1.0, bg.draw_count) / 1000.0
			print("MOTION quality=%d case=%s max_error_px=%.3f max_jump_px=%.3f redraws=%d avg_draw_cpu_ms=%.3f max_draw_calls=%d" % [
				quality, label, max_error, max_jump, bg.draw_count, avg_draw_ms, max_calls])
			if bg.draw_count == 0:
				failures += 1
				push_error("Probe did not render")
			if not baseline and max_error > 0.1:
				failures += 1
				push_error("Background moved relative to the camera: quality=%d case=%s" % [quality, label])
	bg.queue_free()
	camera.queue_free()
	await process_frame
	return true
