class_name CueFlag
extends Node2D
## 起跳旗：插在段落起點的懸崖邊。
## 平常只當節拍器：每 8 拍響一次鈴（前三拍木魚倒數，旗子上跳出 3、2、1，響鈴時 GO!），挑任何一次鈴聲出發都行。
## GO 鈴在小節頭（連招第 0 拍）的前 GO_LEAD 拍響：GO 之後先往前走一拍，第一個動作才落在小節頭。
## 站在旗子旁按「上」才看示範：下一個 8 拍循環開頭，旗子把這段連招彈一遍，
## 鏡頭跟著半透明的示範角色把整段跑完，再飛回玩家；一樣倒數 3、2、1，
## 示範結束後留時間返回玩家，再對齊八拍循環響鈴換玩家跑（機關都是 8 拍循環，所以響鈴時剛好對上）。
## demo 一格 = 半拍，從示範第 0 拍開始寫：T 點、L 長、o 音符點、O 音符長、D 衝、R 環衝、- 休止開始（要站著不動）、. 空。

enum State { FREE, WATCH }

const COLOR := Color(1.0, 0.78, 0.35)
## 起跳旗圖；FLAG_POLE_X = 旗桿在圖裡的橫向位置（比例），旗桿對準旗子的原點
const FLAG_TEX := preload("res://assets/ui/cue_flag.png")
const FLAG_POLE_X := 0.18
const GHOST_COLOR := Color(0.75, 0.9, 1.0)
## ghost 相鄰兩點間隔幾拍（由關卡產生器的物理模擬取樣）
const GHOST_STEP := 0.125
const GO_BEATS := 16.0
## 玩家腳下離旗子這個範圍內（px）按「上」可以看示範
const TRIGGER_BEHIND := 70.0
const TRIGGER_AHEAD := 30.0
const CYCLE_BEATS := 8.0
## GO 比連招第 0 拍早幾拍（出發後至少先走這麼久才需要按）
const GO_LEAD := 1.0

var demo: String = ""
## demo 一拍切幾格（預設 2 = 半拍；有三連音的段落用 6）
var demo_sub: int = 2
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
## 自動跑：在這面旗子等候的目標 GO 拍；-1 表示沒在等
var _auto_go_at: float = -1.0
var _auto_waiting: bool = false
## GO 出發後要先離開旗子旁，才會再在這面旗停一次
var _auto_can_stop: bool = true
var _last_player_x: float = -INF
## 最近一次放玩家出發的連招第 0 拍（停下倒數或直接通過都算；測試機器人用來對拍）
var last_sync_beat: float = -INF
## 這面旗子多久可以放行一次（拍）：段落裡的機關若是 4 拍一輪（tools/campaign.py 會折成 4 拍），GO 就每 4 拍一次
var cycle_beats: float = CYCLE_BEATS
## 設計時連招第 0 拍落在 8 拍小節的第幾拍（關卡產生器算的；-1 = 沒有）。重生時對齊它，後面 8 拍一輪的段落才不會差半小節
var phase8: float = -1.0


func setup(feet: Vector2, demo_pattern: String) -> void:
	position = feet
	demo = demo_pattern


func _ready() -> void:
	z_index = 3


func has_demo() -> bool:
	return demo != ""


func go_beat() -> float:
	# 長譜面先完整示範，再留出鏡頭返回與倒數時間；仍對齊八拍循環。
	var demo_beats := maxf(demo.length() / float(demo_sub), ghost_end())
	return start_beat + maxf(GO_BEATS, ceilf((demo_beats + 2.0) / CYCLE_BEATS) * CYCLE_BEATS)


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
## 示範固定用完整幀循環，不受低畫質 player_frames 定格影響
func _ghost_pose(t: float) -> String:
	if t >= ghost_end():
		return _demo_cycle_pose("idle", Conductor.song_beat)
	var i := clampi(floori(t / GHOST_STEP), 0, ghost.size() - 2)
	var v := (ghost[i + 1] - ghost[i]) / GHOST_STEP
	if absf(v.x) > 230.0:
		return "dash_1"
	if absf(v.y) < 0.5:
		return _demo_cycle_pose("run", start_beat + t)
	if absf(v.y) < Player.APEX_SPEED * Conductor.sec_per_beat:
		return "apex_0"
	return "jump_0" if v.y < 0.0 else "fall_0"


