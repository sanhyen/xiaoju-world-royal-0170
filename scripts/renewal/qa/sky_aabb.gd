extends Node
## 新岛几何体检：逐个 MeshInstance3D 输出世界空间 AABB，确认有没有悬空/缺失。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(9.0).timeout
	var isl: Node = layer.sky_island
	if isl == null:
		out.append("sky_island = NULL")
	else:
		out.append("island global_position = %s" % str((isl as Node3D).global_position))
		_walk(isl, 0)
	var f := FileAccess.open("user://sky_aabb.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("SKY_AABB_DONE")
	get_tree().quit()

func _walk(n: Node, depth: int) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var local: AABB = mi.mesh.get_aabb()
		var xf := mi.global_transform
		# 8 个角点变换后求世界 AABB
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in range(8):
			var c := local.position + Vector3(
				local.size.x * float(i & 1),
				local.size.y * float((i >> 1) & 1),
				local.size.z * float((i >> 2) & 1))
			var w: Vector3 = xf * c
			lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		out.append("%-22s surf=%d tris=%d  world y[%.2f .. %.2f]  x[%.1f .. %.1f]  z[%.1f .. %.1f]" % [
			str(mi.name), mi.mesh.get_surface_count(), _tris(mi), lo.y, hi.y, lo.x, hi.x, lo.z, hi.z])
	elif n is StaticBody3D:
		var cs := n.get_child(0) as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var box := cs.shape as BoxShape3D
			out.append("%-22s COLLISION size=(%.1f,%.1f,%.1f) at=(%.1f,%.1f,%.1f)" % [
				str(n.name), box.size.x, box.size.y, box.size.z,
				(n as Node3D).global_position.x, (n as Node3D).global_position.y, (n as Node3D).global_position.z])
	for c in n.get_children():
		_walk(c, depth + 1)

func _tris(mi: MeshInstance3D) -> int:
	var t := 0
	for s in range(mi.mesh.get_surface_count()):
		var arr := mi.mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return t
