class_name MechanicGuide
extends CanvasLayer
## 機關說明頁：選關畫面按 H／Tab 打開，←→ 換頁，Esc／H／Tab 關閉。
## 每張卡片上方放真的機關跟著音樂動（沒有玩家所以不會發出提示音），
## 休止、盲拍、加速、音浪這些範圍很大的機制改用小動畫示意。

signal closed

const CARD := Vector2(380, 252)
const PREVIEW_H := 140.0
const GAP := 22.0
const COLS := 3
const FLOOR_Y := 128.0
const REST_COLOR := Color(1.0, 0.4, 0.45)
const ORB_COLOR := Color(1.0, 0.78, 0.35)
## 長按平行音符每 1.5 拍一顆，每顆比前一顆高一點點（和遊戲裡的物理相同）
const LONG_ORBS: Array[Vector2] = [Vector2(60, 106), Vector2(190, 98), Vector2(320, 90)]
const LONG_BEATS := 1.5
const LONG_PEAK := 64.0
const SHORT_ORBS: Array[Vector2] = [Vector2(80, 100), Vector2(135, 100), Vector2(190, 100), Vector2(245, 100), Vector2(300, 100)]
const SHORT_BEATS := 0.5
const SHORT_PEAK := 16.0

const PAGES: Array[Dictionary] = [
	{"title": "基本操作", "cards": [
		{"id": "jump", "name": "跳躍：輕點／長按", "keys": "空白鍵",
			"desc": "輕點是小跳（約 1 格高）；按住一下、聽到延音就是大跳（約 4 格高），之後放開也沒關係。"},
		{"id": "dash", "name": "衝刺", "keys": "C 或 Shift",
			"desc": "按 C 或 Shift 往前快速衝約 4 格，空中也能衝一次；落地、碰到音符或衝刺環才補回。兩種鍵效果相同。"},
		{"id": "beat", "name": "跟著拍子", "keys": "",
			"desc": "所有機關都跟著鼓聲動。畫面下方的節拍條和背景的閃光就是拍點，跟著鼓聲按就對了。"},
		{"id": "flag", "name": "起跳旗", "keys": "↑ 看示範",
			"desc": "每 8 拍響一次鈴，旗子上倒數 3、2、1，GO! 就出發。站在旗子旁按 ↑ 先看示範。"},
		{"id": "bench", "name": "長椅", "keys": "R 重來",
			"desc": "存檔點。碰到任何機關都會直接倒下，回到最後坐過的長椅。"},
		{"id": "goal", "name": "終點", "keys": "",
			"desc": "走進門就通關，會記下通關時間和死亡次數。"},
	]},
	{"title": "節奏地形", "cards": [
		{"id": "beat_platform", "name": "節拍平台", "keys": "",
			"desc": "黃、藍兩組平台輪流出現，交接的拍點上兩組都在，要在拍點上跳到另一組。"},
		{"id": "mover", "name": "移動平台", "keys": "",
			"desc": "每一拍「喀」地往前移一步，走到底再折返。"},
		{"id": "melody", "name": "旋律平台", "keys": "",
			"desc": "照節奏一塊接一塊亮起，亮起時響一個音；照著旋律跳過去，不能停下來等。"},
		{"id": "pad", "name": "節拍鼓", "keys": "",
			"desc": "站在上面時，每一拍的鼓點會把你彈得非常高。"},
		{"id": "lift", "name": "升降舞台", "keys": "",
			"desc": "每一拍升高一階、響一個音，升到頂再降回去；終點前的舞台就是它。"},
	]},
	{"title": "危險機關", "cards": [
		{"id": "spike", "name": "尖刺", "keys": "",
			"desc": "固定不動，碰到就倒下。"},
		{"id": "pattern_spike", "name": "節奏尖刺", "keys": "",
			"desc": "地板的在指定拍彈出，那一拍跳起來躲；天花板的在指定拍落下，那一拍不能跳。"},
		{"id": "hopper", "name": "節拍甲蟲", "keys": "",
			"desc": "每一拍跳一下、左右巡邏，打不倒，抓準牠的節奏跳過去。"},
		{"id": "piston", "name": "活塞", "keys": "C／Shift",
			"desc": "在指定拍猛力砸下、再慢慢升回。在正拍按 C 或 Shift 衝刺穿過去，用走的太慢會被砸到。"},
		{"id": "laser", "name": "雷射", "keys": "",
			"desc": "發射前一拍瞄準線會越來越亮。輕點音符頭上常有雷射，按成長按就會撞上。"},
	]},
	{"title": "節奏按鍵", "cards": [
		{"id": "orb", "name": "節奏音符", "keys": "空中按跳",
			"desc": "外圈縮到音符上的那一拍，在空中碰著它按跳，就能再跳一次並補回空中衝刺。"},
		{"id": "long_parallel", "name": "長按平行音符", "keys": "每 1.5 拍長按",
			"desc": "間隔很寬的一排音符：每 1.5 拍長按一顆，大跳的弧線剛好落回差不多的高度。"},
		{"id": "parallel", "name": "短按平行音符", "keys": "每半拍輕點",
			"desc": "擠在一起的一排音符：每半拍輕點一顆，小跳彈起又落回同一高度，平平地飛過去。"},
		{"id": "stairs", "name": "上樓／下樓", "keys": "",
			"desc": "每拍長按一顆音符往上爬約 4 格；每拍輕點一顆往下走約 4 格。"},
		{"id": "ring", "name": "衝刺環", "keys": "C／Shift",
			"desc": "亮起的那一拍按 C 或 Shift 衝刺穿過去，冷卻立刻清零、空中衝刺補回，下一拍能再衝。"},
		{"id": "gate", "name": "光牆", "keys": "C／Shift",
			"desc": "只有打開的那一拍按 C 或 Shift 衝刺能穿過去，其他時間連衝刺也過不去。"},
	]},
	{"title": "特殊段落", "cards": [
		{"id": "tempo", "name": "加速", "keys": "",
			"desc": "過了長椅會變快：音樂、機關、角色一起加速。同一段連招，只是越來越緊。"},
		{"id": "rest", "name": "休止區", "keys": "放開所有鍵",
			"desc": "紅色的休止拍（剛好一拍或兩拍）要站在地上完全不動；搶拍會錯音或直接倒下。"},
		{"id": "blind", "name": "盲拍區", "keys": "",
			"desc": "燈會跟著節奏熄滅，只剩角色周圍一圈光。亮著時記住地形，暗掉時聽聲音跑。"},
		{"id": "gravity", "name": "輕重力區", "keys": "",
			"desc": "淡藍光幕內重力變輕、滯空變長；機關混法和第四關類似，但飄的時候坑更寬。長椅會恢復正常重力。"},
	]},
]