func _demo_cycle_pose(prefix: String, beat: float) -> String:
	return "%s_%d" % [prefix, mini(floori(fposmod(beat, 1.0) * 6.0), 5)]


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
	_counting = move_toward(_counting, 1.0 if state == State.WATCH or _auto_waiting or _in_start_zone(p) else 0.0, delta * 4.0)
	match state:
		State.FREE:
			if near and Input.is_action_just_pressed("up"):
				_clear_auto_wait(p)
				state = State.WATCH
				start_beat = ceilf((b + 1.0) / 8.0) * 8.0
				_demo_step = 0
				_last_slot = floori((b - start_beat) * float(demo_sub))
				p.watching = true
				p.watch_x = _start_x() if p.auto_running else position.x
			else:
				_tick_auto_flag(b, p, near)
				_tick_metronome(b, p)
		State.WATCH:
			# 響鈴前一點點就放開操作，剛好在鈴聲上按的跳才不會被吃掉；
			# 自動跑時在 GO 前半拍從起跑點出發（和模擬一致），不再多等一輪
			if p.auto_running and p.watching and b + 0.004 >= go_beat() - LEAD_BEATS:
				p.watching = false
				_auto_can_stop = false
			elif not p.auto_running and b >= go_beat() - 0.25:
				p.watching = false
			_tick_sounds(b)
			if b >= go_beat():
				state = State.FREE
				_last_slot = floori(b * 2.0)


func _tick_sounds(b: float) -> void:
	var s := floori((b - start_beat) * float(demo_sub))
	if s == _last_slot:
		return
	_last_slot = s
	var go := roundi((go_beat() - start_beat) * float(demo_sub))
	if s >= 0 and s < demo.length() and s < go and demo[s] != ".":
		_play_demo(demo[s])
	var lead := roundi(GO_LEAD * float(demo_sub))
	if s == go - lead:
		GameState.play_cue("cue", 0.0, -6.0)
		GameState.reset_notes()
	elif s == go - lead - 3 * demo_sub or s == go - lead - 2 * demo_sub or s == go - lead - demo_sub:
		GameState.play_cue("block", 0.0, -8.0)


## 起跑區：段落左端到旗子右邊一點、還能操作的時候（節拍器只在這裡響）
func _in_start_zone(p: Player) -> bool:
	var x := p.global_position.x
	return not p.control_locked and x >= section_from and x <= position.x + 60.0


## 關卡產生器的模擬在連招第 -0.5 拍位於段落左端 140px、往右跑（tools/gen_level3.py 的 START，跑速 155px／拍）。
## 自動跑往回推一拍：停在 140 - 77.5 = 62.5，GO 鈴（第 -1 拍）一響就出發，走一拍後剛好對上模擬的位置
const START_X := 62.5
## 自動前進時旗子插在起跑點右邊這麼遠（main.gd 擺放）
const BESIDE_PLAYER := 34.0
## 無縫接軌：關卡產生器把段落間的平地算成「照節奏跑剛好在 GO 拍或略早一點到」，跑速不調整；
## 剛好對上就直接通過，略早就停一下馬上 GO，差太多才會等到下一個 cycle_beats。
## 到起跑點時離 GO 拍差多少以內就直接通過
const PASS_TOLERANCE := 0.07
## 一拍跑多遠（px）：跑速 310 × 半秒
const RUN_PER_BEAT := 155.0
const LEAD_BEATS := GO_LEAD


## 自動跑：跑到起跑點停住等 3、2、1，GO 一響自動出發，先走一拍才到第一個動作（不用自己抓助跑）
func _tick_auto_flag(b: float, p: Player, _near: bool) -> void:
	if not p.auto_running:
		_clear_auto_wait(p)
		_auto_can_stop = true
		return
	## 出發後跑過旗子、回到段落左邊、倒下或被傳送（重生在長椅），下次經過才會再停
	var x := p.global_position.x
	var teleported := absf(x - _last_player_x) > 80.0
	_last_player_x = x
	if p.control_locked or teleported:
		_clear_auto_wait(p)
		_auto_can_stop = true
	if x > position.x + TRIGGER_AHEAD + 40.0 or x < section_from:
		_auto_can_stop = true
	var sx := _start_x()
	## 跑到起跑點：剛好在 GO 拍就直接通過，否則停下倒數
	var arrive := p.is_on_floor() and not p.control_locked and x >= sx - 6.0 and x < position.x + TRIGGER_AHEAD
	var phase := fposmod(b + LEAD_BEATS, cycle_beats)
	if not _auto_waiting and arrive and _auto_can_stop and not p.rest_after_respawn \
			and (phase < PASS_TOLERANCE or phase > cycle_beats - PASS_TOLERANCE):
		_auto_can_stop = false
		last_sync_beat = roundf((b + LEAD_BEATS) / cycle_beats) * cycle_beats
		GameState.play_cue("cue", 0.0, -6.0)
		GameState.reset_notes()
		return
	if not _auto_waiting and arrive and _auto_can_stop:
		_auto_waiting = true
		_auto_can_stop = false
		## 至少留出完整倒數：離下一個小節頭太近就等再下一輪
		## 不再為了湊滿 3、2、1 多等一整輪：最近一個來得及的小節頭就出發，倒數從現在一路數到 0
		## 最近一個來得及的小節頭就出發：在旗子前最多等一輪（4 拍）。
		## 重生後一樣只等最近的一輪（rest_after_respawn 只保證會停下來倒數、不會直接衝過去）；
		## 反應時間改由長椅離旗子比較遠來給（tools/campaign.py _bench_chunk）
		var rest := 0.02
		_auto_go_at = ceilf((b + rest + LEAD_BEATS) / cycle_beats) * cycle_beats
		p.auto_flag_wait = true
		p.watch_x = _start_x()
	if not _auto_waiting:
		return
	p.auto_flag_wait = true
	p.watch_x = _start_x()
	if b + 0.004 >= _auto_go_at - LEAD_BEATS:
		## GO 當下解除等候並保持自動跑，不要求站在旗心或先起跳
		last_sync_beat = _auto_go_at
		_clear_auto_wait(p)
		_auto_can_stop = false
		p.auto_running = true
		p.rest_after_respawn = false


