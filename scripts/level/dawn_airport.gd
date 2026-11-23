extends RefCounted
## 第六關觀景台的裝飾。遠景氣球畫在航廈後方，近景跑道指示燈使用歌曲拍數。

const BALLOON_Y := [-22.0, -20.0, -15.5, -9.0, -2.0, 5.0, 11.0, 17.0, 18.0]
const BALLOON_WIDTH := [1.8, 8.0, 14.0, 16.0, 15.8, 13.0, 8.8, 3.5, 2.0]
const GORE_COLORS := [
	Color("#ad83a3"), Color("#efacb2"), Color("#ffe2ac"),
	Color("#f4be96"), Color("#d58fa7"), Color("#a485a8"),
]
# 日輪中心在天空原畫中的座標。雲海只需鋪到不透明的觀景台地面。
const SUN_CENTER := Vector2(534, 791)
const DECK_HEIGHT_RATIO := 0.888

static var _sunbeam: GradientTexture2D


static func draw_sky(canvas: Node2D, sky: Texture2D, tl: Vector2, size: Vector2, phase: float, motion: float) -> void:
	var art_size := sky.get_size()
	var sky_height := size.y * DECK_HEIGHT_RATIO
	var sun_height := size.y * 0.55
	# 用同一比例裁切天空與雲海，讓日出露在航廈屋頂上方。
	var art_scale := maxf(size.x / art_size.x, (sky_height - sun_height) / (art_size.y - SUN_CENTER.y))
	var origin := tl + Vector2((size.x - art_size.x * art_scale) * SUN_CENTER.x / art_size.x,
		sun_height - SUN_CENTER.y * art_scale)
	canvas.draw_texture_rect(sky, Rect2(origin, art_size * art_scale), false)
	_draw_sunlight(canvas, origin + SUN_CENTER * art_scale, art_scale, phase, motion)


static func _draw_sunlight(canvas: Node2D, sun: Vector2, art_scale: float, phase: float, motion: float) -> void:
	if _sunbeam == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.38, 0.76, 1.0])
		gradient.colors = PackedColorArray([Color("#fff2d5"), Color("#ffecc49c"),
			Color("#ffe7b822"), Color("#ffe7b800")])
		gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		_sunbeam = GradientTexture2D.new()
		_sunbeam.gradient = gradient
		_sunbeam.width = 256
		_sunbeam.height = 256
		_sunbeam.fill = GradientTexture2D.FILL_RADIAL
		_sunbeam.fill_from = Vector2(0.5, 0.5)
		_sunbeam.fill_to = Vector2(1.0, 0.5)
	var pulse := (1.0 - smoothstep(0.0, 0.78, phase)) + smoothstep(0.86, 1.0, phase)
	var tint := Color(1, 1, 1, 0.38 * motion * pulse)
	# 沿原畫朝上的晨光鋪柔光，三筆都從日輪邊緣外開始。
	_draw_sunbeam(canvas, sun, art_scale, -42.0, Vector2(74, 126), tint)
	_draw_sunbeam(canvas, sun, art_scale, -9.0, Vector2(60, 157), tint)
	_draw_sunbeam(canvas, sun, art_scale, 31.0, Vector2(76, 174), tint)
	canvas.draw_set_transform(Vector2.ZERO)


static func _draw_sunbeam(canvas: Node2D, sun: Vector2, art_scale: float,
		angle_degrees: float, beam_size: Vector2, tint: Color) -> void:
	canvas.draw_set_transform(sun, deg_to_rad(angle_degrees), Vector2.ONE * art_scale)
	canvas.draw_texture_rect(_sunbeam,
		Rect2(Vector2(-0.5 * beam_size.x, -44.0 - beam_size.y), beam_size), false, tint)


static func draw_balloons(canvas: Node2D, tl: Vector2, size: Vector2, time: float) -> void:
	_draw_balloon(canvas, tl, size, time + 72.0, 103.0, 88.0, Vector2(-0.06, 0.49), Vector2(1.06, 0.29), 0.49)
	_draw_balloon(canvas, tl, size, time + 24.0, 91.0, 68.0, Vector2(-0.06, 0.53), Vector2(1.06, 0.34), 0.64)
	_draw_balloon(canvas, tl, size, time + 9.0, 74.0, 56.0, Vector2(0.24, 0.65), Vector2(1.08, 0.23), 1.0)