var page: int = 0
var _bg: Control
var _font: Font
var _previews: Node2D
var _card_rects: Array[Rect2] = []
var _opened_frame: int = 0
var _bump: float = 0.0


func _ready() -> void:
	layer = 20
	_opened_frame = Engine.get_process_frames()
	_font = UiKit.font()
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg.draw.connect(_on_bg_draw)
	_build_page()


func _process(delta: float) -> void:
	_bump = move_toward(_bump, 0.0, delta * 4.0)
	_bg.queue_redraw()
	if Engine.get_process_frames() == _opened_frame:
		return
	if Input.is_action_just_pressed("back") or Input.is_action_just_pressed("guide"):
		GameState.play_sfx("pluck", GameState.next_note() - 12.0, -6.0)
		closed.emit()
		queue_free()
		return
	var step := 0
	if Input.is_action_just_pressed("move_left"):
		step = -1
	elif Input.is_action_just_pressed("move_right"):
		step = 1
	if step != 0:
		var next := clampi(page + step, 0, PAGES.size() - 1)
		if next != page:
			page = next
			_bump = 1.0
			GameState.play_sfx("pluck", GameState.next_note(), -6.0)
			_build_page()


func _build_page() -> void:
	if _previews:
		_previews.queue_free()
	_previews = Node2D.new()
	add_child(_previews)
	_card_rects.clear()
	var size := get_viewport().get_visible_rect().size
	var cards: Array = PAGES[page]["cards"]
	var total_w := COLS * CARD.x + (COLS - 1) * GAP
	var x0 := (size.x - total_w) * 0.5
	var y0 := maxf(140.0, (size.y - (2.0 * CARD.y + GAP)) * 0.5 + 20.0)
	for i in cards.size():
		var row := floorf(i / float(COLS))
		var rect := Rect2(Vector2(x0 + (i % COLS) * (CARD.x + GAP), y0 + row * (CARD.y + GAP)), CARD)
		_card_rects.append(rect)
		var root := Node2D.new()
		root.position = rect.position
		_previews.add_child(root)
		_build_preview(String(cards[i]["id"]), root)


