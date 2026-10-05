class_name DeathCoach
extends RefCounted
## 倒下時看玩家最後幾個動作和碰到的機關，判斷是不是「太短、太長、太早、太晚」其中一種，
## 是的話給一句指令；其他原因（沒按、沒衝刺、走下懸崖…）不給提示。
## 有標準節奏（區塊的 plan）的段落，拿這次起跳的位置去找標準節奏裡同一個位置的動作，
## 對照這下該長按還是輕點、之後的音符和衝刺按得早還晚、起跳本身早還晚；
## 光柱走廊這類沒有 plan 的段落只看按錯拍的紀錄和跳的長短。
## 回傳 {"tag": 原因代號, "title": 太短了／太長了／太早了／太晚了, "detail": 指令}，不給提示時回傳空的

## 倒下前這幾拍內的動作才算「剛剛」（掉坑從起跳到掉出畫面就要兩拍多）
const RECENT := 4.0
## 起跳位置和標準節奏差這麼多 px 內才拿來對照（跑一拍約 155px）
const MATCH_PX := 60.0
## 早／晚超過這麼多拍才算
const OFF_BEATS := 0.12
## 標準節奏裡的音符、衝刺，玩家在這麼多拍內有按才算「按了但早晚不對」
const NEAR_BEATS := 0.75


static func advise(p: Player, plan: Array) -> Dictionary:
	var tip := _find(p, plan)
	return {} if tip.is_empty() or tip["tag"] == "" else tip


static func _find(p: Player, plan: Array) -> Dictionary:
	var src := p.death_source
	var b := p.death_beat
	var jump: Dictionary = p.last_jump if not p.last_jump.is_empty() and b - float(p.last_jump["beat"]) < RECENT else {}
	var long_jump := not jump.is_empty() and bool(jump["long"])
	if src is PatternLaser and not (src as PatternLaser).vertical and long_jump:
		return _too_long()
	if src is PatternSpike and (src as PatternSpike).ceiling and long_jump:
		return _too_long()

	var miss: Dictionary = p.last_miss if not p.last_miss.is_empty() and b - float(p.last_miss["beat"]) < RECENT else {}
	if src == null and not miss.is_empty() and not is_nan(float(miss["off"])):
		return _timing(float(miss["off"]), _press_word(String(miss["what"])))
	var planned := _plan_tip(p, jump, plan)
	if not planned.is_empty():
		return planned
	if src == null and plan.is_empty() and not jump.is_empty() and not long_jump:
		return _too_short()
	return {}


## 拿這次起跳去對照標準節奏；對不上回傳空的，找到原因但不是早晚長短時 tag 是空字串
static func _plan_tip(p: Player, jump: Dictionary, plan: Array) -> Dictionary:
	if jump.is_empty() or plan.is_empty() or jump["kind"] == "pad":
		return {}
	var idx := -1
	var best := MATCH_PX
	for i in plan.size():
		var s: Dictionary = plan[i]
		if not String(s["act"]) in ["T", "L", "o", "O"]:
			continue
		var d := absf(float(s["x"]) - float(jump["x"]))
		if d < best:
			best = d
			idx = i
	if idx == -1:
		return {}
	var step: Dictionary = plan[idx]
	var want_long := String(step["act"]) in ["L", "O"]
	if want_long and not jump["long"]:
		return _too_short()
	if not want_long and jump["long"]:
		return _too_long()

	# 這一跳之後、下一次跳之前的音符和衝刺：拍子用自己這次起跳去比，起跳本身早晚最後另外看
	var j0 := float(jump["beat"])
	var k := idx + 1
	while k < plan.size():
		var st: Dictionary = plan[k]
		var act := String(st["act"])
		var due := j0 + float(st["beat"]) - float(step["beat"])
		if p.death_beat < due - 0.2:
			break
		var orb := act in ["o", "O"]
		if not orb and not act in ["D", "R"]:
			break
		var hit := _nearest(p.recent_air_presses if orb else p.recent_dashes, due, j0)
		if absf(hit - due) > NEAR_BEATS:
			return {"tag": ""}
		if absf(hit - due) > OFF_BEATS:
			return _timing(hit - due, "音符" if orb else ("衝刺環" if act == "R" else "衝刺"))
		if orb:
			break
		k += 1

	var off := fposmod(j0 - float(step["beat"]) + 4.0, 8.0) - 4.0
	if absf(off) > OFF_BEATS:
		return _timing(off, "起跳")
	return {}


static func _press_word(what: String) -> String:
	match what:
		"orb":
			return "音符"
		"ring":
			return "衝刺環"
	return "衝刺"


## off：負的是早、正的是晚；what：起跳／音符／衝刺／衝刺環
static func _timing(off: float, what: String) -> Dictionary:
	var early := off < 0.0
	var fix := "晚一點" if early else "早一點"
	var detail := fix + "起跳" if what == "起跳" else what + fix + "按"
	return {"tag": "early" if early else "late", "title": "太早了" if early else "太晚了", "detail": detail}


static func _too_short() -> Dictionary:
	return {"tag": "too_short", "title": "太短了", "detail": "跳鍵按久一點"}


static func _too_long() -> Dictionary:
	return {"tag": "too_long", "title": "太長了", "detail": "輕點跳鍵就好"}


## beats 裡在 after 之後、最接近 target 的拍子（沒有回傳 INF）
static func _nearest(beats: Array[float], target: float, after: float) -> float:
	var hit := INF
	for d in beats:
		if d >= after and absf(d - target) < absf(hit - target):
			hit = d
	return hit
