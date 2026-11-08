extends Node
var layer: Node
var player: CharacterBody3D
var results: Array = []

func _ready() -> void:
	player = layer.player
	if not get_meta("qa_suite_active",false):await layer.main.call("start_game",false)
	await get_tree().create_timer(2).timeout
	if OS.get_cmdline_user_args().has("--rectify-baseline"):
		await _baseline()
		return
	await _run()

func _write(name: String, payload: Variant) -> void:
	FileAccess.open("user://"+name,FileAccess.WRITE).store_string(JSON.stringify(payload,"\t"))

func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=down
	Input.parse_input_event(event)

func _baseline() -> void:
	var report: Dictionary = {"shapes":[],"metadata":{},"boat_methods":[],"boat_properties":{},"floors":[]}
	for node in player.find_children("*","CollisionShape3D",true,false):
		var row := {"path":str(node.get_path()),"position":str(node.position),"type":node.shape.get_class()}
		if node.shape is CapsuleShape3D:
			row["height"]=node.shape.height;row["radius"]=node.shape.radius
		report.shapes.append(row)
	var bay: Dictionary = layer.world.get("spec").bay_layout
	for key in ["decks","deck_areas","terraces","docks","boat_docks"]:
		report[key]=bay.get(key,[])
	for key in ["metadata/entrances110","metadata/upper_routes110"]:
		report.metadata[key]=layer.world.get(key)
	var boat: Node = player.get("boat_controller")
	for method in boat.get_method_list():
		if not str(method.name).begins_with("_"):
			report.boat_methods.append(method)
	for prop in boat.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant=boat.get(prop.name)
			report.boat_properties[prop.name]=str(value) if value is Object else value
	for local in [Vector3(76.8,54,48),Vector3(77.8,54,48),Vector3(25.8,101,64),Vector3(0,107.8,64),Vector3(64,64.5,48)]:
		var at: Vector3=layer.sky_island.wp(local.x,local.y,local.z)
		layer.teleport(at+Vector3.UP*.08)
		await get_tree().create_timer(.6).timeout
		var hit := _floor(at)
		report.floors.append({"local":str(local),"expected":str(at),"end":str(player.global_position),"on_floor":player.is_on_floor(),"support":str(hit.get("collider","")),"hit":str(hit.get("position",""))})
	_write("rectify_baseline.json",report)
	print("RECTIFY_BASELINE_DONE")
	load("res://scripts/renewal/qa/completion.gd").finish(self)

func _floor(at: Vector3, above: float=.35, below: float=.45) -> Dictionary:
	var q:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*above,at-Vector3.UP*below,1,[player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(q)

func _run() -> void:
	var scope:="all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rectify-scope="):scope=arg.substr(16)
	scope=str(get_meta("qa_scope",scope))
	if scope in ["all","movement"]:await _movement()
	if scope=="shore":await _river_boats()
	if scope in ["all","sky"]:await _sky()
	if scope=="walk":await _sky_walk()
	if scope=="flights":await _flights()
	if scope=="spot":await _spot()
	if scope=="boatstate":await _boatstate()
	if scope=="skymap":await _sky_map()
	if scope=="clearance":await _clearance()
	if scope=="grades":_grades()
	if scope=="skyanchors":_sky_anchors()
	if scope=="guards":await _cloud_guards()
	if scope in ["all","rivers","inspect"]:await _rivers(scope=="inspect")
	if scope=="coverage":await _coverage()
	if scope=="persistence":
		_check("sky_journal_reopened",layer.sky_expansion.recorded.size()==9)
		var realm:Node=layer.sky_island.celestial_realm
		_check("celestial_progress_reopened",realm.stamps.size()==3 and realm.shrine_awakened and realm.court.get_node("StarFormation").visible)
	var failed:Array=results.filter(func(row:Dictionary)->bool:return not row.pass)
	var report:Dictionary={"pass":failed.is_empty(),"scope":scope,"cases":results,"failed":failed,"river_meshes":layer.rivers.patched_meshes,"river_shapes":layer.rivers.patched_shapes}
	_write("rectification_test.json",report)
	print("RECTIFICATION_RESULT scope=",scope," cases=",results.size()," failed=",failed.size())
	load("res://scripts/renewal/qa/completion.gd").finish(self,0 if failed.is_empty() else 1)

func _check(label:String,ok:bool,detail:Dictionary={})->void:
	var row:=detail.duplicate();row["name"]=label;row["pass"]=ok;results.append(row)
	if not ok:print("RECTIFICATION_FAIL ",JSON.stringify(row))

func _settle(p:Vector3,frames:int=12)->void:
	if layer.travel_play.in_flight:layer.travel_play._end_flight(layer.travel_play.flight_from,true)
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE]:_key(code,false)
	layer.teleport(p+Vector3.UP*.08)
	player.set("enabled",true)
	layer.world.call("prepare_region",p,65.0)
	for i in range(frames):await get_tree().physics_frame
	layer.rivers.flush_pending()

