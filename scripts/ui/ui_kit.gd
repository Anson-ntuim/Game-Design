class_name UiKit
extends RefCounted
## 介面共用的畫法：字型、圓角卡片面板、按鍵小方塊、音符難度、關卡縮圖。
## 2026 改版（設計稿「Heart Beat UI 改版提案」）：月夜紫底、圓角卡片、粗框，
## 三個重點色對應三種動作：粉＝跳、青＝衝刺、黃＝音符。各場景主題不再各畫一種面板，統一用同一套卡片。
## 佈局依 game-ui-ux：錨在邊角 + 安全邊距（notch／圓角／過掃描），不要寫死貼邊座標。

## 網頁版沒有系統字型，只能用專案裡的字型檔；它只含遊戲用到的字，改了文字要重跑 tools/subset_font.py
const FONT_PATH := "res://assets/fonts/NotoSansTC-Game.ttf"
## 標題、數字用的圓體（Google Fonts 的 Fredoka，SIL OFL 授權，見 assets/fonts/Fredoka-OFL.txt）。
## 只有拉丁字母和數字；中文字自動退回思源黑體
const DISPLAY_FONT_PATH := "res://assets/fonts/Fredoka.ttf"
## 改版色盤
const NIGHT := Color("1A1036")
const CARD := Color("261A4D")
const LINE := Color("4A3A80")
const PINK := Color("FF6FAE")
const PINK_DARK := Color("B23A74")
const CYAN := Color("5BE7F2")
const YELLOW := Color("FFD45C")
const TEXT := Color("FFF6FB")
const MUTED := Color("C9BEE8")
const PANEL := Color(0.149, 0.102, 0.302, 0.9)
const INK := Color("1A1036")
const GOLD := YELLOW
const FLOAT := CYAN
const CUT := 12.0
const KEY_H := 24.0
## 桌面／網頁至少留這圈；手機再疊 DisplayServer safe area
const SAFE_PAD := 24.0

static var _fonts: Dictionary = {}
static var _minimaps: Dictionary = {}
static var _soft_panel_style: StyleBoxFlat
static var _sakura_panel_style: StyleBoxFlat
static var _festival_panel_style: StyleBoxFlat


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


## 標題字：Fredoka 粗體（可變字型 wght 700），中文退回加粗的思源黑體
static func title_font() -> Font:
	return display_font(700)


static func display_font(weight: int = 700) -> Font:
	var key := "display%d" % weight
	if not _fonts.has(key):
		if not ResourceLoader.exists(DISPLAY_FONT_PATH):
			_fonts[key] = font(0.9)
		else:
			var fv := FontVariation.new()
			fv.base_font = load(DISPLAY_FONT_PATH)
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
			fv.fallbacks = [font(0.9)]
			_fonts[key] = fv
	return _fonts[key]


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


## 圓角矩形的多邊形（舊名 chamfer 保留給既有呼叫：現在一律是圓角）；cut 決定圓角大小
static func chamfer(rect: Rect2, cut: float = CUT) -> PackedVector2Array:
	var r := minf(cut * 1.4, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c: Array in corners:
		for k in 6:
			var a: float = float(c[1]) + PI * 0.5 * k / 5.0
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


static var _card_style: StyleBoxFlat


## 卡片面板：月夜紫底、3px 框、圓角。glow > 0 時框換成重點色並多一圈淡光（選中、強調）
static func panel(ci: CanvasItem, rect: Rect2, edge: Color, glow: float = 0.0, alpha: float = 1.0,
		cut: float = CUT, fill: Color = PANEL) -> void:
	if _card_style == null:
		_card_style = StyleBoxFlat.new()
		_card_style.anti_aliasing = true
	var radius := int(minf(cut * 1.5, minf(rect.size.x, rect.size.y) * 0.5))
	var g := clampf(glow, 0.0, 1.0)
	if g > 0.0:
		var halo := StyleBoxFlat.new()
		halo.anti_aliasing = true
		halo.set_corner_radius_all(radius + 6)
		halo.bg_color = Color(edge, 0.18 * g * alpha)
		ci.draw_style_box(halo, rect.grow(6.0))
	var st := _card_style
	st.set_corner_radius_all(radius)
	st.set_border_width_all(3 if rect.size.y > 40.0 else 2)
	st.bg_color = Color(fill, fill.a * alpha)
	st.border_color = Color(LINE.lerp(edge, g), alpha)
	ci.draw_style_box(st, rect)


## 重點按鈕：實心重點色、下方一條深色「厚度」（設計稿的主按鈕）
static func solid_button(ci: CanvasItem, rect: Rect2, label: String, fill: Color = PINK,
		shade: Color = PINK_DARK, size: int = 22, alpha: float = 1.0) -> void:
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(int(minf(20.0, rect.size.y * 0.3)))
	st.bg_color = Color(shade, alpha)
	ci.draw_style_box(st, Rect2(rect.position + Vector2(0, 5), rect.size))
	st.bg_color = Color(fill, alpha)
	ci.draw_style_box(st, rect)
	ci.draw_string(font(0.25), Vector2(rect.position.x, rect.get_center().y + size * 0.36), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, Color(INK, alpha))


## 舊的各場景主題面板：改版後統一成同一種卡片
static func soft_panel(ci: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	panel(ci, rect, LINE, 0.0, alpha)


static func sakura_panel(ci: CanvasItem, rect: Rect2, alpha: float = 1.0, accent: float = 0.0) -> void:
	panel(ci, rect, PINK, accent * 0.6, alpha)


static func festival_panel(ci: CanvasItem, rect: Rect2, alpha: float = 1.0, accent: float = 0.0) -> void:
	panel(ci, rect, PINK, accent * 0.6, alpha)


## 按鍵小方塊：pos 是左上角，回傳寬度
static func keycap(ci: CanvasItem, pos: Vector2, label: String, edge: Color, alpha: float = 1.0,
		size: int = 13, soft: bool = false, sakura: bool = false,
		festival: bool = false) -> float:
	var f := font()
	var w := maxf(KEY_H, width_of(label, size, f) + 14.0)
	var r := Rect2(pos, Vector2(w, KEY_H))
	var st := StyleBoxFlat.new()
	st.anti_aliasing = true
	st.set_corner_radius_all(7)
	st.bg_color = Color(NIGHT, 0.9 * alpha)
	ci.draw_style_box(st, Rect2(r.position + Vector2(0, 3), r.size))
	st.bg_color = Color(CARD, 0.95 * alpha)
	st.set_border_width_all(2)
	st.border_color = Color(LINE, alpha)
	ci.draw_style_box(st, r)
	ci.draw_string(f, Vector2(r.position.x, r.position.y + KEY_H * 0.5 + size * 0.36), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(TEXT, alpha))
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
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, size: int = 13,
		soft: bool = false, sakura: bool = false, festival: bool = false) -> void:
	var total := key_hints_width(items, size)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= total * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= total
	for it: Array in items:
		for k: String in it[0]:
			x += keycap(ci, Vector2(x, y), k, edge, alpha, size, soft, sakura, festival) + 4.0
		x += 4.0
		var label := String(it[1])
		var label_color := Color.WHITE
		if soft:
			label_color = Color("f6e7ee")
		if sakura:
			label_color = Color("fff0e8")
		if festival:
			label_color = Color("efeaff")
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
