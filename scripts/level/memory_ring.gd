extends RefCounted
## 遠景的碎石環。七個拍位、每拍兩塊石頭，第八拍留給右上方的缺口。

const STONE := Color("#8c7898")
const SHADOW := Color("#726381")
const RIM := Color("#ad97b3")
const AFTERGLOW := Color("#ebbed8")


static func draw(canvas: Node2D, center: Vector2, radius: float, beat: float, motion: float) -> void:
	var active_pair := posmod(floori(beat), 8)
	var pulse := (1.0 - smoothstep(0.12, 0.93, fposmod(beat, 1.0))) * motion
	var unit := TAU / 16.0
	for i in 14:
		var lit := pulse if floori(i * 0.5) == active_pair else 0.0
		var start := -0.45 + i * unit + 0.014
		var end := start + unit - (0.065 if i in [2, 8, 12] else 0.033)
		var mid := (start + end) * 0.5
		var outer := radius * (1.0 + 0.022 * sin(i * 2.6))
		var inner := outer - radius * (0.125 + 0.027 * cos(i * 1.72))
		var p := center + Vector2.from_angle(mid) * radius * (0.012 * sin(i * 1.56))
		var a := p + Vector2.from_angle(start) * outer
		var b := p + Vector2.from_angle(mid) * (outer + radius * 0.007)
		var c := p + Vector2.from_angle(end) * (outer - radius * 0.009)
		var d := p + Vector2.from_angle(end - 0.012) * inner
		var e := p + Vector2.from_angle(mid) * inner
		var f := p + Vector2.from_angle(start + 0.017) * (inner + radius * 0.013)
		var face := PackedVector2Array([a,b,c,d,e,f])
		var thickness := Vector2(radius * 0.025, radius * 0.044)
		canvas.draw_colored_polygon(Transform2D(0.0, thickness) * face, SHADOW)
		var light := 0.18 * (1.0 - sin(mid)) + 0.10 * cos(i * 2.7)
		canvas.draw_colored_polygon(face, STONE.lerp(RIM, light).lerp(AFTERGLOW, lit * 0.42))
		var ridge := PackedVector2Array([a,b,c])
		if lit > 0.02:
			canvas.draw_polyline(ridge, Color(AFTERGLOW, lit * 0.19), radius * 0.048, true)
		canvas.draw_polyline(ridge, RIM.lerp(AFTERGLOW, lit), maxf(1.0,radius * 0.014), true)
		if i % 3 == 1:
			var chip := b.lerp(e, 0.50) + Vector2.from_angle(mid + PI * 0.5) * radius * 0.043
			canvas.draw_polyline(PackedVector2Array([b,chip,chip.lerp(e,0.7)]),
				SHADOW.lerp(AFTERGLOW, lit), maxf(1.0,radius * 0.012), true)

	## 缺口中的三枚小碎片，在各自緩慢的浮動軌跡上接光。
	for i in 3:
		var angle := -1.15 + i * 0.26
		var drift := radius * 0.016 * sin(beat * 0.25 + i * 2.2) * motion
		var p := center + Vector2.from_angle(angle) * (radius * (1.02 + 0.10 * sin(i * 2.0)) + drift)
		var along := Vector2.from_angle(angle + PI * 0.5) * radius * (0.046 + i * 0.009)
		var across := Vector2.from_angle(angle) * radius * 0.034
		var lit := pulse * 0.6 if active_pair == (6 if i == 0 else 0) else 0.0
		canvas.draw_colored_polygon(PackedVector2Array([p-along,p+across,p+along,p-across*0.75]),
			STONE.lerp(AFTERGLOW, 0.28 + lit))
		canvas.draw_line(p-along,p+across,RIM.lerp(AFTERGLOW,lit),1.0,true)