# ───────────────────────── 每張卡片的預覽 ─────────────────────────

func _build_preview(id: String, root: Node2D) -> void:
	match id:
		"jump":
			_sketch(root, _paint_jump)
		"dash":
			_sketch(root, _paint_dash)
		"beat":
			_sketch(root, _paint_beat)
		"flag":
			_ground(root)
			var flag := CueFlag.new()
			flag.setup(Vector2(190, FLOOR_Y), "")
			root.add_child(flag)
		"bench":
			_ground(root)
			var cp := Checkpoint.new()
			cp.setup(Vector2(190, FLOOR_Y))
			root.add_child(cp)
		"goal":
			_ground(root)
			var goal := Goal.new()
			goal.setup(Vector2(190, FLOOR_Y))
			root.add_child(goal)
		"beat_platform":
			for i in 2:
				var bp := BeatPlatform.new()
				bp.setup(Vector2(50 + i * 160, 80 - i * 24), 120, i)
				root.add_child(bp)
		"mover":
			var mv := BeatMover.new()
			mv.setup(Vector2(40, 80), 120, Vector2(180, 0), 0)
			root.add_child(mv)
		"melody":
			for i in 4:
				var notes := ".".repeat(i * 2) + "x" + ".".repeat(7 - i * 2)
				var pf := PatternPlatform.new()
				pf.setup(Vector2(30 + i * 85, 100 - i * 20), 70, notes, float(i * 4))
				root.add_child(pf)
		"pad":
			_ground(root)
			var pad := BeatPad.new()
			pad.setup(Vector2(150, FLOOR_Y - 40), 80, 40)
			root.add_child(pad)
		"lift":
			_ground(root)
			var lift := PatternLift.new()
			lift.setup(Vector2(130, FLOOR_Y - 16), 120, 96, "x.x.x.....v.....", 0.0)
			root.add_child(lift)
		"spike":
			_ground(root)
			for i in 3:
				var sp := Spike.new()
				sp.setup(Vector2(130 + i * 40, FLOOR_Y - 40), 40)
				root.add_child(sp)
		"pattern_spike":
			_ground(root)
			_sketch(root, _paint_ceiling)
			for i in 3:
				var floor_spike := PatternSpike.new()
				floor_spike.setup(Vector2(40 + i * 40, FLOOR_Y - 40), 40, "x...x...", false)
				root.add_child(floor_spike)
				var ceil_spike := PatternSpike.new()
				ceil_spike.setup(Vector2(220 + i * 40, 12), 40, "..x...x.", true)
				root.add_child(ceil_spike)
		"hopper":
			_ground(root)
			var en := BeatHopper.new()
			en.setup(Vector2(190, FLOOR_Y))
			root.add_child(en)
		"piston":
			_ground(root)
			var piston := PatternPiston.new()
			piston.setup(Vector2(150, 8), Vector2(80, FLOOR_Y - 8), "x.x.x.x.")
			root.add_child(piston)
		"laser":
			var laser := PatternLaser.new()
			laser.setup(Vector2(30, 70), 320, false, "x...x...")
			root.add_child(laser)
		"orb":
			var orb := RhythmOrb.new()
			orb.setup(Vector2(190, 75), "x.......")
			root.add_child(orb)
		"long_parallel":
			_sketch(root, _paint_long_arcs)
			for i in LONG_ORBS.size():
				var o := RhythmOrb.new()
				o.setup(LONG_ORBS[i], ".".repeat(i * 3) + "x" + ".".repeat(15 - i * 3), 12.0 + i * 4.0)
				root.add_child(o)
		"parallel":
			_sketch(root, _paint_short_arcs)
			for i in SHORT_ORBS.size():
				var o := RhythmOrb.new()
				o.setup(SHORT_ORBS[i], ".".repeat(i) + "x" + ".".repeat(15 - i), 12.0 + i * 3.0)
				root.add_child(o)
		"stairs":
			var ys: Array[float] = [118.0, 78.0, 38.0, 78.0, 118.0]
			for i in ys.size():
				var o := RhythmOrb.new()
				o.setup(Vector2(50 + i * 70, ys[i]), ".".repeat(i * 2) + "x" + ".".repeat(15 - i * 2), 12.0 + i * 3.0)
				root.add_child(o)
			_sketch(root, _paint_stairs)
		"ring":
			for i in 3:
				var ring := DashRing.new()
				ring.setup(Vector2(100 + i * 90, 75), ".".repeat(i) + "x" + ".".repeat(7 - i))
				root.add_child(ring)
		"gate":
			_ground(root)
			var gate := BeatGate.new()
			gate.setup(Vector2(170, 8), 40, FLOOR_Y - 8, "x.......")
			root.add_child(gate)
		"tempo":
			_sketch(root, _paint_tempo)
		"rest":
			_sketch(root, _paint_rest)
		"blind":
			_sketch(root, _paint_blind)
		"gravity":
			_sketch(root, _paint_gravity)
		"wave":
			_sketch(root, _paint_wave)


