extends Node3D
## Physical island links, assisted flight and optional building tour.

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const BRIDGE_WIDTH := 5.8
const TOUR_FILE := "user://building_vistas.json"
const VISTAS := [
	["H06","海风藤编与贝壳风铃馆",Vector2(190,248),Vector2(190,238),"找挂着紫色风铃的海边木架。"],
	["H05","航海罗盘与望远镜观海墅",Vector2(145,222),Vector2(145,212),"沿海岸往西找带望远镜的观海墅。"],
	["B13","山海游客中心",Vector2(57,105),Vector2(57,96),"去街区的山海游客中心，在入口前回望建筑。"]
]

var layer: Node
var player: CharacterBody3D
var links: Array[PackedVector3Array] = []
var stops: Array[Dictionary] = []
var tour_count := 0
var in_flight := false
var flight_from := Vector3.ZERO
var flight_to := Vector3.ZERO
var flight_label := ""
var flight_rise := 9.0
var flight_time := 0.0
var flight_duration := 6.0
var _local_motion := false
var _old_snap := 0.6
var _old_constant_speed:=false
var _air_horizontal_scale:=1.0
var _jump_down := false
var _floor_coyote := 0.0
var _jump_buffer := 0.0
var _jumps_used := 0
var _hint: Label
var _builder: RefCounted
var _mats: Dictionary = {}
var _flight_blade: MeshInstance3D
var _stride := 0.0
var _flight_itinerary:=PackedVector3Array()
var _flight_leg:=0
var _flight_curve:Curve3D
var _flight_distance:=0.0
var _land_next:=false
var _native_transport:Node

func setup(owner_layer: Node) -> void:
	layer = owner_layer
	player = layer.player
	process_physics_priority=-100
	for node in layer.main.find_children("*","Node",true,false):
		var script:Script=node.get_script()
		if script!=null and "creative_transport110" in script.resource_path:_native_transport=node;break
	var flight_input:=preload("res://scripts/renewal/flight_input.gd").new()
	flight_input.name="FlightInputOwner";flight_input.travel=self
	get_tree().root.call_deferred("add_child",flight_input)
	_builder = MeshLib.new()
	_mats = {
		"deck":_material(Color("#b6ae96")),
		"stone":_material(Color("#8b8f7e")),
		"wood":_material(Color("#625042")),
		"light":_material(Color("#7ed2ca"),true)
	}
	_build_links()
	_build_stops()
	_load_tour()
	var mesh := MeshInstance3D.new()
	mesh.name = "TravelRoutes"
	mesh.mesh = _builder.build(_mats)
	add_child(mesh)
	_builder = null
	var ui := CanvasLayer.new()
	ui.layer = 17
	add_child(ui)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -410
	_hint.offset_right = 410
	_hint.offset_top = -118
	_hint.offset_bottom = -82
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size",20)
	_hint.add_theme_constant_override("outline_size",7)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_hint)
	_hint.hide()
	_flight_blade = MeshInstance3D.new()
	var blade := PrismMesh.new()
	blade.size = Vector3(.52,.18,2.75)
	_flight_blade.mesh = blade
	_flight_blade.material_override = _mats["light"]
	add_child(_flight_blade)
	_flight_blade.hide()

