extends Node
var layer:Node
func _ready()->void:
	var payload:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://save/precision_v1/progress.json"))
	var saved:Variant=JSON.parse_string(str(payload.get("payload","{}"))) if payload is Dictionary else {}
	var expected:=Vector3.INF
	if saved is Dictionary and saved.get("position") is Array:
		var point:Array=saved.position;expected=Vector3(point[0],point[1],point[2])
	layer.main.call("start_game",true)
	await get_tree().create_timer(2.0).timeout
	var p:CharacterBody3D=layer.player
	var at:=p.global_position
	var transports:Array=[]
	var controller:Node
	var transport_methods:Array=[]
	for node in layer.main.find_children("*","Node",true,false):
		var script:Script=node.get_script()
		if script==null or not "creative_transport110" in script.resource_path:continue
		controller=node
		for method in script.get_script_method_list():
			if method.name in ["is_riding","disembark","release_for_travel","resume_active"]:transport_methods.append(method.name)
		var properties:Dictionary={}
		for prop in node.get_property_list():
			if not prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:continue
			var value:Variant=node.get(prop.name)
			if value is bool or value is int or value is float or value is Vector3:properties[prop.name]=str(value)
		transports.append(properties)
	var seated:bool=bool(p.get("seated"))
	var before:=p.global_position
	for tick in range(60):await get_tree().physics_frame
	var moved:=Vector2(p.global_position.x-before.x,p.global_position.z-before.z).length()
	var cable_record:Variant=saved.get("activities",{}).get("cable110",{}) if saved is Dictionary else {}
	var restored_vehicle:bool=cable_record is Dictionary and not cable_record.is_empty() and is_instance_valid(controller) and int(controller.get("rider"))>=0
	if restored_vehicle:
		var key:=InputEventKey.new();key.keycode=KEY_F;key.physical_keycode=KEY_F;key.pressed=true;Input.parse_input_event(key)
		for tick in range(4):await get_tree().physics_frame
		key=InputEventKey.new();key.keycode=KEY_F;key.physical_keycode=KEY_F;key.pressed=false;Input.parse_input_event(key)
		for tick in range(60):await get_tree().physics_frame
	var exited:bool=not restored_vehicle or (int(controller.get("rider"))<0 and p.is_on_floor())
	var map_pass:=true;var invalid_kept:=true
	if restored_vehicle and exited:
		controller.call("board",controller.call("near_station"))
		for tick in range(180):
			await get_tree().physics_frame
			if int(controller.get("rider"))>=0 and not bool(controller.get("preparing_board")):break
		var origin:=p.global_position
		await layer.map_marker.travel_to(Vector3(590,-14,635),"无效落点")
		invalid_kept=not layer.map_marker.last_success and int(controller.get("rider"))>=0 and p.global_position.distance_to(origin)<.5
		await layer.map_marker.travel_to(Vector3(292,3.65,252),"海风站")
		for tick in range(60):await get_tree().physics_frame
		map_pass=layer.map_marker.last_success and int(controller.get("rider"))<0 and p.is_on_floor()
	var walked:=0.0;var apex:=0.0
	if exited:
		var key:InputEventKey
		for yaw in [PI,0.0,PI*.5,-PI*.5]:
			var start:=p.global_position;p.set("yaw",yaw)
			key=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true;Input.parse_input_event(key)
			for tick in range(45):await get_tree().physics_frame
			key=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=false;Input.parse_input_event(key)
			walked=maxf(walked,p.global_position.distance_to(start))
			if walked>1:break
		var base_y:=p.global_position.y
		key=InputEventKey.new();key.keycode=KEY_SPACE;key.physical_keycode=KEY_SPACE;key.pressed=true;Input.parse_input_event(key)
		for tick in range(45):
			await get_tree().physics_frame;apex=maxf(apex,p.global_position.y-base_y)
			if tick==4:
				key=InputEventKey.new();key.keycode=KEY_SPACE;key.physical_keycode=KEY_SPACE;key.pressed=false;Input.parse_input_event(key)
	var passed:=expected!=Vector3.INF and Vector2(at.x-expected.x,at.z-expected.z).length()<5 and exited and invalid_kept and map_pass and walked>.7 and apex>.35
	var result:Dictionary={"pass":passed,"expected_position":str(expected),"actual_position":str(at),"after_exit":str(p.global_position),"on_floor":p.is_on_floor(),"seated":seated,"restored_vehicle":restored_vehicle,"vehicle_exit_pass":exited,"invalid_map_keeps_cabin":invalid_kept,"cabin_map_travel":map_pass,"after_exit_walk_m":walked,"after_exit_jump_m":apex,"vehicle_movement_m":moved,"transport_state":transports,"transport_methods":transport_methods,"fixture":"copy of existing precision_v1 save; original untouched"}
	FileAccess.open("user://real_resume.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("REAL_SAVE_RESUME ",JSON.stringify(result))
	get_tree().quit(0 if passed else 1)
