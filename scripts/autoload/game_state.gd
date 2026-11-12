extends Node
## 全域遊戲狀態：音效、色盤（每個段落切換場景配色）、按鍵設定、死亡次數、各關最佳紀錄。

## 遊戲顯示的名稱。project.godot 的 config/name 不能跟著改，user:// 存檔資料夾是用它命名的
const GAME_TITLE := "Heart Beat"
const SFX_DIR := "res://assets/sfx/"
const SAVE_PATH := "user://save.cfg"
## 配樂 Am - F - C - G 每小節換一個和弦；這裡是各和弦的琶音（相對 A4 的半音）
const CHORD_ARPS: Array = [[0, 3, 7, 12], [-4, 0, 3, 8], [-2, 3, 7, 10], [-2, 2, 5, 10]]
## 可選造型：texture 是靜態圖（面向右、腳貼底），每個造型都要有。
## 有 frames 的另外有動作幀 <frames><動作>_<n>.png（tools/make_dog_frames.py 產生）：
## 每幀同樣大小，腳底中心在 frame_anchor，frame_height 是站姿的高度（對應遊戲裡的 Player.SKIN_HEIGHT）
const SKINS: Array[Dictionary] = [
	{
		"name": "菜人尾狗", "texture": "res://assets/characters/dog_side.png",
		"frames": "res://assets/characters/dog/", "frame_anchor": Vector2(224, 280), "frame_height": 192.0,
	},
]
## 判定難度：音符、衝刺環、光柱的判定窗，以 60 fps 的幀數計（x 拍前 early 幀到後 late 幀內按下都算準）。
## 簡單比半拍（120 BPM 時 15 幀）還寬，提早或晚半拍也算準；音符和衝刺環最多往前找兩個半拍格，所以不能超過 30 幀。
## 每拍都開的光柱另外限制在打開間隔的 40%（beat_gate.gd），不然會一直開著
const DIFFICULTIES: Array[Dictionary] = [
	{"name": "簡單", "early": 26, "late": 26},
	{"name": "普通", "early": 10, "late": 11},
	{"name": "困難", "early": 4, "late": 5},
	{"name": "自由", "early": 0, "late": 0, "free": true},
]
const JUDGE_FPS := 60.0
## 畫質：不鎖幀，用減少動畫／特效量來減輕負擔（瀏覽器預設「中」）
## anim：演出強度 0~1；player_frames：跑／待機循環幀數；player_trail：衝刺殘影數
## detail：背景層級；*_redraw_every：裝飾層隔幾幀重畫
const QUALITIES: Array[Dictionary] = [
	{
		"name": "低", "max_fps": 0, "physics_tps": 120, "anim": 0.12,
		"player_frames": 1, "player_trail": 0,
		"bg_motes": 4, "bg_eq_spacing": 110.0, "bg_moon_glow": 0, "bg_stage": false,
		"bg_redraw_every": 3, "terrain_redraw_every": 3, "confetti": 0,
		"ghost": false, "shake": false, "edge_lights": false, "detail": 0,
	},
	{
		"name": "中", "max_fps": 0, "physics_tps": 120, "anim": 0.5,
		"player_frames": 2, "player_trail": 2,
		"bg_motes": 12, "bg_eq_spacing": 72.0, "bg_moon_glow": 1, "bg_stage": false,
		"bg_redraw_every": 2, "terrain_redraw_every": 2, "confetti": 8,
		"ghost": true, "shake": true, "edge_lights": true, "detail": 1,
	},
	{
		"name": "高", "max_fps": 0, "physics_tps": 120, "anim": 1.0,
		"player_frames": 6, "player_trail": 7,
		"bg_motes": 36, "bg_eq_spacing": 46.0, "bg_moon_glow": 4, "bg_stage": true,
		"bg_redraw_every": 1, "terrain_redraw_every": 1, "confetti": 26,
		"ghost": true, "shake": true, "edge_lights": true, "detail": 2,
	},
]
signal quality_changed(index: int)
signal visual_theme_changed(index: int)

