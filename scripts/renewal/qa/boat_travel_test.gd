extends Node

var layer: Node

func _ready() -> void:
	var boat: Node = layer.player.get("boat_controller")
	var p: CharacterBody3D = layer.player
	if not get_meta("qa_suite_active",false):
		await layer.main.call("start_game",false)
		await get_tree().create_timer(3.0).timeout
	var model: Node3D
	for attempt in range(12):
		await get_tree().create_timer(.5).timeout
		if str(boat.get("kind")).is_empty():
			await boat.call("board",0)
		model = boat.get("model")
		if is_instance_valid(model):
			break
	if not is_instance_valid(model):
		push_error("BOAT_TRAVEL_TEST could not board the test boat")
		load("res://scripts/renewal/qa/completion.gd").finish(self,3)
		return
	await get_tree().create_timer(.5).timeout
	var origin := model.global_position
	var old_moored: int = boat.get("moored").size()
	var old_at_destination := _boats_near(boat,Vector3(292,3.65,252),25)
	await layer.map_marker.travel_to(Vector3(590,-14,635),"水域测试")
	var rejected: bool = not layer.map_marker.last_success and not str(boat.get("kind")).is_empty() and model.global_position.distance_to(origin)<2.0
	var reject_detail:Dictionary={"map_success":layer.map_marker.last_success,"kind":boat.get("kind"),"displacement":model.global_position.distance_to(origin),"origin":str(origin),"after":str(model.global_position)}
	layer.main.call("show_map")
	await get_tree().create_timer(.5).timeout
	var view: Control = layer.map_marker.map_view
	var clicked := false
	for hit in view.get("hits"):
		if hit.place.get("name","") != "海风站":
			continue
		var point: Vector2 = view.global_position+hit.label.get_center()
		for pressed in [true,false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.global_position = point
			event.pressed = pressed
			get_viewport().push_input(event,true)
			await get_tree().process_frame
		clicked = true
		break
	for i in range(50):
		await get_tree().create_timer(.06).timeout
		if not layer.map_marker.travelling and layer.map_marker.last_success:
			break
	var detached: bool = str(boat.get("kind")).is_empty() and boat.get("model")==null
	var arrived: bool = layer.map_marker.last_success and p.global_position.distance_to(Vector3(292,3.65,252))<8.0
	var arrival_detail:Dictionary={"position":str(p.global_position),"destination":str(layer.map_marker.last_destination),"success":layer.map_marker.last_success,"enabled":p.get("enabled"),"velocity":str(p.velocity),"program_driven":p.get("program_driven"),"automated_motion":p.get("automated_motion"),"physics":p.is_physics_processing()}
	var boat_near := INF
	var moored: Array = boat.get("moored")
	for b in moored:
		if is_instance_valid(b) and b is Node3D:
			boat_near = minf(boat_near,b.global_position.distance_to(origin))
	var dist := await _walk_after_arrival(p)
	var destination_clear := _boats_near(boat,Vector3(292,3.65,252),25)==old_at_destination
	var original_not_moved := not is_instance_valid(model) or model.global_position.distance_to(origin)<22.0
	var ok := rejected and clicked and arrived and detached and destination_clear and original_not_moved and moored.size()>=old_moored and boat_near<22 and dist>1.0 and p.is_on_floor()
	var result := {"pass":ok,"invalid_destination_keeps_boat":rejected,"invalid_destination_detail":reject_detail,"clicked_map":clicked,"arrived":arrived,"arrival_detail":arrival_detail,"final_position":str(p.global_position),"detached":detached,"no_boat_at_destination":destination_clear,"boat_near_departure_m":boat_near,"moored_before":old_moored,"moored_after":moored.size(),"walk_m":dist,"on_floor":p.is_on_floor()}
	FileAccess.open("user://boat_travel_test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BOAT_TRAVEL_TEST ",JSON.stringify(result))
	load("res://scripts/renewal/qa/completion.gd").finish(self,0 if ok else 1)

func _walk_after_arrival(p: CharacterBody3D) -> float:
	# The station marker can land on either side of nearby scenery.
	# Confirm control by walking away in any clear direction.
	var farthest := 0.0
	for yaw in [PI,0.0,PI/2.0,-PI/2.0]:
		p.set("yaw",yaw)
		var start := p.global_position
		_walk_key(true)
		for step in range(45):
			await get_tree().physics_frame
			var offset := p.global_position-start
			farthest = maxf(farthest,Vector2(offset.x,offset.z).length())
			if farthest>1.25:
				break
		_walk_key(false)
		await get_tree().physics_frame
		if farthest>1.25:
			break
	return farthest

func _walk_key(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = pressed
	Input.parse_input_event(key)

func _boats_near(boat: Node,point: Vector3,radius: float) -> int:
	var count := 0
	for entry in boat.get("moored"):
		if is_instance_valid(entry) and entry is Node3D and entry.global_position.distance_to(point)<radius:
			count += 1
	return count