class Sketch extends Node2D:
	var painter: Callable

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		painter.call(self)


func _sketch(root: Node2D, painter: Callable) -> void:
	var s := Sketch.new()
	s.painter = painter
	root.add_child(s)


func _ground(root: Node2D) -> void:
	_sketch(root, _paint_ground)


func _paint_ground(c: CanvasItem) -> void:
	c.draw_rect(Rect2(10, FLOOR_Y, CARD.x - 20, PREVIEW_H - FLOOR_Y - 2), Color(0.16, 0.16, 0.24))
	c.draw_rect(Rect2(10, FLOOR_Y, CARD.x - 20, 3), Color(GameState.color("edge"), 0.6))


func _paint_ceiling(c: CanvasItem) -> void:
	c.draw_rect(Rect2(200, 4, 160, 8), Color(0.16, 0.16, 0.24))


func _player(c: CanvasItem, feet: Vector2, alpha: float = 1.0, pose: String = "") -> void:
	if pose == "":
		pose = Player.idle_pose(Conductor.song_beat)
	Player.draw_skin(c, GameState.skin, feet, Vector2.ONE * 0.85, 0.0, Color(1, 1, 1, alpha), pose)


## 跳躍弧線上前段上升、中間最高點、後段下落
func _air_pose(t: float) -> String:
	if absf(t - 0.5) < 0.1:
		return "apex_0"
	return "jump_0" if t < 0.5 else "fall_0"


