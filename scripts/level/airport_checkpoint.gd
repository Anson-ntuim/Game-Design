extends Checkpoint
## 第六關的候機長椅：第一次存檔時，旁邊的機械牌沿中央轉軸翻面。

const BOARD := preload("res://assets/themes/dawn_airport/boarding_sign.svg")
const BOARD_ORIGIN := Vector2(24, -70)
const CARD := Rect2(28, -65, 40, 26)
const WAITING_FACE := Rect2(52, 5, 40, 26)
const SAVED_FACE := Rect2(100, 5, 40, 26)
const ART_SCALE := 2.0
const FLIP_SECONDS := 0.48

var _flip_progress := 0.0


func _ready() -> void:
	super()
	activated.connect(_on_first_save, CONNECT_ONE_SHOT)


func _on_first_save(_checkpoint: Checkpoint) -> void:
	create_tween().tween_property(self, "_flip_progress", 1.0, FLIP_SECONDS)


func _draw() -> void:
	super()
	draw_texture_rect_region(BOARD, Rect2(BOARD_ORIGIN, Vector2(48, 70)), Rect2(0, 0, 96, 140))
	if _flip_progress <= 0.0:
		_draw_card(CARD, WAITING_FACE)
	elif _flip_progress >= 1.0:
		_draw_card(CARD, SAVED_FACE, Color.WHITE if active else Color("#bbb4b5"))
	else:
		_draw_flip()
	draw_line(Vector2(CARD.position.x, CARD.get_center().y), Vector2(CARD.end.x, CARD.get_center().y),
		Color("#292c3990"), 1.0)


func _draw_flip() -> void:
	var half := Vector2(CARD.size.x, CARD.size.y * 0.5)
	var hinge := CARD.position + Vector2(0, half.y)
	var lower := Vector2(0, half.y)
	_draw_card(Rect2(CARD.position, half), Rect2(SAVED_FACE.position, half))
	_draw_card(Rect2(hinge, half), Rect2(WAITING_FACE.position + lower, half))
	# 舊的上葉收向轉軸，再展開新的下葉。轉到側面時讓葉片自然變暗。
	var fold := cos(PI * _flip_progress)
	var leaf := Vector2(half.x, half.y * absf(fold))
	var tint := Color.WHITE.darkened(0.44 * (1.0 - absf(fold)))
	if fold > 0.0:
		_draw_card(Rect2(hinge - Vector2(0, leaf.y), leaf), Rect2(WAITING_FACE.position, half), tint)
	elif fold < 0.0:
		_draw_card(Rect2(hinge, leaf), Rect2(SAVED_FACE.position + lower, half), tint)


func _draw_card(rect: Rect2, source: Rect2, tint: Color = Color.WHITE) -> void:
	draw_texture_rect_region(BOARD, rect, Rect2(source.position * ART_SCALE, source.size * ART_SCALE), tint)
