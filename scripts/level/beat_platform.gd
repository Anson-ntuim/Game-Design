class_name BeatPlatform
extends StaticBody2D
## 隨節拍出現/消失的單向平台。A 組與 B 組輪流實體化，
## 交接時兩組會同時存在一小段時間（GRACE），讓玩家在拍點上起跳。

const COLORS: Array[Color] = [Color(1.0, 0.82, 0.3), Color(0.3, 0.82, 1.0)]
const THICKNESS := 16.0
const GRACE := 0.25

var group_id: int = 0
var period_beats: float = 2.0
var size: Vector2 = Vector2(120, THICKNESS)
var solid: bool = true
var _shape: CollisionShape2D


func setup(top_left: Vector2, width: float, group: int) -> void:
	position = top_left
	size = Vector2(width, THICKNESS)
	group_id = group


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
	solid = _is_solid(_phase(Conductor.song_beat))
	_shape.disabled = not solid


func _phase(b: float) -> float:
	return fposmod(b - group_id * period_beats + GRACE, period_beats * 2.0)


func _is_solid(p: float) -> bool:
	return p < period_beats + GRACE * 2.0


func _physics_process(_delta: float) -> void:
	var s := _is_solid(_phase(Conductor.song_beat))
	if s != solid:
		solid = s
		_shape.set_deferred("disabled", not s)
	queue_redraw()


func _draw() -> void:
	var col: Color = COLORS[group_id]
	var p := _phase(Conductor.song_beat)
	var on_len := period_beats + GRACE * 2.0
	var rect := Rect2(Vector2.ZERO, size)
	var remain: float
	if solid:
		remain = on_len - p
		var a := 1.0
		if remain < 0.6:
			a = 0.35 + 0.65 * absf(cos(remain * TAU * 2.5))
		draw_rect(rect, Color(col, a))
		draw_rect(Rect2(0, 0, size.x, 4), Color(1, 1, 1, 0.7 * a))
	else:
		remain = period_beats * 2.0 - p
		var a := 0.25
		if remain < 0.6:
			a = lerpf(0.85, 0.25, remain / 0.6)
		draw_rect(rect, Color(col, a * 0.3))
		draw_rect(rect, Color(col, a), false, 2.0)
	var pips := clampi(ceili(remain), 1, 4)
	for i in pips:
		var x := size.x * 0.5 + (i - (pips - 1) * 0.5) * 12.0
		draw_circle(Vector2(x, size.y * 0.55), 2.5, Color(0, 0, 0, 0.45))