## 只保留心動之城：背景用分層素材；前景平台維持程式霓虹色塊（不貼平台圖集）
const VISUAL_THEMES: Array[Dictionary] = [
	{
		"id": "heartbeat_city", "name": "心動之城", "kind": "layered",
		"blurb": "粉彩城市分層場景",
		"terrain_pure": false,
		## wrap: cover＝天空整張鋪滿；mirror＝遠／近城左右鏡像無限捲
		"layers": [
			{"path": "res://assets/themes/heartbeat_city/bg/sky.png", "parallax": 0.0, "anchor": "fill", "wrap": "cover"},
			{"path": "res://assets/themes/heartbeat_city/bg/city_far.png", "parallax": 0.22, "anchor": "bottom", "wrap": "mirror", "height_frac": 0.42, "alpha": 0.95},
			{"path": "res://assets/themes/heartbeat_city/bg/city_near.png", "parallax": 0.48, "anchor": "bottom", "wrap": "mirror", "height_frac": 0.50, "alpha": 0.88},
		],
		"palettes": [
			{
				"bg_top": Color("2a1840"), "bg_bottom": Color("c4789a"), "far": Color("8a4a78"),
				"mid": Color("5c2e55"), "ground": Color("3d2648"), "edge": Color("ffb4d4"),
			},
			{
				"bg_top": Color("1e2048"), "bg_bottom": Color("6a8fd4"), "far": Color("4a6aaa"),
				"mid": Color("2a3560"), "ground": Color("2c2848"), "edge": Color("a8d4ff"),
			},
			{
				"bg_top": Color("301828"), "bg_bottom": Color("e8a070"), "far": Color("b86858"),
				"mid": Color("6a3840"), "ground": Color("402838"), "edge": Color("ffd0a0"),
			},
			{
				"bg_top": Color("241838"), "bg_bottom": Color("78c0b8"), "far": Color("489090"),
				"mid": Color("2e4850"), "ground": Color("2c3040"), "edge": Color("a8ffe0"),
			},
		],
	},
]

var deaths: int = 0
var skin: int = 0
var difficulty: int = 1
## 0=低 1=中 2=高；未存檔時桌面預設高、網頁預設中
var quality: int = 2
## 整體風格索引（目前固定心動之城）
var visual_theme: int = 0
## 音訊延遲校正（毫秒）。正＝聲音比畫面晚，負＝聲音比畫面早。範圍約 ±300ms
var audio_offset_ms: float = 0.0
const AUDIO_OFFSET_MIN := -300.0
const AUDIO_OFFSET_MAX := 300.0
var _skin_textures: Dictionary = {}
var _theme_textures: Dictionary = {}
var level_index: int = 0
## 進關時跳到的段落索引（0＝從頭）；進關後由 main 消費
var start_section: int = 0
## 0~1，跟著音樂段落（4 小節）逐漸升高、段落開頭歸零，用來加強背景特效
var groove: float = 0.0
var _note_step: int = 0
## 關卡編號 → {"time": 最快秒數, "deaths": 最少死亡數}
var records: Dictionary = {}
## 第五關重力／道路機關解鎖狀態（進關時清空）
var path_unlocks: Dictionary = {}

var palettes: Array[Dictionary] = [
	{ # 月夜藍
		"bg_top": Color("0b1026"), "bg_bottom": Color("233a6b"), "far": Color("2c4a85"),
		"mid": Color("121c3a"), "ground": Color("1b2440"), "edge": Color("7fdbff"),
	},
	{ # 霓虹紫
		"bg_top": Color("1a0b2e"), "bg_bottom": Color("5a1f7a"), "far": Color("7a3aa8"),
		"mid": Color("250d3d"), "ground": Color("2c1245"), "edge": Color("ff6ad5"),
	},
	{ # 翡翠林
		"bg_top": Color("031c19"), "bg_bottom": Color("11574a"), "far": Color("1d7a62"),
		"mid": Color("062b25"), "ground": Color("0e302a"), "edge": Color("6dffb3"),
	},
	{ # 餘燼紅
		"bg_top": Color("250806"), "bg_bottom": Color("7a2512"), "far": Color("a8431c"),
		"mid": Color("33100a"), "ground": Color("3a1510"), "edge": Color("ffb347"),
	},
]

