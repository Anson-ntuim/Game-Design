class_name OrbShowcase
extends Node2D
## 第五關開頭的展示牌：小／一般／大三種黃色音符並排，各畫一條跳躍弧線（高度、寬度都照實際比例），
## 一顆小光點跟著拍子沿弧線跑，看得出「小＝半拍、一般＝一拍、大＝兩拍」。

const KINDS := [
	{"kind": "low", "name": "小音符", "beats": 0.5, "height": 35.0},
	{"kind": "", "name": "一般音符", "beats": 1.0, "height": 140.0},
	{"kind": "high", "name": "大音符", "beats": 2.0, "height": 280.0},
]
const PX_PER_BEAT := 155.0
const GAP := 70.0

var _orbs: Array[RhythmOrb] = []


func _ready() -> void:
	z_index = 4
	var x := 0.0
	for k: Dictionary in KINDS:
		var orb := RhythmOrb.new()
		## 只拿來畫，不放在碰撞層（放在畫面上方，角色碰不到也沒有判定）
		orb.setup(Vector2(x, 0.0), "x.x.x.x.", 12.0)
		orb.jump_kind = String(k["kind"])
		add_child(orb)
		orb.collision_layer = 0
		orb.remove_from_group("rhythm_orb")
		orb.set_physics_process(false)
		_orbs.append(orb)
		x += float(k["beats"]) * PX_PER_BEAT + GAP


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := UiKit.font(0.7)
	var x := 0.0
	var b := Conductor.song_beat
	for k: Dictionary in KINDS:
		var beats: float = k["beats"]
		var w := beats * PX_PER_BEAT
		var h: float = k["height"]
		## 拋物線（虛線點）
		for i in 25:
			var t := float(i) / 24.0
			draw_circle(Vector2(x + w * t, -4.0 * h * t * (1.0 - t)), 2.2, Color(1, 0.86, 0.5, 0.55))
		## 每半拍一個刻度
		var n := int(round(beats * 2.0))
		for i in n + 1:
			var tx := x + w * float(i) / float(n)
			draw_line(Vector2(tx, 34), Vector2(tx, 44), Color(1, 1, 1, 0.5), 2.0)
		draw_line(Vector2(x, 39), Vector2(x + w, 39), Color(1, 1, 1, 0.3), 2.0)
		## 跟著拍子跑的光點
		var t2 := fposmod(b, beats) / beats
		draw_circle(Vector2(x + w * t2, -4.0 * h * t2 * (1.0 - t2)), 6.0, Color(1, 1, 1, 0.9))
		var label := "%s　%s" % [k["name"], "半拍" if beats == 0.5 else "一拍" if beats == 1.0 else "兩拍"]
		draw_string(font, Vector2(x - 20, 74), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.95, 0.8))
		x += w + GAP
