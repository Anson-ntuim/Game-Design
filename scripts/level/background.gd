class_name Background
extends Node2D
const BrokenRing := preload("res://scripts/level/memory_ring.gd")
const FIRST_STREET_PARALLAX := 0.46
const FIRST_STREET_HEIGHT := 0.76
## 高架橋原圖中，愛心招牌正上方的三扇玻璃。保留窗框與裡面的剪影。
const LANDING_WINDOWS := [Rect2(562, 426, 21, 30), Rect2(587, 426, 18, 30),
	Rect2(610, 426, 21, 30)]
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
var _window_beats: float = -1.0
var _bird_rng := RandomNumberGenerator.new()
var _next_flock := 4.0
class MemoryFlock:
	var start: float
	var count: int
	var seed_value: int

var _flocks: Array[MemoryFlock] = []
var _far_cloud_scroll: float = 0.0
var _near_cloud_scroll: float = 0.0
var _rain_cloud_scroll: float = 0.0
var _rain_cloud_near_scroll: float = 0.0
var _ferris_angle: float = 0.0


func _ready() -> void:
	## 大張背景縮小畫：用 mipmap 取樣，捲動時不會閃爍（背景圖 .import 已開 mipmaps）
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	z_index = -100
	if not GameState.visual_theme_changed.is_connected(_on_theme_changed):
		GameState.visual_theme_changed.connect(_on_theme_changed)


func _on_theme_changed(_index: int) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_ambient_time += delta
	if _window_beats >= 0.0:
		# 遊戲的 delta 已隨音樂速度縮放；世界時間一拍固定為參考 BPM 的拍長。
		_window_beats += delta * Conductor.REFERENCE_BPM / 60.0
		if _window_beats >= 2.5:
			clear_landing_windows()
	if profile == "broken_memory" and _ambient_time >= _next_flock:
		while not _flocks.is_empty() and _ambient_time - _flocks.front().start >= 10.0:
			_flocks.pop_front()
		var flock := MemoryFlock.new()
		flock.start = _ambient_time
		flock.count = _bird_rng.randi_range(1, 3)
		flock.seed_value = _bird_rng.randi_range(0, 100000)
		_flocks.append(flock)
		_next_flock = _ambient_time + _bird_rng.randf_range(5.0, 10.0)
	## 累積位移而非用「總時間 × 畫質強度」，切換畫質時雲不會瞬間跳位。
	var motion := GameState.anim_amount()
	_far_cloud_scroll += delta * 6.5 * motion
	_near_cloud_scroll += delta * 12.5 * motion
	## 第四關遠、近雨雲分速向右，製造較安靜的景深。
	_rain_cloud_scroll += delta * 1.8 * motion
	_rain_cloud_near_scroll += delta * 3.8 * motion
	## 約三分鐘一圈；保持比花瓣更安靜，避免搶走平台判讀。
	_ferris_angle += delta * 0.035 * motion
	## 繪圖座標含鏡頭位置與視差，必須和每個顯示幀同步。
	## 跳幀會讓快取的天空先隨鏡頭反向位移、下次重畫又歸位；
	## 網頁預設中畫質時，走路與跳躍都會因此出現背景抖動。
	## 低畫質以減少光點／光暈等細節省效能，不能降低背景捲動更新率。
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
			## 雨夜本身已有前後景雨絲與漣漪，通用圓形光點會使畫面過於雜亂。
			if (detail > 0 or quiet) and profile not in ["rainy_street", "broken_memory", "first_beat_sunset"]:
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
	if profile == "broken_memory" and not dim:
		_draw_broken_memory(tl, size, center)
		return
	if profile == "first_beat_sunset" and not dim:
		_draw_first_beat_sunset(tl, size, center)
		return
	if profile == "calm_city" and not dim:
		_draw_calm_city(tl, size, center)
		return
	if profile == "sakura_park" and not dim:
		_draw_sakura_park(tl, size, center)
		return
	if profile == "music_festival" and not dim:
		_draw_music_festival(tl, size, center)
		return
	if profile == "rainy_street" and not dim:
		_draw_rainy_street(tl, size, center)
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