var _palette_from: int = 0
var _palette_to: int = 0
var _palette_t: float = 1.0
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _sfx_next: int = 0
var _cue_frame: int = -1
var _cue_keys: Dictionary = {}


func _ready() -> void:
	get_window().title = GAME_TITLE
	_setup_input()
	_load_records()
	_apply_audio_offset()
	_apply_quality()
	Conductor.section_changed.connect(_on_section_changed)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)


func set_audio_offset_ms(ms: float, persist: bool = true) -> void:
	audio_offset_ms = clampf(ms, AUDIO_OFFSET_MIN, AUDIO_OFFSET_MAX)
	_apply_audio_offset()
	if persist:
		_save()


func nudge_audio_offset_ms(delta_ms: float) -> void:
	set_audio_offset_ms(audio_offset_ms + delta_ms)


func _apply_audio_offset() -> void:
	Conductor.user_offset = audio_offset_ms / 1000.0


func play_sfx(id: String, semitones: float = 0.0, volume_db: float = -3.0) -> void:
	var stream: AudioStream = _sfx_cache.get(id)
	if stream == null:
		var path := SFX_DIR + id + ".wav"
		if not ResourceLoader.exists(path):
			return
		stream = load(path)
		_sfx_cache[id] = stream
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.pitch_scale = pow(2.0, semitones / 12.0) * Conductor.world_rate
	p.volume_db = volume_db
	p.play()


## 地形發出的節奏提示音：同一個物理幀裡同一種音只播一次，整排尖刺一起彈出也不會疊成爆音
func play_cue(id: String, semitones: float = 0.0, volume_db: float = -9.0) -> void:
	var f := Engine.get_physics_frames()
	if f != _cue_frame:
		_cue_frame = f
		_cue_keys.clear()
	var key := "%s:%s" % [id, semitones]
	if _cue_keys.has(key):
		return
	_cue_keys[key] = true
	play_sfx(id, semitones, volume_db)


## 目前和弦琶音的下一個音（跨兩個八度），每個動作依序往上彈就會變成合和弦的旋律
func next_note() -> float:
	var step := _note_step
	_note_step += 1
	return arp_note(step)


## 目前和弦琶音的第 step 個音；旗子示範連招時也用同一組音，玩家照著跑就會彈出同樣的旋律
func arp_note(step: int) -> float:
	var chord := posmod(floori(Conductor.song_beat / Conductor.beats_per_measure), CHORD_ARPS.size())
	var arp: Array = CHORD_ARPS[chord]
	return float(arp[posmod(step, 4)] + (12 if posmod(step, 8) >= 4 else 0))


## 旗子響鈴換玩家跑的那一拍呼叫：讓玩家的旋律從頭開始，和剛才的示範一致
func reset_notes() -> void:
	_note_step = 0


func _process(delta: float) -> void:
	var section_beats := float(Conductor.beats_per_measure * Conductor.measures_per_section)
	var target := fposmod(Conductor.song_beat, section_beats) / section_beats
	groove = lerpf(groove, target, 1.0 - exp(-3.0 * delta))
	if _palette_t < 1.0:
		_palette_t = minf(1.0, _palette_t + delta / 1.2)


func reset_stats() -> void:
	deaths = 0
	groove = 0.0
	_note_step = 0
	_palette_from = 0
	_palette_to = 0
	_palette_t = 1.0
	path_unlocks.clear()