func _material(c: Color, lit: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = .88
	if lit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = .42
	return m

func _height(x: float, z: float) -> float:
	return float(layer.world.call("height_at",x,z))

func _build_links() -> void:
	if layer.sky_island == null or not layer.sky_island.has_method("wp"):
		return
	# The two west links depart separately and reach different sides of the forest island.
	_bridge(PackedVector3Array([
		Vector3(-686,4.1,394),Vector3(-510,5.1,414),
		Vector3(-296,5.1,437),Vector3(-123,3.8,457),Vector3(-83,_height(-83,472)+.18,472)
	]),"云岫北桥 · 星夜萤火森屿")
	_bridge(PackedVector3Array([
		Vector3(-707,4.1,459),Vector3(-518,5.3,511),
		Vector3(-285,5.3,548),Vector3(-128,3.3,530),Vector3(-82,_height(-82,517)+.18,517)
	]),"云岫南桥 · 星夜萤火森屿")
	_bridge(PackedVector3Array([
		Vector3(-38,_height(-38,509)+.18,509),Vector3(-13,3.1,515),
		Vector3(65,5.0,505),Vector3(111,9.8,486),Vector3(146,9.8,470),
		Vector3(190,1.8,457),Vector3(204,_height(204,449)+.18,449)
	]),"星潮连桥 · 星海珊瑚岛")

func _bridge(points: PackedVector3Array, label: String, piers: bool = true) -> void:
	links.append(points)
	var faces := PackedVector3Array()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in range(points.size()):
		var d := points[mini(i+1,points.size()-1)] - points[maxi(i-1,0)]
		d.y = 0.0
		var side := d.normalized().cross(Vector3.UP)*BRIDGE_WIDTH*.5
		left.append(points[i]+side)
		right.append(points[i]-side)
	for i in range(points.size()-1):
		var a := left[i]; var b := left[i+1]
		var c := right[i+1]; var d := right[i]
		_builder.begin("deck")
		_builder.add_quad(a,b,c,d)
		faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
		var down := Vector3.DOWN*.38
		_builder.begin("stone")
		_builder.add_quad(a,a+down,b+down,b)
		_builder.add_quad(d,c,c+down,d+down)
		for line in [left,right]:
			var u: Vector3 = line[i]
			var v: Vector3 = line[i+1]
			for piece in _rail_pieces(u,v,label):_beam("wood",piece[0]+Vector3.UP*.90,piece[1]+Vector3.UP*.90,.16)
			var divisions := maxi(1,ceili(u.distance_to(v)/4.8))
			for j in range(divisions):
				var p := u.lerp(v,float(j)/float(divisions))
				if "环殿观景廊" in label and p.x<445 and p.z> -503 and p.z< -497:continue
				_box("wood",p+Vector3.UP*.48,Vector3(.19,.96,.19))
				if j%7 == 0:
					_box("light",p+Vector3.UP*1.02,Vector3(.23,.22,.23))
		var count := maxi(1,ceili(points[i].distance_to(points[i+1])/24.0))
		for j in range(1,count):
			var p := points[i].lerp(points[i+1],float(j)/float(count))
			var bottom := _height(p.x,p.z)-.3
			if piers and bottom < p.y-.9:
				_box("stone",Vector3(p.x,(p.y+bottom)*.5,p.z),Vector3(1.35,p.y-bottom,2.1))
	# Extend the first and last contact surface past the painted deck seam.
	for i in [0,points.size()-1]:
		var other := 1 if i==0 else points.size()-2
		var extension := (points[i]-points[other]).normalized()*.65
		var a := left[i]
		var b := right[i]
		faces.append_array(PackedVector3Array([a,b,b+extension,a,b+extension,a+extension]))
		_builder.begin("deck")
		if i == 0:
			_builder.add_quad(a,b,b+extension,a+extension)
		else:
			_builder.add_quad(b,a,a+extension,b+extension)
	var body := StaticBody3D.new()
	body.name = "InterIslandBridge%d" % links.size()
	add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# Collision slivers shared by two concave faces can reject a ray exactly
	# on their edge. A shallow joint plate also gives the player's capsule
	# continuous support while changing direction across that seam.
	for i in range(1,points.size()-1):
		var d := points[i+1]-points[i-1]
		d.y = 0.0
		var joint := BoxShape3D.new()
		joint.size = Vector3(BRIDGE_WIDTH*.78,.20,1.2)
		var plate := CollisionShape3D.new()
		plate.shape = joint
		plate.transform = Transform3D(Basis.looking_at(-d.normalized(),Vector3.UP),points[i]+Vector3.DOWN*.111)
		body.add_child(plate)
	# Guard the long sea spans with slim continuous collision rails.
	for line in [left,right]:
		for i in range(line.size()-1):
			var a: Vector3 = line[i]
			var b: Vector3 = line[i+1]
			for piece in _rail_pieces(a,b,label):
				var u:Vector3=piece[0];var v:Vector3=piece[1]
				var dir:=(v-u).normalized();var basis:=Basis.looking_at(-dir,Vector3.UP)
				var rail:=BoxShape3D.new();rail.size=Vector3(.18,1.14,u.distance_to(v)+.04)
				var rc:=CollisionShape3D.new();rc.shape=rail
				rc.transform=Transform3D(basis,(u+v)*.5+Vector3.UP*.56);body.add_child(rc)
	_sign(points[0]+Vector3.UP*1.8,label,.015)
	_sign(points[-1]+Vector3.UP*1.8,"三岛步道 · "+label.get_slice(" · ",0),.015)

func _rail_pieces(a:Vector3,b:Vector3,label:String)->Array:
	if "环殿观景廊" in label and a.x<445 and b.x<445 and minf(a.z,b.z)< -503 and maxf(a.z,b.z)> -497:
		var low:=a.lerp(b,(-503-a.z)/(b.z-a.z));var high:=a.lerp(b,(-497-a.z)/(b.z-a.z))
		return [[a,low],[high,b]] if a.z<b.z else [[a,high],[low,b]]
	return [[a,b]]

func _box(key: String,p: Vector3,size: Vector3) -> void:
	_builder.begin(key)
	_builder.box(Transform3D(Basis.IDENTITY,p),size)

func _beam(key: String,a: Vector3,b: Vector3,width: float) -> void:
	_builder.begin(key)
	_builder.beam(a,b,width)

func _sign(p: Vector3, words: String, size: float) -> void:
	var sign := Label3D.new()
	sign.text = words
	sign.font_size = 56
	sign.pixel_size = minf(size,.0035)
	sign.visibility_range_begin=3.5
	sign.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.outline_size = 10
	sign.modulate = Color("#fff1cf")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.visibility_range_end = 85
	add_child(sign)
	sign.global_position = p

func _pad(name_text: String,p: Vector3,width: float = 4.5) -> void:
	_box("stone",p+Vector3.DOWN*.23,Vector3(width,.46,width))
	_builder.begin("light")
	for i in range(16):
		var a := TAU*i/16
		var b := TAU*(i+1)/16
		_builder.beam(p+Vector3(cos(a),.016,sin(a))*1.5,p+Vector3(cos(b),.016,sin(b))*1.5,.07)
	var body := StaticBody3D.new()
	body.name = name_text
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,.46,width)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = p+Vector3.DOWN*.23
	body.add_child(cs)