func _draw_broken_memory(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/broken_memory/bg/"
	var sky := GameState.theme_texture(base + "sky.png")
	var city := GameState.theme_texture(base + "city.png")
	var bridge := GameState.theme_texture(base + "bridge.png")
	if sky != null:
		_blit_cover(sky, tl, size, center, 0.03, Color.WHITE)
	var ring_center := tl + size * Vector2(0.79, 0.28)
	BrokenRing.draw(self, ring_center, size.y * 0.076, Conductor.song_beat, GameState.anim_amount())
	for flock in _flocks:
		_draw_memory_flock(tl, size, flock)
	if city != null:
		_blit_parallax(city, tl, size, center, 0.14, "bottom", Color(0.86, 0.79, 0.95, 0.78), true, 0.68)
	if bridge != null:
		_blit_parallax(bridge, tl, size, center, 0.35, "bottom", Color(0.81, 0.74, 0.91, 0.80), true, 0.35)


## 同一群共用航線，跟隨者稍晚進場，錯開轉向和振翅時間。
func _draw_memory_flock(tl: Vector2, size: Vector2, flock: MemoryFlock) -> void:
	var elapsed := _ambient_time - flock.start
	if elapsed >= 10.0:
		return
	var duration := lerpf(5.8, 8.5, _hash(flock.seed_value))
	var altitude := lerpf(0.40, 0.55, _hash(flock.seed_value + 1))
	var curve_phase := TAU * _hash(flock.seed_value + 2)
	for i in flock.count:
		var seed_i := flock.seed_value + i * 11 + 3
		var flight := elapsed - i * 0.41
		var progress := flight / (duration + i * 0.17)
		if progress < 0.0 or progress >= 1.0:
			continue
		var arc := progress * TAU + curve_phase
		var height_offset := [0.0, -0.055, 0.017]
		var y := altitude + float(height_offset[i]) + 0.031 * sin(arc) + 0.009 * sin(2.0 * arc)
		# 高飛的鳥在圓環下緣走一條淺弧，仍與教學框保持距離。
		var ring_clearance := 1.0 - smoothstep(0.035, 0.15, absf(progress - 0.78))
		y = maxf(y, 0.318 + 0.064 * ring_clearance)
		var tilt := 0.10 * cos(arc) + 0.045 * cos(2.0 * arc)
		var position_on_screen := tl + size * Vector2(lerpf(-0.02, 1.02, progress), y)
		var wing_phase := fposmod(flight + _hash(seed_i), 1.65 + 0.55 * _hash(seed_i + 1))
		_draw_memory_bird(position_on_screen, size.y / 800.0 * (1.06 - i * 0.07), tilt, wing_phase)


func _draw_memory_bird(at: Vector2, bird_scale: float, tilt: float, wing_phase: float) -> void:
	var stroke := 0.0
	if wing_phase < 0.72:
		stroke = sin(TAU * 2.0 * wing_phase / 0.72) * sin(PI * wing_phase / 0.72)
	var wing_y := -4.0 - 7.0 * stroke * GameState.anim_amount()
	var silhouette := Color("51445e", 0.86)
	draw_set_transform(at, tilt, Vector2.ONE * bird_scale)
	draw_colored_polygon(PackedVector2Array([Vector2(-12,wing_y), Vector2(-7,wing_y * 0.73),
		Vector2(-1,0), Vector2(-1,2), Vector2(-7,wing_y * 0.73 + 2)]), Color("66566e", 0.84))
	draw_colored_polygon(PackedVector2Array([Vector2(-9,2), Vector2(-4,0), Vector2(0,-1),
		Vector2(4,-2), Vector2(7,0), Vector2(3,1), Vector2(-2,2)]), silhouette)
	draw_colored_polygon(PackedVector2Array([Vector2(-9,wing_y - 2), Vector2(-4,wing_y * 0.8),
		Vector2(2,-1), Vector2(2,1), Vector2(-4,wing_y * 0.8 + 3)]), silhouette)
	draw_set_transform(Vector2.ZERO)


## 正式第一關的夕照街區。教學旗、光柱和落腳線都位於街景前方。
func _draw_first_beat_sunset(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/first_beat/bg/"
	var sky := GameState.theme_texture(base + "sunset.png")
	var blocks := GameState.theme_texture(base + "viaduct.png")
	var signs := GameState.theme_texture(base + "sign_lights.png")
	var far_cloud := GameState.theme_texture("res://assets/themes/heartbeat_city/bg/animated/clouds_far.png")
	var near_cloud := GameState.theme_texture("res://assets/themes/heartbeat_city/bg/animated/clouds_near.png")
	if sky != null:
		_blit_cover(sky, tl, size, center, 0.02, Color.WHITE)
	if far_cloud != null:
		_blit_cover_looping(far_cloud, tl, size, _far_cloud_scroll, Color(1, 0.87, 0.91, 0.15))
	if near_cloud != null:
		_blit_cover_looping(near_cloud, tl, size, _near_cloud_scroll, Color(1, 0.85, 0.9, 0.16))
	# 只移動街景的水平視差；高度依原圖比例，拱橋與實際可走的平台分開。
	var street_origin := tl - Vector2(0, size.y * 0.07)
	if blocks != null:
		_blit_parallax(blocks, street_origin, size, center, FIRST_STREET_PARALLAX, "bottom",
			Color(0.94, 0.91, 0.97, 0.94), true, FIRST_STREET_HEIGHT)
		_draw_landing_windows(blocks, street_origin, size, center)
	if signs != null:
		var alpha := 0.5 * Conductor.pulse(4.5) * GameState.anim_amount()
		_blit_parallax(signs, street_origin, size, center, FIRST_STREET_PARALLAX, "bottom",
			Color(1, 1, 1, alpha), true, FIRST_STREET_HEIGHT)


func light_landing_windows() -> void:
	_window_beats = 0.0


func clear_landing_windows() -> void:
	_window_beats = -1.0


func _draw_landing_windows(street: Texture2D, tl: Vector2, size: Vector2, center: Vector2) -> void:
	# 只點亮第一坑後面那棟樓，使用第一段街景的原圖座標；其他重複街區照常。
	var height := size.y * FIRST_STREET_HEIGHT
	var street_scale := height / street.get_height()
	var origin := Vector2(center.x * (1.0 - FIRST_STREET_PARALLAX), tl.y + size.y - height)
	if origin.x + LANDING_WINDOWS.back().end.x * street_scale < tl.x:
		return
	draw_set_transform(origin, 0.0, Vector2.ONE * street_scale)
	for i in LANDING_WINDOWS.size():
		var pane: Rect2 = LANDING_WINDOWS[i]
		var age := _window_beats - 0.25 * i
		var light := smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(1.15, 2.0, age))
		draw_rect(pane, Color(0.17, 0.12, 0.25, 0.64 * (1.0 - light)))
		if light > 0.0:
			draw_rect(pane.grow(3), Color(1.0, 0.70, 0.36, light * 0.09 * GameState.anim_amount()))
			draw_texture_rect_region(street, pane, pane, Color(1.54, 1.46, 1.12, light))
			draw_rect(pane, Color(1.0, 0.88, 0.56, 0.30 * light))
	draw_set_transform(Vector2.ZERO)


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


## 第二關：夕陽遊樂園，加入低干擾的花瓣景深與緩慢摩天輪。
func _draw_sakura_park(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/sakura_park/bg/"
	var sky := GameState.theme_texture(base + "sky_clean.png")
	var clouds_far := GameState.theme_texture(base + "clouds_far.png")
	var clouds_near := GameState.theme_texture(base + "clouds_near.png")
	var park_far := GameState.theme_texture(base + "park_far_clean.png")
	var wheel := GameState.theme_texture(base + "ferris_wheel.png")
	var trees_mid := GameState.theme_texture(base + "trees_mid.png")
	var park_near_bottom := GameState.theme_texture(base + "park_near_bottom.png")

	if sky != null:
		_blit_cover(sky, tl, size, center, 0.0, Color.WHITE)
	if clouds_far != null:
		_blit_cover_looping(clouds_far, tl, size, _far_cloud_scroll,
			Color(1.0, 0.96, 1.0, 0.46))
	if clouds_near != null:
		_blit_cover_looping(clouds_near, tl, size, _near_cloud_scroll,
			Color(1.0, 0.98, 1.0, 0.60))
	if park_far != null:
		_blit_parallax(park_far, tl, size, center, 0.16, "bottom",
			Color(1.0, 0.96, 1.0, 0.80), true, 0.55)
	if wheel != null and park_far != null:
		_draw_sakura_wheels(wheel, park_far, tl, size, center)
	_draw_sakura_petals(tl, size, false)
	if trees_mid != null:
		_blit_parallax(trees_mid, tl, size, center, 0.34, "bottom",
			Color(1.0, 0.97, 1.0, 0.72), true, 0.36)
	if park_near_bottom != null:
		_blit_parallax(park_near_bottom, tl, size, center, 0.58, "bottom",
			Color(1.0, 0.98, 1.0, 0.76), true, 0.27)
	_draw_sakura_petals(tl, size, true)


func _draw_sakura_wheels(wheel: Texture2D, reference: Texture2D, tl: Vector2,
		size: Vector2, center: Vector2) -> void:
	var reference_size := reference.get_size()
	var scale := size.y * 0.55 / reference_size.y
	var draw_w := reference_size.x * scale
	var draw_h := reference_size.y * scale
	var shift := center.x * 0.84
	var first := floori((tl.x - shift) / draw_w) - 1
	var last := ceili((tl.x + size.x - shift) / draw_w) + 1
	var y := tl.y + size.y - draw_h
	var diameter := draw_h * 0.49
	for i in range(first, last):
		var mirrored := posmod(i, 2) != 0
		var local_x := draw_w * (0.715 if mirrored else 0.285)
		var wheel_center := Vector2(float(i) * draw_w + shift + local_x, y + draw_h * 0.66)
		var base_y := y + draw_h * 0.99
		## 支架不跟著輪體旋轉，讓機械結構看起來有固定在地面上。
		draw_line(wheel_center + Vector2(-diameter * 0.04, diameter * 0.08),
			Vector2(wheel_center.x - diameter * 0.20, base_y), Color("a878a6", 0.72),
			diameter * 0.035, true)
		draw_line(wheel_center + Vector2(diameter * 0.04, diameter * 0.08),
			Vector2(wheel_center.x + diameter * 0.20, base_y), Color("a878a6", 0.72),
			diameter * 0.035, true)
		draw_set_transform(wheel_center, -_ferris_angle if mirrored else _ferris_angle,
			Vector2.ONE)
		draw_texture_rect(wheel, Rect2(Vector2(-diameter, -diameter) * 0.5,
			Vector2(diameter, diameter)), false, Color(1.0, 0.96, 1.0, 0.88))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sakura_petals(tl: Vector2, size: Vector2, near: bool) -> void:
	var detail := GameState.quality_int("detail", 2)
	var count := (6 if detail == 0 else (10 if detail == 1 else 16)) if near else \
		(5 if detail == 0 else (8 if detail == 1 else 12))
	var motion := GameState.anim_amount()
	var margin := 34.0
	for i in count:
		var seed := i + (700 if near else 500)
		var speed_x := (12.0 + _hash(seed + 9) * 10.0) * (1.35 if near else 0.72)
		var speed_y := (4.0 + _hash(seed + 19) * 7.0) * (1.25 if near else 0.72)
		var x := tl.x - margin + fposmod(_hash(seed) * (size.x + margin * 2.0)
			+ _ambient_time * speed_x * motion, size.x + margin * 2.0)
		var y := tl.y - margin + fposmod(_hash(seed + 31) * (size.y + margin * 2.0)
			+ _ambient_time * speed_y * motion, size.y + margin * 2.0)
		x += sin(_ambient_time * (0.65 + _hash(seed + 41)) + seed) * (9.0 if near else 5.0) * motion
		var radius := (3.2 + _hash(seed + 51) * 2.8) if near else (1.8 + _hash(seed + 51) * 1.8)
		var angle := _ambient_time * (0.45 + _hash(seed + 61)) * motion + seed
		var axis := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-axis.y, axis.x)
		var p := Vector2(x, y)
		var shape := PackedVector2Array([
			p + axis * radius,
			p + normal * radius * 0.48,
			p - axis * radius,
			p - normal * radius * 0.48])
		var color := Color("ffd2e4", 0.62) if near else Color("f5b9d2", 0.34)
		draw_colored_polygon(shape, color)


## 第三關：霓虹音樂祭，多層舞台視差與低干擾節拍燈光。
func _draw_music_festival(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/music_festival/bg/"
	var sky := GameState.theme_texture(base + "sky.png")
	var city := GameState.theme_texture(base + "city_far.png")
	var festival := GameState.theme_texture(base + "festival_mid.png")
	var promenade := GameState.theme_texture(base + "festival_near.png")
	var pulse := Conductor.pulse(6.0) * GameState.anim_amount()

	if sky != null:
		_blit_cover(sky, tl, size, center, 0.0, Color.WHITE)
	_draw_festival_spotlights(tl, size, pulse)
	if city != null:
		_blit_parallax(city, tl, size, center, 0.16, "bottom",
			Color(0.94, 0.92, 1.0, 0.82), true, 0.60)
	if festival != null:
		_blit_parallax(festival, tl, size, center, 0.36, "bottom",
			Color(1.0, 0.94, 1.0, 0.72 + pulse * 0.08), true, 0.50)
	if promenade != null:
		_blit_parallax(promenade, tl, size, center, 0.60, "bottom",
			Color(0.96, 0.96, 1.0, 0.84), true, 0.24)
	_draw_festival_notes(tl, size)


func _draw_festival_spotlights(tl: Vector2, size: Vector2, pulse: float) -> void:
	if not GameState.quality_flag("bg_stage", true):
		return
	var detail := GameState.quality_int("detail", 2)
	var positions: Array[float] = [0.08, 0.92]
	if detail == 1:
		positions = [0.08, 0.36, 0.64, 0.92]
	elif detail >= 2:
		positions = [0.08, 0.28, 0.44, 0.56, 0.72, 0.92]
	var motion := GameState.anim_amount()
	for i in positions.size():
		var position_ratio := positions[i]
		var side := 1.0 if position_ratio < 0.5 else -1.0
		var outer := i == 0 or i == positions.size() - 1
		var base_x := tl.x + size.x * position_ratio
		var base := Vector2(base_x, tl.y + size.y * 0.98)
		var speed := (0.14 + i * 0.018) if outer else (0.20 + i * 0.025)
		var amplitude := 0.11 if outer else 0.22
		var sway := sin(_ambient_time * speed + i * 1.7) * amplitude * motion
		var direction := Vector2(side * (0.18 + sway), -1.0).normalized()
		var length := size.y * 1.18
		var spread := 0.075
		var color := Color("55dfff") if i % 2 == 0 else Color("ff5fd7")
		var alpha := (0.018 + pulse * 0.016) if outer else (0.025 + pulse * 0.025)
		draw_colored_polygon(PackedVector2Array([
			base,
			base + direction.rotated(-spread) * length,
			base + direction.rotated(spread) * length]), Color(color, alpha))


func _draw_festival_notes(tl: Vector2, size: Vector2) -> void:
	var detail := GameState.quality_int("detail", 2)
	var count := 4 if detail == 0 else (7 if detail == 1 else 10)
	var motion := GameState.anim_amount()
	var font := UiKit.font()
	for i in count:
		var seed := i + 900
		var x := tl.x + fposmod(_hash(seed) * (size.x + 120.0)
			+ _ambient_time * (3.0 + _hash(seed + 7) * 5.0) * motion, size.x + 120.0) - 60.0
		var y := tl.y + fposmod(_hash(seed + 31) * size.y
			- _ambient_time * (7.0 + _hash(seed + 17) * 7.0) * motion, size.y)
		var glyph := "♫" if i % 3 == 0 else "♪"
		var color := Color("68e4ff") if i % 2 == 0 else Color("ff79dc")
		draw_string(font, Vector2(x, y), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
			13 + i % 3 * 2, Color(color, 0.16 + Conductor.pulse(6.0) * 0.16 * motion))


const RAIN_STREET_PARALLAX := 0.34
const RAIN_STREET_HEIGHT := 0.48

## 第四關：雨夜街道。雨與閃電保持程式化，避免把動畫烘焙進素材。
func _draw_rainy_street(tl: Vector2, size: Vector2, center: Vector2) -> void:
	var base := "res://assets/themes/rainy_street/bg/"
	var sky := GameState.theme_texture(base + "sky_base.png")
	var clouds_far := GameState.theme_texture(base + "clouds_far.png")
	var clouds_near := GameState.theme_texture(base + "clouds_near.png")
	var city := GameState.theme_texture(base + "city_far.png")
	var street := GameState.theme_texture(base + "street_mid.png")
	var street_neon := GameState.theme_texture(base + "street_neon.png")
	var promenade := GameState.theme_texture(base + "promenade_near.png")
	var flash := _rainy_lightning_flash()
	var motion := GameState.anim_amount()
	var beat_pulse := Conductor.pulse(5.0) * motion
	## 拍頭短暫持亮，讓低畫質隔幀重畫時也能讀到拍點。
	var neon_pulse := (1.0 - smoothstep(0.10, 0.76, Conductor.beat_fraction())) * motion
	var city_breathe := (0.5 + 0.5 * sin(_ambient_time * 0.42)) * motion
	if sky != null:
		_blit_cover(sky, tl, size, center, 0.0, Color.WHITE)
	if clouds_far != null:
		_blit_cover_looping(clouds_far, tl, size, _rain_cloud_scroll,
			Color(0.82, 0.86, 1.0, 0.48), true, 0.92)
	if clouds_near != null:
		_blit_cover_looping(clouds_near, tl, size, _rain_cloud_near_scroll,
			Color(1.0, 1.0, 1.0, 0.90), true, 1.05)
	if flash > 0.0:
		draw_rect(Rect2(tl, size), Color(0.72, 0.80, 1.0, flash * 0.20))
	if city != null:
		_blit_parallax(city, tl, size, center, 0.14, "bottom",
			Color(0.82, 0.84, 1.0, 0.68 + flash * 0.10), true, 0.48)
	if street != null:
		_blit_parallax(street, tl, size, center, RAIN_STREET_PARALLAX, "bottom",
			Color(0.92, 0.91, 1.0, 0.72 + flash * 0.08), true, RAIN_STREET_HEIGHT)
	if street_neon != null:
		## 原圖保留最低亮度；獨立霓虹層只在拍點額外增亮，不讓建築一起閃。
		var glow := 1.0 + 0.48 * neon_pulse
		_blit_parallax(street_neon, tl, size, center, RAIN_STREET_PARALLAX, "bottom",
			Color(glow, glow, glow, 0.08 + neon_pulse * 0.90), true, RAIN_STREET_HEIGHT)
	_draw_rain(tl, size, false)
	## 背景有 40px 防震留邊；讓濕地貼近可視底部，露出欄杆下方的路面。
	var promenade_tl := tl - Vector2(0.0, 36.0)
	if promenade != null:
		_blit_parallax(promenade, promenade_tl, size, center, 0.58, "bottom",
			Color(0.94, 0.95, 1.0, 0.76 + city_breathe * 0.035), true, 0.30)
	_draw_rainy_lamp_glows(tl, size, beat_pulse, flash)
	if street_neon != null and promenade != null:
		_draw_rainy_reflections(promenade_tl, size, center, street_neon, neon_pulse)
	_draw_rainy_ripples(tl, size)
	_draw_rain(tl, size, true)


func _rainy_lightning_flash() -> float:
	if GameState.anim_amount() <= 0.0:
		return 0.0
	## 約 13.7 秒一次，短暫雙閃；不畫明確閃電枝，避免遮擋關卡。
	var phase := fposmod(_ambient_time, 13.7)
	var first := clampf(1.0 - absf(phase - 0.10) / 0.08, 0.0, 1.0)
	var second := clampf(1.0 - absf(phase - 0.34) / 0.12, 0.0, 1.0)
	return maxf(first, second * 0.68) * GameState.anim_amount()


func _draw_rain(tl: Vector2, size: Vector2, near: bool) -> void:
	var detail := GameState.quality_int("detail", 2)
	var count := (34 if detail == 0 else (54 if detail == 1 else 78)) if near else \
		(20 if detail == 0 else (32 if detail == 1 else 46))
	var motion := GameState.anim_amount()
	## 風向以很慢的週期改變，雨不會像固定角度的直線貼圖。
	var wind := 0.20 + sin(_ambient_time * 0.18) * 0.075 * motion
	var margin := 70.0
	for i in count:
		var seed := i + (1400 if near else 1200)
		var fall_speed := (360.0 + _hash(seed + 7) * 210.0) * (1.18 if near else 0.72)
		var drift := fall_speed * wind
		var span_x := size.x + margin * 2.0
		var span_y := size.y + margin * 2.0
		var y := tl.y - margin + fposmod(_hash(seed + 17) * span_y
			+ _ambient_time * fall_speed * motion, span_y)
		var x := tl.x - margin + fposmod(_hash(seed) * span_x
			+ _ambient_time * drift * motion, span_x)
		var length := (16.0 + _hash(seed + 31) * 15.0) if near else (9.0 + _hash(seed + 31) * 9.0)
		var alpha := 0.22 if near else 0.10
		draw_line(Vector2(x, y), Vector2(x + length * wind, y + length),
			Color(0.68, 0.82, 1.0, alpha), 1.3 if near else 1.0, true)


func _draw_rainy_lamp_glows(tl: Vector2, size: Vector2, beat_pulse: float,
		flash: float) -> void:
	var detail := GameState.quality_int("detail", 2)
	var spacing := 430.0 if detail > 0 else 620.0
	var first := floori(tl.x / spacing) - 1
	var last := ceili((tl.x + size.x) / spacing) + 1
	var dim_from_flash := 1.0 - flash * 0.55
	var breathe := 0.72 + 0.16 * sin(_ambient_time * 0.65) + beat_pulse * 0.12
	for i in range(first, last):
		var p := Vector2(i * spacing + spacing * 0.52, tl.y + size.y * 0.765)
		for ring in 3:
			draw_circle(p, 20.0 + ring * 14.0,
				Color("ffd28d", (0.040 - ring * 0.009) * breathe * dim_from_flash))


func _draw_rainy_reflections(tl: Vector2, size: Vector2, center: Vector2,
		signs: Texture2D, pulse: float) -> void:
	## 原圖中藍色音符與粉色主招牌的中心；倒影跟店面共用視差與奇偶鏡像。
	var scale_factor := size.y * RAIN_STREET_HEIGHT / signs.get_height()
	var tile_width := signs.get_width() * scale_factor
	var shift := center.x * (1.0 - RAIN_STREET_PARALLAX)
	var surface := tl.y + size.y * 0.963
	var first := floori((tl.x - shift) / tile_width)
	var last := ceili((tl.x + size.x - shift) / tile_width)
	var shimmer := _ambient_time * GameState.anim_amount()
	for tile in range(first, last):
		for sign_x: float in [472.0, 1354.0]:
			var offset := sign_x * scale_factor
			if posmod(tile, 2) == 1:
				offset = tile_width - offset
			var x := shift + tile * tile_width + offset
			var tint := Color("69ceff") if sign_x == 472.0 else Color("ed85dd")
			for band in 7:
				var depth := band / 6.0
				var y := surface + depth * size.y * (0.010 + 0.017 * pulse)
				var half_width := scale_factor * (17.0 - 8.0 * depth + 3.0 * sin(band * 2.4))
				var drift := scale_factor * 4.0 * sin(band * 1.8 + shimmer)
				draw_line(Vector2(x + drift - half_width, y), Vector2(x + drift + half_width, y),
					Color(tint, (0.11 + 0.33 * pulse) * (1.0 - 0.65 * depth)),
					maxf(1.0, scale_factor * 3.5), true)


func _draw_rainy_ripples(tl: Vector2, size: Vector2) -> void:
	var detail := GameState.quality_int("detail", 2)
	var count := 3 if detail == 0 else (5 if detail == 1 else 8)
	var motion := GameState.anim_amount()
	for i in count:
		var seed := i + 1600
		var cycle := fposmod(_ambient_time * (0.45 + _hash(seed) * 0.25)
			+ _hash(seed + 9), 1.0) * motion
		var p := Vector2(tl.x + size.x * (0.08 + _hash(seed + 17) * 0.84),
			tl.y + size.y * (0.86 + _hash(seed + 27) * 0.10))
		var radius := 5.0 + cycle * 18.0
		draw_arc(p, radius, 0.0, TAU, 24, Color(0.55, 0.83, 1.0, (1.0 - cycle) * 0.26), 1.2, true)
		draw_arc(p, radius * 0.52, 0.0, TAU, 20, Color(0.88, 0.60, 1.0, (1.0 - cycle) * 0.14), 1.0, true)


func _draw_panorama(theme: Dictionary, tl: Vector2, size: Vector2, center: Vector2, dim: bool) -> void:
	var tex := GameState.theme_texture(String(theme.get("bg_far", "")))
	if tex == null:
		return
	var tint := Color(1, 1, 1, 0.78 if dim else 1.0)
	## 全景也用鏡像捲，避免月亮／建築在接縫被切成兩半又往回抽
	_blit_parallax(tex, tl, size, center, 0.22, "fill", tint, true)


## 天空等：整張跟著鏡頭鋪滿，月亮／主體永遠完整，不橫向拼貼
func _blit_cover(tex: Texture2D, tl: Vector2, size: Vector2, center: Vector2,
		factor: float, modulate: Color, ambient_offset: float = 0.0) -> void:
	var tex_size := tex.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	var scale := maxf(size.x / tex_size.x, size.y / tex_size.y) * 1.08
	var draw_size := tex_size * scale
	## 輕微視差只在「多出來的邊界」內平移，永不露出圖外、也不循環跳回
	var overflow_x := maxf(0.0, draw_size.x - size.x)
	var overflow_y := maxf(0.0, draw_size.y - size.y)
	var drift := clampf(center.x * factor * 0.04 + ambient_offset,
		-overflow_x * 0.5, overflow_x * 0.5)
	var origin := Vector2(
		tl.x - overflow_x * 0.5 - drift,
		tl.y - overflow_y * 0.5)
	draw_texture_rect(tex, Rect2(origin, draw_size), false, modulate)


## 雲層向右無限捲動；相鄰副本首尾接續，循環重置發生在畫面外。
func _blit_cover_looping(tex: Texture2D, tl: Vector2, size: Vector2,
		scroll: float, modulate: Color, mirror: bool = false,
		scale_mult: float = 1.0) -> void:
	var tex_size := tex.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	var scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
	var draw_size := tex_size * scale * scale_mult
	## 鏡像時以兩張為一個循環，右接右、左接左，避免雲邊緣突然斷裂。
	var period := draw_size.x * (2.0 if mirror else 1.0)
	var offset := fposmod(scroll, period)
	var x := tl.x - period + offset
	var y := tl.y + (size.y - draw_size.y) * 0.5
	var segment := 0
	while x < tl.x + size.x:
		if mirror and segment % 2 != 0:
			draw_texture_rect(tex,
				Rect2(Vector2(x, y), Vector2(-draw_size.x, draw_size.y)),
				false, modulate)
		else:
			draw_texture_rect(tex, Rect2(Vector2(x, y), draw_size), false, modulate)
		x += draw_size.x
		segment += 1


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
	## 光點只跟鏡頭移動一點點（原本 0.8 轉身時會整片掃過螢幕，像雪糊到臉上）
	var factor := 0.15
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
		var y := tl.y + fposmod(_hash(i + 300) * size.y - b * (drift + _hash(i + 7) * (6.0 if quiet else 20.0)) - center.y * 0.15, size.y)
		var r := (1.0 + _hash(i + 11) * 1.4) if quiet else (1.5 + _hash(i + 11) * 2.0 + pulse * 1.5)
		var a := (0.12 + 0.1 * pulse) if quiet else (0.25 + 0.45 * pulse)
		draw_circle(Vector2(x, y), r, Color(edge.lerp(Color.WHITE, 0.5), a))
