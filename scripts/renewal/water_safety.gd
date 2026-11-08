extends Node
## 落水与跌落安全
##  1) 记录最近有效安全落点（有支撑、非水下、非载具、非悬空边缘）；
##  2) 水中上岸辅助：浅水区朝岸边持续前进时可自然爬上缓坡，不再被水缘锁死；
##  3) 异常兜底：持续下坠、跌入深水、长时间有输入无位移时提示“返回附近安全位置”，保留取消。

const SEA_Y := -2.4
const WADE_DEPTH := 1.35
const STUCK_SECONDS := 3.0
const PROMPT_SECONDS := 8.0

var layer: Node
var player: CharacterBody3D
var enabled := true

var safe_point := Vector3.ZERO
var has_safe := false
var submerged := false
var stuck := false
var prompt_visible := false
var recover_count := 0
var climb_count := 0

var _rivers: Array = []
var _stuck_time := 0.0
var _prompt_time := 0.0
var _last_pos := Vector3.ZERO
var _last_check := 0.0
var _water_time:=0.0
var _safe_history:Array[Vector3]=[]
var _last_support:=Vector3.ZERO
var _recovering:=false
var _ui: CanvasLayer
var _panel: PanelContainer
var _label: Label

func setup(p_layer: Node) -> void:
	layer = p_layer
	player = layer.player
	_load_rivers()
	_build_ui()

func _load_rivers() -> void:
	if layer.world == null:
		return
	var spec = layer.world.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var bay = spec.get("bay_layout", {})
	if typeof(bay) == TYPE_DICTIONARY:
		_rivers = bay.get("rivers", [])

var _safe_elapsed:=0.15
var _stuck_recheck:=0.0
var _safe_capsule:CapsuleShape3D
var _safe_probe_at:=Vector3.INF
var _safe_probe_cooldown:=0.0
var _safe_probe_events:=-1

func _physics_process(delta: float) -> void:
	if not enabled or player == null:
		return
	var boat:Node=player.get("boat_controller")
	if bool(player.get("seated")) or (layer.travel_play!=null and (layer.travel_play.in_flight or layer.travel_play.native_transport_active())) or (layer.map_marker!=null and layer.map_marker.travelling) or (is_instance_valid(boat) and not str(boat.get("kind")).is_empty()):
		_stuck_time=0;_water_time=0;stuck=false;submerged=false
		prompt_visible=false;_panel.hide()
		return
	_safe_elapsed+=delta
	_safe_probe_cooldown=maxf(0,_safe_probe_cooldown-delta)
	if _safe_elapsed>=.15:
		_safe_elapsed=0.0
		_check_safe_point()
	_check_water(delta)
	_check_stuck(delta)
	if has_safe and player.global_position.y<_last_support.y-8 and player.velocity.y< -2:
		var q:=PhysicsRayQueryParameters3D.create(player.global_position,player.global_position+Vector3.DOWN*5,1,[player.get_rid()])
		if player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():recover()
	_update_prompt(delta)

# ---------------------------------------------------------------- 安全落点

func _check_safe_point() -> void:
	if not player.is_on_floor():
		return
	var p := player.global_position
	var events:int=int(layer.stream.get("load_events")) if layer.stream!=null else 0
	# Standing at the same wall does not need six identical support queries
	# every 0.15 s. Moving or streaming invalidates this short-lived cache;
	# recovery always performs its own fresh validation.
	if p.distance_to(_safe_probe_at)<.15 and _safe_probe_cooldown>0 and events==_safe_probe_events:return
	_safe_probe_at=p;_safe_probe_cooldown=1.0;_safe_probe_events=events
	# 安全点须明显高于水面，避免把水面/浅滩/船板当成落脚点
	if _water_depth(p) > -0.35:
		return
	if not _valid_safe(p):return
	safe_point = p
	_last_support=p
	has_safe = true
	if _safe_history.is_empty() or _safe_history[-1].distance_to(p)>2:
		_safe_history.append(p)
		if _safe_history.size()>12:_safe_history.pop_front()