func _movement()->void:
	for local in [Vector3(76.8,54,48),Vector3(77.8,54,48),Vector3(25.8,101,64),Vector3(0,107.8,64),Vector3(64,64.5,48)]:
		var point:Vector3=layer.sky_island.wp(local.x,local.y,local.z)
		await _settle(point,45)
		_check("floor_"+str(local),player.is_on_floor() and absf(player.global_position.y-point.y)<.12,{"expected":str(point),"actual":str(player.global_position)})
	for index in range(4):
		var specs:Array=[[-100,11.0],[-66,25.5],[-31,40.5],[62,56.0]]
		var d:float=specs[index][0];var h:float=specs[index][1]
		for sprint in [false,true]:
			await _settle(layer.sky_island.wp(0,d,h),16)
			player.set("yaw",PI*.5);_key(KEY_SHIFT,sprint);_key(KEY_W,true);_key(KEY_SPACE,true)
			var rise:=0.0;var initial_velocity:=0.0;var airborne:=false
			for frame in range(42):
				await get_tree().physics_frame
				if frame==0:initial_velocity=player.velocity.y
				if frame==3:_key(KEY_SPACE,false)
				var p:Vector3=player.global_position
				var depth:float=-770-p.x
				var ground:float=48+(depth-48)*16/28 if index==3 else layer.sky_island.route_height(depth)
				rise=maxf(rise,p.y-ground);airborne=airborne or not player.is_on_floor()
			_key(KEY_W,false);_key(KEY_SHIFT,false);_key(KEY_SPACE,false)
			_check("stair_jump_%d_%s"%[index,sprint],airborne and rise>.45,{"relative_apex_m":rise,"takeoff_velocity":initial_velocity})
	for keys in [[KEY_W],[KEY_S],[KEY_A],[KEY_D],[KEY_W,KEY_A],[KEY_W,KEY_D],[KEY_S,KEY_A],[KEY_S,KEY_D]]:
		await _settle(layer.sky_island.wp(0,35,48))
		player.set("yaw",0.0);var origin:=player.global_position
		for key in keys:_key(key,true)
		for frame in range(24):await get_tree().physics_frame
		for key in keys:_key(key,false)
		_check("direction_"+str(keys),player.global_position.distance_to(origin)>1.5,{"distance":player.global_position.distance_to(origin)})
	# Pushing an ordinary wall must not trigger automatic recovery.
	await _settle(layer.sky_island.wp(21,94,64))
	player.set("yaw",PI);var recovered:int=layer.safety.recover_count
	_key(KEY_W,true)
	for frame in range(210):await get_tree().physics_frame
	_key(KEY_W,false)
	_check("normal_wall_no_recovery",layer.safety.recover_count==recovered)
	for controls in [[KEY_W,0.0],[KEY_S,PI],[KEY_A,-PI*.5],[KEY_D,PI*.5]]:
		await _settle(layer.sky_island.wp(21,94,64))
		player.set("yaw",controls[1]);var initial:=player.global_position
		layer.safety.stuck=false;layer.safety._stuck_time=0
		_key(controls[0],true)
		for frame in range(220):await get_tree().physics_frame
		_key(controls[0],false)
		_check("wall_push_"+str(controls[0]),not layer.safety.stuck and layer.safety.recover_count==recovered and player.global_position.distance_to(initial)<4,{"distance":player.global_position.distance_to(initial),"prompt":layer.safety.stuck})
	await _cloud_guards()

func _cloud_guards()->void:
	var guards:Array=layer.surfaces.cloud_guards
	_check("cloud_guard_network",guards.size()>100,{"solid_sections":guards.size(),"barrier_height_m":1.34})
	var eligible:Array=guards.filter(func(guard:Dictionary)->bool:return guard.a.distance_to(guard.b)>=.8)
	var checked:=0
	for sample in range(mini(12,eligible.size())):
		var guard:Dictionary=eligible[int(float(sample)*(eligible.size()-1)/11.0)]
		var centre:Vector3=(guard.a+guard.b)*.5-Vector3.UP*.52
		var outside:Vector3=guard.outside
		await _settle(centre-outside*.8,18)
		var start:=player.global_position
		var recoveries:int=layer.safety.recover_count
		player.set("yaw",atan2(-outside.x,-outside.z));_key(KEY_W,true);_key(KEY_SHIFT,true)
		var stopped_at:=start
		for tick in range(60):
			await get_tree().physics_frame
			if tick==39:stopped_at=player.global_position
		_key(KEY_W,false);_key(KEY_SHIFT,false)
		var outward:float=(player.global_position-start).dot(outside)
		var inside:float=-(player.global_position-centre).dot(outside)
		var drift:float=absf((player.global_position-stopped_at).dot(outside))
		var contact:=false
		for ci in range(player.get_slide_collision_count()):
			var collision:=player.get_slide_collision(ci)
			if "RouteSupports" in str(collision.get_collider().get_path()) and collision.get_normal().dot(outside)<-.35:contact=true
		_check("cloud_guard_push_%d"%checked,player.is_on_floor() and inside>.04 and drift<.05 and contact and absf(player.global_position.y-centre.y)<.3 and layer.safety.recover_count==recoveries,{"route":guard.label,"position":str(player.global_position),"outward_m":outward,"inside_margin_m":inside,"last_third_drift_m":drift,"barrier_contact":contact,"on_floor":player.is_on_floor()})
		checked+=1
	_check("cloud_guard_samples",checked==12,{"samples":checked})

