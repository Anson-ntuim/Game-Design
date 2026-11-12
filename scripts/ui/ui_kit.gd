class_name UiKit
extends RefCounted
## 介面共用的畫法：字型、切角霓虹面板、按鍵小方塊、音符難度、關卡縮圖。
## 顏色跟著 GameState 的色盤（edge）走，換段落時介面會一起換色。
## 佈局依 game-ui-ux：錨在邊角 + 安全邊距（notch／圓角／過掃描），不要寫死貼邊座標。

## 網頁版沒有系統字型，只能用專案裡的字型檔；它只含遊戲用到的字，改了文字要重跑 tools/subset_font.py
const FONT_PATH := "res://assets/fonts/NotoSansTC-Game.ttf"
const PANEL := Color(0.03, 0.035, 0.09, 0.84)
const INK := Color(0.02, 0.02, 0.07)
const GOLD := Color(1.0, 0.86, 0.42)
const FLOAT := Color(0.45, 0.85, 1.0)
const CUT := 12.0
const KEY_H := 24.0
## 桌面／網頁至少留這圈；手機再疊 DisplayServer safe area
const SAFE_PAD := 24.0

static var _fonts: Dictionary = {}
static var _minimaps: Dictionary = {}
static var _soft_panel_style: StyleBoxFlat


## 回傳 UI 可用矩形（已扣掉安全邊距），單位是目前 viewport 的 UI 座標
static func safe_rect(view_size: Vector2) -> Rect2:
	var pad_l := SAFE_PAD
	var pad_t := SAFE_PAD
	var pad_r := SAFE_PAD
	var pad_b := SAFE_PAD
	var win_size := DisplayServer.window_get_size()
	if win_size.x > 0 and win_size.y > 0:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(win_size))
		var inner := safe.intersection(win)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			var sx := view_size.x / win.size.x
			var sy := view_size.y / win.size.y
			pad_l = maxf(pad_l, (inner.position.x - win.position.x) * sx)
			pad_t = maxf(pad_t, (inner.position.y - win.position.y) * sy)
			pad_r = maxf(pad_r, (win.end.x - inner.end.x) * sx)
			pad_b = maxf(pad_b, (win.end.y - inner.end.y) * sy)
	return Rect2(pad_l, pad_t, view_size.x - pad_l - pad_r, view_size.y - pad_t - pad_b)


static func gravity_label(strength: float) -> String:
	if absf(strength - 2400.0) < 0.5:
		return ""
	if strength < 2400.0:
		return "輕"
	return ""


## 0 = 正常、1 = 輕重力滿檔（給 HUD 浮力度條；第五關固定 1000）
static func gravity_lightness(strength: float) -> float:
	return clampf((2400.0 - strength) / (2400.0 - 1000.0), 0.0, 1.0)


## 字型檔固定 600 字重，標題用 embolden 加粗
static func font(embolden: float = 0.0) -> Font:
	var key := "%.2f" % embolden
	if not _fonts.has(key):
		var f: Font = load(FONT_PATH)
		if embolden > 0.0:
			var fv := FontVariation.new()
			fv.base_font = f
			fv.variation_embolden = embolden
			f = fv
		_fonts[key] = f
	return _fonts[key]


static func title_font() -> Font:
	return font(0.9)


## 網頁字型是精簡子集：自訂歌檔名等未收錄的字改成 '.'，避免方框亂碼。
## Web 上 Font.has_char 對缺字常回 true，改以 get_glyph_index != 0 判斷。
static func safe_text(s: String, f: Font = null) -> String:
	if s.is_empty():
		return s
	if f == null:
		f = font()
	var out := ""
	for i in s.length():
		var code := s.unicode_at(i)
		if code == 10 or code == 13 or code == 9 or code == 32:
			out += String.chr(code)
		elif f.get_glyph_index(16, code, 0) != 0:
			out += String.chr(code)
		else:
			out += "."
	return out


static func width_of(s: String, size: int, f: Font = null) -> float:
	return (f if f else font()).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 帶陰影的文字
static func text(ci: CanvasItem, pos: Vector2, width: float, s: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, f: Font = null) -> void:
	if f == null:
		f = font()
	ci.draw_string(f, pos + Vector2(0, 2), s, align, width, size, Color(0, 0, 0, color.a * 0.6))
	ci.draw_string(f, pos, s, align, width, size, color)


## 粗描邊文字（標題、大訊息用）：外圈深色、內圈霓虹色、最上層填色
static func bold_text(ci: CanvasItem, pos: Vector2, width: float, s: String, size: int, fill: Color, glow: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := title_font()
	var o := maxi(4, int(size / 7.0))
	ci.draw_string_outline(f, pos + Vector2(0, 4), s, align, width, size, o + 4, Color(INK, fill.a * 0.8))
	ci.draw_string_outline(f, pos, s, align, width, size, o + 4, Color(INK, fill.a))
	ci.draw_string_outline(f, pos, s, align, width, size, o, Color(glow, glow.a * fill.a))
	ci.draw_string(f, pos, s, align, width, size, fill)


## 左上、右下切角的多邊形
static func chamfer(rect: Rect2, cut: float = CUT) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x, p.y), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x, e.y), Vector2(p.x, p.y + cut)])


