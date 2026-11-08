extends Node
## Camera regression. Stairs use island_walk.gd --test-sprint from the shore entrance.
var layer:Node

func _ready()->void:
	await get_tree().create_timer(6).timeout
	for key in ["menu","hud","ui"]:
		var item=layer.main.get(key)
		if item is CanvasItem:item.hide()
	var wheel:Node3D=layer.wheel
	var p:CharacterBody3D=layer.player
	var fig:Node3D=p.get("figure")
	var was_visible:bool=fig.visible
	wheel.call("_seat_player")
	await get_tree().create_timer(.3).timeout
	var yaw:float=wheel.get("_cam_yaw")
	var shots:Array=[]
	for i in range(4):
		var e:=InputEventMouseMotion.new();e.relative=Vector2(PI/2/.0032,0)
		Input.parse_input_event(e)
		await get_tree().create_timer(.2).timeout
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var img:=get_viewport().get_texture().get_image()
			if img!=null:
				img.save_png("user://wheel_view_%d.png"%i)
				shots.append(i)
	var turn:float=absf(float(wheel.get("_cam_yaw"))-yaw)
	var report:Dictionary={"turn_radians":turn,"full_circle":turn>=TAU-.01,"figure_hidden":not fig.visible,"camera_current":wheel.get("_ride_cam").current,"screenshots":shots}
	wheel.call("_release_player")
	await get_tree().process_frame
	report["figure_restored"]=fig.visible==was_visible
	report["pass"]=report.full_circle and report.figure_hidden and report.camera_current and report.figure_restored
	FileAccess.open("user://camera_test.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMERA_TEST ",JSON.stringify(report))
	get_tree().quit(0 if report["pass"] else 1)
