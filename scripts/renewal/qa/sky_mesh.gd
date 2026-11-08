extends Node
## 屏幕区域几何探针：把指定屏幕矩形内所有可见 MeshInstance3D 的 AABB 投影出来，
## 用于定位「看得见但没碰撞」的浮空几何。
## 用法：--renewal-probe=skymesh --skycam=px,py,pz,lx,ly,lz --skyrect=x0,y0,x1,y1
## 输出 user://sky_mesh.txt

var layer: Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var cam := Camera3D.new()
	var p := Vector3(0, 55, 345)
	var t := Vector3(70, -3, 485)
	var rect := Rect2(0.15, 0.10, 0.25, 0.25)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skycam="):
			var s := a.substr(9).split(",")
			if s.size() >= 6:
				p = Vector3(float(s[0]), float(s[1]), float(s[2]))
				t = Vector3(float(s[3]), float(s[4]), float(s[5]))
		elif a.begins_with("--skyrect="):
			var r := a.substr(10).split(",")
			if r.size() >= 4:
				rect = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	cam.fov = 62.0
	cam.far = 6000.0
	add_child(cam)
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame

	var vp := get_viewport().get_visible_rect().size
	var out: Array[String] = []
	out.append("camera=%s -> %s  rect=%s" % [str(p), str(t), str(rect)])
	out.append("=== 投影落在目标屏幕矩形内的 MeshInstance3D ===")
	var found: Array = []
	_walk(get_tree().root, cam, vp, rect, found)
	found.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for i in range(min(40, found.size())):
		var d: Dictionary = found[i]
		out.append("  d=%7.1f  aabb=(%.1f,%.1f,%.1f)  center=(%.1f,%.1f,%.1f)  %s" % [
			float(d["d"]), d["size"].x, d["size"].y, d["size"].z,
			d["c"].x, d["c"].y, d["c"].z, str(d["path"])])
	out.append("")
	out.append("total=%d" % found.size())
	_flush(out)

func _walk(n: Node, cam: Camera3D, vp: Vector2, rect: Rect2, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			var c := a.position + a.size * 0.5
			var dc := cam.global_position.distance_to(c)
			# 背面剔除
			var fwd := -cam.global_transform.basis.z
			if (c - cam.global_position).dot(fwd) > 0.0:
				var lo := Vector2(1e9, 1e9)
				var hi := Vector2(-1e9, -1e9)
				var ok := false
				for k in range(8):
					var corner := a.position + Vector3(
						a.size.x * float(k & 1), a.size.y * float((k >> 1) & 1), a.size.z * float((k >> 2) & 1))
					if cam.is_position_behind(corner):
						continue
					var sp := cam.unproject_position(corner)
					lo = lo.min(sp)
					hi = hi.max(sp)
					ok = true
				if ok:
					var r2 := Rect2(lo, hi - lo)
					var tgt := Rect2(rect.position * vp, rect.size * vp)
					if r2.intersects(tgt):
						acc.append({"d": dc, "size": a.size, "c": c, "path": mi.get_path()})
	for ch in n.get_children(true):
		_walk(ch, cam, vp, rect, acc)

func _flush(out: Array[String]) -> void:
	var f := FileAccess.open("user://sky_mesh.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()
	print("SKY_MESH_DONE %d" % out.size())
	get_tree().quit()