## 霓虹面板：深色底、細框、切角處一小段亮線；glow > 0 時外面多一圈光暈
static func panel(ci: CanvasItem, rect: Rect2, edge: Color, glow: float = 0.0, alpha: float = 1.0,
		cut: float = CUT, fill: Color = PANEL) -> void:
	if glow > 0.0:
		for k in 3:
			var g := chamfer(rect.grow(3.0 + k * 3.0), cut + 2.0 + k * 2.0)
			g.append(g[0])
			ci.draw_polyline(g, Color(edge, glow * alpha * (0.3 - k * 0.08)), 3.0, true)
	var pts := chamfer(rect, cut)
	ci.draw_colored_polygon(pts, Color(fill, fill.a * alpha))
	ci.draw_line(Vector2(rect.position.x + cut, rect.position.y + 1.5), Vector2(rect.end.x - 1, rect.position.y + 1.5),
		Color(1, 1, 1, 0.07 * alpha), 2.0)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, Color(edge, (0.45 + 0.4 * minf(glow, 1.0)) * alpha), 1.5, true)
	ci.draw_line(pts[5], pts[0], Color(edge.lerp(Color.WHITE, 0.4), alpha), 3.0, true)
	ci.draw_line(pts[2], pts[3], Color(edge.lerp(Color.WHITE, 0.4), alpha), 3.0, true)


## 心動之城的柔和面板：圓角、葡萄紫半透明底與粉彩細框，保留文字對比。
static func soft_panel(ci: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	if _soft_panel_style == null:
		_soft_panel_style = StyleBoxFlat.new()
		_soft_panel_style.set_border_width_all(2)
		_soft_panel_style.set_corner_radius_all(12)
		_soft_panel_style.shadow_size = 8
		_soft_panel_style.anti_aliasing = true
	var style := _soft_panel_style
	style.bg_color = Color(0.10, 0.055, 0.15, 0.88 * alpha)
	style.border_color = Color(0.94, 0.66, 0.82, 0.72 * alpha)
	style.shadow_color = Color(0.08, 0.025, 0.12, 0.34 * alpha)
	ci.draw_style_box(style, rect)
	var inner := rect.grow(-5.0)
	ci.draw_line(inner.position + Vector2(10, 0), Vector2(inner.end.x - 10, inner.position.y),
		Color(1.0, 0.88, 0.95, 0.13 * alpha), 1.0, true)
	for i in 5:
		var y := inner.position.y + 10.0 + i * maxf(8.0, inner.size.y / 6.0)
		var inset := 14.0 + fposmod(i * 23.0, 31.0)
		ci.draw_line(Vector2(inner.position.x + inset, y),
			Vector2(inner.end.x - inset * 1.4, y), Color(0.95, 0.75, 0.88, 0.025 * alpha), 1.0)


## 按鍵小方塊：pos 是左上角，回傳寬度
static func keycap(ci: CanvasItem, pos: Vector2, label: String, edge: Color, alpha: float = 1.0,
		size: int = 13, soft: bool = false) -> float:
	var f := font()
	var w := maxf(KEY_H, width_of(label, size, f) + 14.0)
	var r := Rect2(pos, Vector2(w, KEY_H))
	var shadow := Color("2b1833") if soft else INK
	var fill := Color("392440") if soft else Color(0.16, 0.17, 0.26)
	var border := Color("dfa2bd") if soft else edge
	ci.draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(shadow, 0.8 * alpha))
	ci.draw_rect(r, Color(fill, 0.92 * alpha))
	ci.draw_rect(r, Color(border, 0.62 * alpha), false, 1.0)
	ci.draw_line(r.position + Vector2(2, 1.5), Vector2(r.end.x - 2, r.position.y + 1.5),
		Color(1, 0.9, 0.96, 0.16 * alpha), 1.0)
	ci.draw_string(f, Vector2(r.position.x, r.position.y + KEY_H * 0.5 + size * 0.36), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(Color("fff4ee"), alpha))
	return w


## 一組「按鍵 + 說明」：items = [[["←", "→"], "選關"], …]，回傳總寬
static func key_hints_width(items: Array, size: int = 13) -> float:
	var total := 0.0
	for it: Array in items:
		for k: String in it[0]:
			total += maxf(KEY_H, width_of(k, size) + 14.0) + 4.0
		total += 4.0 + width_of(String(it[1]), size + 1) + 22.0
	return total - 22.0


