class_name LevelData
extends RefCounted
## 關卡由多個「區塊」左右拼接而成，每段預設高 20 格；row_offset 可把整段放在不同高度。
## row_offset 同時位移地形、音符、示範路徑與存檔點，下一段的起點要接上上一段落點。
## 圖例：
##   #  實心地形            %  光滑牆（不能滑牆/蹬牆，逼玩家用節奏能力通過）
##   =  單向平台（可從下方穿過）
##   A  黃色節拍平台        B  藍色節拍平台（兩組每 2 拍輪流出現）
##   M  節拍移動平台        m  反相的節拍移動平台
##   J  節拍鼓（每一拍鼓點響起時，把站在上面的人彈很高）
##   |  節拍光牆（每一拍打開一下，打開時衝刺才能穿過，垂直連續的 | 會合併成一道牆）
##   ^  固定尖刺            !  偶數拍伸出的尖刺    ?  奇數拍伸出的尖刺
##   E  跳拍甲蟲            C  長椅存檔點          G  終點    P  玩家起點
##   W  音浪觸發點（經過後下一個循環開頭，音浪從後方 10 格處湧出）    Y  音浪停住的位置
##   小寫字母  節奏型地形（見各關的 patterns），地形出現的節奏就是通關要打的節奏
## 區塊的 "orbs" 是節奏音符：[x, y, 節奏型, 音高]，x / y 以格為單位、指音符中心（可有小數）。
## 區塊的 "rings" 是衝刺環，格式和音符相同。
## 區塊的 "ghost" 是旗子示範時半透明角色的路徑：[x0, y0, x1, y1, …]（px，區塊內座標），每 1/8 拍一點。
## 區塊的 "plan" 是整段的標準節奏：[拍, 動作（同 demo 的字元）, 按下時的 x（px，區塊內座標）]，倒下時拿來對照（death_coach.gd）。
## flag 節奏型的 "demo" 是示範的連招（見 cue_flag.gd）。
## 區塊的 "bpm" 是玩家走進這個區塊後要換成的速度（下一個小節頭生效，預設 120）。
## 區塊的 "gravity" 是走進這個區塊後立刻強制套用的重力（預設 2400；第五關輕重力區固定 1000）。
##
## 高度參考（1 格 = 40px）：滿跳約 4.4 格、音符跳約 4.2 格、節拍鼓約 9.4 格；衝刺約 4.2 格。

const TILE := 40
const HEIGHT := 20
const MOVER_TRAVEL_TILES := 6

## 節奏型地形：字元 → 種類與節奏型（一格 = 半拍，x = 觸發；8 格 = 1 小節、16 格 = 2 小節）
##   spike 地板尖刺在 x 拍彈出    ceiling 天花板尖刺在 x 拍落下
##   platform x 期間是實體的平台（tone = 出現時的音高）    gate 只在 x 拍打開的光牆
##   piston 在 x 拍砸下的活塞（字元填滿的矩形 = 行程範圍）  laser 在 x 拍發射的雷射（直排或橫排）
##   lift 每個 x 升一階、v 開始降回的升降舞台（字元填滿的矩形 = 行程範圍）
##   rest 休止區（字元所在欄往右 cols 格）：x 的半拍要站著不動，strict = false 只發出錯音
##   blind 盲拍區（字元所在欄往右 cols 格）：x 的半拍畫面變暗；strobe = true 整段暗、每拍閃一下
## 各關的節奏型與區塊在 demo_*_data.gd（tools/gen_demo.py 產生）。

## 關卡只顯示編號；name／desc 留給舊 UI 相容，畫面以 index+1 為準
const LEVELS: Array[Dictionary] = [
	{"name": "01", "desc": "", "stars": 1,
		"patterns": Demo1Data.PATTERNS, "chunks": Demo1Data.CHUNKS},
	{"name": "02", "desc": "", "stars": 2,
		"patterns": Demo3Data.PATTERNS, "chunks": Demo3Data.CHUNKS, "stage": true},
	{"name": "03", "desc": "", "stars": 3,
		"patterns": Demo2Data.PATTERNS, "chunks": Demo2Data.CHUNKS},
	{"name": "04", "desc": "", "stars": 1,
		"patterns": Demo6Data.PATTERNS, "chunks": Demo6Data.CHUNKS},
	{"name": "05", "desc": "", "stars": 2,
		"patterns": TempoCourseData.PATTERNS, "chunks": TempoCourseData.CHUNKS, "tempo_stage": true},
	{"name": "06", "desc": "", "stars": 3,
		"patterns": Demo4Data.PATTERNS, "chunks": Demo4Data.CHUNKS, "stage": true},
]

