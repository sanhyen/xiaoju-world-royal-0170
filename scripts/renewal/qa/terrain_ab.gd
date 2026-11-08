extends Node
## --terrain=0/1 使用完全相同机位，保存三幅图与物理射线采样元数据。
var layer: Node

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	for key in ["menu", "hud", "ui"]:
		var ui = layer.main.get(key)
		if ui is CanvasItem:
			ui.visible = false
	var suffix := "off" if OS.get_cmdline_user_args().has("--terrain=0") else "on"
	var cam := Camera3D.new()
	cam.fov = 58
	layer.main.add_child(cam)
	cam.current = true
	var views := [
		{"name":"slope", "pos":Vector3(-350,140,-545), "look":Vector3(-350,65,-465)},
		{"name":"beach", "pos":Vector3(280,95,345), "look":Vector3(280,0,345)},
		{"name":"flat", "pos":Vector3(345,70,230), "look":Vector3(345,3,230)}
	]
	for view in views:
		cam.global_position = view.pos
		cam.look_at(view.look, Vector3.FORWARD if view.name != "slope" else Vector3.UP)
		await get_tree().create_timer(1.0).timeout
		for i in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://T2_%s_%s.png" % [view.name, suffix])
		if view.name == "slope" and suffix == "on":
			_debug_mask(true)
			for i in range(8):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://T2_slope_mask.png")
			_debug_mask(false)
		var samples: Array = []
		var size := get_viewport().get_visible_rect().size
		for y in range(50, int(size.y)-50, 30):
			for x in range(50, int(size.x)-50, 30):
				var pixel := Vector2(x,y)
				var from := cam.project_ray_origin(pixel)
				var q := PhysicsRayQueryParameters3D.create(from, from+cam.project_ray_normal(pixel)*1200)
				q.exclude = [layer.player.get_rid()]
				var hit: Dictionary = layer.player.get_world_3d().direct_space_state.intersect_ray(q)
				if hit.is_empty():
					continue
				var p: Vector3 = hit.position
				var normal: Vector3 = hit.normal
				var color: Color = layer.world.call("terrain_color_at", p.x, p.z)
				samples.append({"pixel":[x,y],"uv":[x/size.x,y/size.y],"position":[p.x,p.y,p.z],"normal_y":normal.y,"collider":str(hit.collider.name),"color":[color.r,color.g,color.b,color.a]})
		var f := FileAccess.open("user://T2_%s_%s.json" % [view.name,suffix],FileAccess.WRITE)
		f.store_string(JSON.stringify(samples))
		f.close()
	print("TERRAIN_AB_DONE ",suffix)
	get_tree().quit()

func _debug_mask(value: bool) -> void:
	var appearance: Node = layer.look.get_node_or_null("TerrainAppearance")
	if appearance != null:
		var cache: Dictionary = appearance.get("_cache")
		for material in cache.values():
			(material as ShaderMaterial).set_shader_parameter("p4_debug",value)
