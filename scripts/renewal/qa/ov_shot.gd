extends Node
## 俯视图截图：打开全局俯视，定位到指定中心，截图。

var layer: Node

func _ready() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ov="):
			for kv in a.substr(5).split(";"):
				var p: PackedStringArray = kv.split("=")
				if p.size() == 2:
					args[p[0]] = p[1]
	await get_tree().create_timer(5.0).timeout
	# 关掉启动主菜单，否则它整块盖在俯视图上
	if layer != null and layer.main != null:
		for key in ["menu", "hud", "ui"]:
			var n = layer.main.get(key)
			if n is CanvasItem:
				(n as CanvasItem).visible = false
	var ov = layer.overhead
	if ov == null:
		print("OV_SHOT no_overhead")
		get_tree().quit()
		return
	ov._set_enabled(true)
	await get_tree().process_frame
	ov._target = Vector3(float(args.get("tx", "-200")), 0.0, float(args.get("tz", "300")))
	ov._height = float(args.get("h", "260"))
	ov._update_camera()
	for i in range(50):
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	var out := str(args.get("out", "user://ov.png"))
	img.save_png(out)
	print("OV_SHOT_SAVED ", out)
	get_tree().quit()
