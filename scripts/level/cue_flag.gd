class_name CueFlag
extends Node2D
## 起跳旗：插在段落起點的懸崖邊。
## 平常只當節拍器：每 8 拍響一次鈴（前三拍木魚倒數，旗子上跳出 3、2、1，響鈴時 GO!），挑任何一次鈴聲出發都行。
## 站在旗子旁按「上」才看示範：下一個 8 拍循環開頭，旗子把這段連招彈一遍，
## 鏡頭跟著半透明的示範角色把整段跑完，再飛回玩家；一樣倒數 3、2、1，
## 示範開始後第 GO_BEATS 拍響鈴換玩家跑（機關都是 8 拍循環，所以響鈴時剛好對上）。
## demo 一格 = 半拍，從示範第 0 拍開始寫：T 點、L 長、o 音符點、O 音符長、D 衝、R 環衝、- 休止開始（要站著不動）、. 空。

enum State { FREE, WATCH }

const COLOR := Color(1.0, 0.78, 0.35)
const GHOST_COLOR := Color(0.75, 0.9, 1.0)
## ghost 相鄰兩點間隔幾拍（由關卡產生器的物理模擬取樣）
const GHOST_STEP := 0.125
const GO_BEATS := 16.0
## 玩家腳下離旗子這個範圍內（px）按「上」可以看示範
const TRIGGER_BEHIND := 70.0
const TRIGGER_AHEAD := 30.0
const CYCLE_BEATS := 8.0

var demo: String = ""
## 示範角色的路徑（世界座標），第 0 點 = 連招第 0 拍
var ghost: PackedVector2Array = PackedVector2Array()
## 這面旗子所在段落的左右範圍
var section_from: float = 0.0
var section_to: float = 0.0
var state: State = State.FREE
## 示範第 0 拍（歌曲拍數）
var start_beat: float = 0.0
var _last_slot: int = -9999
var _demo_step: int = 0
## 「↑ 示範」提示的淡入程度
var _prompt: float = 0.0
## 玩家在起跑區（聽得到節拍器）時才顯示倒數
var _counting: float = 0.0


func setup(feet: Vector2, demo_pattern: String) -> void:
	position = feet
	demo = demo_pattern


func _ready() -> void:
	z_index = 3


func has_demo() -> bool:
	return demo != ""


func go_beat() -> float:
	return start_beat + GO_BEATS


## 示範角色跑完（落地）的拍數
func ghost_end() -> float:
	return maxf(0.0, (ghost.size() - 1) * GHOST_STEP)


## 示範中鏡頭要看的位置；示範角色跑完後回傳 null（鏡頭飛回玩家）
func camera_focus() -> Variant:
	if state != State.WATCH or ghost.size() < 2:
		return null
	var t := Conductor.song_beat - start_beat
	if t < 0.0 or t > ghost_end() + 0.25:
		return null
	return _ghost_at(minf(t, ghost_end()))


func _ghost_at(t: float) -> Vector2:
	var f := t / GHOST_STEP
	var i := clampi(floori(f), 0, ghost.size() - 2)
	return ghost[i].lerp(ghost[i + 1], clampf(f - i, 0.0, 1.0))


## 示範角色的動作幀：路徑上這一小段的位移比跑步快很多就是衝刺，沒有上下位移就是在地上跑
func _ghost_pose(t: float) -> String:
	if t >= ghost_end():
		return Player.idle_pose(Conductor.song_beat)
	var i := clampi(floori(t / GHOST_STEP), 0, ghost.size() - 2)
	var v := (ghost[i + 1] - ghost[i]) / GHOST_STEP
	if absf(v.x) > 230.0:
		return "dash_1"
	if absf(v.y) < 0.5:
		return Player.run_pose(start_beat + t)
	if absf(v.y) < Player.APEX_SPEED * Conductor.sec_per_beat:
		return "apex_0"
	return "jump_0" if v.y < 0.0 else "fall_0"


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _at_flag(p: Player) -> bool:
	var dx := p.global_position.x - position.x
	return dx > -TRIGGER_BEHIND and dx < TRIGGER_AHEAD and p.is_on_floor() and not p.control_locked


