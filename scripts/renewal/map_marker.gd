extends Node
## 独立地图叠加层。只读取原地图公开 point(x,z)，不修改面板、目录或 hits。

const ISLAND := Vector2(-770,300)
const ARRIVAL := Vector3(-655,4.2,300)
var layer: Node
var map_view: Control
var canvas: CanvasLayer
var overlay: Control
var button: Button
var used := 0
var travelling := false
var last_destination := Vector3.ZERO
var last_success := false

func setup(owner_layer: Node) -> void:
	layer = owner_layer
	canvas = CanvasLayer.new()
	canvas.name = "RenewalMapCanvas"
	canvas.layer = 35
	add_child(canvas)
	overlay = load("res://scripts/renewal/map_island_draw.gd").new()
	overlay.name = "IslandMapOverlay"
	overlay.marker = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.clip_contents = true
	canvas.add_child(overlay)
	button = Button.new()
	button.name = "SkyIslandMapButton"
	button.text = "云岫仙界 · 登岛"
	button.tooltip_text = "前往云岫仙界，沿天梯探访天门、洗剑泉和观星台"
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(176,44)
	button.add_theme_font_size_override("font_size",18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("234d49")
	style.border_color = Color("ead9a3")
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	button.add_theme_stylebox_override("normal",style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3b6860")
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_color_override("font_color",Color("fff2cf"))
	button.pressed.connect(_visit)
	overlay.add_child(button)
	overlay.hide()

func _process(_delta: float) -> void:
	var modal: Control = layer.main.get("modal") if layer != null else null
	if modal == null or not modal.is_visible_in_tree():
		overlay.hide()
		return
	if not is_instance_valid(map_view) or not modal.is_ancestor_of(map_view):
		map_view = modal.find_child("VisitorMap106",true,false) as Control
		if map_view != null and map_view.has_signal("destination") and not map_view.is_connected("destination",_destination):
			map_view.connect("destination",_destination)
	if map_view == null or not map_view.has_method("point") or not map_view.is_visible_in_tree():
		overlay.hide()
		return
	_fit_default_view()
	var floor_plan := map_view.get_node_or_null("FloorPlan120") as Control
	if floor_plan != null and floor_plan.visible:
		overlay.hide()
		return
	overlay.position = map_view.get_global_rect().position
	overlay.size = map_view.size
	overlay.show()
	var anchor := project(ISLAND)
	button.visible = Rect2(Vector2.ZERO,overlay.size).has_point(anchor)
	button.position = Vector2(clampf(anchor.x-88,8,overlay.size.x-184),clampf(anchor.y-84,24,overlay.size.y-52))
	overlay.queue_redraw()

func _fit_default_view()->void:
	# The native atlas retains its original extent. Expand only its default
	# viewport to include the added western islands, preserving user zoom/pan.
	var current:Variant=map_view.get("view_rect")
	if not current is Rect2 or current.size.x<=0:return
	if not map_view.has_meta("renewal_default_view"):
		map_view.set_meta("renewal_default_view",current)
	if current!=map_view.get_meta("renewal_default_view"):return
	var bounds:Array=layer.world.get("spec").bay_layout.bounds
	var expanded:=Rect2(Vector2(float(bounds[0])-32,float(bounds[2])-32),Vector2(float(bounds[1])-float(bounds[0])+64,float(bounds[3])-float(bounds[2])+64))
	map_view.set("view_rect",expanded)
	map_view.queue_redraw()

func project(world_xz: Vector2) -> Vector2:
	return map_view.call("point",world_xz.x,world_xz.y)

func _visit() -> void:
	await travel_to(ARRIVAL,"云岫仙界")
	if last_success:used += 1

func _destination(place:Dictionary) -> void:
	# Also covers selections emitted by the original map's public destination signal.
	call_deferred("_travel_place",place)

func _travel_place(place:Dictionary) -> void:
	var safe:Variant=place.get("safe",null)
	var target:=Vector3(float(place.get("x",0)),0,float(place.get("z",0)))
	if safe is Array and safe.size()>=3:
		target=Vector3(float(safe[0]),float(safe[1]),float(safe[2]))
	else:
		target.y=float(layer.world.call("height_at",target.x,target.z))+.2
	await travel_to(target,str(place.get("name","地图位置")))

func _input(event:InputEvent) -> void:
	if travelling or not is_instance_valid(map_view) or not overlay.visible:return
	if not event is InputEventMouseButton:return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:return
	if button.visible and button.get_global_rect().has_point(event.position):return
	var local:Vector2=map_view.get_global_transform_with_canvas().affine_inverse()*event.position
	var plot:Rect2=map_view.call("plot_rect")
	if not plot.has_point(local):return
	get_viewport().set_input_as_handled()
	var xz:Vector2=map_view.call("world_point",local)
	if layer.get("sky_expansion")!=null:
		var sky_landing:Vector3=layer.sky_expansion.landing(xz)
		if sky_landing!=Vector3.INF:
			travel_to(sky_landing,"天空群岛");return
	var hits:Array=map_view.get("hits")
	for i in range(hits.size()-1,-1,-1):
		var hit:Dictionary=hits[i]
		if (hit.get("label",Rect2()) as Rect2).has_point(local) or Vector2(hit.get("point",Vector2.INF)).distance_to(local)<14:
			_travel_place(hit.get("place",{}))
			return
	if layer.sky_island.contains_land(Vector3(xz.x,0,xz.y)):
		# The island's distant blockout is not yet a safe destination: land on the built route.
		_visit()
		return
	var h:=float(layer.world.call("height_at",xz.x,xz.y))
	if h < -2.2:
		layer.main.call("notify","这里是水域，请选择陆地、桥梁或地点图标")
		return
	travel_to(Vector3(xz.x,h+.2,xz.y),"地图位置")

func travel_to(target:Vector3,label:String) -> void:
	if travelling:return
	if layer.travel_play != null and layer.travel_play.in_flight:return
	# The legacy station marker is over the bank below the gallery. Use the
	# actual station apron for named arrivals and emergency returns.
	if label in ["海风站","安全入口"] and Vector2(target.x-292,target.z-252).length()<10:
		target=Vector3(289.0,3.675,248.0)
	var bounds:Array=layer.world.get("spec").bay_layout.bounds
	if target.x<float(bounds[0]) or target.x>float(bounds[1]) or target.z<float(bounds[2]) or target.z>float(bounds[3]):
		last_success=false
		layer.main.call("notify","请选择世界边界内的地点")
		return
	travelling=true;last_success=false
	var player:CharacterBody3D=layer.player
	var boat: Node = player.get("boat_controller")
	if layer.travel_play!=null and layer.travel_play.native_transport_active():
		var transport:Node=layer.travel_play.native_transport_controller()
		var old_physics:=transport.is_physics_processing();var old_process:=transport.is_processing()
		transport.set_physics_process(false);transport.set_process(false)
		layer.world.call("prepare_region",target,96.0)
		var arrival:=await _wait_for_landing(player,target,36)
		transport.set_physics_process(old_physics);transport.set_process(old_process)
		if arrival==Vector3.INF:
			travelling=false;layer.main.call("notify","目的地没有安全落点，已保留当前缆车旅程");return
		if not layer.travel_play.release_native_transport_for_travel():
			travelling=false;layer.main.call("notify","请先完成下缆车，再进行旅行");return
		_finish_travel(arrival,label);player.set_physics_process(true);travelling=false
		return
	if is_instance_valid(boat) and not str(boat.get("kind")).is_empty():
		# Prepare the destination without moving the mounted player or the vessel.
		var boat_physics:=boat.is_physics_processing();var boat_process:=boat.is_processing()
		var rider_physics:=player.is_physics_processing()
		boat.set_physics_process(false);boat.set_process(false);player.set_physics_process(false)
		layer.world.call("prepare_region",target,96.0)
		var dock_landing := await _wait_for_landing(player,target,36)
		boat.set_physics_process(boat_physics);boat.set_process(boat_process);player.set_physics_process(rider_physics)
		if dock_landing == Vector3.INF:
			travelling = false
			layer.main.call("notify","没有找到安全上岸点，仍在原船上")
			return
		await boat.call("leave_for_travel")
		if not str(boat.get("kind")).is_empty():
			travelling = false
			layer.main.call("notify","离船未完成，请先靠岸下船")
			return
		_finish_travel(dock_landing,label)
		travelling = false
		return
	var origin:=player.global_position
	if layer.travel_play != null:layer.travel_play.release_motion_for_travel()
	var was_physics:=player.is_physics_processing()
	player.set_physics_process(false)
	layer.teleport(target+Vector3(0,.2,0))
	# Streamed collision needs a few frames at the destination, without letting the player fall.
	var landing := await _wait_for_landing(player,target,15)
	if landing!=Vector3.INF:
		_finish_travel(landing,label)
	else:
		layer.teleport(origin)
		layer.main.call("notify","此处没有安全落点，请选择附近道路或地点入口")
	player.set_physics_process(was_physics)
	travelling=false
	print("MAP_TRAVEL success=",last_success," target=",target," arrival=",player.global_position)

func _wait_for_landing(player: CharacterBody3D,target: Vector3,attempts: int) -> Vector3:
	var shape := CapsuleShape3D.new()
	shape.radius=.33
	shape.height=1.65
	for attempt in range(attempts):
		await get_tree().create_timer(.05).timeout
		if layer.get("rivers")!=null:layer.rivers.flush_pending()
		var space:=player.get_world_3d().direct_space_state
		for offset in [Vector3.ZERO,Vector3(1.5,0,0),Vector3(-1.5,0,0),Vector3(0,0,1.5),Vector3(0,0,-1.5),Vector3(4,0,0),Vector3(-4,0,0),Vector3(0,0,4),Vector3(0,0,-4),Vector3(8,0,0),Vector3(-8,0,0),Vector3(0,0,8),Vector3(0,0,-8)]:
			var at:Vector3=target+offset
			var q:=PhysicsRayQueryParameters3D.create(at+Vector3(0,2,0),at-Vector3(0,80,0))
			q.exclude=[player.get_rid()]
			var hit:=space.intersect_ray(q)
			if hit.is_empty() or hit.normal.y<.65 or hit.position.y< -2.2:continue
			var pos:Vector3=hit.position+Vector3(0,.12,0)
			var body:=PhysicsShapeQueryParameters3D.new();body.shape=shape
			body.transform=Transform3D(Basis.IDENTITY,pos+Vector3(0,.9,0));body.exclude=[player.get_rid()]
			if not space.intersect_shape(body,1).is_empty():continue
			return pos
	return Vector3.INF

func _finish_travel(landing: Vector3,label: String) -> void:
	layer.teleport(landing)
	last_destination=landing
	last_success=true
	layer.main.call("close_modal")
	if layer.safety!=null:
		layer.safety.safe_point=landing
		layer.safety.has_safe=true
	layer.main.call("notify","已抵达 · "+label)