func _sky()->void:
	var sky:Node=layer.sky_expansion
	_sky_anchors()
	var body_state:=_body_state()
	_check("avatar_has_no_vessel_envelope",body_state.shapes.size()==1 and body_state.shapes[0].type=="CapsuleShape3D",body_state)
	_check("island_counts",sky.islands.size()==15 and sky.sites.size()==9)
	var gardens:Dictionary=sky.garden_art
	_check("three_distinct_sky_gardens",gardens.has("flowers") and gardens.has("spring") and gardens.has("moon") and gardens.flowers.petals==48 and gardens.moon.clear_width_m>=3)
	var spring:Dictionary=gardens.spring;var pond_center:Vector3=spring.center
	await _settle(pond_center+Vector3(2.5,0,0),12)
	var pond_floor:=_floor(Vector3(pond_center.x+2.5,spring.water_y,pond_center.z),.2,1.0)
	_check("spring_pond_real_depth",not pond_floor.is_empty() and spring.water_y-pond_floor.position.y>.25 and spring.water_y-pond_floor.position.y<.825,{"water_y":spring.water_y,"bed_hit":str(pond_floor.get("position",Vector3.INF))})
	for row in sky.islands:
		await _settle(row.p,12)
		_check("island_support_"+str(row.id),player.is_on_floor() and absf(player.global_position.y-row.p.y)<.13,{"position":str(player.global_position)})
	for row in sky.sites:
		await _settle(row.p,8)
		_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
		_check("journal_"+str(row.id),sky.recorded.has(row.id))
	var file:=FileAccess.open("user://sky_journal.json",FileAccess.READ)
	var saved:Variant=JSON.parse_string(file.get_as_text()) if file!=null else {}
	_check("journal_written",saved is Dictionary and saved.get("recorded",{}).size()==9)
	var travel:Node=layer.travel_play
	await _settle(sky.climb_stations[0],12)
	_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
	_check("climb_Y_starts",travel.in_flight)
	var frames:=0
	while travel.in_flight and frames<3500:
		await get_tree().physics_frame;frames+=1
	_check("climb_arrives_hall",not travel.in_flight and player.global_position.distance_to(sky.climb_stations[-1])<.4,{"frames":frames,"arrival":str(player.global_position)})
	_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
	for frame in range(40):await get_tree().physics_frame
	_key(KEY_ESCAPE,true);await get_tree().physics_frame;_key(KEY_ESCAPE,false)
	_check("flight_cancel_returns_launch",not travel.in_flight and player.global_position.distance_to(sky.climb_stations[-1])<.4)
	await _settle(sky.climb_stations[0],8)
	_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
	_check("second_climb_starts",travel.in_flight,{"position":str(player.global_position)})
	_key(KEY_SPACE,true)
	for held_frame in range(4):await get_tree().physics_frame
	_key(KEY_SPACE,false)
	frames=0
	while travel.in_flight and frames<1600:await get_tree().physics_frame;frames+=1
	_check("flight_land_next",not travel.in_flight and player.global_position.distance_to(sky.climb_stations[1])<.4,{"position":str(player.global_position),"frames":frames,"flying":travel.in_flight})
	for frame in range(12):await get_tree().physics_frame
	_key(KEY_SPACE,true)
	for frame in range(3):await get_tree().physics_frame
	_key(KEY_SPACE,false)
	var jumped:bool=player.velocity.y>1
	_check("arrival_can_jump",jumped)
	await _sky_walk()

func _sky_anchors()->void:
	var mismatches:Array=[];var sampled:=0
	for route in layer.surfaces.paths:
		if route.kind=="legacy":continue
		var line:PackedVector3Array=route.points
		for endpoint in [line[0],line[-1]]:
			for island in layer.sky_expansion.islands:
				var offset:Vector3=endpoint-island.p
				if Vector2(offset.x/island.r.x,offset.z/island.r.y).length()>.97:continue
				if absf(offset.y)>15:continue
				sampled+=1
				if absf(offset.y)>.15:mismatches.append({"route":route.label,"island":island.id,"endpoint":str(endpoint),"island_y":island.p.y,"height_gap":offset.y})
	_check("sky_island_route_anchors",mismatches.is_empty(),{"samples":sampled,"mismatches":mismatches})

