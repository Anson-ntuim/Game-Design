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
	{"name": "簡單", "early": 20, "late": 20},
	{"name": "普通", "early": 7, "late": 8},
	{"name": "困難", "early": 4, "late": 5},
]
const JUDGE_FPS := 60.0

var deaths: int = 0
var skin: int = 0
var difficulty: int = 1
var _skin_textures: Dictionary = {}
var level_index: int = 0
## 0~1，跟著音樂段落（4 小節）逐漸升高、段落開頭歸零，用來加強背景特效
var groove: float = 0.0
var _note_step: int = 0
## 關卡編號 → {"time": 最快秒數, "deaths": 最少死亡數}
var records: Dictionary = {}

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
	Conductor.section_changed.connect(_on_section_changed)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)


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
	p.pitch_scale = pow(2.0, semitones / 12.0) * Conductor.rate
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
	cfg.set_value("settings", "skin", skin)
	cfg.set_value("settings", "difficulty", difficulty)
	for k: int in records:
		cfg.set_value("level_%d" % k, "time", records[k]["time"])
		cfg.set_value("level_%d" % k, "deaths", records[k]["deaths"])
	cfg.save(SAVE_PATH)


func _load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	skin = clampi(int(cfg.get_value("settings", "skin", 0)), 0, SKINS.size() - 1)
	difficulty = clampi(int(cfg.get_value("settings", "difficulty", 1)), 0, DIFFICULTIES.size() - 1)
	for section in cfg.get_sections():
		if section.begins_with("level_"):
			records[int(section.trim_prefix("level_"))] = {
				"time": float(cfg.get_value(section, "time", 0.0)),
				"deaths": int(cfg.get_value(section, "deaths", 0)),
			}


func color(key: String) -> Color:
	var a: Color = palettes[_palette_from][key]
	var b: Color = palettes[_palette_to][key]
	return a.lerp(b, smoothstep(0.0, 1.0, _palette_t))


func _on_section_changed(section: int) -> void:
	var idx := section % palettes.size()
	if idx == _palette_to:
		return
	_palette_from = _palette_to
	_palette_to = idx
	_palette_t = 0.0


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_action("down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_action("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_add_action("dash", [KEY_C, KEY_SHIFT, KEY_L], [JOY_BUTTON_B], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_action("restart", [KEY_R], [JOY_BUTTON_BACK])
	_add_action("confirm", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START])
	_add_action("back", [KEY_ESCAPE], [JOY_BUTTON_GUIDE])
	_add_action("guide", [KEY_H, KEY_TAB], [JOY_BUTTON_Y])
	_add_action("easier", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("harder", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])


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
