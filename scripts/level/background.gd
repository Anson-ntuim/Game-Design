class_name Background
extends Node2D
## 多層視差背景：依 GameState.visual_theme 切換經典霓虹／心動之城／暮色遺跡。
## 經典＝天空漸層、月亮、等化器、遺跡剪影；素材主題＝貼圖分層或全景＋輕量光點。
## 顏色取自目前風格的色盤，每個音樂段落仍會換氛圍。

var level_height: float = 800.0
## 舞台模式：從畫面底部打上來、跟著節拍擺動的聚光燈
var stage: bool = false
## 標題畫面：更暗、幾乎不動，接近 Hollow Knight 的靜謐感
var quiet: bool = false
## 關卡可選的背景演出；第一關先使用低干擾的動態城市試作。
var profile: String = ""
var _ambient_time: float = 0.0
var _far_cloud_scroll: float = 0.0
var _near_cloud_scroll: float = 0.0


func _ready() -> void:
	z_index = -100
	if not GameState.visual_theme_changed.is_connected(_on_theme_changed):
		GameState.visual_theme_changed.connect(_on_theme_changed)


func _on_theme_changed(_index: int) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_ambient_time += delta
	## 累積位移而非用「總時間 × 畫質強度」，切換畫質時雲不會瞬間跳位。
	var motion := GameState.anim_amount()
	_far_cloud_scroll += delta * 6.5 * motion
	_near_cloud_scroll += delta * 12.5 * motion
	if GameState.should_redraw_decor("bg_redraw_every"):
		queue_redraw()


