extends Node
## Run the existing acceptance probes in one isolated packaged game process.
## Every probe keeps its own assertions and report, with vehicle/input cleanup.
var layer:Node
var records:Array=[]

func _process(_delta:float)->void:
	# --fixed-fps keeps every simulated physics step at the original duration.
	# Removing only the headless presentation cap avoids real-time waits; this
	# probe is never used for rendered FPS measurements or normal play.
	if DisplayServer.get_name()=="headless":Engine.max_fps=0

func _ready()->void:
	if DisplayServer.get_name()=="headless":Engine.max_fps=0
	await layer.main.call("start_game",false)
	await get_tree().create_timer(3.0).timeout
	var selected:PackedStringArray=[]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-only="):selected=argument.substr(10).split(",")
	for row in [
		["movement","rectification_test.gd","rectification_movement.json"],
		["climb","island_walk.gd","island_walk.txt"],
		["collision","island_collision_test.gd","island_collision.json"],
		["travel","travel_test.gd","travel_test.json"],
		["realm","realm_walk.gd","realm_walk.json"],
		["wheel","wheel_test.gd","wheel_test.txt"],
		["boat","boat_travel_test.gd","boat_travel_test.json"],
		["rivers","rectification_test.gd","rectification_rivers.json"],
		["boatstate","rectification_test.gd","rectification_boatstate.json"],
		["coverage","rectification_test.gd","rectification_coverage.json"],
		["sky","rectification_test.gd","rectification_sky.json"],
		["skymap","rectification_test.gd","rectification_skymap.json"],
		["clearance","rectification_test.gd","rectification_clearance.json"],
		["spot","rectification_test.gd","rectification_spot.json"],
		["flights","rectification_test.gd","rectification_flights.json"]]:
		if not selected.is_empty() and not str(row[0]) in selected:continue
		print("SUITE_BEGIN ",row[0])
		await _reset()
		var test:Node=load("res://scripts/renewal/qa/"+row[1]).new()
		test.layer=layer;test.set_meta("qa_suite_active",true);test.set_meta("qa_scope",row[0])
		if row[0]=="travel":test.inspect_only=false
		add_child(test)
		var ticks:=0
		while not test.has_meta("qa_finished") and ticks<50000:
			await get_tree().physics_frame;ticks+=1
		var code:int=int(test.get_meta("qa_finished",-1))
		var output:String=row[2]
		if row[1]=="rectification_test.gd":
			FileAccess.open("user://"+output,FileAccess.WRITE).store_string(FileAccess.get_file_as_string("user://rectification_test.json"))
		var content:=FileAccess.get_file_as_string("user://"+output)
		var passed:=code==0
		if output.ends_with(".json"):
			var parsed:Variant=JSON.parse_string(content);passed=passed and parsed is Dictionary and bool(parsed.get("pass",false))
		elif row[0]=="climb":passed=passed and "VERDICT bridge_and_stairs=PASS" in content
		elif row[0]=="wheel":
			for check in ["walk_to_deck reached=true","seated riding=true","save_written=true","player_follow_err=0.00m"]:passed=passed and check in content
		records.append({"name":row[0],"exit":code,"pass":passed,"report":output,"physics_ticks":ticks})
		print("SUITE_END ",row[0]," pass=",passed)
		test.queue_free();await get_tree().process_frame
	var failed:=records.filter(func(row:Dictionary)->bool:return not row.pass)
	FileAccess.open("user://suite_report.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":failed.is_empty(),"checks":records,"failed":failed},"\t"))
	print("RECTIFICATION_SUITE_DONE failed=",failed.size())
	get_tree().quit(0 if failed.is_empty() else 1)

func _reset()->void:
	for key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_Y,KEY_ESCAPE]:
		var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=false;Input.parse_input_event(event)
	if layer.travel_play.in_flight:layer.travel_play._end_flight(layer.travel_play.flight_from,true)
	if bool(layer.wheel.get("riding")):layer.wheel.call("_release_player")
	await layer.map_marker.travel_to(Vector3(292,3.65,252),"验收起点")
	layer.travel_play.release_motion_for_travel();layer.player.set_physics_process(true);layer.player.set("enabled",true)
	layer.player.velocity=Vector3.ZERO;layer.player.call("reset_jump_state")
	layer.safety._last_support=layer.player.global_position
	for tick in range(10):await get_tree().physics_frame