func _sky_walk()->void:
	# Long cloud routes and all branch mouths: sample support independent of render mesh.
	var missing:Array=[];var samples:=0
	for row in layer.surfaces.paths:
		if row.kind=="legacy":continue
		var line:PackedVector3Array=row.points
		for i in range(line.size()-1):
			var count:=maxi(1,ceili(line[i].distance_to(line[i+1])))
			for j in range(count+1):
				var p:=line[i].lerp(line[i+1],float(j)/count);samples+=1
				var hit:=_floor(p,.2,.25)
				if hit.is_empty():missing.append({"route":row.label,"p":str(p)})
	_check("sky_routes_support",missing.is_empty(),{"samples":samples,"missing":missing.slice(0,30)})
	# Actual movement in both directions, including every junction.
	var walks:Array=[]
	for original in layer.surfaces.paths:
		if original.kind=="legacy":continue
		walks.append(original)
		var reverse:Dictionary=original.duplicate();var points:PackedVector3Array=original.points.duplicate();points.reverse()
		reverse.points=points;reverse.label=str(original.label)+"回程";walks.append(reverse)
	var selected:PackedStringArray=[]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rectify-path="):selected=arg.substr(15).split(",")
	for row in walks:
		if row.kind=="legacy":continue
		if not selected.is_empty() and not str(row.id) in selected:continue
		var line:PackedVector3Array=row.points
		var total:=0.0
		for i in range(line.size()-1):total+=line[i].distance_to(line[i+1])
		await _settle(line[0],12)
		var waypoint:=1;var walk_frames:=0;var stuck_frames:=0;var last:=player.global_position
		var recovered:int=layer.safety.recover_count
		_key(KEY_W,true);_key(KEY_SHIFT,true)
		while waypoint<line.size() and walk_frames<int(total/18.0*60*2)+180:
			var p:=player.global_position
			while waypoint<line.size() and Vector2(p.x-line[waypoint].x,p.z-line[waypoint].z).length()<.75:waypoint+=1
			if waypoint>=line.size():break
			var direction:=line[waypoint]-p;direction.y=0
			player.set("yaw",atan2(-direction.x,-direction.z))
			await get_tree().physics_frame;walk_frames+=1
			stuck_frames=stuck_frames+1 if player.global_position.distance_to(last)<.025 else 0
			last=player.global_position
			if stuck_frames>90 or layer.safety.recover_count>recovered:break
		_key(KEY_W,false);_key(KEY_SHIFT,false)
		var contacts:Array=[]
		for i in range(player.get_slide_collision_count()):
			var c:=player.get_slide_collision(i);contacts.append({"collider":str(c.get_collider().get_path()),"normal":str(c.get_normal()),"position":str(c.get_position())})
		_check("walk_"+str(row.label),waypoint>=line.size() and layer.safety.recover_count==recovered,{"path_id":row.id,"waypoint":waypoint,"waypoints":line.size(),"frames":walk_frames,"length_m":total,"end":str(player.global_position),"target":str(line[mini(waypoint,line.size()-1)]),"contacts":contacts})

func _mouse_button(point:Vector2,down:bool)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
	get_viewport().push_input(event,true);await get_tree().process_frame

func _sky_map()->void:
	var marker:Node=layer.map_marker
	for row in layer.sky_expansion.islands.slice(0,3):
		layer.main.call("show_map")
		for tick in range(30):await get_tree().process_frame
		var view:Control=marker.map_view
		view.call("reset_view")
		for tick in range(6):await get_tree().process_frame
		var target:Vector2=view.global_position+marker.project(Vector2(row.p.x,row.p.z))
		await _mouse_button(target,true);await _mouse_button(target,false)
		for tick in range(100):await get_tree().physics_frame
		_check("M_island_"+str(row.id),marker.last_success and player.global_position.distance_to(row.p)<.5,{"arrival":str(player.global_position),"target":str(row.p),"click":str(target),"view":str(view.get("view_rect")),"plot":str(view.call("plot_rect"))})
		var overhead:Node=layer.overhead
		overhead._set_enabled(true);overhead._target=row.p;overhead._update_camera()
		for tick in range(10):await get_tree().process_frame
		var cursor:Vector2=overhead.cam.unproject_position(row.p)
		var motion:=InputEventMouseMotion.new();motion.position=cursor;motion.global_position=cursor
		get_viewport().push_input(motion,true);await get_tree().process_frame
		await _mouse_button(cursor,true);await _mouse_button(cursor,false)
		for tick in range(100):await get_tree().physics_frame
		overhead._set_enabled(false)
		for tick in range(12):await get_tree().physics_frame
		_check("V_island_"+str(row.id),marker.last_success and player.global_position.distance_to(row.p)<.6 and player.is_on_floor(),{"arrival":str(player.global_position),"target":str(row.p)})

func _flights()->void:
	var sky:Node=layer.sky_expansion
	var routes:Array=[
		{"name":"resume_climb","from":sky.climb_stations[1],"to":sky.climb_stations[-1]},
		{"name":"full_descent","from":sky.climb_stations[-1],"to":sky.climb_stations[0]},
		{"name":"north_sky_outbound","from":Vector3(-670,90,70),"to":Vector3(490,146,-620)},
		{"name":"north_sky_return","from":Vector3(490,146,-620),"to":Vector3(-670,90,70)}]
	for row in routes:
		await _settle(row.from,15)
		_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
		var started:bool=layer.travel_play.in_flight;var frames:=0
		while layer.travel_play.in_flight and frames<14000:
			await get_tree().physics_frame;frames+=1
		_check(row.name,started and not layer.travel_play.in_flight and player.global_position.distance_to(row.to)<.4,{"frames":frames,"arrival":str(player.global_position),"target":str(row.to)})