## y 是按鍵的上緣；align 決定 x 是左端、中央或右端
static func key_hints(ci: CanvasItem, x: float, y: float, items: Array, edge: Color, alpha: float = 1.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, size: int = 13, soft: bool = false) -> void:
	var total := key_hints_width(items, size)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= total * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= total
	for it: Array in items:
		for k: String in it[0]:
			x += keycap(ci, Vector2(x, y), k, edge, alpha, size, soft) + 4.0
		x += 4.0
		var label := String(it[1])
		var label_color := Color("f6e7ee") if soft else Color.WHITE
		text(ci, Vector2(x, y + KEY_H * 0.5 + (size + 1) * 0.36), -1, label, size + 1,
			Color(label_color, 0.78 * alpha))
		x += width_of(label, size + 1) + 22.0


## 音符難度：n 顆亮、其餘暗
static func notes(ci: CanvasItem, pos: Vector2, n: int, total: int, color: Color, size: int = 20) -> void:
	var f := font()
	for i in total:
		var c := color if i < n else Color(1, 1, 1, 0.18 * color.a)
		ci.draw_string(f, pos + Vector2(i * size * 0.8, 0), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


## 膠囊形標籤：回傳寬度
static func pill(ci: CanvasItem, pos: Vector2, label: String, fill: Color, ink: Color, size: int = 13) -> float:
	var f := font()
	var h := size + 11.0
	var w := width_of(label, size, f) + h
	var r := h * 0.5
	ci.draw_rect(Rect2(pos + Vector2(r, 0), Vector2(w - h, h)), fill)
	ci.draw_circle(pos + Vector2(r, r), r, fill)
	ci.draw_circle(pos + Vector2(w - r, r), r, fill)
	ci.draw_string(f, Vector2(pos.x, pos.y + r + size * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, w, size, ink)
	return w


static func clear_minimaps() -> void:
	_minimaps.clear()


## 關卡縮圖：每格一個像素，地形白、平台半透明；回傳 {tex, cols, benches, goal}
static func minimap(level: int) -> Dictionary:
	if _minimaps.has(level):
		return _minimaps[level]
	var data := LevelData.build(level)
	var grid: Array[String] = data["grid"]
	var cols: int = data["width"]
	var patterns: Dictionary = data["patterns"]
	var img := Image.create(maxi(cols, 1), grid.size(), false, Image.FORMAT_RGBA8)
	var benches: Array[int] = []
	var goal := cols - 1
	for r in grid.size():
		var line := grid[r]
		for c in line.length():
			var ch := line[c]
			var a := 0.0
			match ch:
				"#", "%":
					a = 1.0
				"=", "A", "B", "M", "m", "J":
					a = 0.55
				"^", "!", "?":
					a = 0.35
				"C":
					benches.append(c)
				"G":
					goal = c
				_:
					var kind: String = patterns.get(ch, {}).get("kind", "")
					if kind == "platform" or kind == "lift":
						a = 0.55
			if a > 0.0:
				img.set_pixel(c, r, Color(1, 1, 1, a))
	var info := {"tex": ImageTexture.create_from_image(img), "cols": cols, "benches": benches, "goal": goal}
	_minimaps[level] = info
	return info


## 畫縮圖（只取地面附近的列，上面多是空的）；progress 0..1 以左的部分畫亮
static func draw_minimap(ci: CanvasItem, level: int, rect: Rect2, edge: Color, alpha: float = 1.0,
		progress: float = -1.0) -> void:
	var info := minimap(level)
	var tex: ImageTexture = info["tex"]
	var cols := float(info["cols"])
	var src := Rect2(0, 6, cols, tex.get_height() - 6)
	ci.draw_rect(rect, Color(INK, 0.7 * alpha))
	if progress < 0.0:
		ci.draw_texture_rect_region(tex, rect, src, Color(edge.lerp(Color.WHITE, 0.25), 0.85 * alpha))
	else:
		var split := clampf(progress, 0.0, 1.0)
		ci.draw_texture_rect_region(tex, rect, src, Color(1, 1, 1, 0.22 * alpha))
		ci.draw_texture_rect_region(tex, Rect2(rect.position, Vector2(rect.size.x * split, rect.size.y)),
			Rect2(src.position, Vector2(src.size.x * split, src.size.y)), Color(edge.lerp(Color.WHITE, 0.25), 0.95 * alpha))
	for c: int in info["benches"]:
		var x := rect.position.x + rect.size.x * c / cols
		ci.draw_rect(Rect2(x - 1.5, rect.position.y + 2, 3, rect.size.y - 4), Color(GOLD, 0.85 * alpha))
	var gx := rect.position.x + rect.size.x * float(info["goal"]) / cols
	ci.draw_line(Vector2(gx, rect.end.y - 2), Vector2(gx, rect.position.y - 6), Color(1, 1, 1, alpha), 2.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(gx, rect.position.y - 6), Vector2(gx + 10, rect.position.y - 2),
		Vector2(gx, rect.position.y + 2)]), Color(GOLD, alpha))
	ci.draw_rect(rect, Color(edge, 0.35 * alpha), false, 1.0)


## 「第一關　基礎教學」拆成 ["第一關", "基礎教學"]
static func split_name(full: String) -> PackedStringArray:
	var parts := full.split("　", false, 1)
	if parts.size() < 2:
		parts.append("")
	return parts
