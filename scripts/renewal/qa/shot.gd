extends Node
## 截图探针：在真实渲染窗口下把相机放到指定位置并保存 PNG。

var layer: Node
var cam: Camera3D

func _ready() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var pairs: PackedStringArray = a.substr(7).split(";")
			for kv in pairs:
				var p: PackedStringArray = kv.split("=")
				if p.size() == 2:
					args[p[0]] = p[1]
	await get_tree().create_timer(4.0).timeout
	if args.has("px"):
		var tp := Vector3(float(args.get("px")), float(args.get("py", "30")), float(args.get("pz")))
		(layer.player as CharacterBody3D).global_position = tp
		await get_tree().create_timer(2.5).timeout
	var hide_ui := str(args.get("hideui", "1")) == "1"
	if hide_ui and layer != null and layer.main != null:
		for key in ["menu", "hud", "ui"]:
			var n = layer.main.get(key)
			if n is CanvasItem:
				(n as CanvasItem).visible = false
	var pos := Vector3(float(args.get("x", "-350")), float(args.get("y", "80")), float(args.get("z", "-395")))
	var look := Vector3(float(args.get("lx", "-350")), float(args.get("ly", "60")), float(args.get("lz", "-300")))
	if layer != null and layer.main != null and str(args.get("noshadow", "0")) == "1":
		var s0 = layer.main.get("sun")
		if s0 is DirectionalLight3D:
			(s0 as DirectionalLight3D).shadow_enabled = false
	if args.has("sun") and layer != null and layer.main != null:
		var sun = layer.main.get("sun")
		if sun is DirectionalLight3D:
			(sun as DirectionalLight3D).light_energy = float(args.get("sun"))
		var env_node = layer.main.get("environment")
		if env_node is WorldEnvironment and (env_node as WorldEnvironment).environment != null:
			(env_node as WorldEnvironment).environment.ambient_light_energy = float(args.get("ambient", "1.0"))
	cam = Camera3D.new()
	cam.fov = float(args.get("fov", "70"))
	layer.main.add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.current = true
	for i in range(40):
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	var out := str(args.get("out", "user://shot.png"))
	img.save_png(out)
	print("SHOT_SAVED ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