func _spot()->void:
	var at:=Vector3(-288,14,-112)
	var movements:Array=[];var shapes:Array=[]
	await _settle(at,45)
	var settled:=player.global_position
	var shape:=CapsuleShape3D.new();shape.radius=.33;shape.height=1.65
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.exclude=[player.get_rid()];query.transform=Transform3D(Basis.IDENTITY,settled+Vector3.UP*.85)
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query,20):shapes.append(str(hit.collider.get_path()))
	for keys in [[KEY_W],[KEY_S],[KEY_A],[KEY_D],[KEY_W,KEY_A],[KEY_W,KEY_D],[KEY_S,KEY_A],[KEY_S,KEY_D]]:
		await _settle(at,12);player.set("yaw",0.0);var start:=player.global_position
		for key in keys:_key(key,true)
		for tick in range(30):await get_tree().physics_frame
		for key in keys:_key(key,false)
		movements.append({"keys":str(keys),"distance":start.distance_to(player.global_position),"end":str(player.global_position)})
	await _settle(at,12);var start_y:=player.global_position.y;var apex:=0.0
	_key(KEY_SPACE,true)
	for tick in range(45):
		await get_tree().physics_frame;apex=maxf(apex,player.global_position.y-start_y)
		if tick==4:_key(KEY_SPACE,false)
	var free:=movements.filter(func(row:Dictionary)->bool:return row.distance>.7)
	_check("saved_location_can_escape",not free.is_empty() and apex>.35,{"saved":str(at),"settled":str(settled),"overlaps":shapes,"directions":movements,"jump_apex":apex})

func _body_state()->Dictionary:
	var shapes:Array=[]
	for node in player.find_children("*","CollisionShape3D",true,false):
		var item:Dictionary={"path":str(node.get_path()),"type":node.shape.get_class(),"transform":str(node.global_transform),"disabled":node.disabled}
		if node.shape is CapsuleShape3D:item["radius"]=node.shape.radius;item["height"]=node.shape.height
		if node.shape is BoxShape3D:item["size"]=str(node.shape.size)
		shapes.append(item)
	var boat:Node=player.get("boat_controller")
	var methods:Array=[]
	for method in boat.get_method_list():
		if "envelope" in str(method.name) or "body" in str(method.name) or "leave" in str(method.name):methods.append(method.name)
	var properties:Dictionary={}
	for key in ["collision_layer","collision_mask","floor_snap_length","floor_max_angle","safe_margin","motion_mode","up_direction"]:properties[key]=str(player.get(key))
	return {"shapes":shapes,"kind":boat.get("kind"),"envelope":str(boat.get("envelope")),"speed":boat.get("speed"),"player_scale":str(player.global_basis.get_scale()),"methods":methods,"properties":properties}

func _boatstate()->void:
	var boat:Node=player.get("boat_controller");var rows:Array=[_body_state()]
	boat.call("begin_board","flower",Vector3(70,.4,-45),0.0)
	for tick in range(90):await get_tree().physics_frame
	rows.append(_body_state())
	boat.call("leave_for_travel")
	for tick in range(15):await get_tree().physics_frame
	rows.append(_body_state())
	_write("boat_body_state.json",rows)
	_check("boat_exit_restores_avatar",rows[-1].shapes.size()==1 and rows[-1].shapes[0].type=="CapsuleShape3D",{"states":rows,"cleaned":layer.rivers.envelopes_cleaned})

func _rivers(inspect:bool=false)->void:
	var rivers:Node=layer.rivers
	var seen:Dictionary={};var failures:Array=[];var samples:=0
	for row in rivers.channels:
		var mid:Vector3=(row.a+row.b)*.5
		var data:Dictionary=rivers.profile(Vector2(mid.x,mid.z))
		await _settle(Vector3(mid.x,float(data.water)-rivers.depth,mid.z),20)
		var hit:=_floor(Vector3(mid.x,data.water+.05,mid.z),.05,rivers.player_height)
		seen[row.river]=true;samples+=1
		var actual:=INF if hit.is_empty() else float(data.water)-float(hit.position.y)
		if actual>rivers.player_height*.5+.04 or actual<.05:failures.append({"river":row.key,"p":str(mid),"depth":actual,"collider":str(hit.get("collider",""))})
	_check("seven_shallow_rivers",seen.size()==7 and failures.is_empty(),{"samples":samples,"failed":failures})
	var sampled_depths:=0;var worst:=0.0
	for channel in rivers.channels:
		var steps:=maxi(1,ceili(channel.a.distance_to(channel.b)))
		for i in range(steps+1):
			var at:Vector3=channel.a.lerp(channel.b,float(i)/steps)
			var value:Dictionary=rivers.profile(Vector2(at.x,at.z),false)
			if value.is_empty():continue
			worst=maxf(worst,float(value.water)-float(value.bed));sampled_depths+=1
	_check("all_river_profiles_shallow",worst<=rivers.player_height*.5,{"samples":sampled_depths,"max_profile_depth":worst})
	_check("terrain_stream_patched",rivers.patched_meshes>0 and rivers.patched_shapes>0,{"meshes":rivers.patched_meshes,"shapes":rivers.patched_shapes})
	await _wade_both_directions(rivers)
	await _river_boats(inspect)

