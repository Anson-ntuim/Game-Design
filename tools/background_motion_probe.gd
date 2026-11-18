extends "res://scripts/level/background.gd"
## Instrumentation for check_background_motion.gd; not part of the game scene.

var marker_world := Vector2.ZERO
var draw_count := 0
var draw_usec := 0


func _draw() -> void:
	var started := Time.get_ticks_usec()
	super._draw()
	marker_world = get_viewport().get_camera_2d().get_screen_center_position() + Vector2(-300, -200)
	draw_rect(Rect2(marker_world - Vector2(4, 4), Vector2(8, 8)), Color.MAGENTA)
	draw_count += 1
	draw_usec += Time.get_ticks_usec() - started