func _build_stops() -> void:
	if layer.sky_island != null and layer.sky_island.has_method("wp"):
		var shore := Vector3(-446,2.22,300.0)
		var island := Vector3(-653,4.06,300.0)
		_link_stops(shore,island,"云岫接驳 · 海岸","云岫接驳 · 登岛",5.5,8.0)
	_build_sky_terrace()
	_sign(Vector3(288,_height(288,246)+1.6,246),"建筑寻景 · 按 Y 查看线索",.010)
	for vista in VISTAS:
		var xz: Vector2 = vista[2]
		_sign(Vector3(xz.x,_height(xz.x,xz.y)+1.6,xz.y),"建筑寻景 · "+str(vista[1]),.008)

func _build_sky_terrace() -> void:
	var ground := Vector3(438,_height(438,-435)+.18,-435)
	var terrace := Vector3(466,112.15,-483.5)
	_pad("SwordLaunch",ground,3.6)
	_pad("FloatingLanding",terrace,5.2)
	# Walk around the original main hall. The original roof and rock remain visible.
	var ring := PackedVector3Array([
		terrace,Vector3(446,112.15,-483.5),Vector3(446,112.15,-521.2),
		Vector3(486,112.15,-521.2),Vector3(486,112.15,-483.5),terrace
	])
	_bridge(ring,"浮空宫苑 · 环殿观景廊",false)
	_link_stops(ground,terrace,"浮空宫苑 · 御剑起飞","浮空宫苑 · 回望台",7.2,14.0)

func _link_stops(a: Vector3,b: Vector3,a_name: String,b_name: String,seconds: float,rise: float) -> void:
	stops.append({"p":a,"to":b,"name":a_name,"dest":b_name,"time":seconds,"rise":rise})
	stops.append({"p":b,"to":a,"name":b_name,"dest":a_name,"time":seconds,"rise":rise})
	_sign(a+Vector3.UP*1.45,a_name+"  [Y]",.013)
	_sign(b+Vector3.UP*1.45,b_name+"  [Y]",.013)