func _wade_both_directions(rivers:Node)->void:
	var center:=Vector2(70,-45)
	var channel:Dictionary=rivers.profile(center,false)
	var lateral:=Vector2(-channel.flow.y,channel.flow.x)
	var offset:float=float(channel.half)+2.5
	var results_by_direction:Array=[]
	for direction in [-1.0,1.0]:
		var start:Vector2=center-lateral*offset*float(direction)
		var finish:Vector2=center+lateral*offset*float(direction)
		var bank:Dictionary=rivers.profile(start)
		await _settle(Vector3(start.x,bank.bed+.09,start.y),60)
		var maximum_depth:=0.0
		_key(KEY_W,true)
		for tick in range(260):
			var at:=Vector2(player.global_position.x,player.global_position.z)
			var delta:=finish-at
			if delta.length()<.65:break
			player.set("yaw",atan2(-delta.x,-delta.y))
			var water:Dictionary=rivers.profile(at,false)
			if not water.is_empty():maximum_depth=maxf(maximum_depth,float(water.water)-player.global_position.y)
			await get_tree().physics_frame
		_key(KEY_W,false)
		for tick in range(10):await get_tree().physics_frame
		var gap:=Vector2(player.global_position.x,player.global_position.z).distance_to(finish)
		results_by_direction.append({"direction":direction,"finish_gap_m":gap,"depth_m":maximum_depth,"grounded":player.is_on_floor(),"pass":gap<1.0 and maximum_depth>.25 and maximum_depth<=rivers.player_height*.5 and player.is_on_floor()})
	_check("wade_to_either_shore",results_by_direction.all(func(row):return row.pass),{"directions":results_by_direction})

