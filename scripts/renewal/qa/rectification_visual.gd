extends Node
var layer:Node
var _camera:Camera3D
var _show_player:=false

func _process(_delta:float)->void:
	if is_instance_valid(_camera):_camera.current=true
	if layer!=null and layer.player!=null:
		var figure:Node3D=layer.player.get("figure")
		if figure!=null:figure.visible=_show_player

func _ready()->void:
	await layer.main.call("start_game",false)
	await get_tree().create_timer(2).timeout
	for key in ["menu","hud","ui"]:
		var item:Variant=layer.main.get(key)
		if item is CanvasItem or item is CanvasLayer:item.hide()
	layer.travel_play.release_motion_for_travel()
	layer.player.set("enabled",false);layer.player.set_physics_process(false)
	var cam:=Camera3D.new();cam.fov=62;cam.far=3500;layer.main.add_child(cam);cam.current=true
	_camera=cam;process_priority=1000
	var views:Array=[
		["island_overview",Vector3(-590,158,490),Vector3(-780,45,300)],
		["cliff_walk",Vector3(-735,75,502),Vector3(-850,43,400)],
		["hall_rear",Vector3(-917,91,250),Vector3(-850,63,290)],
		["flower_island",Vector3(-596,123,145),Vector3(-670,90,70)],
		["spring_island",Vector3(-798,143,610),Vector3(-870,106,535)],
		["moon_island",Vector3(592,191,-510),Vector3(490,143,-600)],
		["creek_close",Vector3(132,12,-40),Vector3(140,.35,-20)],
		["creek_junction",Vector3(235,11,104),Vector3(255,.25,80)]
	]
	views.append(["river_compare",Vector3(146,10,-7),Vector3(140,.35,-20)])
	views.append(["saved_location",Vector3(-280,20,-100),Vector3(-288,15,-112)])
	var gardens:Dictionary=layer.sky_expansion.garden_art
	if gardens.has("spring"):
		var center:Vector3=gardens.spring.center;var fall:Vector3=gardens.spring.fall_top
		views.append(["spring_garden_close",center+Vector3(-12,8,11),center+Vector3.UP*.5])
		views.append(["spring_waterfall",fall+Vector3(-11,4,10),fall-Vector3.UP*1.6])
	if gardens.has("moon"):
		var center:Vector3=gardens.moon.center
		views.append(["moon_gallery",center+Vector3(-12,5,10),center+Vector3.UP*1.8])
	views.append(["flower_petals",Vector3(-675,94,80),Vector3(-670,93,70)])
	for route in layer.surfaces.paths:
		if route.label=="北天云路":
			var line:PackedVector3Array=route.points
			var index:=mini(int(line.size()*.36),line.size()-2)
			var at:Vector3=line[index]
			var ahead:Vector3=line[mini(index+3,line.size()-1)]
			views.append(["celestial_guardrail",at+Vector3.UP*1.75,ahead+Vector3.UP*.95])
			break
	var report:Array=[]
	for view in views:
		var eye:Vector3=view[1];var look:Vector3=view[2]
		if str(view[0]).begins_with("creek"):
			var river:Dictionary=layer.rivers.profile(Vector2(look.x,look.z),false)
			if not river.is_empty():
				look.y=float(river.water)+.1
				var side:=Vector2(-river.flow.y,river.flow.x)*(float(river.half)+3.5)
				var left:=Vector2(look.x,look.z)+side;var right:=Vector2(look.x,look.z)-side
				var bank:Vector2=left if float(layer.world.call("height_at",left.x,left.y))<float(layer.world.call("height_at",right.x,right.y)) else right
				var shore:Dictionary=layer.rivers.profile(bank)
				var ground:float=float(layer.world.call("height_at",bank.x,bank.y))
				if not shore.is_empty():ground=maxf(ground,float(shore.bed))
				eye=Vector3(bank.x,ground+2.1,bank.y)
		layer.world.call("prepare_region",look,120.0)
		layer.teleport(look+Vector3.UP*3)
		cam.global_position=eye;cam.look_at(look,Vector3.UP);cam.current=true
		for frame in range(100):await get_tree().process_frame
		layer.rivers.flush_pending()
		await RenderingServer.frame_post_draw
		var img:=get_viewport().get_texture().get_image()
		img.save_png("user://"+str(view[0])+".png")
		report.append({"view":view[0],"eye":str(eye),"target":str(look),"width":img.get_width(),"height":img.get_height()})
	if OS.get_cmdline_user_args().has("--rectify-video"):
		DirAccess.make_dir_recursive_absolute("user://tour_frames")
		for i in range(128):
			var t:=float(i)/128;var angle:=lerpf(-.55,.55,t)
			cam.global_position=Vector3(-770+cos(angle)*215,142,300+sin(angle)*235)
			cam.look_at(Vector3(-780,47,300),Vector3.UP)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://tour_frames/frame_%04d.png"%i)
		await _gameplay_clips()
	FileAccess.open("user://visual_capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RECTIFICATION_VISUAL views=",report.size())
	get_tree().quit()

func _key(code:Key,down:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;Input.parse_input_event(event)

func _gameplay_clips()->void:
	_show_player=true
	for key in ["hud","ui"]:
		var item:Variant=layer.main.get(key)
		if item is CanvasItem or item is CanvasLayer:item.show()
	var p:CharacterBody3D=layer.player
	p.set("enabled",true);p.set_physics_process(true)
	for clip in ["walk","sky","wade","flight"]:
		DirAccess.make_dir_recursive_absolute("user://"+clip+"_frames")
		var points:=PackedVector3Array()
		if clip=="walk" or clip=="sky":
			for row in layer.surfaces.paths:
				if row.label==("南崖木栈道" if clip=="walk" else "北天云路"):points=row.points;break
		elif clip=="flight":points=layer.sky_expansion.climb_stations
		else:
			var at:=Vector2(70,-45);var water:Dictionary=layer.rivers.profile(at)
			var side:=Vector3(-water.flow.y,0,water.flow.x)
			points=PackedVector3Array([Vector3(at.x,water.bed,at.y)-side*2,Vector3(at.x,water.water,at.y)+side*(water.half+9)])
		layer.teleport(points[0]+Vector3.UP*.15);layer.world.call("prepare_region",points[0],100.0)
		for tick in range(30):await get_tree().physics_frame
		layer.rivers.flush_pending()
		var waypoint:=1
		if clip=="flight":_key(KEY_Y,true);await get_tree().physics_frame;_key(KEY_Y,false)
		else:_key(KEY_W,true)
		var count:=360 if clip=="flight" else 120
		for frame in range(count):
			for tick in range(4):
				if clip!="flight":
					while waypoint<points.size()-1 and Vector2(p.global_position.x-points[waypoint].x,p.global_position.z-points[waypoint].z).length()<1:waypoint+=1
					var d:=points[waypoint]-p.global_position;p.set("yaw",atan2(-d.x,-d.z))
					if clip=="wade" and Vector2(d.x,d.z).length()<.55:_key(KEY_W,false)
				await get_tree().physics_frame
			var offset:=Vector3(6,7,4) if clip=="wade" else Vector3(10,6,12)
			_camera.global_position=p.global_position+offset
			_camera.look_at(p.global_position+Vector3.UP)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://"+clip+"_frames/frame_%04d.png"%frame)
		_key(KEY_W,false)
		if layer.travel_play.in_flight:layer.travel_play._end_flight(layer.travel_play.flight_from,true)