func _arc_points(x0: float, x1: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(Vector2(lerpf(x0, x1, t), FLOOR_Y - 4.0 * h * t * (1.0 - t)))
	return pts


## 第 0 拍輕點小跳、第 2 拍長按大跳，四拍一輪
func _paint_jump(c: CanvasItem) -> void:
	_paint_ground(c)
	var edge := GameState.color("edge")
	c.draw_polyline(_arc_points(50, 135, 26), Color(edge, 0.45), 2.0, true)
	c.draw_polyline(_arc_points(50, 330, 100), Color(ORB_COLOR, 0.45), 2.0, true)
	c.draw_string(_font, Vector2(78, FLOOR_Y - 34), "點", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(edge, 0.9))
	c.draw_string(_font, Vector2(180, FLOOR_Y - 106), "長", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ORB_COLOR, 0.9))
	var b := fposmod(Conductor.song_beat, 4.0)
	var feet := Vector2(50, FLOOR_Y)
	var pose := ""
	if b < 0.55:
		var t := b / 0.55
		feet = Vector2(lerpf(50, 135, t), FLOOR_Y - 104.0 * t * (1.0 - t))
		pose = _air_pose(t)
	elif b < 2.0:
		feet = Vector2(135, FLOOR_Y)
	elif b < 3.63:
		var t := (b - 2.0) / 1.63
		feet = Vector2(lerpf(50, 330, t), FLOOR_Y - 400.0 * t * (1.0 - t))
		pose = _air_pose(t)
	else:
		feet = Vector2(330, FLOOR_Y)
	_player(c, feet, 1.0, pose)


func _paint_dash(c: CanvasItem) -> void:
	_paint_ground(c)
	var b := fposmod(Conductor.song_beat, 2.0)
	var t := smoothstep(0.0, 0.4, b)
	var x := lerpf(70, 290, t)
	if b < 0.6:
		var a := 1.0 - b / 0.6
		for i in 4:
			var y := FLOOR_Y - 12.0 - i * 9.0
			c.draw_line(Vector2(maxf(70, x - 120 + i * 14), y), Vector2(x - 16, y), Color(1, 1, 1, 0.5 * a), 3.0)
	var alpha := 1.0 if b < 1.6 else 1.0 - (b - 1.6) / 0.4
	var pose := ""
	if b < 0.4:
		pose = "dash_0" if b < 0.08 else ("dash_1" if b < 0.32 else "dash_2")
	_player(c, Vector2(x, FLOOR_Y), alpha, pose)


func _paint_beat(c: CanvasItem) -> void:
	var edge := GameState.color("edge")
	var b := Conductor.song_beat
	var y := 70.0
	c.draw_line(Vector2(30, y), Vector2(350, y), Color(1, 1, 1, 0.3), 2.0)
	for i in 5:
		var x := 30.0 + i * 80.0
		var hit := 1.0 - clampf(absf(fposmod(b, 4.0) - i) * 3.0, 0.0, 1.0)
		c.draw_line(Vector2(x, y - 16 - hit * 8), Vector2(x, y + 16 + hit * 8), Color(edge, 0.5 + 0.5 * hit), 3.0 + hit * 2.0)
		if i < 4:
			c.draw_string(_font, Vector2(x - 6, y + 46), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5 + 0.5 * hit))
	var cx := 30.0 + fposmod(b, 4.0) * 80.0
	c.draw_circle(Vector2(cx, y), 9.0 + Conductor.pulse(6.0) * 5.0, Color(edge, 0.9))


func _paint_long_arcs(c: CanvasItem) -> void:
	_paint_orb_arcs(c, LONG_ORBS, LONG_BEATS, LONG_PEAK, "長", ORB_COLOR)


func _paint_short_arcs(c: CanvasItem) -> void:
	_paint_orb_arcs(c, SHORT_ORBS, SHORT_BEATS, SHORT_PEAK, "點", GameState.color("edge").lerp(Color.WHITE, 0.3))


