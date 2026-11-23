extends Node2D
## 開機畫面：①「戴上耳機或打開聲音」提示 → ② Logo → 進主選單。
## 按任意鍵或點一下跳到下一步。網頁版瀏覽器要先有一次點擊才能出聲，所以第一步會等玩家點一下再繼續。
## Logo 圖放在 res://assets/ui/logo.png（透明背景）；還沒有圖時用角色＋遊戲名稱代替。

const HOME_SCENE := "res://scenes/home.tscn"
const LOGO_PATH := "res://assets/ui/logo.png"
const NOTICE_TIME := 2.6
const LOGO_TIME := 2.6
const FADE := 0.45

var _view: Control
var _phase: int = 0
var _t: float = 0.0
var _logo: Texture2D = null
var _waiting_click: bool = false


func _ready() -> void:
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.size = get_viewport_rect().size
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_view)
	_view.draw.connect(_on_draw)
	if ResourceLoader.exists(LOGO_PATH):
		_logo = load(LOGO_PATH)
	_waiting_click = OS.has_feature("web")


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	_waiting_click = false
	_next()


func _next() -> void:
	if _phase == 0:
		_phase = 1
		_t = 0.0
	else:
		get_tree().change_scene_to_file(HOME_SCENE)


func _process(delta: float) -> void:
	_view.size = get_viewport_rect().size
	_t += delta
	var dur := NOTICE_TIME if _phase == 0 else LOGO_TIME
	if _phase == 0 and _waiting_click:
		_t = minf(_t, FADE)
	elif _t >= dur:
		_next()
	_view.queue_redraw()


## 淡入、停住、淡出
func _alpha(dur: float) -> float:
	return clampf(minf(_t / FADE, (dur - _t) / FADE), 0.0, 1.0)


func _on_draw() -> void:
	var size := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, size), UiKit.NIGHT)
	var c := size * 0.5
	if _phase == 0:
		var a := _alpha(NOTICE_TIME) if not _waiting_click else clampf(_t / FADE, 0.0, 1.0)
		_draw_headphones(c + Vector2(0, -60), Color(UiKit.TEXT, a))
		var line := "戴上耳機或打開聲音，獲得最佳體驗"
		UiKit.text(_view, Vector2(0, c.y + 60), size.x, line, 26, Color(UiKit.TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, UiKit.font(0.6))
		if _waiting_click:
			UiKit.text(_view, Vector2(0, c.y + 104), size.x, "點一下繼續", 18, Color(UiKit.MUTED, a), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var a := _alpha(LOGO_TIME)
		## 進場時輕輕放大到原尺寸
		var s := lerpf(0.92, 1.0, ease(clampf(_t / 0.6, 0.0, 1.0), 0.4))
		if _logo:
			var h := size.y * 0.62 * s
			var w := h * float(_logo.get_width()) / float(_logo.get_height())
			_view.draw_texture_rect(_logo, Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h), false, Color(1, 1, 1, a))
		else:
			## draw_skin 自己會設 transform，所以直接給腳的位置和縮放
			Player.draw_skin(_view, 0, c + Vector2(0, 40), Vector2(4.0, 4.0) * s, 0.0, Color(1, 1, 1, a))
			var f := UiKit.title_font()
			var title := GameState.GAME_TITLE
			var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 88).x
			_view.draw_string(f, Vector2(c.x - tw * 0.5 + 5, c.y + 150), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 88, Color(UiKit.PINK, a))
			_view.draw_string(f, Vector2(c.x - tw * 0.5, c.y + 145), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 88, Color(UiKit.TEXT, a))


## 簡單的耳機圖示：頭帶＋兩個耳罩
func _draw_headphones(at: Vector2, col: Color) -> void:
	_view.draw_arc(at + Vector2(0, 10), 52.0, PI * 1.05, PI * 1.95, 40, col, 9.0, true)
	for side: float in [-1.0, 1.0]:
		var cup := Rect2(at.x + side * 50.0 - 15.0, at.y + 4.0, 30.0, 50.0)
		var st := StyleBoxFlat.new()
		st.anti_aliasing = true
		st.set_corner_radius_all(12)
		st.bg_color = col
		_view.draw_style_box(st, cup)
	## 兩邊的聲波
	for side: float in [-1.0, 1.0]:
		for k in 2:
			var r := 22.0 + k * 14.0
			var mid := 0.0 if side > 0 else PI
			_view.draw_arc(at + Vector2(side * 74.0, 30.0), r, mid - 0.6, mid + 0.6, 16, Color(UiKit.PINK, col.a * (0.9 - k * 0.3)), 4.0, true)
