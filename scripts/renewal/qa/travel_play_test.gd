extends Node

var layer: Node
var player: CharacterBody3D
var result: Dictionary = {}

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _ready() -> void:
	player = layer.player
	layer.main.call("start_game",false)
	await get_tree().create_timer(1.5).timeout
	layer.teleport(Vector3(-669,12.8,300))
	await get_tree().create_timer(1.4).timeout
	var before := player.global_position
	var yaw_before: float = player.get("yaw")
	var mouse_turn := 0.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(160,0)
		Input.parse_input_event(mm)
		await get_tree().process_frame
		mouse_turn = absf(float(player.get("yaw"))-yaw_before)
	result["stair_mouse_turn_rad"] = mouse_turn
	var high := before.y
	_key(KEY_SPACE,true)
	for i in range(36):
		await get_tree().physics_frame
		high = maxf(high,player.global_position.y)
	_key(KEY_SPACE,false)
	result["stair_jump_m"] = high-before.y
	await get_tree().physics_frame
	var second_start := player.global_position.y
	var second_high := second_start
	_key(KEY_SPACE,true)
	for i in range(26):
		await get_tree().physics_frame
		second_high = maxf(second_high,player.global_position.y)
	_key(KEY_SPACE,false)
	result["stair_second_jump_m"] = second_high-second_start
	await get_tree().create_timer(.7).timeout
	player.set("yaw",PI/2)
	before = player.global_position
	_key(KEY_D,true)
	await get_tree().create_timer(.27).timeout
	_key(KEY_D,false)
	result["stair_side_m"] = absf(player.global_position.z-before.z)
	layer.teleport(Vector3(-788,48.2,300))
	await get_tree().create_timer(.6).timeout
	before = player.global_position
	player.set("yaw",0.0)
	_key(KEY_W,true)
	await get_tree().create_timer(.42).timeout
	_key(KEY_W,false)
	player.set("yaw",PI)
	_key(KEY_W,true)
	await get_tree().create_timer(.42).timeout
	_key(KEY_W,false)
	result["platform_turn_end_error_m"] = Vector2(player.global_position.x-before.x,player.global_position.z-before.z).length()
	var travel: Node = layer.travel_play
	var bridges: Array = []
	for n in range(travel.links.size()):
		var path: PackedVector3Array = travel.links[n]
		var support := 0
		var total := 0
		var length := 0.0
		var misses: Array = []
		for i in range(path.size()-1):
			length += path[i].distance_to(path[i+1])
			var count := maxi(1,ceili(path[i].distance_to(path[i+1])/6.0))
			for j in range(count+1):
				var point := path[i].lerp(path[i+1],float(j)/count)
				var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.55,point-Vector3.UP*.4)
				query.exclude = [player.get_rid()]
				var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
				total += 1
				if not hit.is_empty() and hit.normal.y>.68:
					support += 1
				else:
					misses.append({"point":str(point),"hit":str(hit)})
		var middle: Vector3 = path[1].lerp(path[2],.5)
		layer.teleport(middle+Vector3.UP*.12)
		await get_tree().create_timer(.45).timeout
		var delta := path[2]-path[1]
		player.set("yaw",atan2(-delta.x,-delta.z))
		before = player.global_position
		_key(KEY_W,true)
		await get_tree().create_timer(.65).timeout
		_key(KEY_W,false)
		bridges.append({"length_m":length,"support":support,"samples":total,"misses":misses,"walk_m":before.distance_to(player.global_position),"on_floor":player.is_on_floor()})
	result["links"] = bridges
	var flights: Array = []
	for index in [0,2,3]:
		var stop: Dictionary = travel.stops[index]
		layer.teleport(stop.p+Vector3.UP*.13)
		await get_tree().create_timer(.40).timeout
		_key(KEY_Y,true)
		await get_tree().process_frame
		_key(KEY_Y,false)
		var started: bool = travel.in_flight
		await get_tree().create_timer(float(stop.time)+.45).timeout
		flights.append({"started":started,"arrived":player.global_position.distance_to(stop.to)<.7,"on_floor":player.is_on_floor(),"to":str(stop.to)})
	result["flights"] = flights
	var quest: Array = []
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for vista in travel.VISTAS:
		var p: Vector2 = vista[2]
		var target: Vector2 = vista[3]
		var h: float = layer.world.call("height_at",p.x,p.y)
		layer.teleport(Vector3(p.x,h+.6,p.y))
		await get_tree().create_timer(.9).timeout
		cam.global_position = player.global_position+Vector3.UP*1.8
		cam.look_at(Vector3(target.x,cam.global_position.y,target.y))
		_key(KEY_Y,true)
		await get_tree().process_frame
		_key(KEY_Y,false)
		quest.append(travel.tour_count)
	cam.queue_free()
	result["tour_steps"] = quest
	var ok: bool = result.stair_jump_m>.45 and result.stair_second_jump_m>.45 and result.stair_side_m>.8 and result.platform_turn_end_error_m<1.8
	for check in bridges:
		ok = ok and check.support == check.samples and check.walk_m>2 and check.on_floor
	for check in flights:
		ok = ok and check.started and check.arrived and check.on_floor
	ok = ok and quest == [1,2,3] and FileAccess.file_exists(travel.TOUR_FILE)
	if DisplayServer.get_name() != "headless":
		ok = ok and mouse_turn>.12
	result["pass"] = ok
	FileAccess.open("user://travel_play_test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("TRAVEL_PLAY_TEST ",JSON.stringify(result))
	get_tree().quit(0 if ok else 1)
