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
	var sakura_park := GameState.level_index == 1 and String(GameState.current_theme().get("id", "")) == "heartbeat_city"
	var music_festival := GameState.level_index == 2 and String(GameState.current_theme().get("id", "")) == "heartbeat_city"
	var rainy_street := GameState.level_index == 3 and String(GameState.current_theme().get("id", "")) == "heartbeat_city"
	var edge_col := edge.lerp(Color.WHITE, pulse * 0.4)
	if soft_city:
		edge_col = Color("e9a9c6").lerp(Color("ffe1ed"), pulse * 0.22)
	elif sakura_park:
		edge_col = Color("e8a6bd").lerp(Color("ffe8dc"), pulse * 0.25)
	elif music_festival:
		edge_col = Color("ff65d5").lerp(Color("76e9ff"), pulse * 0.34)
	elif rainy_street:
		edge_col = Color("78bfff").lerp(Color("d3ddff"), pulse * 0.24)
	edge_col.a = (0.68 + 0.16 * pulse) if (soft_city or sakura_park or music_festival or rainy_street) else (0.55 + 0.45 * pulse)
	var detail := GameState.quality_int("detail", 2)
	var edge_lights := GameState.quality_flag("edge_lights", true)

	for r in fill_rects:
		if not r.intersects(view):
			continue
		_draw_solid_body(r, ground, detail, soft_city, sakura_park, music_festival, rainy_street)

	var stripe := Color(ground.lightened(0.25), 0.5)
	var stripe_step := 28.0 if detail == 0 else 18.0
	for r in slick_rects:
		if not r.intersects(view):
			continue
		draw_rect(r, Color("273454") if rainy_street else (Color("34255a") if music_festival else ground.lightened(0.06)))
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
			var underglow := edge
			if soft_city:
				underglow = Color("d78eae")
			elif sakura_park:
				underglow = Color("c77f9b")
			elif music_festival:
				underglow = Color("6bdff4")
			elif rainy_street:
				underglow = Color("78c9ff")
			draw_rect(Rect2(r.position + Vector2(0, 4.0), Vector2(r.size.x, 6)),
				Color(underglow, (0.08 + 0.08 * pulse) if soft_city else (0.10 + 0.18 * pulse)))
		if not edge_lights:
			continue
		var count := int(r.size.x / tile)
		for i in count:
			var tx := int(r.position.x / tile) + i
			if posmod(tx - beat_i, 4) == 0:
				var c := Color(edge.lerp(Color.WHITE, 0.5),
					(0.35 + 0.65 * pulse) * (0.5 + 0.5 * groove))
				if soft_city:
					c = Color(Color("d9a0ba"), 0.28)
				elif sakura_park:
					c = Color(Color("ffe1b8"), 0.26 + pulse * 0.24)
				elif music_festival:
					c = Color(Color("72e8ff").lerp(Color("ff79dc"), float(i % 2)),
						0.32 + pulse * 0.42)
				elif rainy_street:
					c = Color(Color("75c8ff").lerp(Color("e6a1ff"), 1.0 if i % 3 == 0 else 0.0),
						0.24 + pulse * 0.30)
				draw_rect(Rect2(r.position.x + i * tile + tile * 0.35, r.position.y + 14, tile * 0.3, 4), c)


func _draw_solid_body(r: Rect2, ground: Color, detail: int, soft_city: bool,
		sakura_park: bool, music_festival: bool, rainy_street: bool) -> void:
	if soft_city:
		_draw_soft_city_body(r, detail)
		return
	if sakura_park:
		_draw_sakura_park_body(r, detail)
		return
	if music_festival:
		_draw_music_festival_body(r, detail)
		return
	if rainy_street:
		_draw_rainy_street_body(r, detail)
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