## 同一種機關（含不同按法）在整條關卡線上，前幾次才保留提示文字
const MECHANIC_HINT_LIMIT := 2


static func level_code(index: int) -> String:
	return "%02d" % (index + 1)


## 機關種類：可在 chunk 寫 mechanic；否則用提示標題（長椅／終點會正規化）
static func mechanic_key(chunk: Dictionary) -> String:
	var explicit := String(chunk.get("mechanic", "")).strip_edges()
	if explicit != "":
		return explicit
	var text := String(chunk.get("hint", "")).strip_edges()
	if text == "":
		return ""
	var title := text.split("\n")[0].strip_edges()
	## 長椅／終點無論標題怎麼寫都算同一機關
	if title.find("長椅") >= 0:
		return "bench"
	if title.begins_with("終點") or title.begins_with("抵達") or title.find("終點") >= 0:
		return "goal"
	return title


## 統計到 level 之前，各機關已出現幾次（含更早關卡）
static func _mechanic_counts_before(level: int) -> Dictionary:
	var seen: Dictionary = {}
	for i in mini(maxi(level, 0), LEVELS.size()):
		for chunk: Dictionary in LEVELS[i]["chunks"]:
			var key := mechanic_key(chunk)
			if key == "":
				continue
			seen[key] = int(seen.get(key, 0)) + 1
	return seen


