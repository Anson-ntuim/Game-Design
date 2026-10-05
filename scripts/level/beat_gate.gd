class_name BeatGate
extends StaticBody2D
## 節拍光牆：一律是實心的，只有在節奏型（notes）的 x 拍上按下的衝刺能穿過去，沒指定時每一拍都算。
## 判定看的是「按下衝刺的時間」（和衝刺環相同），由玩家在按衝刺時呼叫 accepts() 決定要不要穿過，
## 所以貼著光柱提早按、或按晚了，都會被擋下。
## 打開前一拍兩側光條往柱子收攏（像音符外圈縮小），判定窗內柱子變透明、出現往右的箭頭。

## 判定窗和音符、衝刺環相同，跟著選關畫面的難度（GameState.DIFFICULTIES）
const OPEN_COLOR := Color(0.35, 0.85, 1.0)
const CLOSED_COLOR := Color(0.45, 0.5, 0.75)
## 倒數光條從柱子中心幾 px 外開始收攏
const BRACKET_FROM := 64.0

var size: Vector2 = Vector2(40, 120)
var notes: String = "x.x.x.x."
var is_open: bool = true
var _reject_flash: float = 0.0
var _open_flash: float = 0.0
var _last_cue_slot: int = -1


func setup(top_left: Vector2, width: float, height: float, pattern: String = "x.x.x.x.") -> void:
	position = top_left
	size = Vector2(width, height)
	notes = pattern


func _ready() -> void:
	collision_layer = Player.LAYER_GATE | Player.LAYER_WORLD
	collision_mask = 0
	z_index = 4
	add_to_group("no_cling")
	add_to_group("beat_gate")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(size.x * 0.5, size.y)
	shape.shape = r
	shape.position = size * 0.5
	add_child(shape)
	is_open = accepts(Conductor.song_beat)


func reject() -> void:
	_reject_flash = 1.0


## 在 dash_beat 按下的衝刺能不能穿過這道光牆。
## 判定窗不超過兩次打開間隔的 40%：每拍都開的光柱在簡單難度下才不會一直開著、晚半拍衝也能過
func accepts(dash_beat: float) -> bool:
	var spb := Conductor.sec_per_beat
	var cap := _min_gap() * 0.4 * spb
	return BeatPattern.since_hit(notes, dash_beat) * spb <= minf(GameState.judge_late(), cap) \
		or BeatPattern.until_hit(notes, dash_beat) * spb <= minf(GameState.judge_early(), cap)


## 相鄰兩次打開相隔幾拍（循環）
func _min_gap() -> float:
	var hits: Array[int] = []
	for i in notes.length():
		if notes[i] == "x":
			hits.append(i)
	if hits.is_empty():
		return INF
	var gap := notes.length() - hits[-1] + hits[0]
	for k in range(1, hits.size()):
		gap = mini(gap, hits[k] - hits[k - 1])
	return gap * 0.5


## 判定窗比拍子早開，提示音和閃光要等到真正的拍點（半拍格）才發
func _physics_process(_delta: float) -> void:
	is_open = accepts(Conductor.song_beat)
	var s := floori(Conductor.song_beat * 2.0)
	if s != _last_cue_slot and notes[posmod(s, notes.length())] == "x":
		_last_cue_slot = s
		_open_flash = 1.0
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("cue", 0.0, -10.0)


func _process(delta: float) -> void:
	_reject_flash = maxf(0.0, _reject_flash - delta * 3.0)
	_open_flash = maxf(0.0, _open_flash - delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var cx := size.x * 0.5
	var b := Conductor.song_beat
	if is_open:
		_draw_open(cx, b)
	else:
		_draw_closed(cx, b)
	# 打開前一拍：兩側的光條往柱子收攏，收到柱子上那一刻就是拍子
	var until := BeatPattern.until_hit(notes, b)
	if until < 1.0:
		var t := 1.0 - until
		var d := lerpf(BRACKET_FROM, 13.0, t * t)
		var col := Color(OPEN_COLOR.lerp(Color.WHITE, 0.5 * t), 0.2 + 0.75 * t)
		for side: float in [-1.0, 1.0]:
			var x := cx + side * d
			draw_line(Vector2(x, 0), Vector2(x, size.y), col, 3.0)
			draw_line(Vector2(x, 1.5), Vector2(x - side * 9.0, 1.5), col, 3.0)
			draw_line(Vector2(x, size.y - 1.5), Vector2(x - side * 9.0, size.y - 1.5), col, 3.0)
	var cap := Color(0.85, 0.95, 1.0) if is_open else Color(0.55, 0.6, 0.8)
	draw_rect(Rect2(cx - 14, 0, 28, 4), cap)
	draw_rect(Rect2(cx - 14, size.y - 4, 28, 4), cap)


func _draw_closed(cx: float, b: float) -> void:
	var until := BeatPattern.until_hit(notes, b)
	var t := clampf(1.0 - until, 0.0, 1.0)
	var base := CLOSED_COLOR.lerp(OPEN_COLOR, t).lerp(Color(1.0, 0.35, 0.4), _reject_flash)
	draw_rect(Rect2(cx - 10, 0, 20, size.y), Color(base, 0.28 + 0.2 * t))
	draw_rect(Rect2(cx - 3, 0, 6, size.y), Color(base.lerp(Color.WHITE, 0.4 * t), 0.85))
	var scroll := fposmod(b * 40.0, 20.0)
	var y := -20.0 + scroll
	while y < size.y:
		if y > 0.0:
			draw_line(Vector2(cx - 12, y), Vector2(cx + 12, y), Color(base, 0.35), 2.0)
		y += 20.0
	for ly in _marks():
		draw_line(Vector2(cx - 12, ly - 6), Vector2(cx + 12, ly + 6), Color(base, 0.85), 3.0)
		draw_line(Vector2(cx - 12, ly + 6), Vector2(cx + 12, ly - 6), Color(base, 0.85), 3.0)


func _draw_open(cx: float, b: float) -> void:
	var f := _open_flash
	draw_rect(Rect2(cx - 10, 0, 20, size.y), Color(OPEN_COLOR, 0.07 + 0.5 * f))
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(cx + side * 10.0, 0), Vector2(cx + side * 10.0, size.y), Color(OPEN_COLOR, 0.35), 1.5)
	if f > 0.0:
		var g := 10.0 + (1.0 - f) * 26.0
		draw_rect(Rect2(cx - g, 0, g * 2.0, size.y), Color(1, 1, 1, 0.35 * f))
	# 往右的衝刺箭頭，跟著半拍往右滑
	var slide := fposmod(b * 2.0, 1.0) * 8.0
	var col := Color(1, 1, 1, 0.95)
	for ly in _marks():
		for i in 2:
			var tip := Vector2(cx - 4.0 + i * 10.0 + slide, ly)
			draw_polyline(PackedVector2Array([tip + Vector2(-8, -10), tip, tip + Vector2(-8, 10)]),
				Color(OPEN_COLOR, 0.6), 6.0, true)
			draw_polyline(PackedVector2Array([tip + Vector2(-8, -10), tip, tip + Vector2(-8, 10)]), col, 3.0, true)


## 叉叉／箭頭畫在哪些高度：矮的光柱畫在正中間，高的每 120px 一個
func _marks() -> Array[float]:
	var out: Array[float] = []
	var n := maxi(1, roundi(size.y / 120.0))
	for i in n:
		out.append(size.y * (i + 0.5) / n)
	return out