func _river_boats(inspect:bool=false)->void:
	var rivers:Node=layer.rivers
	var boat:Node=player.get("boat_controller")
	var values:Dictionary={}
	for p in [Vector3(-110,.5,-120),Vector3(140,.35,-20),Vector3(310,.25,103)]:values[str(p)]=boat.call("water_at",p)
	await _settle(Vector3(289,3.675,248),90)
	await boat.call("board",0)
	for frame in range(60):await get_tree().physics_frame
	var model:Node3D=boat.get("model")
	var envelope:Variant=boat.get("envelope")
	if envelope is Object:
		for prop in envelope.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:values["envelope_"+str(prop.name)]=str(envelope.get(prop.name))
	var meshes:Array=[]
	if is_instance_valid(model):
		for node in model.find_children("*","MeshInstance3D",true,false):
			meshes.append({"type":node.mesh.get_class(),"local":str(node.position),"aabb":str(node.mesh.get_aabb()),"transform":str(node.transform)})
	values["meshes"]=meshes;values["kind"]=boat.get("kind");values["player"]=str(player.global_position)
	_write("boat_inspection.json",values)
	_check("boat_boarding_preserved",is_instance_valid(model))
	if inspect:return
	if is_instance_valid(model):
		# Relocate the normally boarded personal vessel into the river fixture;
		# retain its source/ownership, parking record and normal boarding API.
		player.global_position=Vector3(70,.6,-45);model.global_position=Vector3(70,.45,-45)
		boat.set("heading",atan2(-140.0,-50.0));boat.set("speed",0.0)
		for frame in range(90):await get_tree().physics_frame
		model=boat.get("model")
		if not is_instance_valid(model):
			_check("river_boat_created",false);return
		boat.set("testing",true);boat.set("test_input",Vector2(0,1))
		var origin:=model.global_position
		for frame in range(180):await get_tree().physics_frame
		boat.set("test_input",Vector2.ZERO);boat.set("testing",false)
		_check("boat_can_move",model.global_position.distance_to(origin)>1,{"distance":model.global_position.distance_to(origin)})
		var water_data:Dictionary=boat.call("water_at",model.global_position)
		_check("river_boat_uses_shallow_water",float(water_data.get("depth",10))<=rivers.player_height*.5,{"water":water_data,"model":str(model.global_position)})
		var minimum:=INF;var vertices:=0
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				for point in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var at:Vector3=mesh.global_transform*point
					var bed:Dictionary=rivers.profile(Vector2(at.x,at.z))
					if not bed.is_empty():minimum=minf(minimum,at.y-float(bed.bed));vertices+=1
		_check("river_boat_hull_clearance",vertices>0 and minimum>=.13,{"vertices":vertices,"minimum_bed_clearance_m":minimum})
		_key(KEY_SPACE,true)
		for tick in range(60):await get_tree().physics_frame
		_key(KEY_SPACE,false)
		for tick in range(15):await get_tree().physics_frame
		_key(KEY_F,true)
		for tick in range(4):await get_tree().physics_frame
		_key(KEY_F,false)
		for tick in range(90):await get_tree().physics_frame
		var detached:=str(boat.get("kind")).is_empty();var landed:=player.is_on_floor();var walked:=0.0
		var dock_foot:=player.global_position
		if detached:
			for yaw in [0.0,PI,PI*.5,-PI*.5]:
				player.set("yaw",yaw);var foot:=player.global_position;_key(KEY_W,true)
				for tick in range(45):await get_tree().physics_frame
				_key(KEY_W,false);walked=maxf(walked,player.global_position.distance_to(foot))
				if walked>1:break
		_check("river_F_dock_and_walk",detached and landed and walked>1,{"detached":detached,"landed":landed,"walk_m":walked,"player":str(player.global_position)})
		if detached:
			player.global_position=dock_foot
			var closest:=-1;var nearest:=INF
			# Personal parked boats use free_models. The moored array is the
			# separate catalogue of vessels placed by the original world.
			var parked_boats:Array=boat.get("free_models")
			for index in range(parked_boats.size()):
				var gap:float=parked_boats[index].global_position.distance_to(dock_foot)
				if gap<nearest:nearest=gap;closest=index
			var reboarded:bool=false
			if closest>=0 and nearest<15:reboarded=await boat.call("board_moored",closest)
			for tick in range(90):await get_tree().physics_frame
			var return_distance:=player.global_position.distance_to(dock_foot)
			_check("river_moored_boat_reboard",reboarded and not str(boat.get("kind")).is_empty() and return_distance<15,{"returned":reboarded,"kind":boat.get("kind"),"distance_from_dock":return_distance,"nearest_parked_m":nearest,"parked_index":closest,"source":boat.get("active_source"),"free_models":boat.get("free_models").size(),"player":str(player.global_position)})
		boat.call("leave_for_travel")
	var graded_levels:Array=[];var checked_rivers:Dictionary={}
	for channel in rivers.channels:
		if checked_rivers.has(channel.river):continue
		checked_rivers[channel.river]=true
		var mid:Vector3=channel.a.lerp(channel.b,.5)
		var channel_water:Dictionary=rivers.profile(Vector2(mid.x,mid.z),false)
		var launch:=Vector3(mid.x,float(channel_water.water)+.05,mid.z)
		layer.world.call("prepare_region",launch,80.0)
		for tick in range(60):await get_tree().physics_frame
		rivers.flush_pending()
		var started:bool=await boat.call("begin_board","flower",launch,atan2(-channel_water.flow.x,-channel_water.flow.y))
		for tick in range(45):await get_tree().physics_frame
		var vessel:Node3D=boat.get("model")
		var error:=INF if not is_instance_valid(vessel) else absf(vessel.global_position.y-(float(channel_water.water)+.05))
		graded_levels.append({"river":channel.key,"started":started,"error_m":error,"water":channel_water.water,"model":str(vessel.global_position) if is_instance_valid(vessel) else "missing"})
		await boat.call("leave_for_travel")
	_check("seven_river_actual_boat_levels",graded_levels.all(func(row):return row.error_m<.18),{"rivers":graded_levels})

func _clearance()->void:
	await _settle(Vector3(490,146,-620),45)
	var shape:=CapsuleShape3D.new();shape.radius=.32;shape.height=1.65
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.exclude=[player.get_rid()]
	var issues:Array=[];var samples:=0
	for row in layer.surfaces.paths:
		if row.kind=="legacy":continue
		var line:PackedVector3Array=row.points
		for i in range(line.size()-1):
			var count:=maxi(1,ceili(line[i].distance_to(line[i+1])))
			for j in range(count+1):
				var p:=line[i].lerp(line[i+1],float(j)/count)
				query.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*.98)
				var hit:=player.get_world_3d().direct_space_state.intersect_shape(query,1);samples+=1
				if not hit.is_empty():
					var collider:CollisionObject3D=hit[0].collider
					var owner_id:=collider.shape_find_owner(hit[0].shape)
					var owner:CollisionShape3D=collider.shape_owner_get_owner(owner_id)
					issues.append({"route":row.label,"path_id":row.id,"segment":i,"p":str(p),"collider":str(collider.get_path()),"shape":owner.shape.get_class(),"shape_at":str(owner.global_position),"size":str(owner.shape.size) if owner.shape is BoxShape3D else "","owner_route":owner.get_meta("route",""),"owner_path_id":owner.get_meta("path_id",-1),"owner_segment":owner.get_meta("segment",-1)})
	_write("route_clearance.json",{"samples":samples,"issues":issues})
	_check("route_clearance",issues.is_empty(),{"samples":samples,"count":issues.size(),"first":issues.slice(0,8)})