## 音符之間畫出角色飛過去的弧線，角色在 8 拍循環開頭照節奏沿著弧線飛一遍
func _paint_orb_arcs(c: CanvasItem, orbs: Array[Vector2], beats: float, peak: float, label: String, col: Color) -> void:
	for i in orbs.size() - 1:
		c.draw_polyline(_orb_arc(orbs[i], orbs[i + 1], peak), Color(col, 0.4), 2.0, true)
		var mid := (orbs[i] + orbs[i + 1]) * 0.5 - Vector2(6, peak + 8)
		c.draw_string(_font, mid, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col, 0.9))
	var b := fposmod(Conductor.song_beat, 8.0)
	var seg := floori(b / beats)
	if seg >= orbs.size() - 1:
		return
	var t := fposmod(b, beats) / beats
	var a := orbs[seg]
	var d := orbs[seg + 1]
	var center := a.lerp(d, t) - Vector2(0, 4.0 * peak * t * (1.0 - t))
	var pose := "orb_1" if t < 0.25 else _air_pose(t)
	Player.draw_skin(c, GameState.skin, center + Vector2(0, 13), Vector2.ONE * 0.6, 0.0, Color.WHITE, pose)


func _orb_arc(a: Vector2, d: Vector2, peak: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		pts.append(a.lerp(d, t) - Vector2(0, 4.0 * peak * t * (1.0 - t)))
	return pts


func _paint_stairs(c: CanvasItem) -> void:
	var edge := GameState.color("edge")
	c.draw_string(_font, Vector2(56, 66), "長 ↗", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ORB_COLOR, 0.95))
	c.draw_string(_font, Vector2(290, 66), "↘ 點", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(edge.lerp(Color.WHITE, 0.3), 0.95))


func _paint_tempo(c: CanvasItem) -> void:
	var edge := GameState.color("edge")
	var b := Conductor.song_beat
	var bpms: Array[float] = [120.0, 135.0, 150.0]
	for i in 3:
		var base := Vector2(80 + i * 110, 118)
		var k: float = bpms[i] / 120.0
		var ang := 0.55 * sin(b * PI * k)
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-26, 0), base + Vector2(26, 0), base + Vector2(10, -82), base + Vector2(-10, -82)]),
			Color(0.2, 0.18, 0.28))
		var tip := base + Vector2(0, -12) + Vector2(sin(ang), -cos(ang)) * 70.0
		c.draw_line(base + Vector2(0, -12), tip, Color(edge.lerp(Color.WHITE, 0.3), 0.9), 3.0)
		c.draw_circle(base + Vector2(0, -12) + Vector2(sin(ang), -cos(ang)) * 44.0, 5.0, ORB_COLOR)
		c.draw_string(_font, base + Vector2(-30, 20), "BPM %d" % int(bpms[i]), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(1, 1, 1, 0.75))


## 8 拍一輪，第 2～3 拍和第 6 拍是休止：角色在休止拍停下、頭上出現暫停符號
func _paint_rest(c: CanvasItem) -> void:
	var b := fposmod(Conductor.song_beat, 8.0)
	var rests := [2, 3, 6]
	for i in 8:
		var r := Rect2(30 + i * 40, 104, 36, 14)
		var col := REST_COLOR if i in rests else Color(1, 1, 1, 0.25)
		var now := floori(b) == i
		c.draw_rect(r, Color(col, 0.9 if now else 0.45))
	c.draw_rect(Rect2(30 + b * 40, 100, 3, 22), Color.WHITE)
	var moved := 0.0
	for i in 8:
		if not (i in rests):
			moved += clampf(b - i, 0.0, 1.0)
	var feet := Vector2(50 + moved * 50, 90)
	c.draw_rect(Rect2(20, 90, 340, 3), Color(1, 1, 1, 0.3))
	_player(c, feet)
	if floori(b) in rests:
		var head := feet + Vector2(0, -60)
		c.draw_rect(Rect2(head + Vector2(-8, -9), Vector2(5, 18)), REST_COLOR)
		c.draw_rect(Rect2(head + Vector2(3, -9), Vector2(5, 18)), REST_COLOR)


