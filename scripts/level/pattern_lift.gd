class_name PatternLift
extends AnimatableBody2D
## 升降舞台：節奏型的每個 x 往上升一段（一拍一階），v 那拍開始降回底部。
## 升起時每一階彈出和弦裡的一個音，整座舞台升到頂就是一段上行琶音。

const THICKNESS := 16.0
const STEP_BEATS := 0.25
const DESCENT_BEATS := 1.5
const STEP_TONES := [0.0, 4.0, 7.0, 12.0, 16.0, 19.0]

var bottom_pos: Vector2
var width: float = 120.0
var travel: float = 240.0
var notes: String = "x.x.x.....v....."
var tone: float = 0.0
var _steps: int = 1
var _last_step: int = -1


## bottom_top_left：舞台在最低點時的左上角；travel_px：總共升高多少
func setup(bottom_top_left: Vector2, platform_width: float, travel_px: float, pattern: String, base_tone: float) -> void:
	bottom_pos = bottom_top_left
	width = platform_width
	travel = travel_px
	notes = pattern
	tone = base_tone
	position = bottom_top_left


func _ready() -> void:
	sync_to_physics = true
	collision_layer = Player.LAYER_WORLD
	collision_mask = 0
	z_index = 2
	_steps = maxi(1, notes.count("x"))
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, THICKNESS)
	shape.shape = r
	shape.position = r.size * 0.5
	shape.one_way_collision = true
	add_child(shape)
	position = bottom_pos - Vector2(0, _height_at(Conductor.song_beat))


## 回傳 [升高量, 目前已經升了幾階]
func _state_at(b: float) -> Array:
	var c := BeatPattern.cycle(notes)
	var p := fposmod(b, c)
	var vs := maxi(0, notes.find("v")) * 0.5
	var e := fposmod(p - vs, c)
	if e < DESCENT_BEATS:
		return [travel * (1.0 - smoothstep(0.0, 1.0, e / DESCENT_BEATS)), 0]
	var step := travel / _steps
	var h := 0.0
	var count := 0
	for i in notes.length():
		if notes[i] == "x":
			var ts := fposmod(i * 0.5 - vs, c)
			if ts <= e:
				h += step * smoothstep(0.0, STEP_BEATS, e - ts)
				count += 1
	return [h, count]


func _height_at(b: float) -> float:
	return _state_at(b)[0]


func _physics_process(_delta: float) -> void:
	var st := _state_at(Conductor.song_beat)
	position = bottom_pos - Vector2(0, st[0])
	var count: int = st[1]
	if count != _last_step:
		if count > _last_step and count > 0 and BeatPattern.near_player(self, 800.0):
			var k := (count - 1) % STEP_TONES.size()
			GameState.play_cue("cue", tone + STEP_TONES[k] - 12.0, -7.0)
		_last_step = count
	queue_redraw()


func _draw() -> void:
	var edge := GameState.color("edge")
	var pulse := Conductor.pulse(8.0)
	var h := bottom_pos.y - position.y
	if h > 2.0:
		var legs := 4
		var seg := h / legs
		for i in legs:
			var y0 := THICKNESS + i * seg
			var y1 := y0 + seg
			draw_line(Vector2(8, y0), Vector2(width - 8, y1), Color(0.5, 0.52, 0.62), 3.0)
			draw_line(Vector2(width - 8, y0), Vector2(8, y1), Color(0.5, 0.52, 0.62), 3.0)
		draw_rect(Rect2(0, h + THICKNESS - 6, width, 6), Color(0.2, 0.2, 0.28))
	draw_rect(Rect2(0, 0, width, THICKNESS), Color(0.95, 0.9, 0.8))
	draw_rect(Rect2(0, 0, width, 4), edge.lerp(Color.WHITE, pulse))
	var lamps := int(width / 20.0)
	var lit := _last_step
	for i in lamps:
		var on := posmod(i + lit, 3) == 0
		draw_circle(Vector2(10 + i * 20, THICKNESS * 0.62), 3.0, Color(edge, 0.9 if on else 0.3))