func _valid_safe(p:Vector3)->bool:
	var space:=player.get_world_3d().direct_space_state
	for off in [Vector3.ZERO,Vector3(.36,0,0),Vector3(-.36,0,0),Vector3(0,0,.36),Vector3(0,0,-.36)]:
		var q:=PhysicsRayQueryParameters3D.create(p+off+Vector3.UP*.28,p+off-Vector3.UP*.5,1,[player.get_rid()])
		var hit:=space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y<.65:return false
	if _safe_capsule==null:
		_safe_capsule=CapsuleShape3D.new();_safe_capsule.radius=.33;_safe_capsule.height=1.65
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_safe_capsule;query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*.88);query.exclude=[player.get_rid()]
	return space.intersect_shape(query,1).is_empty()

func recover() -> void:
	if _recovering:return
	var boat:Node=player.get("boat_controller")
	if bool(player.get("seated")) or (layer.travel_play!=null and (layer.travel_play.in_flight or layer.travel_play.native_transport_active())) or (layer.map_marker!=null and layer.map_marker.travelling) or (is_instance_valid(boat) and not str(boat.get("kind")).is_empty()):return
	_recovering=true
	var target:=Vector3.INF
	var candidates:=_safe_history.duplicate()
	if has_safe:candidates.append(safe_point)
	candidates.reverse()
	for candidate in candidates:
		if _valid_safe(candidate):target=candidate+Vector3.UP*.06;break
	if target==Vector3.INF:
		if layer.map_marker!=null:
			await layer.map_marker.travel_to(Vector3(292,3.65,252),"安全入口")
			if layer.map_marker.last_success:
				recover_count+=1;_stuck_time=0;_water_time=0;stuck=false;submerged=false;prompt_visible=false
				_say("已返回海风站安全入口")
		_recovering=false
		return
	if layer.travel_play!=null:layer.travel_play.release_motion_for_travel()
	player.global_position = target
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	player.set("automated_motion",false);player.set("program_driven",false)
	player.call("reset_jump_state")
	_stuck_time=0;_water_time=0;stuck=false;submerged=false
	recover_count += 1
	_recovering=false
	_prompt_time = 0.0
	prompt_visible = false
	_say("已返回附近安全位置")

# ---------------------------------------------------------------- 水域

func _water_depth(p: Vector3) -> float:
	if layer.get("rivers")!=null:
		var profile:Dictionary=layer.rivers.profile(Vector2(p.x,p.z),false)
		return float(profile.water)-p.y if not profile.is_empty() else SEA_Y-p.y
	# 海面
	var best := SEA_Y
	# 河流：取最近河段插值水面
	for r in _rivers:
		var pts: Array = r.get("points", [])
		for i in range(pts.size() - 1):
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			var ax := float(a[0]); var az := float(a[2])
			var bx := float(b[0]); var bz := float(b[2])
			var dx := bx - ax
			var dz := bz - az
			var l2 := dx * dx + dz * dz
			if l2 < 0.01:
				continue
			var t := clampf(((p.x - ax) * dx + (p.z - az) * dz) / l2, 0.0, 1.0)
			var cx := ax + dx * t
			var cz := az + dz * t
			var dist := Vector2(p.x - cx, p.z - cz).length()
			if dist < 5.5:
				var wy := lerpf(float(a[1]), float(b[1]), t)
				best = maxf(best, wy)
	return best - p.y

func _check_water(delta: float) -> void:
	var depth := _water_depth(player.global_position)
	submerged = depth > WADE_DEPTH
	# 浅水：朝岸边持续前进时辅助上岸
	if depth > 0.15 and depth <= WADE_DEPTH + 0.4 and _forward_pressed():
		if layer.get("rivers")==null or not layer.rivers.contains(player.global_position):_climb_out(delta)
	if submerged:
		_water_time += delta
		if _water_time > 2.0:
			_show_prompt("落入深水 · 按 F 返回附近安全位置")
			_prompt_time += delta
			if _prompt_time > PROMPT_SECONDS:
				recover()
	else:
		_water_time=0.0

