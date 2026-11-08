extends Node
var layer: Node

func _ready() -> void:
	var bay: Dictionary = layer.world.get("spec").get("bay_layout", {})
	var report: Dictionary = {"bounds":bay.get("bounds"), "island":bay.get("island"), "island2":bay.get("island2"), "areas":[]}
	# Independent height-field samples; reef ellipses are reported separately.
	for rect in [Rect2(135,385,200,155),Rect2(-170,430,230,180)]:
		var area := 0.0
		var edge_dry := 0
		for ix in range(int(rect.size.x)):
			for iz in range(int(rect.size.y)):
				var x: float = rect.position.x+ix+0.5
				var z: float = rect.position.y+iz+0.5
				if float(layer.world.call("height_at",x,z)) > -2.4:
					area += 1.0
					if ix==0 or iz==0 or ix==int(rect.size.x)-1 or iz==int(rect.size.y)-1:
						edge_dry += 1
		report.areas.append({"rect":str(rect),"grid_m":1.0,"height_field_dry_m2":area,"dry_boundary_samples":edge_dry})
	var fig: Node3D = layer.player.get("figure")
	var parts: Array = []
	for part in fig.get_children():
		if part is MeshInstance3D:
			var m = part.get_active_material(0)
			parts.append({"name":part.name,"position":str(part.position),"size":str(part.mesh.get_aabb().size),"mesh":part.mesh.get_class(),"color":str(m.albedo_color) if m is StandardMaterial3D else str(m)})
	report.figure = parts
	FileAccess.open("user://rebuild_baseline.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if DisplayServer.get_name() != "headless":
		for key in ["menu","hud","ui"]:
			var ui = layer.main.get(key)
			if ui is CanvasItem: ui.hide()
		layer.player.set("enabled",false)
		layer.player.set_physics_process(false)
		fig.visible = true
		var cam := Camera3D.new()
		layer.main.add_child(cam)
		cam.current=true
		cam.fov=38
		var center: Vector3 = layer.player.global_position+Vector3(0,1.05,0)
		for shot in [["front",Vector3(0,0.2,-4)],["side",Vector3(4,0.2,0)],["back",Vector3(0,0.2,4)]]:
			cam.global_position=center+shot[1]
			cam.look_at(center)
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://figure_original_"+shot[0]+".png")
	print("REBUILD_BASELINE_DONE")
	get_tree().quit()
