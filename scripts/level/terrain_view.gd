class_name TerrainView
extends Node2D
## 畫出地形：前景固定程式霓虹色塊＋節拍邊光（平台素材圖集暫不套用）。

var fill_rects: Array[Rect2] = []
## 光滑牆（不能滑牆/蹬牆），畫上斜紋提示玩家
var slick_rects: Array[Rect2] = []
var top_edges: Array[Rect2] = []
var side_edges: Array[Rect2] = []
var tile: float = 40.0


func _ready() -> void:
	if not GameState.visual_theme_changed.is_connected(_on_theme_changed):
		GameState.visual_theme_changed.connect(_on_theme_changed)


func _on_theme_changed(_index: int) -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if GameState.should_redraw_decor("terrain_redraw_every"):
		queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view_size := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - view_size * 0.5, view_size).grow(tile * 2.0)

	var ground := GameState.color("ground")
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(7.0)
	var groove := GameState.groove
	var edge_col := edge.lerp(Color.WHITE, pulse * 0.4)
	edge_col.a = 0.55 + 0.45 * pulse
	var detail := GameState.quality_int("detail", 2)
	var edge_lights := GameState.quality_flag("edge_lights", true)

	for r in fill_rects:
		if not r.intersects(view):
			continue
		_draw_solid_body(r, ground, detail)

	var stripe := Color(ground.lightened(0.25), 0.5)
	var stripe_step := 28.0 if detail == 0 else 18.0
	for r in slick_rects:
		if not r.intersects(view):
			continue
		draw_rect(r, ground.lightened(0.06))
		if detail == 0:
			continue
		var x := r.position.x - r.size.y
		while x < r.end.x:
			var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(0.0, r.position.x - x))
			var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + minf(r.size.y, r.end.x - x))
			draw_line(a, b, stripe, 3.0)
			x += stripe_step

	for r in side_edges:
		if r.intersects(view):
			draw_rect(r, Color(edge_col, edge_col.a * 0.45))

	var beat_i := floori(Conductor.song_beat)
	for r in top_edges:
		if not r.intersects(view):
			continue
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), edge_col)
		if detail > 0:
			draw_rect(Rect2(r.position + Vector2(0, 4.0), Vector2(r.size.x, 6)), Color(edge, 0.10 + 0.18 * pulse))
		if not edge_lights:
			continue
		var count := int(r.size.x / tile)
		for i in count:
			var tx := int(r.position.x / tile) + i
			if posmod(tx - beat_i, 4) == 0:
				var c := Color(edge.lerp(Color.WHITE, 0.5), (0.35 + 0.65 * pulse) * (0.5 + 0.5 * groove))
				draw_rect(Rect2(r.position.x + i * tile + tile * 0.35, r.position.y + 14, tile * 0.3, 4), c)


func _draw_solid_body(r: Rect2, ground: Color, detail: int) -> void:
	draw_rect(r, ground)
	if r.size.y <= 18.0:
		return
	draw_rect(Rect2(r.position + Vector2(0, 10), r.size - Vector2(0, 10)), ground.darkened(0.14))
	if detail > 0 and r.size.y > 48.0:
		draw_rect(Rect2(r.position + Vector2(0, 34), r.size - Vector2(0, 34)), ground.darkened(0.22))