func _near_stop() -> Dictionary:
	var nearest:Dictionary={};var distance:=3.65
	for stop in stops:
		var candidate:=player.global_position.distance_to(stop.p)
		if candidate<=distance:nearest=stop;distance=candidate
	return nearest

func _start_flight(stop: Dictionary) -> void:
	_leave_local_motion()
	flight_from = stop.p
	flight_to = stop.to
	flight_label = stop.dest
	flight_duration = stop.time
	flight_rise = stop.rise
	flight_time = 0.0
	var itinerary:PackedVector3Array=stop.get("itinerary",PackedVector3Array())
	_flight_itinerary=itinerary.duplicate()
	_flight_leg=0;_land_next=false
	in_flight = true
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	_flight_blade.show()
	if _flight_itinerary.size()>1:_build_flight_leg()

func _build_flight_leg()->void:
	var a:=_flight_itinerary[_flight_leg];var b:=_flight_itinerary[_flight_leg+1]
	_flight_curve=Curve3D.new();_flight_curve.bake_interval=.25
	var rise:=flight_rise if a.distance_to(b)>45 else minf(6,flight_rise)
	for attempt in range(12):
		_flight_curve.clear_points()
		_flight_curve.add_point(a+Vector3.UP*.1)
		_flight_curve.add_point(a+Vector3.UP*4.0)
		_flight_curve.add_point(a.lerp(b,.35)+Vector3.UP*rise)
		_flight_curve.add_point(a.lerp(b,.65)+Vector3.UP*rise)
		_flight_curve.add_point(b+Vector3.UP*4.0)
		_flight_curve.add_point(b+Vector3.UP*.1)
		if curve_clear(_flight_curve):break
		rise+=4.0
		if attempt==11:
			_end_flight(flight_from,true)
			layer.main.call("notify","御剑线路暂有遮挡，已返回出发台")
			return
	_flight_distance=0

func curve_clear(curve:Curve3D)->bool:
	var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.65
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.exclude=[player.get_rid()]
	var length:=curve.get_baked_length();var steps:=maxi(1,ceili(length/.25))
	for i in range(steps+1):
		var p:=curve.sample_baked(length*float(i)/steps)
		query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*.85)
		if not player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	return true

func _end_flight(target: Vector3, cancelled: bool = false) -> void:
	layer.teleport(target+Vector3.UP*.11)
	player.set_physics_process(true)
	player.call("reset_jump_state")
	in_flight = false
	_flight_curve=null;_flight_itinerary=PackedVector3Array();_jump_buffer=0;_jumps_used=0
	_jump_down=Input.is_key_pressed(KEY_SPACE)
	_flight_blade.hide()
	if layer.safety != null:
		layer.safety.safe_point = target+Vector3.UP*.12
		layer.safety.has_safe = true
	layer.main.call("notify","已返回出发台" if cancelled else "已到达 · "+flight_label)

func _physics_process(delta: float) -> void:
	if in_flight:
		var jump_now:=Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE)
		if jump_now and not _jump_down and _flight_curve!=null:_land_next=true
		_jump_down=jump_now
		if _flight_curve!=null:
			var length:=_flight_curve.get_baked_length()
			var remaining:=length-_flight_distance
			var speed:=minf(12.0,maxf(2.4,minf(_flight_distance+2.4,remaining+2.4)))
			_flight_distance=minf(length,_flight_distance+speed*delta)
			var at:=_flight_curve.sample_baked(_flight_distance)
			var ahead:=_flight_curve.sample_baked(minf(length,_flight_distance+.4))
			player.global_position=at;_flight_blade.global_position=at+Vector3.DOWN*.12
			var heading:=ahead-at;heading.y=0
			if heading.length_squared()>.0001:_flight_blade.global_basis=Basis.looking_at(heading.normalized(),Vector3.UP)
			if _flight_distance>=length:
				_flight_leg+=1
				if _land_next or _flight_leg>=_flight_itinerary.size()-1:
					if _land_next and _flight_leg<_flight_itinerary.size()-1:flight_label="途中落台"
					_end_flight(_flight_itinerary[_flight_leg])
				else:_build_flight_leg()
			return
		flight_time += delta
		var t := clampf(flight_time/flight_duration,0,1)
		var eased := smoothstep(0,1,t)
		player.global_position = flight_from.lerp(flight_to,eased)+Vector3.UP*(sin(t*PI)*flight_rise+.1)
		_flight_blade.global_position = player.global_position+Vector3.DOWN*.12
		var dir := flight_to-flight_from
		dir.y = 0.0
		_flight_blade.global_basis = Basis.looking_at(dir.normalized(),Vector3.UP)
		if t >= 1.0:
			_end_flight(flight_to)
		return
	_update_island_motion(delta)

