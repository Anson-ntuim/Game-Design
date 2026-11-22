class_name PatternSpike
extends Area2D
## 依節奏型彈出的尖刺。地板尖刺要在它彈出的那一拍跳起來躲過；
## 天花板尖刺會在指定拍落下，那一拍跳起來就會撞到，逼玩家「休止」。
## 在拍點上開始伸出，稍晚才有傷害，所以剛好在拍點上起跳就能躲過。
## 預告：彈出前半拍先冒出一小截尖端（沒有傷害），越接近越高、尖端閃白，地上亮一條紅光，看得出「下一拍要出來」。

const POP_DELAY := 0.08
const ACTIVE_TIME := 0.15
const RETRACT_TIME := 0.08
const WARN_BEATS := 0.5
## 預告時冒出的高度（佔全高的比例）：半拍前 PEEK_MIN，彈出前一刻 PEEK_MAX
const PEEK_MIN := 0.12
const PEEK_MAX := 0.32

var tile: float = 40.0
var notes: String = "x......."
var ceiling: bool = false
var _height: float = 0.0
var _harmful: bool = false
var _last_hit: int = -99999
## 0～1：預告程度（彈出前一拍開始升到 1）
var _warn: float = 0.0


func setup(top_left: Vector2, tile_size: float, pattern: String, on_ceiling: bool) -> void:
	position = top_left
	tile = tile_size
	notes = pattern
	ceiling = on_ceiling


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	z_index = 2
	add_to_group("hazard")
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	if ceiling:
		r.size = Vector2(tile - 8.0, tile * 0.9)
		shape.position = Vector2(tile * 0.5, r.size.y * 0.5)
	else:
		r.size = Vector2(tile - 8.0, 14.0)
		shape.position = Vector2(tile * 0.5, tile - r.size.y * 0.5)
	shape.shape = r
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var b := Conductor.song_beat
	var spb := Conductor.sec_per_beat
	var since := BeatPattern.since_hit(notes, b) * spb
	_harmful = since >= POP_DELAY and since < POP_DELAY + ACTIVE_TIME
	if since < POP_DELAY:
		_height = smoothstep(0.0, POP_DELAY, since)
	elif since < POP_DELAY + ACTIVE_TIME:
		_height = 1.0
	elif since < POP_DELAY + ACTIVE_TIME + RETRACT_TIME:
		_height = 1.0 - (since - POP_DELAY - ACTIVE_TIME) / RETRACT_TIME
	else:
		_height = 0.0
	var until_hit := fposmod(-BeatPattern.since_hit(notes, b), BeatPattern.cycle(notes))
	_warn = 0.0
	if _height <= 0.0 and until_hit < WARN_BEATS:
		_warn = 1.0 - until_hit / WARN_BEATS
		_height = lerpf(PEEK_MIN, PEEK_MAX, _warn * _warn)
		## 冒出來的那一下：半拍前從 0 很快頂到 PEEK_MIN
		_height *= clampf((WARN_BEATS - until_hit) * 16.0, 0.0, 1.0)
	var hit_id := roundi((b - since / spb) * 2.0)
	if since < 0.1 and hit_id != _last_hit:
		_last_hit = hit_id
		if BeatPattern.near_player(self, 700.0):
			GameState.play_cue("block", -7.0 if ceiling else 0.0, -10.0)
	## 離玩家很遠就不重畫（整關幾十個節奏機關每秒 120 次重畫會拖慢後段）
	if BeatPattern.near_player(self, 1400.0):
		queue_redraw()


func is_harmful() -> bool:
	return _harmful


func _draw() -> void:
	var col := Spike.HAZARD_COLOR if _harmful or _height > 0.9 else Spike.HAZARD_COLOR.lerp(Color.WHITE, 0.45)
	if _warn > 0.0:
		## 預告中：尖端在白與紅之間閃（每半拍一次），越接近越紅
		var blink := 0.5 + 0.5 * cos(_warn * TAU)
		col = Spike.HAZARD_COLOR.lerp(Color.WHITE, 0.6 * blink * (1.0 - _warn * 0.5))
		var glow_y := 0.0 if ceiling else tile - 3.0
		draw_rect(Rect2(0, glow_y - 2.0, tile, 5.0), Color(Spike.HAZARD_COLOR, 0.25 + 0.5 * _warn))
	if ceiling:
		draw_rect(Rect2(2, 0, tile - 4, 5), Color(Spike.HAZARD_COLOR, 0.4))
		draw_set_transform(Vector2(0, tile), 0.0, Vector2(1, -1))
		Spike.draw_spikes(self, tile, _height * 1.1, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(2, tile - 5, tile - 4, 5), Color(Spike.HAZARD_COLOR, 0.4))
		Spike.draw_spikes(self, tile, _height, col)
