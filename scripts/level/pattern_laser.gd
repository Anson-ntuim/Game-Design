class_name PatternLaser
extends Area2D
## 節拍雷射：節奏型的 x 拍發射一道光束，發射前一拍瞄準線會越來越亮。
## 一整排雷射一起在每一拍發射、只在某一拍留下缺口時，缺口移動的節奏就是前進的節奏。

const CHARGE_BEATS := 1.0
const FIRE_DELAY := 0.03
const FIRE_TIME := 0.2
const BEAM := 10.0
const COLOR := Color(1.0, 0.3, 0.55)

var length: float = 640.0
var vertical: bool = true
var notes: String = "x.x.x.x."
var _harmful: bool = false
var _last_hit: int = -99999


## start 是光束起點的中心線位置（直的在頂端、橫的在左端）
func setup(start: Vector2, beam_length: float, is_vertical: bool, pattern: String) -> void:
	position = start
	length = beam_length
	vertical = is_vertical
	notes = pattern


func _ready() -> void:
	collision_layer = Player.LAYER_HAZARD
	collision_mask = 0
	monitoring = false
	z_index = 4
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(BEAM, length) if vertical else Vector2(length, BEAM)
	shape.shape = r
	shape.position = r.size * 0.5 - (Vector2(BEAM * 0.5, 0) if vertical else Vector2(0, BEAM * 0.5))
	add_child(shape)


func is_harmful() -> bool:
	return _harmful


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var since := BeatPattern.since_hit(notes, b) * Conductor.sec_per_beat
	_harmful = since >= FIRE_DELAY and since < FIRE_DELAY + FIRE_TIME
	var hit_id := roundi((b - since / Conductor.sec_per_beat) * 2.0)
	if since < 0.1 and hit_id != _last_hit:
		_last_hit = hit_id
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("zap", 0.0, -9.0)
	queue_redraw()


func _draw() -> void:
	var b := Conductor.song_beat
	var since := BeatPattern.since_hit(notes, b) * Conductor.sec_per_beat
	var until := BeatPattern.until_hit(notes, b)
	var dir := Vector2(0, 1) if vertical else Vector2(1, 0)
	var end := dir * length
	for p: Vector2 in [Vector2.ZERO, end]:
		draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), Color(0.12, 0.1, 0.18))
		draw_circle(p, 4.0, COLOR.lerp(Color.WHITE, 0.3 + 0.7 * clampf(1.0 - until, 0.0, 1.0)))

	var fire := since < FIRE_DELAY + FIRE_TIME + 0.08
	if fire:
		var a := 1.0 - clampf((since - FIRE_DELAY - FIRE_TIME) / 0.08, 0.0, 1.0)
		draw_line(Vector2.ZERO, end, Color(COLOR, 0.25 * a), BEAM * 3.2)
		draw_line(Vector2.ZERO, end, Color(COLOR, 0.8 * a), BEAM)
		draw_line(Vector2.ZERO, end, Color(1, 1, 1, 0.9 * a), BEAM * 0.35)
	elif until < CHARGE_BEATS:
		var t := 1.0 - until / CHARGE_BEATS
		var dash := 14.0
		var n := int(length / dash)
		var off := fposmod(b * 40.0, dash * 2.0)
		for i in range(0, n, 2):
			var s := dir * (i * dash + off)
			if s.length() < length:
				draw_line(s, (s + dir * dash).limit_length(length), Color(COLOR, 0.15 + 0.6 * t * t), 1.0 + 2.0 * t)
