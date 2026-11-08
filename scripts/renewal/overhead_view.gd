extends Node
## 全局俯视（V 键）
##
## 需求：不只是一张固定全图，而是「在任意地点打开，就能看任意地方的俯视图」。
## 所以这里是一个真正可移动的俯视相机：平移、缩放都跟随地图实时渲染，不是贴图。
##
## 操作：
##   V            打开 / 关闭
##   W A S D      平移（按当前视高等比缩放速度）
##   方向键        同上
##   鼠标右键拖动   平移
##   滚轮          缩放（视高 60 ~ 620 m）
##   左键点击      把玩家传送过去（等价于原版地图的点击跳转）
##   Esc          关闭
##
## 不碰原版 M 键地图：M 仍然打开原来的全图面板。上次往它的 PanelContainer 里
## 注入按钮，把布局和点击一起弄坏了，这次完全独立、零注入。

const MIN_H := 60.0
const MAX_H := 620.0
const START_H := 220.0
const ZOOM_STEP := 0.86
## 相机前倾比例：0 = 纯垂直俯视（看不出建筑高度），0.35 约等于俯角 71°
const TILT := 0.35

var layer: Node
var main: Node
var player: CharacterBody3D
var enabled := false

var cam: Camera3D
var _ui: CanvasLayer
var _panel: PanelContainer
var _label: Label
var _height := START_H
var _target := Vector3.ZERO
var _saved_cam: Camera3D
var _dragging := false
var _drag_prev := Vector2.ZERO
var _built := false
var _v_was_down := false
var _say_timer := 0.0
var _auto_open := false

func setup(p_layer: Node) -> void:
	layer = p_layer
	main = layer.main
	player = layer.player
	_auto_open = OS.get_cmdline_user_args().has("--overhead=open")
	set_process(true)

func _build() -> void:
	if _built:
		return
	_built = true
	cam = Camera3D.new()
	cam.name = "OverheadCamera"
	cam.fov = 55.0
	cam.near = 1.0
	cam.far = 4000.0
	add_child(cam)

	_ui = CanvasLayer.new()
	_ui.name = "OverheadUI"
	_ui.layer = 40
	add_child(_ui)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.11, 0.82)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(24, 24)
	_ui.add_child(_panel)

	var v := VBoxContainer.new()
	_panel.add_child(v)
	var title := Label.new()
	title.text = "全局俯视"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82))
	v.add_child(title)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.80, 0.90, 0.92))
	v.add_child(_label)
	var hint := Label.new()
	hint.text = "WASD / 方向键 平移 · 右键拖动 · 滚轮缩放\n左键点击传送 · V 或 Esc 关闭"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.66, 0.76, 0.78))
	v.add_child(hint)
	_panel.visible = false

func _process(delta: float) -> void:
	if not _built:
		_build()
	var v_now := Input.is_key_pressed(KEY_V)
	if v_now and not _v_was_down:
		_toggle()
	_v_was_down = v_now
	if not enabled:
		return
	_pan(delta)
	_update_camera()
	_update_label(delta)

func _toggle() -> void:
	_set_enabled(not enabled)

func _set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_saved_cam = get_viewport().get_camera_3d()
		_target = player.global_position if player != null else Vector3.ZERO
		_height = START_H
		_update_camera()
		cam.make_current()
		_panel.visible = true
		# 停掉玩家控制器的每帧处理：它可能每帧把自己相机设回 current，
		# 那样俯视相机会被顶掉；同时避免 WASD 把人一起带着走。
		if player != null:
			player.set("program_driven", true)
			player.set("automated_motion", false)
			player.set("automated_horizontal", Vector2.ZERO)
			player.set_process(false)
			player.set_physics_process(false)
	else:
		_panel.visible = false
		if player != null:
			player.set("program_driven", false)
			player.set_process(true)
			player.set_physics_process(true)
		if _saved_cam != null and is_instance_valid(_saved_cam):
			_saved_cam.make_current()

func _pan(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector3.ZERO:
		_target += dir.normalized() * _height * 0.55 * delta
	# 西边界必须跟着 world.spec.bay_layout.bounds 一起放宽，否则云岫仙山
	# （岛心 x = -770）根本平移不过去，俯视图里看不到新岛。
	_target.x = clampf(_target.x, -960.0, 640.0)
	_target.z = clampf(_target.z, -700.0, 780.0)

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_height = maxf(MIN_H, _height * ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_height = minf(MAX_H, _height / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			_drag_prev = get_viewport().get_mouse_position()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _over_panel(mb.position):
				_teleport_to_cursor(mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.relative * (_height / 900.0)
		_target.x -= d.x
		_target.z -= d.y
		_drag_prev = get_viewport().get_mouse_position()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			_set_enabled(false)
			get_viewport().set_input_as_handled()

func _over_panel(point:Vector2=Vector2.INF) -> bool:
	if _panel == null:
		return false
	if point==Vector2.INF:point=get_viewport().get_mouse_position()
	return Rect2(_panel.global_position, _panel.size).has_point(point)

func _update_camera() -> void:
	if cam == null:
		return
	cam.global_position = _target + Vector3(0.0, _height, _height * TILT)
	cam.look_at(_target, Vector3.UP)

func _teleport_to_cursor(point:Vector2=Vector2.INF) -> void:
	if player == null or layer == null or layer.world == null:
		return
	var mp := get_viewport().get_mouse_position() if point==Vector2.INF else point
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit = _ray_ground(from, dir)
	if hit == null:
		return
	var pos: Vector3 = hit
	if layer.get("sky_expansion")!=null:
		var sky_landing:Vector3=layer.sky_expansion.landing(Vector2(pos.x,pos.z))
		if sky_landing!=Vector3.INF:pos=sky_landing
	var boat: Node = player.get("boat_controller")
	if is_instance_valid(boat) and not str(boat.get("kind")).is_empty():
		if layer.map_marker == null:
			_say("请先靠岸下船，再使用快速跳转")
			return
		await layer.map_marker.travel_to(pos,"俯视选点")
		if layer.map_marker.last_success:
			_set_enabled(false)
		return
	if layer.map_marker!=null:
		await layer.map_marker.travel_to(pos,"俯视选点")
	else:layer.teleport(pos+Vector3.UP*.12)
	_target = pos
	_say("已传送至 (%.0f, %.0f)" % [pos.x, pos.z])

func _ray_ground(from: Vector3, dir: Vector3):
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3000.0)
	var h := space.intersect_ray(q)
	if not h.is_empty():
		return h["position"]
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	return from + dir * t

func _say(msg: String) -> void:
	if _label != null:
		_label.text = msg
	_say_timer = 2.2

func _update_label(delta: float) -> void:
	if _say_timer > 0.0:
		_say_timer -= delta
		return
	var gy := 0.0
	if layer != null and layer.world != null:
		gy = float(layer.world.call("height_at", _target.x, _target.z))
	_label.text = "中心 (%.0f, %.0f) · 地面 %.1f m · 视高 %.0f m" % [_target.x, _target.z, gy, _height]
