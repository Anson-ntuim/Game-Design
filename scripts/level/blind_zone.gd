class_name BlindZone
extends Node2D
## 盲拍區：玩家在區內時，notes 裡 x 的半拍畫面變暗，只剩角色周圍一圈微光。
## 機關照常運作、提示音照常響，暗掉時要靠剛才看到的地形和耳朵跑。
## strobe = true：整段都暗，只在每一拍的鼓點閃一下。
## 畫面的黑幕由主場景依 darkness() 交給 HUD 畫。

const COLOR := Color(0.7, 0.75, 1.0)

var left: float = 0.0
var right: float = 0.0
var ground_y: float = 640.0
var notes: String = ""
var strobe: bool = false


func setup(x0: float, x1: float, floor_y: float, pattern: String, is_strobe: bool) -> void:
	left = x0
	right = x1
	ground_y = floor_y
	notes = pattern
	strobe = is_strobe


func _ready() -> void:
	z_index = 2


func contains(x: float) -> bool:
	return x >= left and x <= right


## 0 = 全亮、1 = 全暗
func darkness(b: float, x: float) -> float:
	if not contains(x):
		return 0.0
	if strobe:
		return 1.0 - Conductor.pulse(7.0)
	return 1.0 if notes[posmod(floori(b * 2.0), notes.length())] == "x" else 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var top := ground_y - 15.0 * LevelData.TILE
	for x in [left, right]:
		var y := top
		while y < ground_y:
			draw_line(Vector2(x, y), Vector2(x, minf(y + 6.0, ground_y)), Color(COLOR, 0.35), 2.0)
			y += 18.0
