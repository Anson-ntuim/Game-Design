class_name PatternPiston
extends Area2D
## 節拍活塞：平常縮在頂端，節奏型的 x 拍猛力砸到地面、停一下再慢慢升回去。
## 被砸到或撞上還沒升起的活塞頭會受傷。一排活塞一拍接一拍往前砸時，跟在後面走就是節奏。

const RETRACTED := 28.0
const HEAD := 30.0
const SLAM_BEATS := 0.1
const HOLD_BEATS := 0.3
const RISE_BEATS := 0.9
const WARN_BEATS := 1.0

var size: Vector2 = Vector2(80, 160)
var notes: String = "x...x...x...x..."
var _rect: RectangleShape2D
var _shape: CollisionShape2D
var _bottom: float = RETRACTED
var _was_down: bool = false
var _dust: float = 0.0


## top_left 是活塞行程範圍的左上角，size 是整個行程範圍（活塞頭砸到底時的大小）
func setup(top_left: Vector2, region: Vector2, pattern: String) -> void:
	position = top_left + Vector2(region.x * 0.5, 0.0)
	size = region
	notes = pattern


func _ready() -> void:
	collision_layer = Player.LAYER_HAZARD
	collision_mask = 0
	monitoring = false
	z_index = 3
	_rect = RectangleShape2D.new()
	_shape = CollisionShape2D.new()
	_shape.shape = _rect
	add_child(_shape)
	_update(Conductor.song_beat)


func _bottom_at(b: float) -> float:
	var since := BeatPattern.since_hit(notes, b)
	if since < SLAM_BEATS:
		return lerpf(RETRACTED, size.y, pow(since / SLAM_BEATS, 2.0))
	if since < HOLD_BEATS:
		return size.y
	if since < RISE_BEATS:
		return lerpf(size.y, RETRACTED, (since - HOLD_BEATS) / (RISE_BEATS - HOLD_BEATS))
	var until := BeatPattern.until_hit(notes, b)
	return RETRACTED + 10.0 * clampf(1.0 - until / 0.5, 0.0, 1.0)


func is_harmful() -> bool:
	return _bottom > RETRACTED + 12.0


func _update(b: float) -> void:
	_bottom = _bottom_at(b)
	var h := maxf(2.0, _bottom - RETRACTED)
	_rect.size = Vector2(size.x - 6.0, h)
	_shape.position = Vector2(0.0, RETRACTED + h * 0.5)


func _physics_process(delta: float) -> void:
	_update(Conductor.song_beat)
	var down := _bottom >= size.y - 0.5
	if down and not _was_down:
		_dust = 1.0
		if BeatPattern.near_player(self, 800.0):
			GameState.play_cue("slam", 0.0, -5.0)
			get_tree().call_group("main", "shake", 7.0)
	_was_down = down
	_dust = maxf(0.0, _dust - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var edge := GameState.color("edge")
	var hw := size.x * 0.5
	var until := BeatPattern.until_hit(notes, Conductor.song_beat)
	var warn := clampf(1.0 - until / WARN_BEATS, 0.0, 1.0)
	var shake := Vector2(sin(Conductor.song_beat * 90.0) * 1.5 * warn, 0.0) if until < 0.5 else Vector2.ZERO

	draw_rect(Rect2(-hw, 0, size.x, RETRACTED), Color(0.1, 0.1, 0.16))
	draw_rect(Rect2(-hw, RETRACTED - 4, size.x, 4), Color(edge, 0.35 + 0.65 * warn))
	var pips := clampi(ceili(until), 1, 4)
	if until <= 4.0:
		for i in pips:
			var px := (i - (pips - 1) * 0.5) * 12.0
			draw_circle(Vector2(px, RETRACTED * 0.45), 3.0, Color(edge, 0.5 + 0.5 * warn))

	var head_top := maxf(RETRACTED, _bottom - HEAD)
	for rx in [-hw * 0.5, hw * 0.5]:
		draw_line(Vector2(rx, RETRACTED) + shake, Vector2(rx, head_top) + shake, Color(0.55, 0.58, 0.66), 5.0)
	var head := Rect2(Vector2(-hw + 2, head_top) + shake, Vector2(size.x - 4, _bottom - head_top))
	draw_rect(head, Color(0.72, 0.75, 0.84))
	draw_rect(Rect2(head.position, Vector2(head.size.x, 5)), Color(edge.lerp(Color.WHITE, 0.3), 0.9))
	var teeth := 6
	var tw := head.size.x / teeth
	for i in teeth:
		var x0 := head.position.x + i * tw
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, head.end.y - 1), Vector2(x0 + tw, head.end.y - 1), Vector2(x0 + tw * 0.5, head.end.y + 7)]),
			Spike.HAZARD_COLOR)

	if _dust > 0.0:
		for i in 6:
			var side := -1.0 if i % 2 == 0 else 1.0
			var d := (1.0 - _dust) * (30.0 + i * 8.0)
			draw_circle(Vector2(side * (hw + d), size.y - 6.0 - (1.0 - _dust) * 10.0 * (i % 3)),
				5.0 * _dust + 1.0, Color(1, 1, 1, 0.5 * _dust))