## 淡藍光幕＋上浮粒子，示意單一輕重力
func _paint_gravity(c: CanvasItem) -> void:
	var b := Conductor.song_beat
	var lit := 0.7
	var col := Color(UiKit.FLOAT, 0.12 + 0.2 * lit)
	c.draw_rect(Rect2(40, 8, 300, FLOOR_Y - 8), col)
	c.draw_line(Vector2(40, 8), Vector2(40, FLOOR_Y), Color(UiKit.FLOAT, 0.5 + 0.4 * lit), 2.0)
	c.draw_line(Vector2(340, 8), Vector2(340, FLOOR_Y), Color(UiKit.FLOAT, 0.5 + 0.4 * lit), 2.0)
	for k in 8:
		var t := fposmod(b * (0.5 + lit) + k * 0.18, 1.0)
		var y := lerpf(FLOOR_Y - 6.0, 16.0, t)
		c.draw_circle(Vector2(70.0 + k * 32.0, y), 2.0 + 2.0 * lit, Color(UiKit.FLOAT, 0.25 + 0.55 * lit * sin(t * PI)))
	c.draw_string(_font, Vector2(150, FLOOR_Y + 18), "輕重力", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiKit.FLOAT, 0.95))
	c.draw_rect(Rect2(10, FLOOR_Y, CARD.x - 20, 3), Color(UiKit.FLOAT, 0.55))
	var hop := -absf(sin(b * PI * 0.5)) * 36.0
	_player(c, Vector2(190, FLOOR_Y + hop))


## 後半拍暗掉，只剩角色周圍一圈光
func _paint_blind(c: CanvasItem) -> void:
	var edge := GameState.color("edge")
	var b := fposmod(Conductor.song_beat, 4.0)
	var x := 40.0 + b / 4.0 * 300.0
	c.draw_rect(Rect2(10, FLOOR_Y, CARD.x - 20, 3), Color(edge, 0.6))
	for i in 3:
		c.draw_circle(Vector2(110 + i * 90, 60), 10.0, ORB_COLOR)
	_player(c, Vector2(x, FLOOR_Y))
	var dark := smoothstep(1.8, 2.1, b) * (1.0 - smoothstep(3.8, 4.0, b))
	if dark <= 0.0:
		return
	var col := Color(0.01, 0.01, 0.03, 0.95 * dark)
	var hole := Rect2(x - 34, FLOOR_Y - 70, 68, 80)
	var area := Rect2(4, 4, CARD.x - 8, PREVIEW_H - 4)
	c.draw_rect(Rect2(area.position, Vector2(hole.position.x - area.position.x, area.size.y)), col)
	c.draw_rect(Rect2(Vector2(hole.end.x, area.position.y), Vector2(area.end.x - hole.end.x, area.size.y)), col)
	c.draw_rect(Rect2(Vector2(hole.position.x, area.position.y), Vector2(hole.size.x, hole.position.y - area.position.y)), col)
	c.draw_rect(Rect2(Vector2(hole.position.x, hole.end.y), Vector2(hole.size.x, area.end.y - hole.end.y)), col)
	c.draw_arc(hole.get_center(), 52.0, 0.0, TAU, 40, col, 30.0)


## 音浪每一拍往前推進一段
func _paint_wave(c: CanvasItem) -> void:
	_paint_ground(c)
	var b := fposmod(Conductor.song_beat, 8.0)
	var step := floorf(b)
	var front := 20.0 + (step + smoothstep(0.0, 0.3, b - step)) * 34.0
	var col := Color(1.0, 0.35, 0.5)
	var pts := PackedVector2Array([Vector2(10, FLOOR_Y), Vector2(10, 12)])
	for i in 9:
		var y := 12.0 + i * (FLOOR_Y - 12.0) / 8.0
		pts.append(Vector2(front + (8.0 if i % 2 == 0 else -6.0) + sin(Conductor.song_beat * 6.0 + i) * 3.0, y))
	c.draw_colored_polygon(pts, Color(col, 0.35))
	c.draw_polyline(pts.slice(2), Color(col, 0.9), 3.0, true)
	_player(c, Vector2(minf(front + 70.0, 350.0), FLOOR_Y))


