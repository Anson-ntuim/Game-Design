class_name RestZone
extends Node2D
## 休止區：notes 裡 x 的半拍是休止。玩家在區內遇到休止，就要站在地上完全不動（放開方向鍵）。
## 休止開始後有 GRACE 拍的寬限（剛好落地、放開按鍵的反應時間），結束前 END_GRACE 拍也不判定
## （休止一結束就要起跳時，稍微提早按不算搶拍），中間還在動就算搶拍：
##   strict = false 只發出錯音提醒；strict = true 直接倒下回長椅。
## 休止時配樂壓低音量（由主場景依 resting() 控制），讓「安靜」聽得出來；
## 休止開始時響一聲收音，前一拍角色頭上出現倒數圈，休止中顯示暫停符號。

const GRACE := 0.2
const END_GRACE := 0.25
const COLOR_GO := Color(0.55, 1.0, 0.75)
const COLOR_REST := Color(1.0, 0.42, 0.42)

var left: float = 0.0
var right: float = 0.0
var ground_y: float = 640.0
var notes: String = ""
var strict: bool = true
var _last_slot: int = -9999
var _caught_beat: float = -99.0
var _flash: float = 0.0
var _rest_vis: float = 0.0


func setup(x0: float, x1: float, floor_y: float, pattern: String, is_strict: bool) -> void:
	left = x0
	right = x1
	ground_y = floor_y
	notes = pattern
	strict = is_strict


func _ready() -> void:
	z_index = 11


func contains(x: float) -> bool:
	return x >= left and x <= right


func is_rest_at(b: float) -> bool:
	return notes[posmod(floori(b * 2.0), notes.length())] == "x"


## 休止中（含寬限）
func resting(b: float) -> bool:
	return is_rest_at(b)


## 寬限過後、真的要判定不能動的時候
func judging(b: float) -> bool:
	return is_rest_at(b) and is_rest_at(b - GRACE) and is_rest_at(b + END_GRACE)


## 距離下一次休止開始還有幾拍（休止中回傳 0）
func until_rest(b: float) -> float:
	if is_rest_at(b):
		return 0.0
	var n := notes.length()
	var s := floori(b * 2.0)
	for k in range(1, n + 1):
		if notes[posmod(s + k, n)] == "x":
			return (s + k) * 0.5 - b
	return INF


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var b := Conductor.song_beat
	var inside := contains(p.global_position.x) and not p.control_locked
	_rest_vis = move_toward(_rest_vis, 1.0 if resting(b) else 0.0, delta * 14.0)
	_flash = move_toward(_flash, 0.0, delta * 3.0)

	var s := floori(b * 2.0)
	if s != _last_slot:
		_last_slot = s
		var near := p.global_position.x > left - 200.0 and p.global_position.x < right
		if near and is_rest_at(b) and not is_rest_at(b - 0.5):
			GameState.play_cue("hush", 0.0, -4.0)

	if not inside or not judging(b) or b - _caught_beat < 1.0:
		return
	if not p.is_on_floor() or absf(p.velocity.x) > 1.0:
		_caught_beat = b
		_flash = 1.0
		GameState.play_sfx("miss", 0.0, -2.0)
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("shake"):
			main.shake(8.0)
		if strict:
			p.kill()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var col := COLOR_GO.lerp(COLOR_REST, _rest_vis)
	var top := ground_y - 15.0 * LevelData.TILE
	draw_rect(Rect2(left, top, right - left, ground_y - top), Color(col, 0.035 + 0.06 * _rest_vis + 0.25 * _flash))
	for x in [left, right]:
		var y := top
		while y < ground_y:
			draw_line(Vector2(x, y), Vector2(x, minf(y + 14.0, ground_y)), Color(col, 0.35), 2.0)
			y += 28.0

	var p := _player()
	if p == null or not contains(p.global_position.x):
		return
	var head := to_local(p.global_position) + Vector2(0, -62)
	var b := Conductor.song_beat
	var until := until_rest(b)
	if until > 0.0 and until <= 1.0:
		var k := 1.0 - until
		draw_arc(head, 6.0 + 18.0 * (1.0 - k), 0.0, TAU, 32, Color(COLOR_REST, 0.3 + 0.6 * k), 3.0, true)
	if _rest_vis > 0.0:
		var a := _rest_vis
		draw_rect(Rect2(head + Vector2(-8, -9), Vector2(5, 18)), Color(COLOR_REST, a))
		draw_rect(Rect2(head + Vector2(3, -9), Vector2(5, 18)), Color(COLOR_REST, a))