func _draw_sakura_park_body(r: Rect2, detail: int) -> void:
	var top := Color("76536f")
	var bottom := Color("49364f")
	draw_rect(r, bottom)
	var bands := 6
	for i in bands:
		var y0 := r.position.y + r.size.y * float(i) / bands
		var y1 := r.position.y + r.size.y * float(i + 1) / bands
		draw_rect(Rect2(r.position.x, y0, r.size.x, y1 - y0 + 1.0),
			top.lerp(bottom, float(i) / maxf(1.0, bands - 1.0)))
	## 草緣不超出碰撞頂面，避免美術暗示出不存在的平台高度。
	draw_rect(Rect2(r.position, Vector2(r.size.x, minf(8.0, r.size.y))), Color("ba7895"))
	if r.size.y > 7.0:
		draw_rect(Rect2(r.position + Vector2(0, 7),
			Vector2(r.size.x, minf(3.0, r.size.y - 7.0))), Color("f0b6c8", 0.48))
	if detail <= 0:
		return
	var first_block := floori(r.position.x / 72.0)
	var last_block := ceili(r.end.x / 72.0)
	for i in range(first_block, last_block):
		var x := i * 72.0
		draw_line(Vector2(x, r.position.y + 25.0), Vector2(x, r.end.y),
			Color("d39ab2", 0.09), 2.0)
		if r.size.y > 52.0:
			draw_line(Vector2(maxf(x, r.position.x), r.position.y + 54.0),
				Vector2(minf(x + 72.0, r.end.x), r.position.y + 54.0),
				Color("2d2234", 0.16), 2.0)
	var first_flower := floori(r.position.x / 38.0)
	var last_flower := ceili(r.end.x / 38.0)
	for i in range(first_flower, last_flower):
		var x := i * 38.0 + 13.0 + fposmod(i * 17.0, 10.0)
		if x < r.position.x + 5.0 or x > r.end.x - 5.0:
			continue
		draw_circle(Vector2(x, r.position.y + 4.0), 2.4, Color("ffd6e3", 0.78))


func _draw_music_festival_body(r: Rect2, detail: int) -> void:
	var top := Color("39285f")
	var bottom := Color("171329")
	draw_rect(r, bottom)
	var bands := 6
	for i in bands:
		var y0 := r.position.y + r.size.y * float(i) / bands
		var y1 := r.position.y + r.size.y * float(i + 1) / bands
		draw_rect(Rect2(r.position.x, y0, r.size.x, y1 - y0 + 1.0),
			top.lerp(bottom, float(i) / maxf(1.0, bands - 1.0)))
	## 霓虹頂緣與金屬桁架都畫在碰撞矩形內。
	draw_rect(Rect2(r.position, Vector2(r.size.x, minf(7.0, r.size.y))), Color("ff61d2", 0.78))
	if r.size.y > 7.0:
		draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(r.size.x, minf(4.0, r.size.y - 7.0))),
			Color("6ee7ff", 0.28))
	if detail <= 0 or r.size.y < 32.0:
		return
	var first := floori(r.position.x / 64.0)
	var last := ceili(r.end.x / 64.0)
	for i in range(first, last):
		var x0 := maxf(r.position.x, i * 64.0)
		var x1 := minf(r.end.x, i * 64.0 + 64.0)
		var y0 := r.position.y + 16.0
		var y1 := minf(r.end.y - 8.0, y0 + 44.0)
		if x1 - x0 < 8.0 or y1 <= y0:
			continue
		draw_line(Vector2(x0 + 5.0, y0), Vector2(x1 - 5.0, y1), Color("a279ce", 0.22), 3.0, true)
		draw_line(Vector2(x1 - 5.0, y0), Vector2(x0 + 5.0, y1), Color("6d52a5", 0.22), 3.0, true)
		draw_line(Vector2(x1, y0), Vector2(x1, r.end.y), Color("bc8bd9", 0.10), 2.0)


func _draw_rainy_street_body(r: Rect2, detail: int) -> void:
	var top := Color("405177")
	var bottom := Color("19243b")
	draw_rect(r, bottom)
	for i in 6:
		var y0 := r.position.y + r.size.y * float(i) / 6.0
		var y1 := r.position.y + r.size.y * float(i + 1) / 6.0
		draw_rect(Rect2(r.position.x, y0, r.size.x, y1 - y0 + 1.0),
			top.lerp(bottom, float(i) / 5.0))
	## 濕金屬頂面與冷色反光均收在碰撞矩形內。
	draw_rect(Rect2(r.position, Vector2(r.size.x, minf(6.0, r.size.y))), Color("a9d7ff", 0.72))
	if r.size.y > 6.0:
		draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(r.size.x, minf(5.0, r.size.y - 6.0))),
			Color("527eb9", 0.34))
	if detail <= 0 or r.size.y < 34.0:
		return
	var first := floori(r.position.x / 72.0)
	var last := ceili(r.end.x / 72.0)
	for i in range(first, last):
		var x0 := maxf(r.position.x, i * 72.0)
		var x1 := minf(r.end.x, i * 72.0 + 72.0)
		draw_line(Vector2(x1, r.position.y + 15.0), Vector2(x1, r.end.y),
			Color("91a9d1", 0.14), 2.0)
		if r.size.y > 58.0 and x1 - x0 > 26.0:
			draw_rect(Rect2(x0 + 13.0, r.position.y + 29.0, minf(34.0, x1 - x0 - 18.0), 18.0),
				Color("101a2c", 0.50))
			draw_rect(Rect2(x0 + 13.0, r.position.y + 29.0, minf(34.0, x1 - x0 - 18.0), 18.0),
				Color("738dbb", 0.28), false, 1.0)
