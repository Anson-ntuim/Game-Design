class_name QualityPicker
extends CanvasLayer
## 第一次開遊戲：校正完延遲後選畫面品質。三張大卡（低／中／高），點一下或 ←→ 選，空白鍵／Enter／再點一次確定。
## Esc 直接用目前的（裝置預設）。之後在設定裡也能改。

signal closed

const CARDS := [
	{"name": "低", "desc": "最順，適合手機或舊電腦", "dots": 1},
	{"name": "中", "desc": "畫面和流暢度平衡", "dots": 2},
	{"name": "高", "desc": "最漂亮，電腦比較好再選", "dots": 3},
]
const INPUT_GRACE := 0.5

var _view: Control
var _sel: int = 1
var _age: float = 0.0
var _open_t: float = 0.0


func _ready() -> void:
	layer = 22
	_sel = GameState.quality
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_view)
	_view.draw.connect(_on_draw)
	_view.gui_input.connect(_on_gui_input)


func _card_rect(i: int) -> Rect2:
	var size := _view.size
	var w := minf(300.0, (size.x - 160.0) / 3.0)
	var h := 260.0
	var total := w * 3.0 + 40.0
	return Rect2(size.x * 0.5 - total * 0.5 + i * (w + 20.0), size.y * 0.5 - h * 0.5 + 10.0, w, h)


func _pick(i: int) -> void:
	_sel = clampi(i, 0, CARDS.size() - 1)
	GameState.set_quality(_sel, false)
	GameState.play_sfx("pluck", 4.0 + _sel * 3.0, -8.0)


func _confirm() -> void:
	GameState.set_quality(_sel)
	GameState.play_sfx("pluck", 12.0, -6.0)
	closed.emit()
	queue_free()


func _on_gui_input(event: InputEvent) -> void:
	if _age < INPUT_GRACE:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in CARDS.size():
		if _card_rect(i).has_point(mb.position):
			## 點已選的那張＝確定；點別張＝先選它
			if i == _sel:
				_confirm()
			else:
				_pick(i)
			return
	if _ok_rect().has_point(mb.position):
		_confirm()


func _ok_rect() -> Rect2:
	var size := _view.size
	return Rect2(size.x * 0.5 - 130.0, size.y - 120.0, 260.0, 64.0)


func _process(delta: float) -> void:
	_age += delta
	_open_t = minf(1.0, _open_t + delta * 4.0)
	_view.queue_redraw()
	if _age < INPUT_GRACE:
		return
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("easier"):
		_pick(_sel - 1)
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("harder"):
		_pick(_sel + 1)
	elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("back"):
		_confirm()


func _on_draw() -> void:
	var size := _view.size
	var k := ease(_open_t, -2.0)
	_view.draw_rect(Rect2(Vector2.ZERO, size), UiKit.NIGHT)
	UiKit.text(_view, Vector2(0, size.y * 0.5 - 170.0), size.x, "選擇畫面品質", 34, Color(UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.8))
	for i in CARDS.size():
		var c: Dictionary = CARDS[i]
		var r := _card_rect(i)
		var on := i == _sel
		var st := StyleBoxFlat.new()
		st.anti_aliasing = true
		st.set_corner_radius_all(22)
		st.bg_color = Color(Color("2E1F5C") if on else UiKit.CARD, k)
		st.set_border_width_all(4 if on else 2)
		st.border_color = Color(UiKit.PINK if on else UiKit.LINE, k)
		_view.draw_style_box(st, r.grow(6.0 if on else 0.0))
		## 品質點數：一到三顆
		var n: int = c["dots"]
		for d in 3:
			var p := Vector2(r.get_center().x + (d - 1) * 34.0, r.position.y + 70.0)
			_view.draw_circle(p, 12.0, Color(UiKit.YELLOW if d < n else UiKit.LINE, k))
		_view.draw_string(UiKit.title_font(), Vector2(r.position.x, r.position.y + 160.0), String(c["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 64, Color(UiKit.TEXT, k))
		UiKit.text(_view, Vector2(r.position.x + 16.0, r.position.y + 215.0), r.size.x - 32.0, String(c["desc"]), 16,
			Color(UiKit.MUTED if not on else UiKit.TEXT, k), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.solid_button(_view, _ok_rect(), "空白鍵　就用這個", UiKit.PINK, UiKit.PINK_DARK, 20, k)
	UiKit.text(_view, Vector2(0, size.y - 30.0), size.x, "之後可以在「設定」裡改", 14, Color(UiKit.MUTED, k), HORIZONTAL_ALIGNMENT_CENTER)