static func _draw_balloon(canvas: Node2D, tl: Vector2, size: Vector2, time: float,
		period: float, duration: float, start: Vector2, end: Vector2, depth: float) -> void:
	# 空檔留給晨曦；循環換位時，氣球已離開右側畫面。
	var flight := fposmod(time, period)
	if flight > duration:
		return
	var t := flight / duration
	var path := Vector2(lerpf(start.x, end.x, t), lerpf(start.y, end.y, smoothstep(0.0, 0.87, t)))
	path.y += sin(flight * 0.23) * 0.004
	var scale_factor := size.y / 800.0 * depth
	canvas.draw_set_transform(tl + size * path, sin(flight * 0.16) * 0.024, Vector2.ONE * scale_factor)
	var rig := Color("#a7878e")
	canvas.draw_line(Vector2(-3.5, 16.0), Vector2(-2.4, 23.0), rig, 1.0, true)
	canvas.draw_line(Vector2(3.5, 16.0), Vector2(2.4, 23.0), rig, 1.0, true)
	canvas.draw_rect(Rect2(-2.7, 22.0, 5.4, 3.5), Color("#997b85"))
	# 依球面經線切出布幅，色帶在球頂和氣囊口自然收束。
	for gore in GORE_COLORS.size():
		var left := -cos(PI * gore / GORE_COLORS.size())
		var right := -cos(PI * (gore + 1) / GORE_COLORS.size())
		var strip := PackedVector2Array()
		for row in BALLOON_Y.size():
			strip.append(Vector2(left * BALLOON_WIDTH[row], BALLOON_Y[row]))
		for row in range(BALLOON_Y.size() - 1, -1, -1):
			strip.append(Vector2(right * BALLOON_WIDTH[row], BALLOON_Y[row]))
		var cloth: Color = GORE_COLORS[gore]
		canvas.draw_colored_polygon(strip, cloth.lerp(Color("#b9c4e4"), (1.0 - depth) * 0.80))
	canvas.draw_set_transform(Vector2.ZERO)


static func draw_promenade(canvas: Node2D, tl: Vector2, size: Vector2, center: Vector2,
		beat: float, motion: float) -> void:
	var scale_factor := size.y / 800.0
	var spacing := 88.0 * scale_factor
	var camera_shift := center.x * 0.56
	var deck_y := tl.y + size.y * DECK_HEIGHT_RATIO
	var rail_y := deck_y - 33.0 * scale_factor
	var rail := Color("#797a96")
	var trim := Color("#bab4be")
	canvas.draw_rect(Rect2(tl.x, deck_y, size.x, tl.y + size.y - deck_y), Color("#9998ae"))
	canvas.draw_line(Vector2(tl.x, deck_y), Vector2(tl.x + size.x, deck_y), trim, 2.0)
	canvas.draw_line(Vector2(tl.x, rail_y), Vector2(tl.x + size.x, rail_y), rail, 2.0, true)
	canvas.draw_line(Vector2(tl.x, rail_y + 11), Vector2(tl.x + size.x, rail_y + 11),
		Color(rail, 0.67), 1.5, true)
	var first := floori((tl.x - camera_shift) / spacing) - 1
	var last := ceili((tl.x + size.x - camera_shift) / spacing) + 1
	var step := posmod(floori(beat), 4)
	var pulse := exp(-4.0 * fposmod(beat, 1.0))
	for i in range(first, last):
		var x := camera_shift + i * spacing
		canvas.draw_line(Vector2(x, rail_y - 2), Vector2(x, deck_y), rail, 3.0 * scale_factor, true)
		if posmod(i, 6) == 2:
			_draw_planter(canvas, Vector2(x + spacing * 0.39, deck_y), scale_factor)
		# 每組四盞由左至右點亮，第四拍整排齊亮後重新開始。
		var slot := posmod(i, 4)
		var lamp := Vector2(x, rail_y - 3.0 * scale_factor)
		var intensity := (0.72 + 0.28 * pulse if slot == step else 0.62) if slot <= step else 0.0
		intensity *= clampf(motion, 0.0, 1.0)
		canvas.draw_circle(lamp, 7.0 * scale_factor, Color(1.0, 0.78, 0.51, 0.20 * intensity))
		canvas.draw_circle(lamp, 2.9 * scale_factor, Color("#aa9192").lerp(Color("#fff2c6"), intensity))


static func _draw_planter(canvas: Node2D, base: Vector2, scale_factor: float) -> void:
	canvas.draw_set_transform(base, 0.0, Vector2.ONE * scale_factor)
	canvas.draw_rect(Rect2(-17, -8, 34, 8), Color("#71788d"))
	canvas.draw_rect(Rect2(-19, -10, 38, 3), Color("#aaa4ad"))
	for j in 9:
		var tip := Vector2(-15.5 + j * 3.85, -11.0 - 2.0 * sin(2.3 * j))
		canvas.draw_circle(tip, 3.7, Color("#7e917f"))
		if j % 2 == 1:
			canvas.draw_circle(tip + Vector2(0.0, -2.0), 2.0, Color("#dca7b3"))
	canvas.draw_set_transform(Vector2.ZERO)