func free_rhythm() -> bool:
	return bool(DIFFICULTIES[difficulty].get("free", false))


func set_path_unlock(id: String, on: bool) -> void:
	if on:
		path_unlocks[id] = true
	else:
		path_unlocks.erase(id)


func is_path_unlock(id: String) -> bool:
	return path_unlocks.get(id, false)


## 記下過關成績，回傳是否刷新了任何一項紀錄
func record_clear(level: int, time: float, death_count: int) -> bool:
	var old: Dictionary = records.get(level, {})
	var improved := old.is_empty() or time < float(old["time"]) or death_count < int(old["deaths"])
	records[level] = {
		"time": minf(time, float(old.get("time", time))),
		"deaths": mini(death_count, int(old.get("deaths", death_count))),
	}
	_save()
	return improved


func set_skin(index: int) -> void:
	skin = posmod(index, SKINS.size())
	_save()


func set_difficulty(index: int) -> void:
	difficulty = clampi(index, 0, DIFFICULTIES.size() - 1)
	_save()


func set_prefer_reference_tempo(on: bool, persist: bool = true) -> void:
	Conductor.set_prefer_reference_tempo(on)
	if persist:
		_save()


func set_quality(index: int, persist: bool = true) -> void:
	var next := clampi(index, 0, QUALITIES.size() - 1)
	var changed := next != quality
	quality = next
	_apply_quality()
	if changed:
		quality_changed.emit(quality)
	if persist:
		_save()


func set_visual_theme(index: int, persist: bool = true) -> void:
	var next := posmod(index, VISUAL_THEMES.size())
	var changed := next != visual_theme
	visual_theme = next
	## 換風格時色盤從頭過渡，避免殘留上一主題的色相
	_palette_from = _palette_to
	_palette_to = 0
	_palette_t = 0.0
	if changed:
		visual_theme_changed.emit(visual_theme)
	if persist:
		_save()


func current_theme() -> Dictionary:
	return VISUAL_THEMES[visual_theme]


func theme_name(index: int = -1) -> String:
	var i := visual_theme if index < 0 else clampi(index, 0, VISUAL_THEMES.size() - 1)
	return String(VISUAL_THEMES[i]["name"])


func theme_is_procedural(index: int = -1) -> bool:
	var i := visual_theme if index < 0 else clampi(index, 0, VISUAL_THEMES.size() - 1)
	return String(VISUAL_THEMES[i].get("kind", "procedural")) == "procedural"


func theme_terrain_pure(index: int = -1) -> bool:
	var i := visual_theme if index < 0 else clampi(index, 0, VISUAL_THEMES.size() - 1)
	return bool(VISUAL_THEMES[i].get("terrain_pure", false))


## 地板／浮台／立柱：以碰撞形狀判斷，避免方塊地面被當成柱子、細高牆被貼地板
func theme_platform_role_for(rect: Rect2) -> String:
	var w := rect.size.x
	var h := rect.size.y
	## 很薄＝單向平台
	if h <= 22.0 and w >= 40.0:
		return "one_way"
	## 細高＝立柱／牆
	if w < 56.0 and h > w * 1.15:
		return "tall"
	if h > w * 1.35 and w < 160.0:
		return "tall"
	## 夠寬的可走面＝地板拼接
	if w >= 100.0:
		return "floor"
	## 短平台／踏腳＝浮台
	return "ledge"


func theme_platform_kit_path(key: String) -> String:
	var kit: Variant = current_theme().get("platform_kit", null)
	if kit is Dictionary and (kit as Dictionary).has(key):
		return String((kit as Dictionary)[key])
	return ""