func on_link(p: Vector3) -> bool:
	for line in links:
		for i in range(line.size()-1):
			var a: Vector3 = line[i]
			var b: Vector3 = line[i+1]
			var a2 := Vector2(a.x,a.z)
			var b2 := Vector2(b.x,b.z)
			var at := Vector2(p.x,p.z)
			var near := Geometry2D.get_closest_point_to_segment(at,a2,b2)
			var t := a2.distance_to(near)/maxf(.01,a2.distance_to(b2))
			var deck_y := lerpf(a.y,b.y,t)
			if near.distance_to(at) <= BRIDGE_WIDTH*.5+.45 and p.y > deck_y-.65 and p.y < deck_y+5.0:
				return true
	return false

func _needs_local_motion() -> bool:
	if native_transport_active():return false
	if layer.overhead!=null and layer.overhead.enabled:return false
	if layer.map_marker != null and layer.map_marker.travelling:
		return false
	var p := player.global_position
	var boat:Node=player.get("boat_controller")
	if is_instance_valid(boat) and not str(boat.get("kind")).is_empty():return false
	if _local_motion and not player.is_on_floor():return true
	if layer.get("surfaces")!=null and layer.surfaces.contains(p):return true
	if layer.passability!=null and layer.passability.contains(p):return true
	if layer.get("sky_expansion")!=null and layer.sky_expansion.contains(p,false):return true
	if layer.get("rivers")!=null and layer.rivers.contains(p):return true
	# Existing elevated decks are also owned while stepping off their visible edge.
	if p.y>75 and p.x>390 and p.x<590 and p.z< -445 and p.z> -600:return true
	if layer.sky_island != null and layer.sky_island.has_method("contains_land"):
		if p.y > -.6 and layer.sky_island.contains_land(p):
			return true
	if layer.roads != null and layer.roads.on_repaired_road(p):
		return true
	return on_link(p)

func _leave_local_motion() -> void:
	if not _local_motion:
		return
	_local_motion = false
	player.floor_snap_length = _old_snap
	player.floor_constant_speed=_old_constant_speed
	_air_horizontal_scale=1.0
	if player.is_on_floor():player.call("reset_jump_state")
	player.set_physics_process(not native_transport_active() and not (is_instance_valid(layer.wheel) and bool(layer.wheel.get("riding"))))
	_floor_coyote = 0.0
	_jump_buffer = 0.0
	_jumps_used = 0

func native_transport_active()->bool:
	return is_instance_valid(_native_transport) and (bool(_native_transport.call("is_riding")) or bool(_native_transport.get("restoring")) or bool(_native_transport.get("preparing_board")))

func native_transport_controller()->Node:
	return _native_transport

func release_native_transport_for_travel()->bool:
	if not is_instance_valid(_native_transport):return true
	_native_transport.call("release_for_travel")
	return not native_transport_active()

func release_motion_for_travel() -> void:
	_leave_local_motion()

