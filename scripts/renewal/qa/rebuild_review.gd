extends Node
var layer: Node

func _ready() -> void:
	get_window().size=Vector2i(1920,1080)
	get_window().content_scale_size=Vector2i(1920,1080)
	await get_tree().create_timer(2.0).timeout
	var island:Node3D=layer.sky_island
	if not island.has_method("wp"):
		push_error("Review requires --island-rebuild=s1 or s2")
		get_tree().quit(2);return
	for key in ["menu","hud","ui"]:
		var ui=layer.main.get(key)
		if ui is CanvasItem:ui.hide()
	layer.player.set("enabled",false)
	layer.player.set_physics_process(false)
	layer.player.global_position=island.wp(1.4,-9,48.05)
	var fig:Node3D=layer.player.get("figure")
	fig.visible=true
	fig.rotation.y=-PI/2
	var cam:=Camera3D.new();layer.main.add_child(cam);cam.current=true;cam.far=1800;cam.fov=50
	var shots:Array=[
		["water",Vector3(-49,-32,59),Vector3(-26,-1,34)],
		["overview",Vector3(130,-220,220),Vector3(0,5,30)],
		["gate",Vector3(25,-55,72),Vector3(0,0,50)],
		["eye",Vector3(1,-23,45.85),Vector3(0,3,52)],
		["character",Vector3(1.4,-13.6,49.2),Vector3(1.4,-9,49)],
		["character_side",Vector3(6,-9,49.2),Vector3(1.4,-9,49)],
		["character_back",Vector3(1.4,-4.4,49.2),Vector3(1.4,-9,49)],
		["side",Vector3(70,-25,62),Vector3(0,-20,38)]]
	for shot in shots:
		var a:Vector3=shot[1];var b:Vector3=shot[2]
		cam.global_position=island.wp(a.x,a.y,a.z)
		cam.look_at(island.wp(b.x,b.y,b.z))
		await get_tree().create_timer(2).timeout
		await RenderingServer.frame_post_draw
		var img:=get_viewport().get_texture().get_image()
		img.save_png("user://"+island.stage+"_"+shot[0]+".png")
		print("REBUILD_SHOT ",shot[0]," ",img.get_size())
	var report:Dictionary=island.stats.duplicate(true)
	report["viewport"]=str(get_viewport().get_visible_rect().size)
	report["render_method"]=ProjectSettings.get_setting("rendering/renderer/rendering_method")
	report["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["render_primitives"]=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if OS.get_cmdline_user_args().has("--rebuild-perf"):
		print("REBUILD_PERF_BEGIN warmup=10 duration=180 no_image_capture")
		await get_tree().create_timer(10).timeout
		var frames:Array[float]=[]
		var start:int=Time.get_ticks_usec()
		var last:int=start
		while Time.get_ticks_usec()-start<180000000:
			var time:float=(Time.get_ticks_usec()-start)/1000000.0
			var d:float=-70.0+55.0*(sin(time*.075)*.5+.5)
			var x:float=sin(time*.11)*22
			cam.global_position=island.wp(x,d,island.route_height(d)+9)
			cam.look_at(island.wp(0,0,52))
			await get_tree().process_frame
			var now:int=Time.get_ticks_usec()
			frames.append((now-last)/1000.0);last=now
		frames.sort()
		var over33:=0
		var over50:=0
		for value in frames:
			if value>33.3:over33+=1
			if value>50:over50+=1
		var perf:Dictionary={"duration_s":180,"sample_count":frames.size(),"resolution":str(get_viewport().get_visible_rect().size),"p50_ms":frames[int(frames.size()*.5)],"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"frames_over_33_3_ms":over33,"frames_over_50_ms":over50,"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"measurement":"offscreen real rendered frame wall intervals, automatic camera path, full original world loaded; not manual play or GPU-only time"}
		FileAccess.open("user://s2_performance.json",FileAccess.WRITE).store_string(JSON.stringify(perf,"\t"))
		print("REBUILD_PERF_DONE ",JSON.stringify(perf))
	if OS.get_cmdline_user_args().has("--rebuild-video"):
		DirAccess.make_dir_recursive_absolute("user://motion")
		for i in range(96):
			var t:float=i/95.0
			cam.global_position=island.wp(24*sin(t*1.4),lerpf(-65,-20,t),lerpf(68,59,t))
			cam.look_at(island.wp(0,0,52))
			await get_tree().create_timer(.1).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://motion/frame_%03d.png"%i)
		print("REBUILD_VIDEO_FRAMES 96")
	FileAccess.open("user://"+island.stage+"_review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	get_tree().quit()