## 依地形長寬比挑選平台素材路徑；支援 platforms 為分類 Dictionary 或舊版 Array
func theme_platform_path_for(rect: Rect2) -> String:
	var plats: Variant = current_theme().get("platforms", null)
	if plats == null:
		return ""
	var bucket := theme_platform_role_for(rect)
	var paths: Array = []
	if plats is Dictionary:
		var d: Dictionary = plats
		var order: Array[String] = [bucket, "floor", "long", "ledge", "mid", "island", "one_way", "tall"]
		for key in order:
			if d.has(key) and not (d[key] as Array).is_empty():
				paths = d[key] as Array
				break
	elif plats is Array:
		paths = plats as Array
		if paths.is_empty():
			return ""
		var aspect := rect.size.x / maxf(1.0, rect.size.y)
		var idx := 0
		if aspect < 0.6 and paths.size() > 2:
			idx = 2
		elif aspect < 1.6 and paths.size() > 1:
			idx = 1
		elif aspect > 3.5 and paths.size() > 3:
			idx = 3
		return String(paths[idx])
	if paths.is_empty():
		return ""
	var h: int = absi(hash(Vector2i(roundi(rect.position.x / 40.0), roundi(rect.position.y / 40.0))))
	return String(paths[h % paths.size()])


func theme_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _theme_textures.has(path):
		_theme_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _theme_textures[path]


func active_palettes() -> Array:
	var theme: Dictionary = current_theme()
	if theme.has("palettes"):
		return theme["palettes"] as Array
	return palettes


func quality_settings() -> Dictionary:
	return QUALITIES[quality]


func quality_flag(key: String, default: bool = true) -> bool:
	return bool(QUALITIES[quality].get(key, default))


func quality_int(key: String, default: int = 0) -> int:
	return int(QUALITIES[quality].get(key, default))


func quality_float(key: String, default: float = 0.0) -> float:
	return float(QUALITIES[quality].get(key, default))


## 演出強度 0~1：低畫質幾乎靜止，高畫質全開（脈動、標題彈跳、鏡頭 punch…）
func anim_amount() -> float:
	return quality_float("anim", 1.0)


## 依畫質決定這一幀要不要重畫裝飾層（背景／地形光）；玩法物件仍每幀更新
func should_redraw_decor(every_key: String = "bg_redraw_every") -> bool:
	var every := maxi(1, quality_int(every_key, 1))
	return every <= 1 or Engine.get_process_frames() % every == 0


func _apply_quality() -> void:
	var q: Dictionary = QUALITIES[quality]
	## 不鎖幀：效能靠減少動畫與裝飾密度，手感維持 120 物理步
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = int(q.get("physics_tps", 120))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## 判定窗（秒）：在 x 拍前多久按下還算準
func judge_early() -> float:
	return int(DIFFICULTIES[difficulty]["early"]) / JUDGE_FPS


## 判定窗（秒）：在 x 拍後多久按下還算準
func judge_late() -> float:
	return int(DIFFICULTIES[difficulty]["late"]) / JUDGE_FPS


## x 拍的 dt 秒後（負數是提早）按下算不算準
func in_window(dt: float) -> bool:
	return dt >= -judge_early() and dt <= judge_late()


## 目前造型的靜態圖
func skin_texture(index: int = -1) -> Texture2D:
	var path: String = SKINS[skin if index < 0 else index]["texture"]
	if not _skin_textures.has(path):
		_skin_textures[path] = load(path)
	return _skin_textures[path]


## 造型的動作幀（例如 "run_3"）；沒有動作幀或缺這一幀時回傳 null
func skin_frame(pose: String, index: int = -1) -> Texture2D:
	var dir: String = SKINS[skin if index < 0 else index].get("frames", "")
	if dir == "" or pose == "":
		return null
	var path := dir + pose + ".png"
	if not _skin_textures.has(path):
		_skin_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _skin_textures[path]


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "level_order_version", 2)
	cfg.set_value("settings", "skin", skin)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "visual_theme", visual_theme)
	cfg.set_value("settings", "audio_offset_ms", audio_offset_ms)
	cfg.set_value("settings", "prefer_reference_tempo", Conductor.prefer_reference_tempo)
	for k: int in records:
		cfg.set_value("level_%d" % k, "time", records[k]["time"])
		cfg.set_value("level_%d" % k, "deaths", records[k]["deaths"])
	cfg.save(SAVE_PATH)


