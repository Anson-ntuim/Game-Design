class_name TouchControls
extends CanvasLayer
## 手機觸控按鍵（關卡中）：一律自動前進，所以只需要兩個動作。
##   畫面右半邊任何地方按下＝跳（空白鍵），左半邊＝衝刺（Shift）；上方中間的圓鈕＝暫停（Esc）。
## 用 Input.action_press／action_release 模擬按鍵，遊戲其他地方不用改。多指同時按也可以（各指各算）。
## 只在有觸控螢幕的裝置顯示（或環境變數 HB_TOUCH=1，桌機測試用）；第一次碰到觸控也會自動打開。

const PAUSE_R := 30.0

var _view: Control
var _held: Dictionary = {}  ## 手指編號 → 動作名稱
var _flash: Dictionary = {"jump": 0.0, "dash": 0.0}
var _shown: bool = false


static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_environment("HB_TOUCH") == "1"


func _ready() -> void:
	layer = 15
	## 暫停時也要收得到「放開」，不然按著的鍵會卡住
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown = wanted()
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_on_draw)


func _exit_tree() -> void:
	for a: String in _held.values():
		Input.action_release(a)
	_held.clear()


## 「看示範」按鈕（倒下太多次、站在旗子前時才出現），在暫停鈕左邊
func _demo_rect() -> Rect2:
	var pc := _pause_center()
	return Rect2(pc.x - PAUSE_R - 150.0, pc.y - 22.0, 132.0, 44.0)


func _pause_center() -> Vector2:
	return Vector2(_view.size.x * 0.5, 34.0)


func _action_at(pos: Vector2) -> String:
	## 過關畫面：點下面三顆按鈕＝選關（Esc）／再玩一次（R）／下一關（Enter），其他地方不動作
	var main := get_tree().get_first_node_in_group("main")
	if main and bool(main.get("_completed")):
		var hud: Node = main.get("hud")
		var i: int = hud.call("result_button_at", pos) if hud else -1
		return ["back", "restart", "confirm"][i] if i >= 0 else ""
	if pos.distance_to(_pause_center()) <= PAUSE_R + 10.0:
		return "back"
	if main and main.call("demo_offer_ready") and _demo_rect().grow(10.0).has_point(pos):
		return "up"
	return "dash" if pos.x < _view.size.x * 0.5 else "jump"


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null:
		return
	_shown = true
	## 暫停選單開著時不模擬按鍵（讓觸控照常當成點選單），只處理放開
	if t.pressed and get_tree().paused:
		return
	if t.pressed:
		var action := _action_at(t.position)
		if action == "":
			return
		_held[t.index] = action
		Input.action_press(action)
		if _flash.has(action):
			_flash[action] = 1.0
	elif _held.has(t.index):
		Input.action_release(String(_held[t.index]))
		_held.erase(t.index)
	## 觸控不要再被當成滑鼠點擊傳下去（關卡裡沒有要點的東西）
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for k: String in _flash.keys():
		_flash[k] = maxf(0.0, float(_flash[k]) - delta * 4.0)
	visible = _shown
	if _shown:
		_view.queue_redraw()


func _on_draw() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and bool(main.get("_completed")):
		return
	var size := _view.size
	var r := minf(70.0, size.y * 0.11)
	var y := size.y - r - 28.0
	_draw_button(Vector2(r + 36.0, y), r, "衝刺", UiKit.CYAN, _flash["dash"])
	_draw_button(Vector2(size.x - r - 36.0, y), r, "跳", UiKit.PINK, _flash["jump"])
	if main and main.call("demo_offer_ready"):
		var dr := _demo_rect()
		var st := StyleBoxFlat.new()
		st.anti_aliasing = true
		st.set_corner_radius_all(22)
		st.bg_color = Color(UiKit.YELLOW, 0.92)
		_view.draw_style_box(st, dr)
		UiKit.text(_view, Vector2(dr.position.x, dr.position.y + 29.0), dr.size.x, "看示範", 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
	## 暫停
	var pc := _pause_center()
	_view.draw_circle(pc, PAUSE_R, Color(UiKit.NIGHT, 0.55))
	_view.draw_arc(pc, PAUSE_R, 0.0, TAU, 32, Color(UiKit.TEXT, 0.5), 2.0, true)
	for dx: float in [-6.0, 6.0]:
		_view.draw_rect(Rect2(pc.x + dx - 3.0, pc.y - 10.0, 6.0, 20.0), Color(UiKit.TEXT, 0.85))


## 半透明圓鈕：平常淡淡的，按下去亮一下
func _draw_button(c: Vector2, r: float, label: String, col: Color, flash: float) -> void:
	_view.draw_circle(c, r, Color(col, 0.16 + 0.35 * flash))
	_view.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.55 + 0.4 * flash), 3.0, true)
	UiKit.text(_view, Vector2(c.x - r, c.y + 9), r * 2.0, label, 24, Color(UiKit.TEXT, 0.85), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
