extends Node
var layer: Node
var inspect_only := true
var report := {}

func _ready() -> void:
	if not get_meta("qa_suite_active",false):layer.main.call("start_game",false)
	await get_tree().create_timer(3).timeout
	if not inspect_only:
		await _test()
		return
	var extremes: Array = []
	var roads: Array = layer.world.get("spec").bay_layout.roads
	for road in roads:
		for point in road.get("points",[]):
			var h := float(layer.world.call("height_at",point[0],point[2]))
			if float(point[1])-h > .3:
				extremes.append({"id":road.id,"point":point,"height_at":h,"gap":float(point[1])-h})
	extremes.sort_custom(func(a,b):return a.gap>b.gap)
	report["road_extremes"] = extremes.slice(0,30)
	var mesh_samples := []
	layer.teleport(Vector3(-307.5,80,-522.5))
	await get_tree().create_timer(3).timeout
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-307.5,76,-522.5),Vector3(-307.5,20,-522.5))
	ray.exclude=[layer.player.get_rid()]
	var hit: Dictionary=layer.player.get_world_3d().direct_space_state.intersect_ray(ray)
	report["road_ground_ray"] = str(hit)
	var stacked := []
	for y in [85.0,78.0,70.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(-307.5,y,-522.5),Vector3(-307.5,20,-522.5))
		q.exclude=[layer.player.get_rid()]
		var h: Dictionary=layer.player.get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty():
			stacked.append({"from":y,"position":str(h.position),"path":str(h.collider.get_path()),"parent":str(h.collider.get_parent().get_path())})
	report["stacked"]=stacked
	for mi in layer.world.find_children("*","MeshInstance3D",true,false):
		if "road" in str(mi.name).to_lower() or "path" in str(mi.name).to_lower():
			mesh_samples.append({"path":str(mi.get_path()),"visible":mi.is_visible_in_tree(),"aabb":str(mi.get_aabb())})
	report["road_meshes"]=mesh_samples
	var coast := []
	for x in range(-660,-419,10):
		coast.append([x,layer.world.call("height_at",x,300)])
	report["coast"] = coast
	layer.main.call("show_map")
	await get_tree().create_timer(1).timeout
	var view: Control = layer.map_marker.map_view
	report["map_signals"] = view.get_signal_list()
	report["hits"] = view.get("hits")
	report["map_rect"] = str(view.get_global_rect())
	report["world_point_sample"] = str(view.call("world_point",view.call("point",100.0,200.0)))
	var f := FileAccess.open("user://travel_audit.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t")); f.close()
	print("TRAVEL_AUDIT_DONE")
	load("res://scripts/renewal/qa/completion.gd").finish(self)