func _hash(i: int) -> float:
	return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	## 視差版面用「未 zoom」的可視範圍，避免節拍 zoom／縮放讓拼接段左右跳格
	var center := cam.get_screen_center_position()
	var size := get_viewport_rect().size + Vector2(80, 80)
	var tl := center - size * 0.5
	var b := Conductor.song_beat
	var anim := GameState.anim_amount()
	var pulse := Conductor.pulse(6.0) * anim
	var groove := GameState.groove * anim
	var edge := GameState.color("edge")
	var detail := GameState.quality_int("detail", 2)
	if quiet:
		detail = mini(detail, 1)

	var top := GameState.color("bg_top")
	var bottom := GameState.color("bg_bottom")
	if quiet:
		top = top.darkened(0.45).lerp(Color(0.02, 0.02, 0.04), 0.55)
		bottom = bottom.darkened(0.35).lerp(Color(0.04, 0.05, 0.08), 0.4)
		edge = Color(0.78, 0.82, 0.88)
	draw_polygon(
		PackedVector2Array([tl, tl + Vector2(size.x, 0), tl + size, tl + Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	var theme: Dictionary = GameState.current_theme()
	var kind := String(theme.get("kind", "procedural"))
	match kind:
		"layered":
			_draw_art_layers(theme, tl, size, center, quiet)
			if detail > 0 or quiet:
				_draw_motes(tl, size, center, b, pulse, groove)
		"panorama":
			_draw_panorama(theme, tl, size, center, quiet)
			if detail > 0 or quiet:
				_draw_motes(tl, size, center, b, pulse, groove)
		_:
			_draw_classic(tl, size, center, b, pulse, groove, edge, detail, top)

	## 暗角：標題畫面加深
	var vig := 0.55 if quiet else 0.18
	draw_rect(Rect2(tl, Vector2(size.x, size.y * 0.14)), Color(0, 0, 0, vig * 0.65))
	draw_rect(Rect2(tl + Vector2(0, size.y * 0.84), Vector2(size.x, size.y * 0.16)), Color(0, 0, 0, vig))


func _draw_classic(tl: Vector2, size: Vector2, center: Vector2, b: float, pulse: float,
		groove: float, edge: Color, detail: int, top: Color) -> void:
	var moon := tl + Vector2(size.x * 0.74, size.y * 0.26)
	var moon_r := 62.0 + pulse * (6.0 + 10.0 * groove)
	var glow_n := 0 if quiet else GameState.quality_int("bg_moon_glow", 4)
	for i in glow_n:
		draw_circle(moon, moon_r + 18.0 * (i + 1) + pulse * 8.0, Color(edge, 0.05 + 0.03 * pulse))
	if not quiet or detail > 0:
		draw_circle(moon, moon_r * (0.7 if quiet else 1.0), top.lerp(Color.WHITE, 0.55 if quiet else 0.82))

	if stage and not quiet and GameState.quality_flag("bg_stage", true):
		_draw_spotlights(tl, size, b, pulse, edge, detail)
	if not quiet and detail > 0:
		_draw_equalizer(tl, size, center, b, pulse, groove)
	if not quiet:
		_draw_ruins(tl, size, center, pulse, detail)
	if detail > 0 or quiet:
		_draw_motes(tl, size, center, b, pulse, groove)


func _draw_art_layers(theme: Dictionary, tl: Vector2, size: Vector2, center: Vector2, dim: bool) -> void:
	if profile == "calm_city" and not dim:
		_draw_calm_city(tl, size, center)
		return
	var layers: Array = theme.get("layers", [])
	for layer in layers:
		var path := String(layer.get("path", ""))
		var tex := GameState.theme_texture(path)
		if tex == null:
			continue
		var factor := float(layer.get("parallax", 0.4))
		var anchor := String(layer.get("anchor", "fill"))
		var wrap := String(layer.get("wrap", "mirror"))
		var alpha := float(layer.get("alpha", 1.0)) * (0.72 if dim else 1.0)
		var tint := Color(1, 1, 1, alpha)
		var height_frac := float(layer.get("height_frac", 0.0))
		match wrap:
			"cover":
				_blit_cover(tex, tl, size, center, factor, tint)
			"mirror":
				_blit_parallax(tex, tl, size, center, factor, anchor, tint, true, height_frac)
			_:
				_blit_parallax(tex, tl, size, center, factor, anchor, tint, false, height_frac)


## 第一關試作：拆開天空元素，讓環境緩慢呼吸，但不干擾平台判讀。
func _draw_calm_city(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/heartbeat_city/bg/animated/"
	var sky := GameState.theme_texture(base + "sky_base.png")
	var stars := GameState.theme_texture(base + "stars.png")
	var moon := GameState.theme_texture(base + "moon.png")
	var clouds_far := GameState.theme_texture(base + "clouds_far.png")
	var clouds_near := GameState.theme_texture(base + "clouds_near.png")
	var city_far := GameState.theme_texture("res://assets/themes/heartbeat_city/bg/city_far.png")
	var city_near := GameState.theme_texture("res://assets/themes/heartbeat_city/bg/city_near.png")
	var far_glow := GameState.theme_texture(base + "city_far_glow.png")
	var near_glow := GameState.theme_texture(base + "city_near_glow.png")
	var anim := GameState.anim_amount()
	var beat_pulse := Conductor.pulse(6.0) * anim
	var twinkle := 0.72 + 0.18 * sin(_ambient_time * 0.85) * anim

	if sky != null:
		_blit_cover(sky, tl, size, center, 0.0, Color.WHITE)
	if stars != null:
		_blit_cover(stars, tl, size, center, 0.0, Color(1, 1, 1, twinkle))
	if moon != null:
		_blit_cover(moon, tl, size, center, 0.0,
			Color(1.0, 0.96, 0.90, 0.86 + beat_pulse * 0.12))
	if clouds_far != null:
		_blit_cover_looping(clouds_far, tl, size, _far_cloud_scroll, Color(0.88, 0.86, 1.0, 0.58))
	if clouds_near != null:
		_blit_cover_looping(clouds_near, tl, size, _near_cloud_scroll, Color(1, 1, 1, 0.94))

	if city_far != null:
		_blit_parallax(city_far, tl, size, center, 0.22, "bottom", Color(1, 1, 1, 0.95), true, 0.42)
	if far_glow != null:
		_blit_parallax(far_glow, tl, size, center, 0.22, "bottom",
			Color(1, 1, 1, 0.16 + beat_pulse * 0.30), true, 0.42)
	if city_near != null:
		_blit_parallax(city_near, tl, size, center, 0.48, "bottom", Color(1, 1, 1, 0.88), true, 0.50)
	if near_glow != null:
		_blit_parallax(near_glow, tl, size, center, 0.48, "bottom",
			Color(1, 1, 1, 0.12 + beat_pulse * 0.24), true, 0.50)


func _draw_panorama(theme: Dictionary, tl: Vector2, size: Vector2, center: Vector2, dim: bool) -> void:
	var tex := GameState.theme_texture(String(theme.get("bg_far", "")))
	if tex == null:
		return
	var tint := Color(1, 1, 1, 0.78 if dim else 1.0)
	## 全景也用鏡像捲，避免月亮／建築在接縫被切成兩半又往回抽
	_blit_parallax(tex, tl, size, center, 0.22, "fill", tint, true)


## 天空等：整張跟著鏡頭鋪滿，月亮／主體永遠完整，不橫向拼貼
func _blit_cover(tex: Texture2D, tl: Vector2, size: Vector2, center: Vector2,
		factor: float, modulate: Color) -> void:
	var tex_size := tex.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	var scale := maxf(size.x / tex_size.x, size.y / tex_size.y) * 1.08
	var draw_size := tex_size * scale
	## 輕微視差只在「多出來的邊界」內平移，永不露出圖外、也不循環跳回
	var overflow_x := maxf(0.0, draw_size.x - size.x)
	var overflow_y := maxf(0.0, draw_size.y - size.y)
	var drift := clampf(center.x * factor * 0.04, -overflow_x * 0.5, overflow_x * 0.5)
	var origin := Vector2(
		tl.x - overflow_x * 0.5 - drift,
		tl.y - overflow_y * 0.5)
	draw_texture_rect(tex, Rect2(origin, draw_size), false, modulate)


## 雲層向右無限捲動；相鄰副本首尾接續，循環重置發生在畫面外。
func _blit_cover_looping(tex: Texture2D, tl: Vector2, size: Vector2,
		scroll: float, modulate: Color) -> void:
	var tex_size := tex.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	var scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
	var draw_size := tex_size * scale
	var offset := fposmod(scroll, draw_size.x)
	var x := tl.x - draw_size.x + offset
	var y := tl.y + (size.y - draw_size.y) * 0.5
	while x < tl.x + size.x:
		draw_texture_rect(tex, Rect2(Vector2(x, y), draw_size), false, modulate)
		x += draw_size.x


func _blit_parallax(tex: Texture2D, tl: Vector2, size: Vector2, center: Vector2,
		factor: float, anchor: String, modulate: Color, mirror: bool = false,
		height_frac: float = 0.0) -> void:
	var tex_size := tex.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	var scale := size.y / tex_size.y
	if anchor == "bottom":
		## 城市剪影等：預設約半高貼底；可用 height_frac 覆寫，避免「整座橋」蓋住關卡
		var frac := height_frac if height_frac > 0.05 else 0.52
		scale = size.y * clampf(frac, 0.15, 1.0) / tex_size.y
	var draw_h := tex_size.y * scale
	## step 必須 = draw_w：用重疊會讓鏡像段在縮放時左右錯位，看起來像抽動
	var draw_w := tex_size.x * scale
	var step := draw_w
	var shift := center.x * (1.0 - factor)
	var y: float
	if anchor == "bottom":
		y = tl.y + size.y - draw_h
	else:
		y = tl.y + (size.y - draw_h) * 0.5
	var first := floori((tl.x - shift) / step) - 1
	var last := ceili((tl.x + size.x - shift) / step) + 1
	for i in range(first, last):
		var x := float(i) * step + shift
		if mirror and posmod(i, 2) != 0:
			## 奇數段水平鏡像，讓左右邊緣對上，捲動時不像被抽回
			draw_set_transform(Vector2(x + draw_w, y), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(draw_w, draw_h)), false, modulate)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(x, y, draw_w, draw_h), false, modulate)


func _draw_equalizer(tl: Vector2, size: Vector2, center: Vector2, b: float, pulse: float, groove: float) -> void:
	var factor := 0.15
	var spacing := GameState.quality_float("bg_eq_spacing", 46.0)
	var shift := center.x * (1.0 - factor)
	var first := floori((tl.x - shift) / spacing) - 1
	var last := ceili((tl.x + size.x - shift) / spacing) + 1
	var far := GameState.color("far")
	var eighth := floori(b * 2.0)
	var base_y := tl.y + size.y * 0.8
	for i in range(first, last):
		var x := i * spacing + shift
		var v := 0.25 + 0.75 * absf(sin(i * 1.7 + eighth * 2.3))
		var h := (70.0 + 170.0 * v) * (0.45 + 0.55 * pulse) * (0.8 + 0.5 * groove)
		draw_rect(Rect2(x, base_y - h, spacing * 0.62, h), Color(far, 0.55))
		draw_rect(Rect2(x, base_y - h, spacing * 0.62, 4), Color(far.lerp(Color.WHITE, 0.4), 0.7))


func _draw_spotlights(tl: Vector2, size: Vector2, b: float, pulse: float, edge: Color, detail: int) -> void:
	var count := 3 if detail < 2 else 5
	var downbeat := posmod(floori(b), Conductor.beats_per_measure) == 0
	for i in count:
		var base := tl + Vector2(size.x * (i + 0.5) / count, size.y + 30.0)
		var sway := sin(b * PI * 0.5 + i * 1.3) * 0.45 * (1.0 if i % 2 == 0 else -1.0)
		var dir := Vector2(sin(sway), -cos(sway))
		var length := size.y * 1.5
		var spread := 0.11
		var tip_l := base + dir.rotated(-spread) * length
		var tip_r := base + dir.rotated(spread) * length
		var hue_shift := Color.from_hsv(fposmod(edge.h + i * 0.13, 1.0), 0.55, 1.0)
		var a := 0.05 + 0.07 * pulse + (0.06 * pulse if downbeat else 0.0)
		draw_colored_polygon(PackedVector2Array([base, tip_l, tip_r]),
			Color(hue_shift, a))
		if detail >= 2:
			draw_colored_polygon(PackedVector2Array([base, base + dir.rotated(-spread * 0.4) * length, base + dir.rotated(spread * 0.4) * length]),
				Color(hue_shift, a * 0.8))


func _draw_ruins(tl: Vector2, size: Vector2, center: Vector2, pulse: float, detail: int) -> void:
	var factor := 0.45
	var spacing := 220.0 if detail == 0 else 170.0
	var shift := center.x * (1.0 - factor)
	var y_shift := (center.y - level_height * 0.5) * 0.3
	var first := floori((tl.x - shift) / spacing) - 1
	var last := ceili((tl.x + size.x - shift) / spacing) + 1
	var mid := GameState.color("mid")
	var edge := GameState.color("edge")
	var base_y := tl.y + size.y + 20.0 - y_shift
	for i in range(first, last):
		var x := i * spacing + shift + _hash(i) * 60.0
		var w := 40.0 + _hash(i + 50) * 60.0
		var h := 160.0 + _hash(i + 99) * 260.0
		draw_rect(Rect2(x, base_y - h, w, h + 400.0), mid)
		if detail > 0:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 6, base_y - h), Vector2(x + w * 0.5, base_y - h - 26.0), Vector2(x + w + 6, base_y - h)]), mid)
		var lit := posmod(i + floori(Conductor.song_beat), 3) == 0
		var a := (0.25 + 0.75 * pulse) if lit else 0.12
		draw_rect(Rect2(x + w * 0.5 - 3.0, base_y - h + 30.0, 6, 10), Color(edge, a))