# ───────────────────────── 背景、卡片框與文字 ─────────────────────────

func _on_bg_draw() -> void:
	var size := _bg.size
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(6.0)
	_bg.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06, 0.97))
	_bg.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, 130), Vector2(0, 130)]),
		PackedColorArray([Color(edge, 0.12), Color(edge, 0.12), Color(edge, 0), Color(edge, 0)]))

	var title := "機關說明"
	var tw := UiKit.width_of(title, 38, UiKit.title_font())
	UiKit.bold_text(_bg, Vector2(size.x * 0.5 - tw * 0.5, 58), -1, title, 38, Color.WHITE, edge)
	UiKit.text(_bg, Vector2(size.x * 0.5 + tw * 0.5 + 14, 50 - pulse * 4.0), -1, "♪", 26, Color(edge, 0.8))

	var tab_w := 140.0
	var tabs_x := (size.x - tab_w * PAGES.size()) * 0.5
	for i in PAGES.size():
		var r := Rect2(tabs_x + i * tab_w + 5, 80, tab_w - 10, 34)
		var on := i == page
		var pts := UiKit.chamfer(r.grow(2.0 * _bump) if on else r, 8.0)
		if on:
			_bg.draw_colored_polygon(pts, edge)
		else:
			_bg.draw_colored_polygon(pts, Color(1, 1, 1, 0.06))
			pts.append(pts[0])
			_bg.draw_polyline(pts, Color(1, 1, 1, 0.18), 1.0, true)
		_bg.draw_string(_font, r.position + Vector2(0, 23), String(PAGES[i]["title"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17,
			UiKit.INK if on else Color(1, 1, 1, 0.55))
	if page > 0:
		UiKit.keycap(_bg, Vector2(tabs_x - 34, 85), "←", edge, 0.8)
	if page < PAGES.size() - 1:
		UiKit.keycap(_bg, Vector2(tabs_x + tab_w * PAGES.size() + 10, 85), "→", edge, 0.8)

	var cards: Array = PAGES[page]["cards"]
	for i in mini(cards.size(), _card_rects.size()):
		_draw_card(_card_rects[i], cards[i], edge)

	UiKit.key_hints(_bg, size.x * 0.5, size.y - 34, [[["←", "→"], "換頁"], [["Esc", "H"], "關閉"]], edge, 0.85)


func _draw_card(rect: Rect2, info: Dictionary, edge: Color) -> void:
	UiKit.panel(_bg, rect, edge, 0.0, 1.0, 14.0, Color(0.05, 0.05, 0.11, 0.96))
	var shot := UiKit.chamfer(Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2, PREVIEW_H)), 13.0)
	shot.remove_at(3)
	shot.set(2, Vector2(rect.end.x - 1, rect.position.y + PREVIEW_H + 1))
	_bg.draw_colored_polygon(shot, Color(0.08, 0.09, 0.17))
	_bg.draw_line(Vector2(rect.position.x + 1, rect.position.y + PREVIEW_H + 1), Vector2(rect.end.x - 1, rect.position.y + PREVIEW_H + 1),
		Color(edge, 0.35), 1.0)
	var x := rect.position.x + 18.0
	var w := rect.size.x - 36.0
	var y := rect.position.y + PREVIEW_H
	_bg.draw_rect(Rect2(x, y + 15, 4, 20), edge)
	UiKit.text(_bg, Vector2(x + 12, y + 32), w, String(info["name"]), 20, Color.WHITE)
	var keys := String(info.get("keys", ""))
	if not keys.is_empty():
		var kw := UiKit.width_of(keys, 13) + 14.0
		UiKit.keycap(_bg, Vector2(rect.end.x - 18.0 - kw, y + 13), keys, edge)
	_bg.draw_multiline_string(_font, Vector2(x, y + 60), String(info["desc"]), HORIZONTAL_ALIGNMENT_LEFT,
		w, 15, 3, Color(1, 1, 1, 0.8))