func _load_records() -> void:
	var cfg := ConfigFile.new()
	var default_quality := 1 if OS.has_feature("web") else 2
	if cfg.load(SAVE_PATH) != OK:
		quality = default_quality
		return
	skin = clampi(int(cfg.get_value("settings", "skin", 0)), 0, SKINS.size() - 1)
	difficulty = clampi(int(cfg.get_value("settings", "difficulty", 1)), 0, DIFFICULTIES.size() - 1)
	quality = clampi(int(cfg.get_value("settings", "quality", default_quality)), 0, QUALITIES.size() - 1)
	visual_theme = 0
	audio_offset_ms = clampf(float(cfg.get_value("settings", "audio_offset_ms", 0.0)), AUDIO_OFFSET_MIN, AUDIO_OFFSET_MAX)
	Conductor.prefer_reference_tempo = bool(cfg.get_value("settings", "prefer_reference_tempo", false))
	var order_version := int(cfg.get_value("settings", "level_order_version", 1))
	records.clear()
	for section in cfg.get_sections():
		if section.begins_with("level_"):
			var index := int(section.trim_prefix("level_"))
			if order_version < 2 and index >= 4:
				index += 1
			records[index] = {
				"time": float(cfg.get_value(section, "time", 0.0)),
				"deaths": int(cfg.get_value(section, "deaths", 0)),
			}


func color(key: String) -> Color:
	var pals := active_palettes()
	var n := pals.size()
	if n <= 0:
		return Color.WHITE
	var from_i := posmod(_palette_from, n)
	var to_i := posmod(_palette_to, n)
	var a: Color = pals[from_i][key]
	var b: Color = pals[to_i][key]
	return a.lerp(b, smoothstep(0.0, 1.0, _palette_t))


func _on_section_changed(section: int) -> void:
	var n := active_palettes().size()
	if n <= 0:
		return
	var idx := section % n
	if idx == _palette_to:
		return
	_palette_from = _palette_to
	_palette_to = idx
	_palette_t = 0.0


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("auto_run", [KEY_F], [JOY_BUTTON_LEFT_STICK])
	_add_action("up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_action("down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_action("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_add_action("dash", [KEY_C, KEY_SHIFT, KEY_L], [JOY_BUTTON_B], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_action("restart", [KEY_R], [JOY_BUTTON_BACK])
	_add_action("confirm", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START])
	_add_action("back", [KEY_ESCAPE], [JOY_BUTTON_GUIDE])
	_add_action("guide", [KEY_H, KEY_TAB], [JOY_BUTTON_Y])
	_add_action("use_item", [KEY_V], [JOY_BUTTON_X])
	_add_action("easier", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("harder", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("quality_down", [KEY_BRACKETLEFT, KEY_MINUS], [])
	_add_action("quality_up", [KEY_BRACKETRIGHT, KEY_EQUAL], [])
	_add_action("section_prev", [KEY_COMMA, KEY_PAGEUP], [])
	_add_action("section_next", [KEY_PERIOD, KEY_PAGEDOWN], [])
	_add_action("calibrate", [KEY_O], [JOY_BUTTON_RIGHT_STICK])
	_add_action("music_setup", [KEY_M], [])


func _add_action(action: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.35)
	for k in keys:
		var ek := InputEventKey.new()
		ek.physical_keycode = k
		InputMap.action_add_event(action, ek)
	for b in buttons:
		var eb := InputEventJoypadButton.new()
		eb.button_index = b
		InputMap.action_add_event(action, eb)
	for a in axes:
		var em := InputEventJoypadMotion.new()
		em.axis = a[0]
		em.axis_value = a[1]
		InputMap.action_add_event(action, em)
