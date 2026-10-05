class_name PatternPlatform
extends StaticBody2D
## 依節奏型出現的單向平台：x 格期間是實體，其餘時間消失。
## 一排平台各自在不同拍出現，玩家必須照「平台亮起的節奏」一塊接一塊跳過去，
## 不能停下來等。平台出現時會響一個音，整排依序出現就是一段旋律。

const COLOR := Color(0.55, 1.0, 0.72)
const THICKNESS := 16.0
const GRACE := 0.12
const WARN_BEATS := 1.0

var notes: String = "xxxx...."
var tone: float = 0.0
var size: Vector2 = Vector2(80, THICKNESS)
var solid: bool = false
var _shape: CollisionShape2D
var _was_on: bool = false


func setup(top_left: Vector2, width: float, pattern: String, semitones: float) -> void:
	position = top_left
	size = Vector2(width, THICKNESS)
	notes = pattern
	tone = semitones


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	_shape.shape = r
	_shape.position = size * 0.5
	_shape.one_way_collision = true
	add_child(_shape)
	solid = _is_solid(Conductor.song_beat)
	_was_on = BeatPattern.is_on(notes, Conductor.song_beat)
	_shape.disabled = not solid


func _is_solid(b: float) -> bool:
	return BeatPattern.is_on(notes, b) or BeatPattern.is_on(notes, b - GRACE / Conductor.sec_per_beat)


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var on := BeatPattern.is_on(notes, b)
	if on and not _was_on and BeatPattern.near_player(self):
		GameState.play_cue("cue", tone - 12.0, -8.0)
	_was_on = on
	var s := _is_solid(b)
	if s != solid:
		solid = s
		_shape.set_deferred("disabled", not s)
	queue_redraw()


func _draw() -> void:
	var b := Conductor.song_beat
	var rect := Rect2(Vector2.ZERO, size)
	if solid:
		var remain := BeatPattern.until_end(notes, b)
		var a := 1.0
		if remain < 0.75:
			a = 0.35 + 0.65 * absf(cos(remain * TAU * 2.0))
		draw_rect(rect, Color(COLOR, a))
		draw_rect(Rect2(0, 0, size.x, 4), Color(1, 1, 1, 0.75 * a))
		var pips := clampi(ceili(remain), 1, 4)
		for i in pips:
			var x := size.x * 0.5 + (i - (pips - 1) * 0.5) * 12.0
			draw_circle(Vector2(x, size.y * 0.55), 2.5, Color(0, 0, 0, 0.45))
	else:
		var until := BeatPattern.until_start(notes, b)
		var a := 0.18
		if until < WARN_BEATS:
			a = lerpf(0.95, 0.18, until / WARN_BEATS)
		draw_rect(rect, Color(COLOR, a * 0.25))
		draw_rect(rect, Color(COLOR, a), false, 2.0)
