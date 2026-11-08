extends Node
var layer: Node

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	for key in ["menu","hud","ui"]:
		var ui = layer.main.get(key)
		if ui is CanvasItem:
			ui.visible = false
	var suffix := "before" if OS.get_cmdline_user_args().has("--environment-polish=0") else "after"
	var cam := Camera3D.new()
	cam.fov = 62
	layer.main.add_child(cam)
	cam.current = true
	var views := [
		{"name":"all","pos":Vector3(305,32,185),"look":Vector3(252,4,252)},
		{"name":"reef","pos":Vector3(260,120,530),"look":Vector3(200,0,440)},
		{"name":"junction","pos":Vector3(270,40,235),"look":Vector3(270,3,235)}
	]
	_set_time(0)
	for view in views:
		cam.global_position = view.pos
		cam.look_at(view.look,Vector3.FORWARD if view.name=="junction" else Vector3.UP)
		await get_tree().create_timer(0.8).timeout
		for i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://T8_%s_%s.png" % [view.name,suffix])
	cam.global_position = Vector3(245,35,370)
	cam.look_at(Vector3(245,-1,315),Vector3.UP)
	for time in [0.0,3.0]:
		_set_time(time)
		for i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://T8_foam_%s_%d.png" % [suffix,int(time)])
	var depth: Dictionary = layer.roads.get("depth_layout")
	var result := {"polished":suffix=="after","road_count":layer.roads.get("_roads"),"road_triangles":layer.roads.get("_tris"),"depth_layout":depth}
	var f := FileAccess.open("user://environment_ab_%s.json" % suffix,FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("ENVIRONMENT_AB_DONE ",suffix)
	get_tree().quit()

func _set_time(value: float) -> void:
	if not bool(layer.nearshore.get("polish_enabled")):
		return
	var material: ShaderMaterial = layer.nearshore.get("_mat_band")
	material.set_shader_parameter("qa_time",value)
	var reefs: Array = layer.nearshore.get("_reef_mats")
	for reef in reefs:
		(reef as ShaderMaterial).set_shader_parameter("qa_time",value)