func _physics_process(delta: float) -> void:
	if not has_demo():
		return
	var p := _player()
	if p == null:
		return
	var b := Conductor.song_beat
	var near := state == State.FREE and _at_flag(p)
	_prompt = move_toward(_prompt, 1.0 if near else 0.0, delta * 5.0)
	_counting = move_toward(_counting, 1.0 if state == State.WATCH or _in_start_zone(p) else 0.0, delta * 4.0)
	match state:
		State.FREE:
			if near and Input.is_action_just_pressed("up"):
				state = State.WATCH
				start_beat = ceilf((b + 1.0) / 8.0) * 8.0
				_demo_step = 0
				_last_slot = floori((b - start_beat) * 2.0)
				p.watching = true
				p.watch_x = position.x
			else:
				_tick_metronome(b, p)
		State.WATCH:
			# 響鈴前一點點就放開操作，剛好在鈴聲上按的跳才不會被吃掉
			if b >= go_beat() - 0.25:
				p.watching = false
			_tick_sounds(b)
			if b >= go_beat():
				state = State.FREE
				_last_slot = floori(b * 2.0)


func _tick_sounds(b: float) -> void:
	var s := floori((b - start_beat) * 2.0)
	if s == _last_slot:
		return
	_last_slot = s
	var go := roundi(GO_BEATS * 2.0)
	if s >= 0 and s < demo.length() and s < go and demo[s] != ".":
		_play_demo(demo[s])
	if s == go:
		GameState.play_cue("cue", 0.0, -6.0)
		GameState.reset_notes()
	elif s == go - 6 or s == go - 4 or s == go - 2:
		GameState.play_cue("block", 0.0, -8.0)


## 起跑區：段落左端到旗子右邊一點、還能操作的時候（節拍器只在這裡響）
func _in_start_zone(p: Player) -> bool:
	var x := p.global_position.x
	return not p.control_locked and x >= section_from and x <= position.x + 60.0


func _tick_metronome(b: float, p: Player) -> void:
	var s := floori(b * 2.0)
	if s == _last_slot:
		return
	_last_slot = s
	if not _in_start_zone(p):
		return
	var slot := posmod(s, roundi(CYCLE_BEATS * 2.0))
	if slot == 0:
		GameState.play_cue("cue", 0.0, -6.0)
		GameState.reset_notes()
	elif slot == 10 or slot == 12 or slot == 14:
		GameState.play_cue("block", 0.0, -8.0)


## 示範用的聲音和玩家做同一個動作時的聲音相同：跳彈琶音、音符高八度、長會接延音、衝刺是拍手
func _play_demo(d: String) -> void:
	if d == "-":
		GameState.play_sfx("hush", 0.0, -4.0)
		return
	if d == "D" or d == "R":
		GameState.play_sfx("clap", 0.0, -5.0)
	if d == "D":
		return
	var note := GameState.arp_note(_demo_step)
	_demo_step += 1
	if d in "oOR":
		note += 12.0
	GameState.play_sfx("pluck", note, -4.0)
	if d == "L" or d == "O":
		get_tree().create_timer(0.1, false).timeout.connect(GameState.play_sfx.bind("hold", note, -10.0))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var b := Conductor.song_beat
	var until := INF
	var since := INF
	if state == State.WATCH:
		until = go_beat() - b
	elif state == State.FREE:
		until = ceilf(b / CYCLE_BEATS) * CYCLE_BEATS - b
		since = b - floorf(b / CYCLE_BEATS) * CYCLE_BEATS
	draw_line(Vector2(0, 0), Vector2(0, -56), Color(0.85, 0.85, 0.9), 3.0)
	var fill := 0.25
	if until <= 2.0:
		fill = lerpf(0.5, 1.0, 1.0 - until / 2.0)
	elif state == State.WATCH:
		fill = 0.5
	var flash := clampf(1.0 - since * 3.0, 0.0, 1.0)
	var col := COLOR.lerp(Color.WHITE, flash)
	draw_colored_polygon(PackedVector2Array([Vector2(1, -56), Vector2(30, -47), Vector2(1, -38)]), Color(col, fill))
	_draw_countdown(until, since)
	if flash > 0.0:
		draw_arc(Vector2(0, -47), 20.0 + (1.0 - flash) * 24.0, 0.0, TAU, 32, Color(COLOR, flash), 3.0, true)
	if _prompt > 0.0:
		_draw_prompt()
	if state == State.WATCH and ghost.size() > 1:
		var t := b - start_beat
		if t >= 0.0 and t <= ghost_end() + 0.3:
			_draw_ghost(t)