## 上岸辅助：前向 1.2m 处若有 40° 以内、抬升不超过 1.3m 的坡面，则沿坡抬升。
func _climb_out(delta: float) -> void:
	var yaw := float(player.get("yaw"))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var space := player.get_world_3d().direct_space_state
	for dist in [0.8, 1.3, 1.9]:
		var dist_f := float(dist)
		var probe: Vector3 = player.global_position + fwd * dist_f + Vector3(0, 1.4, 0)
		var q := PhysicsRayQueryParameters3D.create(probe, probe - Vector3(0, 3.2, 0))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var target: Vector3 = hit.position
		var rise := target.y - player.global_position.y
		if rise > 0.08 and rise < 1.3:
			var n: Vector3 = hit.normal
			if n.angle_to(Vector3.UP) < deg_to_rad(42.0):
				var step := minf(2.6 * delta, maxf(0.0, rise))
				player.global_position = player.global_position + Vector3(0, step + 0.02, 0) + fwd * (1.2 * delta)
				climb_count += 1
				return

# ---------------------------------------------------------------- 卡死

func _check_stuck(delta: float) -> void:
	_stuck_recheck=maxf(0,_stuck_recheck-delta)
	if submerged:
		return
	var p := player.global_position
	var moved := p.distance_to(_last_pos)
	_last_pos = p
	if not _movement_pressed():
		stuck = false
		_stuck_time = 0.0
		_stuck_recheck=0.0
		return
	if moved < 0.02:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
		stuck = false
		_stuck_recheck=0.0
	if _stuck_time > STUCK_SECONDS and not stuck and _stuck_recheck<=0:
		# A rejected diagnosis (ordinary wall contact) must also be rate limited.
		_stuck_recheck=.6
		var yaw:float=player.get("yaw")
		var forward:=float(_pressed(KEY_W,KEY_UP))-float(_pressed(KEY_S,KEY_DOWN))
		var sideways:=float(_pressed(KEY_D,KEY_RIGHT))-float(_pressed(KEY_A,KEY_LEFT))
		var request:=(Vector3(-sin(yaw),0,-cos(yaw))*forward+Vector3(cos(yaw),0,-sin(yaw))*sideways).normalized()*.5
		var blocked:=player.test_move(player.global_transform,request)
		var abnormal:=not blocked
		if blocked:
			abnormal=true
			for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				if not player.test_move(player.global_transform,direction*.5):
					abnormal=false
					break
		if abnormal:
			stuck = true
			_show_prompt("似乎被困住了 · 按 F 返回附近安全位置")

func _pressed(code:Key,arrow:Key)->bool:
	return Input.is_physical_key_pressed(code) or Input.is_key_pressed(code) or Input.is_physical_key_pressed(arrow) or Input.is_key_pressed(arrow)

func _movement_pressed()->bool:
	for key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT]:
		if Input.is_physical_key_pressed(key) or Input.is_key_pressed(key):return true
	return false

func _forward_pressed() -> bool:
	return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_F and prompt_visible:
			recover()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "SafetyUI"
	_ui.layer = 21
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.14, 0.86)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86))
	_label.add_theme_font_size_override("font_size", 18)
	_panel.add_child(_label)
	_ui.add_child(_panel)

var _msg := ""
var _msg_time := 0.0

func _say(msg: String) -> void:
	_msg = msg
	_msg_time = 3.0
	_label.text = msg
	_panel.visible = true

func _show_prompt(msg: String) -> void:
	prompt_visible = true
	_label.text = msg
	_panel.visible = true

func _update_prompt(delta: float) -> void:
	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time <= 0.0 and not prompt_visible:
			_panel.visible = false
	if prompt_visible:
		if not submerged and not stuck:
			prompt_visible = false
			_prompt_time = 0.0
			_panel.visible = false
	var vp := get_viewport().get_visible_rect().size
	_panel.reset_size()
	_panel.position = Vector2(vp.x * 0.5 - _panel.size.x * 0.5, vp.y - 200.0)