func _update_island_motion(delta: float) -> void:
	var jump := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE)
	var pressed := jump and not _jump_down
	_jump_down = jump
	if not _needs_local_motion():
		_leave_local_motion()
		return
	if bool(player.get("seated")):
		_leave_local_motion()
		return
	if not bool(player.get("enabled")):
		return
	if not _local_motion:
		if not player.is_physics_processing() and (bool(player.get("automated_motion")) or bool(player.get("program_driven"))):
			return
		_local_motion = true
		_old_snap = player.floor_snap_length
		_old_constant_speed=player.floor_constant_speed
		player.floor_snap_length = .32
		player.floor_constant_speed=true
	# Native menu/scene callbacks may re-enable the character after acquisition.
	# Claim motion before its physics callback on every frame that we own it.
	player.set_physics_process(false)
	var move := Vector2(
		float(_key(KEY_D,KEY_RIGHT))-float(_key(KEY_A,KEY_LEFT)),
		float(_key(KEY_W,KEY_UP))-float(_key(KEY_S,KEY_DOWN))
	).limit_length()
	var yaw: float = player.get("yaw")
	var fwd := Vector3(-sin(yaw),0,-cos(yaw))
	var side := Vector3(cos(yaw),0,-sin(yaw))
	var speed: float = player.get("walk_speed")
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= float(player.get("run_multiplier"))
	var velocity := (fwd*move.y+side*move.x)*speed
	var grounded:=player.is_on_floor()
	var ground_rise:=0.0
	if grounded:
		var normal:=player.get_floor_normal()
		if normal.y>.65 and velocity.length_squared()>.001:
			var tangent:=velocity.slide(normal).normalized()*speed*move.length()
			velocity.x=tangent.x;velocity.z=tangent.z;ground_rise=tangent.y
			_air_horizontal_scale=Vector2(tangent.x,tangent.z).length()/maxf(.001,speed*move.length())
		elif move.length_squared()<.001:_air_horizontal_scale=1.0
	else:
		velocity.x*=_air_horizontal_scale;velocity.z*=_air_horizontal_scale
	velocity.y = player.velocity.y
	_floor_coyote = .095 if player.is_on_floor() else maxf(0,_floor_coyote-delta)
	_jump_buffer = .12 if pressed else maxf(0,_jump_buffer-delta)
	if grounded:
		_jumps_used = 0
	elif _floor_coyote <= 0:
		_jumps_used = maxi(1,_jumps_used)
	var takeoff:=false
	if _jump_buffer > 0 and _jumps_used < 2:
		var slope_rise:=0.0
		if player.is_on_floor() or _floor_coyote>0:
			var normal:=player.get_floor_normal()
			if normal.y>.65:slope_rise=maxf(0.0,-(normal.x*velocity.x+normal.z*velocity.z)/normal.y)
		velocity.y = 6.7+slope_rise
		takeoff=true
		_jumps_used += 1
		_jump_buffer = 0.0
		_floor_coyote = 0.0
	elif player.is_on_floor():
		velocity.y = ground_rise-.75
	else:
		velocity.y -= 17.2*delta
	player.velocity = velocity
	player.move_and_slide()
	if grounded and not takeoff and _jumps_used==0:player.apply_floor_snap()
	_update_figure(move,delta)

func _update_figure(move: Vector2,delta: float) -> void:
	var figure: Node3D = player.get("figure")
	if figure == null:
		return
	var travel := player.get_position_delta()
	if move.length_squared()>.01 and Vector2(travel.x,travel.z).length_squared()>.0001:
		figure.rotation.y = atan2(-travel.x,-travel.z)
		_stride += Vector2(travel.x,travel.z).length()*.91
	var angle := sin(_stride)*.43 if move.length_squared()>.01 and player.is_on_floor() else 0.0
	var legs: Array = player.get("legs")
	var arms: Array = player.get("arms")
	for i in range(legs.size()):
		if legs[i] is Node3D:
			legs[i].rotation.x = lerpf(legs[i].rotation.x,angle*(1 if i%2==0 else -1),minf(1,delta*16))
	for i in range(arms.size()):
		if arms[i] is Node3D:
			arms[i].rotation.x = lerpf(arms[i].rotation.x,-angle*.72*(1 if i%2==0 else -1),minf(1,delta*16))

func _key(code: Key, arrow: Key) -> bool:
	return Input.is_physical_key_pressed(code) or Input.is_key_pressed(code) or Input.is_key_pressed(arrow)

