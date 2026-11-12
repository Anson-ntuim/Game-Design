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
	var soft_city := GameState.level_index == 0 and String(GameState.current_theme().get("id", "")) == "heartbeat_city"
	var edge_col := Color("e9a9c6").lerp(Color("ffe1ed"), pulse * 0.22) if soft_city else edge.lerp(Color.WHITE, pulse * 0.4)
	edge_col.a = (0.68 + 0.16 * pulse) if soft_city else (0.55 + 0.45 * pulse)
	var detail := GameState.quality_int("detail", 2)
	var edge_lights := GameState.quality_flag("edge_lights", true)

	for r in fill_rects:
		if not r.intersects(view):
			continue
		_draw_solid_body(r, ground, detail, soft_city)

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
			var underglow := Color("d78eae") if soft_city else edge
			draw_rect(Rect2(r.position + Vector2(0, 4.0), Vector2(r.size.x, 6)),
				Color(underglow, (0.08 + 0.08 * pulse) if soft_city else (0.10 + 0.18 * pulse)))
		if not edge_lights:
			continue
		var count := int(r.size.x / tile)
		for i in count:
			var tx := int(r.position.x / tile) + i
			if posmod(tx - beat_i, 4) == 0:
				var c := Color(Color("d9a0ba"), 0.28) if soft_city else Color(edge.lerp(Color.WHITE, 0.5), (0.35 + 0.65 * pulse) * (0.5 + 0.5 * groove))
				draw_rect(Rect2(r.position.x + i * tile + tile * 0.35, r.position.y + 14, tile * 0.3, 4), c)


func _draw_solid_body(r: Rect2, ground: Color, detail: int, soft_city: bool) -> void:
	if soft_city:
		_draw_soft_city_body(r, detail)
		return
	draw_rect(r, ground)
	if r.size.y <= 18.0:
		return
	draw_rect(Rect2(r.position + Vector2(0, 10), r.size - Vector2(0, 10)), ground.darkened(0.14))
	if detail > 0 and r.size.y > 48.0:
		draw_rect(Rect2(r.position + Vector2(0, 34), r.size - Vector2(0, 34)), ground.darkened(0.22))


func _draw_soft_city_body(r: Rect2, detail: int) -> void:
	var top := Color("553653")
	var bottom := Color("302238")
	draw_rect(r, bottom)
	var bands := 7
	for i in bands:
		var y0 := r.position.y + r.size.y * float(i) / bands
		var y1 := r.position.y + r.size.y * float(i + 1) / bands
		var col := top.lerp(bottom, float(i) / maxf(1.0, bands - 1.0))
		draw_rect(Rect2(r.position.x, y0, r.size.x, y1 - y0 + 1.0), col)
	if detail <= 0 or r.size.y < 36.0:
		return
	var first := floori(r.position.x / 96.0)
	var last := ceili(r.end.x / 96.0)
	for i in range(first, last):
		var x := i * 96.0 + 18.0 + fposmod(i * 37.0, 31.0)
		var y := r.position.y + 22.0 + fposmod(absf(i * 53.0), maxf(20.0, r.size.y - 32.0))
		var w := 24.0 + fposmod(absf(i * 29.0), 38.0)
		draw_line(Vector2(x, y), Vector2(minf(x + w, r.end.x - 8.0), y),
			Color("c58bab", 0.075), 2.0, true)