## 倒數：響鈴前三拍跳出 3、2、1，響鈴那拍 GO!；下面四顆燈一拍亮一顆
func _draw_countdown(until: float, since: float) -> void:
	if _counting <= 0.0:
		return
	var label := ""
	var age := 0.0
	if until > 0.0 and until <= 3.0:
		label = str(ceili(until))
		age = ceilf(until) - until
	elif since < 0.75:
		label = "GO!"
		age = since
	if label == "":
		return
	var go := label == "GO!"
	var a := _counting * (clampf((0.75 - age) * 4.0, 0.0, 1.0) if go else 1.0)
	var lit := 4 if go else 4 - ceili(until)
	for i in 4:
		var on := i < lit
		var r := (5.0 if i == 3 else 4.0) + (1.5 if on and i == lit - 1 else 0.0)
		draw_circle(Vector2(-24.0 + i * 16.0, -116.0), r, Color(COLOR, a) if on else Color(1, 1, 1, 0.25 * a))
	var font_size := 50 if go else 60
	var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age * 5.0)
	var w := UiKit.width_of(label, font_size, UiKit.title_font())
	var fill := COLOR if go or label == "1" else Color.WHITE
	draw_set_transform(Vector2(0, -158), 0.0, Vector2(pop, pop))
	UiKit.bold_text(self, Vector2(-w * 0.5, font_size * 0.36), -1, label, font_size, Color(fill, a), COLOR)
	draw_set_transform(Vector2.ZERO)


func _draw_prompt() -> void:
	var a := ease(_prompt, -2.0)
	var y := -74.0 - 6.0 * a
	var label_w := UiKit.width_of("示範", 14)
	var w := UiKit.KEY_H + 6.0 + label_w
	var box := Rect2(-w * 0.5 - 8.0, y - 20.0, w + 16.0, 32.0)
	draw_colored_polygon(UiKit.chamfer(box, 6.0), Color(UiKit.PANEL, 0.85 * a))
	UiKit.keycap(self, Vector2(box.position.x + 8.0, y - 17.0), "↑", COLOR, a)
	UiKit.text(self, Vector2(box.position.x + 14.0 + UiKit.KEY_H, y), -1, "示範", 14, Color(COLOR.lerp(Color.WHITE, 0.4), a))


func _draw_ghost(t: float) -> void:
	var fade := clampf(t * 4.0, 0.0, 1.0) * clampf((ghost_end() + 0.3 - t) * 3.0, 0.0, 1.0)
	var slot := mini(floori(t * 2.0), demo.length() - 1)
	var hit := -1.0
	for k in range(slot, -1, -1):
		if demo[k] != "." and demo[k] != "-":
			hit = t - k * 0.5
			break
	var p := to_local(_ghost_at(minf(t, ghost_end())))
	var body := Color(GHOST_COLOR, 0.55 * fade)
	Player.draw_skin(self, GameState.skin, p + Vector2(0, Player.BODY_SIZE.y * 0.5), Vector2.ONE, 0.0, body, _ghost_pose(t))
	if hit >= 0.0 and hit < 0.35:
		var k := 1.0 - hit / 0.35
		draw_arc(p, 20.0 + (1.0 - k) * 26.0, 0.0, TAU, 32, Color(COLOR, k * fade), 3.0, true)
