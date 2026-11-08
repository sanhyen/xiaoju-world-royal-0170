extends Node
## Verify obstacles as well as open routes using the real player and input path.
var layer: Node
var player: CharacterBody3D
var island: Node3D
var results: Array = []

func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _point(local: Vector3) -> Vector3:
	return island.wp(local.x,local.y,local.z)

func _attempt(label: String, start: Vector3, end: Vector3, blocked: bool, sprint: bool = false) -> void:
	_key(KEY_W,false)
	_key(KEY_SHIFT,false)
	layer.teleport(_point(start)+Vector3.UP*.04)
	for frame in range(8):
		await get_tree().physics_frame
	var origin := player.global_position
	var direction := (_point(end)-_point(start)).normalized()
	direction.y = 0
	direction = direction.normalized()
	player.set("yaw",atan2(-direction.x,-direction.z))
	var motion := direction*origin.distance_to(_point(end))
	var sweep := KinematicCollision3D.new()
	var shape_hit := player.test_move(player.global_transform,motion,sweep)
	var sweep_normal := sweep.get_normal() if shape_hit else Vector3.ZERO
	var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.85,_point(end)+Vector3.UP*.85,1,[player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	var furthest := 0.0
	var contact := false
	_key(KEY_SHIFT,sprint)
	_key(KEY_W,true)
	for frame in range(42):
		await get_tree().physics_frame
		furthest = maxf(furthest,(player.global_position-origin).dot(direction))
		for i in range(player.get_slide_collision_count()):
			if absf(player.get_slide_collision(i).get_normal().y)<.5:
				contact = true
	_key(KEY_W,false)
	_key(KEY_SHIFT,false)
	var limit := Vector2(end.x-start.x,end.y-start.y).length()*.5
	# A horizontal capsule sweep may touch the bridge's 5 cm raised floor.
	# Only a wall normal is an obstruction; real input must still cross the gate.
	var obstacle_hit := shape_hit and absf(sweep_normal.y)<.5
	var passed := obstacle_hit and not hit.is_empty() and contact and furthest<limit if blocked else furthest>limit and not obstacle_hit and hit.is_empty()
	results.append({"name":label,"expected_blocked":blocked,"sprint":sprint,"pass":passed,
		"capsule_hit":shape_hit,"sweep_normal":str(sweep_normal),"ray_hit":str(hit.collider.get_path()) if not hit.is_empty() else "",
		"wall_contact":contact,"furthest_m":furthest,"boundary_m":limit,"end":str(player.global_position)})

func _ready() -> void:
	player = layer.player
	island = layer.sky_island
	player.set("enabled",true)
	# These locations are taken from the visible authored model, not collision data.
	for side in [-1,1]:
		await _attempt("gate_panel_%d"%side,Vector3(side*4.75,1.42,48),Vector3(side*4.75,4.42,48),true)
		await _attempt("gate_wing_%d"%side,Vector3(side*11,.5,48.5),Vector3(side*11,3.5,48.5),true)
		await _attempt("gate_apron_rail_%d"%side,Vector3(side*15.7,8,48),Vector3(side*18.7,8,48),true,true)
		await _attempt("courtyard_front_rail_%d"%side,Vector3(side*40,13.5,48),Vector3(side*40,10.5,48),true)
		await _attempt("outer_court_rail_%d"%side,Vector3(side*66.5,45,48),Vector3(side*69.5,45,48),true,true)
		await _attempt("upper_stair_rail_%d"%side,Vector3(side*3.1,62,56),Vector3(side*6.1,62,56),true,true)
		await _attempt("pond_bridge_rail_%d"%side,Vector3(34+side*.1,56,48.68),Vector3(34+side*3.1,56,48.68),true,true)
		for flight in [[-100,11],[-66,25.5],[-31,40.5]]:
			await _attempt("climb_rail_%d_%d"%[side,flight[0]],Vector3(side*3,flight[0],flight[1]),Vector3(side*6,flight[0],flight[1]),true,true)
	for hall in [["main",0,94,64,46,22],["west",-46,66,48,25,16],["east_front",61,17,48,18,15],["east_rear",64,54,48,21,15]]:
		var cx: float = hall[1]
		var depth: float = hall[2]
		var height: float = hall[3]
		var width: float = hall[4]
		var length: float = hall[5]
		await _attempt(hall[0]+"_side",Vector3(cx+width*.5-1.5,depth,height),Vector3(cx+width*.5+1.5,depth,height),true,true)
		await _attempt(hall[0]+"_other_side",Vector3(cx-width*.5+1.5,depth,height),Vector3(cx-width*.5-1.5,depth,height),true,true)
		await _attempt(hall[0]+"_rear",Vector3(cx+4,depth+length*.5-1.5,height),Vector3(cx+4,depth+length*.5+1.5,height),true)
		await _attempt(hall[0]+"_front_window",Vector3(cx+width*.3,depth-length*.5-1.5,height),Vector3(cx+width*.3,depth-length*.5+1.5,height),true)
		await _attempt(hall[0]+"_window_from_inside",Vector3(cx+width*.3,depth-length*.5+1.5,height),Vector3(cx+width*.3,depth-length*.5-1.5,height),true,true)
		await _attempt(hall[0]+"_column",Vector3(cx-width/3-1.5,depth-length*.5-1,height),Vector3(cx-width/3+1.5,depth-length*.5-1,height),true,true)
		await _attempt(hall[0]+"_door_in",Vector3(cx,depth-length*.5-2,height),Vector3(cx,depth-length*.5+2,height),false)
		await _attempt(hall[0]+"_door_out",Vector3(cx,depth-length*.5+2,height),Vector3(cx,depth-length*.5-2,height),false)
	await _attempt("gate_main_open",Vector3(0,-4.5,48),Vector3(0,4.5,48),false,true)
	await _attempt("spring_access_open",Vector3(18,14.5,48),Vector3(23,14.5,48),false)
	await _attempt("side_bridge_open",Vector3(13.5,14.5,48),Vector3(20.5,14.5,48),false,true)
	await _attempt("side_bridge_return_open",Vector3(22,14.5,48),Vector3(15,14.5,48),false,true)
	await _attempt("hall_interior_open",Vector3(0,86,64),Vector3(0,91,64),false)
	await _attempt("pavilion_column",Vector3(29.5,77,48),Vector3(32.5,77,48),true,true)
	await _attempt("spring_basin",Vector3(46.8,36.1,48),Vector3(54.6,36.1,48),true)
	await _jump_wall()
	var failed: Array = results.filter(func(row: Dictionary) -> bool: return not row["pass"])
	var report := {"pass":failed.is_empty(),"cases":results,"failed":failed.size(),"player_layer":player.collision_layer,"player_mask":player.collision_mask}
	FileAccess.open("user://island_collision.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ISLAND_COLLISION ",JSON.stringify(report))
	load("res://scripts/renewal/qa/completion.gd").finish(self,0 if failed.is_empty() else 1)

func _jump_wall() -> void:
	layer.teleport(island.wp(21.2,94,64.05))
	for i in range(8):
		await get_tree().physics_frame
	var origin := player.global_position
	var direction: Vector3 = (island.wp(25,94,64)-origin).normalized()
	direction.y = 0
	direction = direction.normalized()
	player.set("yaw",atan2(-direction.x,-direction.z))
	var high := origin.y
	var furthest := 0.0
	_key(KEY_W,true)
	_key(KEY_SHIFT,true)
	for i in range(65):
		if i==0 or i==22:
			_key(KEY_SPACE,true)
		if i==3 or i==25:
			_key(KEY_SPACE,false)
		await get_tree().physics_frame
		high = maxf(high,player.global_position.y)
		furthest = maxf(furthest,(player.global_position-origin).dot(direction))
	_key(KEY_W,false)
	_key(KEY_SHIFT,false)
	_key(KEY_SPACE,false)
	results.append({"name":"double_jump_sprint_against_wall","pass":high>origin.y+1.1 and furthest<1.8,"jump_height_m":high-origin.y,"furthest_m":furthest})
