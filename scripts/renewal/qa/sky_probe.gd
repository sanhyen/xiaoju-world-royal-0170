extends Node
## 屏幕射线探针：按给定机位把屏幕上半部打成网格射线，报告命中的节点与距离。
## 用法：--renewal-probe=sky --skycam=px,py,pz,lx,ly,lz
## 输出 user://sky_probe.txt

var layer: Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var cam := Camera3D.new()
	var p := Vector3(0, 55, 345)
	var t := Vector3(70, -3, 485)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skycam="):
			var s := a.substr(9).split(",")
			if s.size() >= 6:
				p = Vector3(float(s[0]), float(s[1]), float(s[2]))
				t = Vector3(float(s[3]), float(s[4]), float(s[5]))
	cam.fov = 62.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame

	var space := get_viewport().world_3d.direct_space_state
	var out: Array[String] = []
	out.append("camera=%s -> %s" % [str(p), str(t)])
	out.append("viewport=%s" % str(get_viewport().get_visible_rect().size))
	var vp := get_viewport().get_visible_rect().size
	# 扫上半屏：x 0.0~0.55，y 0.05~0.55（左上区域）
	for iy in range(11):
		var line := ""
		for ix in range(12):
			var sx := 0.02 + 0.052 * float(ix)
			var sy := 0.04 + 0.048 * float(iy)
			var from := cam.project_ray_origin(Vector2(sx * vp.x, sy * vp.y))
			var dir := cam.project_ray_normal(Vector2(sx * vp.x, sy * vp.y))
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				line += "."
			else:
				var n: Node = hit["collider"]
				var nm := str(n.name)
				var tag := "?"
				if nm.begins_with("Far"): tag = "F"
				elif nm.begins_with("Terrain") or nm.begins_with("Cell"): tag = "T"
				elif nm.begins_with("Theme"): tag = "B"
				elif nm.to_lower().contains("water") or nm.to_lower().contains("ocean"): tag = "W"
				else: tag = "X"
				line += tag
		out.append("%4.2f %s" % [0.04 + 0.048 * float(iy), line])

	# 对左上区域做一次详细列表：命中的不同节点名 + 最近距离
	out.append("")
	out.append("=== 命中节点明细（左上 1/3 屏）===")
	var seen := {}
	for iy in range(40):
		for ix in range(40):
			var sx2 := 0.0 + (0.45 / 40.0) * float(ix)
			var sy2 := 0.02 + (0.45 / 40.0) * float(iy)
			var from2 := cam.project_ray_origin(Vector2(sx2 * vp.x, sy2 * vp.y))
			var dir2 := cam.project_ray_normal(Vector2(sx2 * vp.x, sy2 * vp.y))
			var q2 := PhysicsRayQueryParameters3D.create(from2, from2 + dir2 * 4000.0)
			var h2 := space.intersect_ray(q2)
			if h2.is_empty():
				continue
			var nn: Node = h2["collider"]
			var key := str(nn.get_path())
			if not seen.has(key):
				seen[key] = {"n": 0, "d": 99999.0, "pos": Vector3.ZERO}
			var e: Dictionary = seen[key]
			e["n"] = int(e["n"]) + 1
			if float(h2["position"].distance_to(cam.global_position)) < float(e["d"]):
				e["d"] = h2["position"].distance_to(cam.global_position)
				e["pos"] = h2["position"]
	for k in seen:
		var e2: Dictionary = seen[k]
		out.append("  hits=%3d  d=%8.1f  at=%s  %s" % [int(e2["n"]), float(e2["d"]), str(e2["pos"]), str(k)])
	_flush(out)

func _flush(out: Array[String]) -> void:
	var f := FileAccess.open("user://sky_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()
	print("SKY_PROBE_DONE %d" % out.size())
	get_tree().quit()