func _start_x() -> float:
	return minf(section_from + START_X, position.x)


func _clear_auto_wait(p: Player) -> void:
	_auto_waiting = false
	_auto_go_at = -1.0
	if p:
		p.auto_flag_wait = false


func _tick_metronome(b: float, p: Player) -> void:
	var s := floori(b * 2.0)
	if s == _last_slot:
		return
	_last_slot = s
	if not _in_start_zone(p) and not _auto_waiting:
		return
	var slot := posmod(s + roundi(GO_LEAD * 2.0), roundi(cycle_beats * 2.0))
	if slot == 0:
		GameState.play_cue("cue", 0.0, -6.0)
		GameState.reset_notes()
	else:
		var n := roundi(cycle_beats * 2.0)
		if slot == n - 6 or slot == n - 4 or slot == n - 2:
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
		until = go_beat() - GO_LEAD - b
	elif state == State.FREE:
		if _auto_waiting and _auto_go_at >= 0.0:
			until = _auto_go_at - GO_LEAD - b
			since = INF
		else:
			until = ceilf((b + GO_LEAD) / cycle_beats) * cycle_beats - GO_LEAD - b
			since = b + GO_LEAD - floorf((b + GO_LEAD) / cycle_beats) * cycle_beats
	var fill := 0.25
	if until <= 2.0:
		fill = lerpf(0.5, 1.0, 1.0 - until / 2.0)
	elif state == State.WATCH:
		fill = 0.5
	var flash := clampf(1.0 - since * 3.0, 0.0, 1.0)
	## 旗子圖（手繪）：平常暗一點，倒數越接近越亮，GO 那下閃白
	var fh := 68.0
	var fw := fh * float(FLAG_TEX.get_width()) / float(FLAG_TEX.get_height())
	var tint := Color(1, 1, 1).darkened(0.4 * (1.0 - fill)).lerp(Color(1.6, 1.6, 1.6), flash)
	draw_texture_rect(FLAG_TEX, Rect2(-fw * FLAG_POLE_X, -fh, fw, fh), false, tint)
	_draw_countdown(until, since)
	if flash > 0.0:
		draw_arc(Vector2(0, -47), 20.0 + (1.0 - flash) * 24.0, 0.0, TAU, 32, Color(COLOR, flash), 3.0, true)
	if _prompt > 0.0:
		## 「↑ 示範」只在第一關提示，之後就不寫字了
		if GameState.level_index == 0 and not TouchControls.wanted():
			_draw_prompt()
	## 示範角色是關卡提示，不隨低畫質關掉（quality ghost 只影響其他裝飾）
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
	## 自動前進等候中：從停下來就開始倒數（最多 8），數到 0 就是 GO
	var max_count := 8.0 if _auto_waiting else 3.0
	if until > 0.0 and until <= max_count:
		label = str(ceili(until))
		age = ceilf(until) - until
	elif since < 0.75:
		label = "GO!"
		age = since
	if label == "":
		return
	var go := label == "GO!"
	var a := _counting * (clampf((0.75 - age) * 4.0, 0.0, 1.0) if go else 1.0)
	var lit := 4 if go else clampi(4 - ceili(until), 0, 4)
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
	var slot := mini(floori(t * float(demo_sub)), demo.length() - 1)
	var hit := -1.0
	for k in range(slot, -1, -1):
		if demo[k] != "." and demo[k] != "-":
			hit = t - k / float(demo_sub)
			break
	var p := to_local(_ghost_at(minf(t, ghost_end())))
	var body := Color(GHOST_COLOR, 0.55 * fade)
	Player.draw_skin(self, GameState.skin, p + Vector2(0, Player.BODY_SIZE.y * 0.5), Vector2.ONE, 0.0, body, _ghost_pose(t))
	if hit >= 0.0 and hit < 0.35:
		var k := 1.0 - hit / 0.35
		draw_arc(p, 20.0 + (1.0 - k) * 26.0, 0.0, TAU, 32, Color(COLOR, k * fade), 3.0, true)