func _test() -> void:
	var checks:Dictionary={}
	var marker:Node=layer.map_marker
	var destinations:Array=[]
	for site in [Vector3(-307.5,79,-522.5),Vector3(-420,74,-481),Vector3(292,6,252)]:
		layer.teleport(site)
		await get_tree().create_timer(3).timeout
		layer.roads.snap_nearby()
		# Shape replacements become visible to physics queries on the next tick.
		await get_tree().physics_frame
		await get_tree().physics_frame
		for tick in range(12):await get_tree().physics_frame
		var count:=0;var floating:=0;var max_gap:=0.0;var failures:=[]
		var space:PhysicsDirectSpaceState3D=layer.player.get_world_3d().direct_space_state
		for group in layer.roads.groups:
			var verts:PackedVector3Array=group.v
			for i in range(0,verts.size(),7):
				var p:Vector3=verts[i]
				if Vector2(p.x-site.x,p.z-site.z).length()>24:continue
				var q:=PhysicsRayQueryParameters3D.create(p+Vector3(0,.1,0),p-Vector3(0,2,0))
				q.exclude=[layer.player.get_rid()]
				var hit:Dictionary=space.intersect_ray(q)
				if hit.is_empty():
					floating+=1;failures.append(str(p));continue
				count+=1
				max_gap=maxf(max_gap,p.y-hit.position.y)
				if p.y-hit.position.y>.08:failures.append(str(p)+" hit="+str(hit))
		checks["road_"+str(site)]={"samples":count,"failures":failures,"no_support":floating,"max_gap":max_gap,"pass":count>0 and floating==0 and max_gap<.08}
	# Test actual map label/icon events, not direct teleport calls.
	for index in [0,1,2,4]:
		layer.main.call("show_map")
		await get_tree().create_timer(.5).timeout
		var view:Control=marker.map_view
		var hits:Array=view.get("hits")
		if hits.size()<=index:continue
		var hit:Dictionary=hits[index]
		var point:Vector2=hit.point
		if index%2==0:point=hit.label.get_center()
		await _click(view.global_position+point)
		await get_tree().create_timer(1.1).timeout
		destinations.append({"name":hit.place.get("name"),"success":marker.last_success,"closed":not layer.main.get("modal").visible,"arrival":str(layer.player.global_position)})
	checks["map_destinations"]=destinations
	checks["map_icons_and_labels"]=destinations.size()==4
	for d in destinations:checks["map_icons_and_labels"]=checks["map_icons_and_labels"] and d.success and d.closed
	layer.main.call("show_map")
	await get_tree().create_timer(.5).timeout
	var view:Control=marker.map_view
	var before:Rect2=view.get("view_rect")
	await _mouse(view.global_position+view.size*.5,MOUSE_BUTTON_WHEEL_UP,true)
	await _mouse(view.global_position+view.size*.5,MOUSE_BUTTON_WHEEL_UP,false)
	await get_tree().create_timer(.2).timeout
	checks["zoom_preserved"]=view.get("view_rect")!=before
	var pan_before:Rect2=view.get("view_rect")
	var start:Vector2=view.global_position+view.size*.5
	await _mouse(start,MOUSE_BUTTON_RIGHT,true)
	var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(40,20);motion.global_position=motion.position
	motion.relative=Vector2(40,20);motion.button_mask=MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(motion,true);await get_tree().process_frame
	await _mouse(motion.position,MOUSE_BUTTON_RIGHT,false)
	checks["pan_preserved"]=view.get("view_rect")!=pan_before
	view.call("reset_view")
	await get_tree().create_timer(.4).timeout
	await _click(marker.button.global_position+marker.button.size*.5)
	await get_tree().create_timer(1.2).timeout
	checks["island_arrival"]=marker.last_success and absf(layer.player.global_position.z-300)<.5 and layer.player.global_position.y>3
	checks["island_arrival_position"]=str(layer.player.global_position)
	layer.main.call("show_map")
	await get_tree().create_timer(.5).timeout
	view=marker.map_view
	await _click(view.global_position+marker.project(Vector2(-530,300)))
	await get_tree().create_timer(1).timeout
	checks["free_ground_click"]=marker.last_success and absf(layer.player.global_position.x+530)<9 and not layer.main.get("modal").visible
	var before_reject:Vector3=layer.player.global_position
	await marker.travel_to(Vector3(-1100,10,0),"outside")
	checks["bounds_rejected"]=not marker.last_success and layer.player.global_position.distance_to(before_reject)<.1
	if DisplayServer.get_name()!="headless":
		await _shot("bridge",Vector3(-502,28,355),Vector3(-580,3,300))
		await _shot("road",Vector3(-307,108,-505),Vector3(-307,76,-522))
	var passed:=true
	for key in checks:
		if checks[key] is bool and not checks[key]:passed=false
		if checks[key] is Dictionary and checks[key].has("pass") and not checks[key].pass:passed=false
	checks["pass"]=passed
	var f:=FileAccess.open("user://travel_test.json",FileAccess.WRITE);f.store_string(JSON.stringify(checks,"\t"));f.close()
	print("TRAVEL_TEST ",checks)
	load("res://scripts/renewal/qa/completion.gd").finish(self,0 if passed else 1)

func _mouse(point:Vector2,index:MouseButton,pressed:bool) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=index;event.pressed=pressed
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _click(point:Vector2) -> void:
	await _mouse(point,MOUSE_BUTTON_LEFT,true)
	await _mouse(point,MOUSE_BUTTON_LEFT,false)

func _shot(label:String,pos:Vector3,target:Vector3) -> void:
	layer.teleport(target+Vector3(0,2,0))
	await get_tree().create_timer(2).timeout
	for key in ["menu","hud","ui"]:
		var n:Variant=layer.main.get(key)
		if n is CanvasItem:n.hide()
	var camera:=Camera3D.new();layer.main.add_child(camera);camera.global_position=pos;camera.look_at(target);camera.current=true
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://travel_"+label+".png")
	camera.queue_free()
