extends Node
## 坐进摩天轮吊舱后截图，验证相机是否在舱内、能否看到窗外。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	if layer != null and layer.main != null:
		for key in ["menu", "hud", "ui"]:
			var n = layer.main.get(key)
			if n is CanvasItem:
				(n as CanvasItem).visible = false
	var wheel = layer.wheel
	if wheel == null:
		print("WHEEL_SHOT no_wheel")
		get_tree().quit()
		return
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	wheel.boarding_index = 0
	wheel.state = "boarding"
	wheel.door_open = 1.0
	await get_tree().create_timer(1.0).timeout
	wheel._seat_player()
	await get_tree().create_timer(0.6).timeout
	# 让轮子转到一个有风景的角度
	wheel.angle = deg_to_rad(110.0)
	await get_tree().create_timer(2.5).timeout
	var lines: Array[String] = []
	lines.append("riding=%s zoom=%.2f spring=%.2f" % [
		str(wheel.riding), float(p.get("zoom")),
		(p.get("arm") as SpringArm3D).spring_length if p.get("arm") is SpringArm3D else -1.0])
	lines.append("player=%s" % str(p.global_position))
	var cam := get_viewport().get_camera_3d()
	if cam is Camera3D:
		lines.append("cam_pos=%s current=%s path=%s" % [str((cam as Camera3D).global_position), str((cam as Camera3D).current),str(cam.get_path())])
	var f := FileAccess.open("user://wheel_shot.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	var img := get_viewport().get_texture().get_image()
	var output := "user://wheel_inside.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wheelshot-out="):
			output = arg.substr("--wheelshot-out=".length())
	img.save_png(output)
	print("WHEEL_SHOT_SAVED")
	get_tree().quit()
