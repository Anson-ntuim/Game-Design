class_name HitFx
extends Node2D
## 打擊特效（一次性，播完自己刪掉）：
##   burst：音符／環／鞦韆打中時炸開的碎片＋外擴圓圈；perfect 碎片更多、更亮，還會跳出「PERFECT」
##   dust：落地時腳邊往兩側噴的小灰塵
## 只是畫面，不影響物理。

const LIFE := {"burst": 0.5, "dust": 0.3}

var kind: String = "burst"
var grade: String = "good"
var color: Color = Color(1.0, 0.78, 0.35)
var _t: float = 0.0
var _shards: Array[Dictionary] = []


static func spawn(parent: Node, at: Vector2, fx_kind: String, fx_grade: String = "good",
		tint: Color = Color(1.0, 0.78, 0.35)) -> void:
	var fx := HitFx.new()
	fx.kind = fx_kind
	fx.grade = fx_grade
	fx.color = tint
	fx.position = at
	parent.add_child(fx)


func _ready() -> void:
	z_index = 20
	var amount := GameState.anim_amount()
	var n := 0
	if kind == "burst":
		n = int(round((14 if grade == "perfect" else 8) * maxf(amount, 0.4)))
		for i in n:
			var a := TAU * (float(i) + randf() * 0.6) / float(n)
			var speed := randf_range(180.0, 340.0) * (1.25 if grade == "perfect" else 1.0)
			_shards.append({"v": Vector2(cos(a), sin(a)) * speed, "p": Vector2.ZERO,
				"r": randf_range(3.0, 5.5), "spin": randf_range(-8.0, 8.0), "note": i % 3 == 0})
	else:
		n = int(round(6 * maxf(amount, 0.4)))
		for i in n:
			var side := -1.0 if i % 2 == 0 else 1.0
			_shards.append({"v": Vector2(side * randf_range(60.0, 160.0), randf_range(-70.0, -20.0)),
				"p": Vector2(side * 6.0, 0.0), "r": randf_range(3.0, 6.0), "spin": 0.0, "note": false})


func _process(delta: float) -> void:
	_t += delta
	if _t >= float(LIFE[kind]):
		queue_free()
		return
	for s: Dictionary in _shards:
		s["p"] += s["v"] * delta
		if kind == "burst":
			s["v"] = s["v"] * (1.0 - 3.5 * delta) + Vector2(0.0, 520.0 * delta)
		else:
			s["v"] = s["v"] * (1.0 - 5.0 * delta)
	queue_redraw()


func _draw() -> void:
	var life: float = LIFE[kind]
	var k := _t / life
	var fade := 1.0 - k
	if kind == "burst":
		## 外擴的圓圈：perfect 兩圈（白＋金）
		draw_arc(Vector2.ZERO, lerpf(18.0, 70.0, ease(k, 0.4)), 0.0, TAU, 40, Color(color, 0.8 * fade), 4.0 * fade + 1.0, true)
		if grade == "perfect":
			draw_arc(Vector2.ZERO, lerpf(10.0, 96.0, ease(k, 0.3)), 0.0, TAU, 48, Color(1, 1, 1, 0.9 * fade), 3.0 * fade + 1.0, true)
			if k < 0.18:
				draw_circle(Vector2.ZERO, 34.0 * (1.0 - k / 0.18), Color(1, 1, 1, 0.55))
		for s: Dictionary in _shards:
			var p: Vector2 = s["p"]
			var col := Color(1, 1, 1, fade) if grade == "perfect" and int(s["r"] * 10) % 2 == 0 else Color(color.lightened(0.2), fade)
			if s["note"]:
				## 小音符形狀的碎片
				draw_circle(p, float(s["r"]) * 0.8, col)
				draw_line(p + Vector2(float(s["r"]) * 0.7, 0), p + Vector2(float(s["r"]) * 0.7, -float(s["r"]) * 2.6), col, 1.6)
			else:
				var rot := float(s["spin"]) * _t
				var r := float(s["r"])
				var pts := PackedVector2Array()
				for j in 4:
					var a := rot + TAU * j / 4.0
					pts.append(p + Vector2(cos(a), sin(a)) * r * (1.0 if j % 2 == 0 else 0.45))
				draw_colored_polygon(pts, col)
		## 判定字
		var label := "PERFECT" if grade == "perfect" else "GOOD"
		var lc := Color(1.0, 0.92, 0.45) if grade == "perfect" else Color(0.75, 0.95, 1.0)
		var rise := -46.0 - 26.0 * ease(k, 0.5)
		var size := 26 if grade == "perfect" else 20
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - k * 6.0)
		draw_set_transform(Vector2(0, rise), 0.0, Vector2(pop, pop))
		var font := UiKit.display_font(800)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string_outline(font, Vector2(-w * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.08, 0.05, 0.12, fade))
		draw_string(font, Vector2(-w * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(lc, fade))
		draw_set_transform(Vector2.ZERO)
	else:
		for s: Dictionary in _shards:
			draw_circle(s["p"], float(s["r"]) * (0.6 + 0.6 * k), Color(0.92, 0.9, 1.0, 0.45 * fade))
