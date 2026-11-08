extends Node
## 批量取证：一次启动内为 20 栋建筑拍改造前/后同视角截图。
## 用法：--renewal-probe=batch --batch=buildings --tag=after [--themes=...]

var layer: Node
var tag := "after"
var mode := "buildings"
var out_dir := "D:/xiaojuWorld/renewal/evidence/shots/buildings"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		if a.begins_with("--batch="):
			mode = a.substr(8)
	await get_tree().create_timer(4.0).timeout
	# 进入游戏态并隐藏主菜单/HUD，保证截图只反映世界本身
	await get_tree().create_timer(0.5).timeout
	for key in ["menu", "hud"]:
		var n = layer.main.get(key)
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	if mode == "buildings":
		await _buildings()
	else:
		await _wheel()
	print("BATCH_DONE ", tag)
	get_tree().quit()

func _buildings() -> void:
	var f := FileAccess.open("res://data/renewal/buildings_0170.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	var p: CharacterBody3D = layer.player
	for cfg in data["buildings"]:
		var id := str(cfg["id"])
		var c := Vector3(float(cfg["center"][0]), float(cfg["floor_y"]), float(cfg["center"][2]))
		var w := float(cfg["w"]); var d := float(cfg["d"]); var h := float(cfg["h"])
		var dist := maxf(w, d) * 0.5 + 16.0
		var eye := Vector3(c.x, c.y + h + 6.0, c.z + dist)
		var look := Vector3(c.x, c.y + h * 0.5, c.z)
		# 传送玩家触发该区域流式加载与就近隐藏
		p.global_position = Vector3(c.x, c.y + 1.0, c.z + dist - 3.0)
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(2.6).timeout
		print("POS ", id, " player=", p.global_position)
		var cam := Camera3D.new()
		cam.fov = 55.0
		layer.main.add_child(cam)
		cam.global_position = eye
		cam.look_at(look, Vector3.UP)
		cam.current = true
		for i in range(12):
			await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, id, tag])
		cam.queue_free()
		print("SHOT ", id)

func _wheel() -> void:
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	var site := Vector3(-420.0, 4.0, 275.0)
	var shots := [
		["wheel_far", Vector3(site.x + 40.0, site.y + 26.0, site.z + 110.0), Vector3(site.x, site.y + 40.0, site.z), 58.0],
		["wheel_front", Vector3(site.x, site.y + 4.0, site.z + 58.0), Vector3(site.x, site.y + 36.0, site.z), 64.0],
		["wheel_side", Vector3(site.x + 86.0, site.y + 18.0, site.z + 34.0), Vector3(site.x, site.y + 40.0, site.z), 60.0],
		["wheel_deck", Vector3(site.x, site.y + 4.6, site.z + 14.0), Vector3(site.x, site.y + 4.0, site.z), 66.0],
	]
	for s in shots:
		p.global_position = Vector3(site.x, site.y + 2.0, site.z + 18.0)
		await get_tree().create_timer(2.2).timeout
		var cam := Camera3D.new()
		cam.fov = float(s[3])
		layer.main.add_child(cam)
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		cam.current = true
		for i in range(14):
			await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, str(s[0]), tag])
		cam.queue_free()
		print("SHOT ", str(s[0]))
