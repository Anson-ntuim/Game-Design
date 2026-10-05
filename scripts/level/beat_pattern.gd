class_name BeatPattern
extends RefCounted
## 節奏型：一個字元 = 一個八分音符（半拍），x = 觸發、. = 空。
## 整串是一個循環，從歌曲第 0 拍（小節開頭）對齊：8 個字元 = 1 小節、16 個字元 = 2 小節。

## 只讓玩家附近的地形發出提示音
static func near_player(node: Node2D, distance: float = 900.0) -> bool:
	var p := node.get_tree().get_first_node_in_group("player") as Node2D
	return p != null and absf(p.global_position.x - node.global_position.x) < distance


static func cycle(notes: String) -> float:
	return notes.length() * 0.5


static func _slot(notes: String, beat: float) -> int:
	return mini(floori(fposmod(beat, cycle(notes)) * 2.0), notes.length() - 1)


static func is_on(notes: String, beat: float) -> bool:
	return not notes.is_empty() and notes[_slot(notes, beat)] == "x"


## 距離上一個 x 格開始過了幾拍（沒有 x 時回傳 INF）
static func since_hit(notes: String, beat: float) -> float:
	var c := cycle(notes)
	var p := fposmod(beat, c)
	var best := INF
	for i in notes.length():
		if notes[i] == "x":
			best = minf(best, fposmod(p - i * 0.5, c))
	return best


## 距離下一個 x 格開始還有幾拍（正好在 x 的開頭時回傳一整個循環；沒有 x 時回傳 INF）
static func until_hit(notes: String, beat: float) -> float:
	var c := cycle(notes)
	var p := fposmod(beat, c)
	var best := INF
	for i in notes.length():
		if notes[i] == "x":
			var d := fposmod(i * 0.5 - p, c)
			best = minf(best, d if d > 0.0 else c)
	return best


## 離最近的 x 格開頭幾拍：負的是還沒到（按早了）、正的是已經過了（按晚了）
static func offset(notes: String, beat: float) -> float:
	var since := since_hit(notes, beat)
	var until := until_hit(notes, beat)
	return since if since <= until else -until


## 距離下一個「由空轉為 x」的時間點還有幾拍（沒有時回傳 INF）
static func until_start(notes: String, beat: float) -> float:
	var c := cycle(notes)
	var p := fposmod(beat, c)
	var n := notes.length()
	var best := INF
	for i in n:
		if notes[i] == "x" and notes[posmod(i - 1, n)] != "x":
			var d := fposmod(i * 0.5 - p, c)
			if d > 0.0:
				best = minf(best, d)
	return best


## 目前這段連續 x 還剩幾拍結束（不在 x 上回傳 0）
static func until_end(notes: String, beat: float) -> float:
	if not is_on(notes, beat):
		return 0.0
	var n := notes.length()
	var p := fposmod(beat, cycle(notes))
	var i := _slot(notes, beat)
	var steps := 0
	while notes[posmod(i + 1, n)] == "x" and steps < n:
		i += 1
		steps += 1
	return (i + 1) * 0.5 - p