## 關卡各段落標題（hint 第一行）
static func section_titles(level: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if level < 0 or level >= LEVELS.size():
		return out
	for chunk: Dictionary in LEVELS[level]["chunks"]:
		var text := String(chunk.get("hint", "")).strip_edges()
		var title := text.split("\n")[0] if not text.is_empty() else "（無標題）"
		out.append(title)
	return out


## 把指定關卡的所有區塊拼成一張完整的字元地圖，並回傳提示範圍與音符
static func build(level: int) -> Dictionary:
	var info: Dictionary = LEVELS[level]
	var height := HEIGHT
	for chunk: Dictionary in info["chunks"]:
		height = maxi(height, int(chunk.get("row_offset", 0)) + chunk["rows"].size())
	var grid: Array[String] = []
	for r in height:
		grid.append("")
	var hints: Array[Dictionary] = []
	var orbs: Array[Dictionary] = []
	var rings: Array[Dictionary] = []
	var ghosts: Array[Dictionary] = []
	var dual_orbs: Array[Dictionary] = []
	var slow_items: Array[Dictionary] = []
	var gravity_switches: Array[Dictionary] = []
	var gravity_zones: Array[Dictionary] = []
	var path_blocks: Array[Dictionary] = []
	var tempo_pads: Array[Dictionary] = []
	## 和 hints 一一對應
	var plans: Array = []
	var x_offset := 0
	var mechanic_seen: Dictionary = _mechanic_counts_before(level)
	for chunk: Dictionary in info["chunks"]:
		var rows: Array = chunk["rows"]
		var row_offset := int(chunk.get("row_offset", 0))
		var y_offset := row_offset * TILE
		var lines: Array[String] = []
		var w := 0
		for r in height:
			var local_row := r - row_offset
			var line: String = rows[local_row] if local_row >= 0 and local_row < rows.size() else ""
			lines.append(line)
			w = maxi(w, line.length())
		for r in height:
			grid[r] += lines[r].rpad(w)
		## 同一機關前 MECHANIC_HINT_LIMIT 次保留提示，之後清空（區塊節奏／重力仍照常）
		var hint_text := String(chunk.get("hint", ""))
		var mkey := mechanic_key(chunk)
		if mkey != "":
			var seen_n := int(mechanic_seen.get(mkey, 0))
			if seen_n >= MECHANIC_HINT_LIMIT:
				hint_text = ""
			mechanic_seen[mkey] = seen_n + 1
		hints.append({"from": x_offset * TILE, "to": (x_offset + w) * TILE, "text": hint_text,
			"mechanic": mkey,
			"bpm": float(chunk.get("bpm", 120)), "gravity": float(chunk.get("gravity", 2400)),
			"score_beats": float(chunk.get("score_beats", 0)),
			"subdivision_cue": bool(chunk.get("subdivision_cue", false)),
			"music_duck": float(chunk.get("music_duck", 0)),
			"kill_y": (row_offset + rows.size()) * TILE + 120.0})
		for o: Array in chunk.get("orbs", []):
			orbs.append({
				"pos": Vector2((x_offset + float(o[0])) * TILE, float(o[1]) * TILE + y_offset),
				"notes": o[2],
				"tone": float(o[3]) if o.size() > 3 else 12.0,
				"subdiv": int(o[4]) if o.size() > 4 else 2,
			})
		for o: Array in chunk.get("rings", []):
			rings.append({
				"pos": Vector2((x_offset + float(o[0])) * TILE, float(o[1]) * TILE + y_offset),
				"notes": o[2],
				"tone": float(o[3]) if o.size() > 3 else 19.0,
			})
		for pad: Array in chunk.get("tempo_pads", []):
			tempo_pads.append({"pos": Vector2((x_offset + float(pad[0])) * TILE, float(pad[1]) * TILE + y_offset),
				"bpm": float(pad[2]), "width": float(pad[3]) * TILE if pad.size() > 3 else 144.0})
		for o: Array in chunk.get("dual_orbs", []):
			dual_orbs.append({
				"pos": Vector2((x_offset + float(o[0])) * TILE, float(o[1]) * TILE + y_offset),
				"notes3": o[2],
				"notes4": o[3],
				"tone": float(o[4]) if o.size() > 4 else 12.0,
			})
		for o: Array in chunk.get("slow_items", []):
			slow_items.append({
				"pos": Vector2((x_offset + float(o[0])) * TILE, float(o[1]) * TILE + y_offset),
			})
		for o: Array in chunk.get("gravity_switches", []):
			gravity_switches.append({
				"pos": Vector2((x_offset + float(o[0])) * TILE, float(o[1]) * TILE + y_offset),
				"id": String(o[2]),
				"label": String(o[3]) if o.size() > 3 else "切換重力道路",
			})
		for z: Dictionary in chunk.get("gravity_zones", []):
			gravity_zones.append({
				"from": (x_offset + float(z["from"])) * TILE,
				"to": (x_offset + float(z["to"])) * TILE,
				"gravity": float(z.get("gravity", 2400.0)),
				"flip": bool(z.get("flip", false)),
			})
		for b: Array in chunk.get("path_blocks", []):
			path_blocks.append({
				"rect": Rect2(
					(x_offset + float(b[0])) * TILE, float(b[1]) * TILE + y_offset,
					float(b[2]) * TILE, float(b[3]) * TILE),
				"id": String(b[4]),
			})
		var g: Array = chunk.get("ghost", [])
		if not g.is_empty():
			var pts := PackedVector2Array()
			for i in range(0, g.size() - 1, 2):
				pts.append(Vector2(x_offset * TILE + float(g[i]), float(g[i + 1]) + y_offset))
			ghosts.append({"from": x_offset * TILE, "to": (x_offset + w) * TILE, "points": pts})
		var steps: Array[Dictionary] = []
		for s: Array in chunk.get("plan", []):
			steps.append({"beat": float(s[0]), "act": String(s[1]), "x": x_offset * TILE + float(s[2])})
		plans.append(steps)
		x_offset += w
	return {
		"grid": grid, "width": x_offset, "height": height, "hints": hints, "orbs": orbs, "rings": rings, "ghosts": ghosts,
		"plans": plans, "dual_orbs": dual_orbs, "slow_items": slow_items, "gravity_switches": gravity_switches,
		"gravity_zones": gravity_zones, "path_blocks": path_blocks,
		"patterns": info["patterns"], "name": level_code(level), "stage": info.get("stage", false),
		"tempo_pads": tempo_pads, "tempo_stage": bool(info.get("tempo_stage", false)),
	}
