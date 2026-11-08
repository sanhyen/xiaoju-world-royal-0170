extends Node
var layer: Node
var player: CharacterBody3D
var rows: Array = []

func _ready() -> void:
	player = layer.player
	player.set("enabled",true)
	layer.teleport(Vector3(100,8,274))
	await get_tree().create_timer(1.5).timeout
	player.set("run_toggle",true)
	player.set("run_latched",false)
	player.set("yaw",-PI*0.5)
	_key(KEY_W,true)
	await _sample("walk",1.6)
	player.set("run_latched",true)
	await _sample("run",1.6)
	player.set("run_latched",false)
	_key(KEY_W,false)
	await get_tree().create_timer(0.4).timeout
	player.set("jump_requested",true)
	await _sample("jump",2.2)
	player.call("sit_at",player.global_position+Vector3(0,0.5,0),0.0)
	if player.get_method_argument_count("apply_seated_pose") == 0:
		player.call("apply_seated_pose")
	var legs: Array = player.get("legs")
	var native := Vector2(legs[0].rotation.x,legs[1].rotation.x)
	await get_tree().create_timer(0.3).timeout
	var seat_after := Vector2(legs[0].rotation.x,legs[1].rotation.x)
	var seat_ok := bool(player.get("seated")) and seat_after.distance_to(native)<0.001
	player.call("stand_up")
	player.set("run_toggle",false)
	await get_tree().create_timer(0.3).timeout
	var walk_peak := 0.0
	var run_peak := 0.0
	var walk_speed := 0.0
	var run_speed := 0.0
	var anti := true
	var rise := 0
	var fall := 0
	for row in rows:
		if row.stage == "jump" and not row.floor:
			if row.vy>0.5: rise += 1
			if row.vy< -0.5: fall += 1
		if row.floor and row.air_blend<0.01 and row.speed>1:
			anti = anti and row.leg_l*row.arm_l<=0.0001 and row.leg_r*row.arm_r<=0.0001
			if row.stage == "walk":
				walk_peak = maxf(walk_peak,absf(row.leg_l))
				walk_speed = maxf(walk_speed,row.speed)
			elif row.stage == "run":
				run_peak = maxf(run_peak,absf(row.leg_l))
				run_speed = maxf(run_speed,row.speed)
	var result := {"walk_peak_rad":walk_peak,"run_peak_rad":run_peak,"walk_speed":walk_speed,"run_speed":run_speed,"arms_antiphase":anti,"jump_rise_samples":rise,"jump_fall_samples":fall,"native_seated_pose_preserved":seat_ok,"native_seat":str(native),"seat_after":str(seat_after),"stand_up":not bool(player.get("seated")),"samples":rows}
	result["pass"] = anti and walk_peak>0.1 and run_peak>walk_peak*1.1 and run_peak<=0.91 and run_speed>walk_speed*1.5 and rise>0 and fall>0 and seat_ok
	var f := FileAccess.open("user://figure_motion.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	result.erase("samples")
	print("FIGURE_MOTION ",result)
	get_tree().quit(0 if result["pass"] else 1)

func _key(code: Key,down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _sample(stage: String,seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < seconds*1000:
		await get_tree().create_timer(0.05).timeout
		var look: Node = layer.get_node("FigureLook")
		var legs: Array = player.get("legs")
		var arms: Array = player.get("arms")
		rows.append({"stage":stage,"time":Time.get_ticks_msec()/1000.0,"floor":player.is_on_floor(),"speed":Vector2(player.velocity.x,player.velocity.z).length(),"vy":player.velocity.y,"gain":look.get("current_gain"),"air_blend":look.get("_air_blend"),"leg_l":legs[0].rotation.x,"leg_r":legs[1].rotation.x,"arm_l":arms[0].rotation.x,"arm_r":arms[1].rotation.x})