func _grades()->void:
	var rows:Array=[]
	for channel in layer.rivers.channels:
		var p:Vector3=(channel.a+channel.b)*.5
		var dir:Vector3=(channel.b-channel.a).normalized();var side:=Vector3(dir.z,0,-dir.x).normalized()
		var left:Vector3=p+side*(float(channel.half)+3.5);var right:Vector3=p-side*(float(channel.half)+3.5)
		var banks:Array=[]
		for offset in [3.5,7.0,12.0,20.0]:
			var l:Vector3=p+side*(float(channel.half)+float(offset));var r:Vector3=p-side*(float(channel.half)+float(offset))
			banks.append({"offset":offset,"left":layer.world.call("height_at",l.x,l.z),"right":layer.world.call("height_at",r.x,r.z)})
		rows.append({"key":channel.key,"p":str(p),"banks":banks,"left":layer.world.call("height_at",left.x,left.z),"right":layer.world.call("height_at",right.x,right.z),"center":layer.world.call("height_at",p.x,p.z)})
	_write("river_grades.json",rows)

func _coverage()->void:
	for tick in range(900):
		if layer.roads._seam_cursor>=layer.roads._seam_points.size():break
		await get_tree().physics_frame
	var was_processing:bool=layer.roads.is_physics_processing()
	layer.roads.set_physics_process(false)
	var groups:Dictionary={};var expected:Array=[]
	for gi in range(layer.roads.groups.size()):
		var group:Dictionary=layer.roads.groups[gi];var verts:PackedVector3Array=group.v
		var links:Dictionary={};var indices:PackedInt32Array=group.i
		for triangle in range(0,indices.size(),3):
			var lo:=mini(indices[triangle],mini(indices[triangle+1],indices[triangle+2]))/7
			var hi:=maxi(indices[triangle],maxi(indices[triangle+1],indices[triangle+2]))/7
			if hi==lo+1:links[lo*7]=true
		for i in range(0,verts.size(),7):
			for k in [1,3,5]:
				var p:=verts[i+k];var key:=Vector2i(floori(p.x/64),floori(p.z/64))
				if not groups.has(key):groups[key]=[]
				groups[key].append(p)
				if links.has(i) and i+k+7<verts.size():
					var next:Vector3=verts[i+k+7]
					var steps:=maxi(2,ceili(p.distance_to(next)))
					for j in range(1,steps):
						var between:=p.lerp(next,float(j)/steps)
						var cell:=Vector2i(floori(between.x/64),floori(between.z/64))
						if not groups.has(cell):groups[cell]=[]
						groups[cell].append(between)
	var missing:Array=[];var sampled:=0
	for key in groups:
		var center:=Vector3((key.x+.5)*64,30,(key.y+.5)*64)
		layer.world.call("prepare_region",center,90.0)
		for frame in range(10):await get_tree().physics_frame
		layer.rivers.flush_pending()
		for p in groups[key]:
			var hit:=_floor(p,.25,.35);sampled+=1
			if hit.is_empty():missing.append(str(p))
	_check("road_coverage",missing.is_empty(),{"roads":480,"sampled":sampled,"missing_count":missing.size(),"missing":missing.slice(0,100)})
	var floor_missing:Array=[];var floor_samples:=0
	for area in layer.world.get("spec").bay_layout.deck_areas:
		if float(area[2])-float(area[0])<1 or float(area[3])-float(area[1])<1:continue
		for xi in range(ceili(float(area[0])*2)+1,floori(float(area[2])*2)):
			for zi in range(ceili(float(area[1])*2)+1,floori(float(area[3])*2)):
				var p:=Vector3(xi*.5,area[4],zi*.5);floor_samples+=1
				if _floor(p).is_empty():floor_missing.append(str(p))
	_check("deck_grid_coverage",floor_missing.is_empty(),{"samples":floor_samples,"missing_count":floor_missing.size(),"missing":floor_missing.slice(0,100)})
	var island_samples:=0;var island_missing:Array=[]
	for island in layer.sky_expansion.islands:
		var p:Vector3=island.p;var r:Vector2=island.r
		for xi in range(ceili((p.x-r.x)*2),floori((p.x+r.x)*2)):
			for zi in range(ceili((p.z-r.y)*2),floori((p.z+r.y)*2)):
				var at:=Vector3(xi*.5,p.y,zi*.5)
				if Vector2((at.x-p.x)/r.x,(at.z-p.z)/r.y).length()>.94:continue
				island_samples+=1
				if _floor(at,.25,.35).is_empty():island_missing.append(str(at))
	_check("new_island_grid_coverage",island_missing.is_empty(),{"samples":island_samples,"missing":island_missing.slice(0,50),"missing_count":island_missing.size()})
	_write("coverage_details.json",{"road_missing":missing,"deck_missing":floor_missing,"island_missing":island_missing,"road_samples":sampled,"deck_samples":floor_samples,"island_samples":island_samples})
	layer.roads.set_physics_process(was_processing)