func _draw_motes(tl: Vector2, size: Vector2, center: Vector2, b: float, pulse: float, groove: float) -> void:
	var factor := 0.8
	var shift := center.x * (1.0 - factor)
	var base_count := 10 if quiet else GameState.quality_int("bg_motes", 36)
	var count := base_count + (int(groove * 20.0) if not quiet and GameState.quality_int("detail", 2) >= 2 else 0)
	## 素材主題光點稍少，避免蓋過手繪場景
	if not GameState.theme_is_procedural():
		count = mini(count, 18 if quiet else 22)
	var edge := Color(0.85, 0.88, 0.92) if quiet else GameState.color("edge")
	var drift := 3.0 if quiet else 12.0
	for i in count:
		var span := size.x + 200.0
		var lx := fposmod(_hash(i) * 3000.0 - (tl.x - shift), span)
		var x := tl.x + lx - 100.0
		var y := tl.y + fposmod(_hash(i + 300) * size.y - b * (drift + _hash(i + 7) * (6.0 if quiet else 20.0)), size.y)
		var r := (1.0 + _hash(i + 11) * 1.4) if quiet else (1.5 + _hash(i + 11) * 2.0 + pulse * 1.5)
		var a := (0.12 + 0.1 * pulse) if quiet else (0.25 + 0.45 * pulse)
		draw_circle(Vector2(x, y), r, Color(edge.lerp(Color.WHITE, 0.5), a))