func _process(_delta: float) -> void:
	if not is_instance_valid(_hint):
		return
	_hint.hide()
	if in_flight:
		_hint.text = flight_label+"  ·  空格 下一站落地  ·  Esc 返回出发台" if _flight_curve!=null else flight_label+"  ·  Esc 返回出发台"
		_hint.show()
	elif native_transport_active() and bool(player.get("enabled")):
		if bool(_native_transport.get("restoring")) or bool(_native_transport.get("preparing_board")):
			_hint.text="缆车正在准备 · 请稍候"
		elif bool(_native_transport.get("traveling")):
			_hint.text="缆车行进中 · 到站后按 F 下车"
		else:_hint.text="缆车已停靠 · 按 F 下车后可步行与跳跃"
		_hint.show()
	elif bool(player.get("enabled")) and not bool(player.get("seated")):
		var stop := _near_stop()
		if not stop.is_empty():
			_hint.text = "Y  前往 "+stop.dest
			_hint.show()
		elif not _realm_hint().is_empty():
			_hint.text = _realm_hint()
			_hint.show()
		elif layer.get("sky_expansion")!=null and not layer.sky_expansion.hint(player.global_position).is_empty():
			_hint.text=layer.sky_expansion.hint(player.global_position);_hint.show()
		elif tour_count < VISTAS.size() and _near_vista(VISTAS[tour_count]):
			_hint.text = "Y  在入口前寻找取景角度"
			_hint.show()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (_local_motion or in_flight) and bool(player.get("enabled")):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var sensitivity: float = player.get("sensitivity")
			var yaw: float = player.get("yaw")
			var pitch: float = player.get("pitch")
			player.set("yaw",yaw-event.relative.x*sensitivity)
			player.set("pitch",clampf(pitch-event.relative.y*sensitivity*(-1.0 if bool(player.get("invert_y")) else 1.0),-1.23,1.15))
			var pivot: Node3D = player.get("pivot")
			if pivot != null:
				pivot.rotation = Vector3(float(player.get("pitch")),float(player.get("yaw")),0)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if in_flight and event.keycode==KEY_SPACE and _flight_curve!=null:
		_land_next=true;get_viewport().set_input_as_handled();return
	if in_flight and event.keycode == KEY_ESCAPE:
		_end_flight(flight_from,true)
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_Y or in_flight or native_transport_active() or not bool(player.get("enabled")) or bool(player.get("seated")):
		return
	if layer.map_marker != null and layer.map_marker.travelling:
		return
	var stop := _near_stop()
	if not stop.is_empty():
		_start_flight(stop)
	elif not _realm_hint().is_empty():
		layer.sky_island.celestial_realm.interact(player.global_position)
	elif layer.get("sky_expansion")!=null and layer.sky_expansion.interact(player.global_position):
		pass
	else:
		_visit_vista()
	get_viewport().set_input_as_handled()

func _realm_hint() -> String:
	if layer.sky_island == null or not layer.sky_island.has_method("wp"):
		return ""
	var realm: Node = layer.sky_island.celestial_realm
	return "" if realm == null else realm.hint(player.global_position)

func _near_vista(vista: Array) -> bool:
	var p := player.global_position
	return Vector2(p.x,p.z).distance_to(vista[2]) < 9.0 and absf(p.y-_height(p.x,p.z)) < 7.0

func _visit_vista() -> void:
	if tour_count >= VISTAS.size():
		layer.main.call("notify","建筑寻景已完成 · 三处建筑已收入游记")
		return
	var vista: Array = VISTAS[tour_count]
	if not _near_vista(vista):
		layer.main.call("notify","寻景 %d/3 · %s" % [tour_count,vista[4]])
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target: Vector2 = vista[3]
	var forward := -cam.global_basis.z
	var facing := Vector2(forward.x,forward.z).normalized()
	var wanted := (target-Vector2(cam.global_position.x,cam.global_position.z)).normalized()
	if facing.dot(wanted) < .70:
		layer.main.call("notify","把镜头转向入口，再按 Y 收录")
		return
	tour_count += 1
	var file := FileAccess.open(TOUR_FILE,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version":1,"count":tour_count}))
	var next := "三处建筑均已收入游记" if tour_count == VISTAS.size() else str(VISTAS[tour_count][4])
	layer.main.call("notify","已收录 %s · %d/3 · %s" % [vista[1],tour_count,next])

func _load_tour() -> void:
	var file := FileAccess.open(TOUR_FILE,FileAccess.READ)
	if file == null:
		return
	var record = JSON.parse_string(file.get_as_text())
	if record is Dictionary:
		tour_count = clampi(int(record.get("count",0)),0,VISTAS.size())
