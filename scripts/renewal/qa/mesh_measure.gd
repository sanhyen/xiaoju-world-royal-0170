extends Node
## 网格精度实测：决定"顶点级改动"是否可行。
## 非索引网格按每 3 顶点取三角形，量真实边长。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(10.0).timeout
	var root: Node = get_tree().root

	out.append("=== TRIANGLE EDGE LENGTH ===")
	_measure(root, "BackgroundOcean")
	_measure(root, "CoastalWaterContinuity130")
	_measure(root, "BayConnectedRivers")

	out.append("")
	out.append("=== PATH MESH ATTRS ===")
	_paths(root)

	out.append("")
	out.append("=== TERRAIN BLOCK ATTRS + EDGE ===")
	_terrain(root)

	var f := FileAccess.open("user://mesh_measure.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("MESH_MEASURE_DONE")
	get_tree().quit()

func _find(root: Node, nm: String) -> Node:
	return root.find_child(nm, true, false)

func _measure(root: Node, nm: String) -> void:
	var n := _find(root, nm)
	if n == null or not (n is MeshInstance3D):
		out.append("  %s: NOT FOUND" % nm)
		return
	var mi := n as MeshInstance3D
	if mi.mesh == null:
		out.append("  %s: null mesh" % nm)
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var has_idx: bool = arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if has_idx else PackedInt32Array()
	var tri: int = (vs.size() / 3) if not has_idx else (idx.size() / 3)
	var min_d := 1e9
	var max_d := 0.0
	var sum := 0.0
	var cnt := 0
	var sample: int = mini(tri, 800)
	for t in range(sample):
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if not has_idx:
			a = vs[t * 3]; b = vs[t * 3 + 1]; c = vs[t * 3 + 2]
		else:
			a = vs[idx[t * 3]]; b = vs[idx[t * 3 + 1]]; c = vs[idx[t * 3 + 2]]
		for d in [a.distance_to(b), b.distance_to(c), c.distance_to(a)]:
			if d > 0.0001:
				min_d = min(min_d, d)
				max_d = max(max_d, d)
				sum += d
				cnt += 1
	var aabb := mi.mesh.get_aabb()
	out.append("  %-26s verts=%d tris=%d idx=%s aabb=(%.0f,%.0f,%.0f)" % [
		nm, vs.size(), tri, str(has_idx), aabb.size.x, aabb.size.y, aabb.size.z])
	out.append("       edge  min=%.2f  avg=%.2f  max=%.2f  (sampled %d tris)" % [
		min_d, sum / maxf(1.0, float(cnt)), max_d, sample])

func _paths(root: Node) -> void:
	var hits: Array = []
	_collect_by_shader(root, "path_paving", hits)
	out.append("  path meshes=%d" % hits.size())
	for d in hits.slice(0, 3):
		var mi := d as MeshInstance3D
		var arr := mi.mesh.surface_get_arrays(0)
		var names: Array[String] = []
		var lbl := ["VERTEX", "NORMAL", "TANGENT", "COLOR", "UV", "UV2", "CUSTOM0", "CUSTOM1", "CUSTOM2", "CUSTOM3", "BONES", "WEIGHTS", "INDEX"]
		for i in range(min(lbl.size(), arr.size())):
			if arr[i] != null:
				names.append(lbl[i])
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var has_idx: bool = arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if has_idx else PackedInt32Array()
		var tri: int = (vs.size() / 3) if not has_idx else (idx.size() / 3)
		# 三角形边长
		var min_d := 1e9
		var sum := 0.0
		var cnt := 0
		var sample: int = mini(tri, 500)
		for t in range(sample):
			var a: Vector3
			var b: Vector3
			var c2: Vector3
			if not has_idx:
				a = vs[t * 3]; b = vs[t * 3 + 1]; c2 = vs[t * 3 + 2]
			else:
				a = vs[idx[t * 3]]; b = vs[idx[t * 3 + 1]]; c2 = vs[idx[t * 3 + 2]]
			for d2 in [a.distance_to(b), b.distance_to(c2), c2.distance_to(a)]:
				if d2 > 0.0001:
					min_d = min(min_d, d2)
					sum += d2
					cnt += 1
		out.append("    %-34s verts=%d tris=%d arrays=%s edge min=%.2f avg=%.2f" % [
			str(mi.name), vs.size(), tri, ",".join(names), min_d, sum / maxf(1.0, float(cnt))])
		# 顶点色样本
		if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null:
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			out.append("       COLOR sample: %s" % str(cols.slice(0, 3)))

func _terrain(root: Node) -> void:
	var hits: Array = []
	_prefix(root, "TerrainPartition110", hits)
	out.append("  blocks=%d" % hits.size())
	if hits.is_empty():
		return
	var mi := hits[0] as MeshInstance3D
	if mi.mesh == null:
		out.append("    first block mesh=null")
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var has_idx: bool = arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if has_idx else PackedInt32Array()
	var tri: int = (vs.size() / 3) if not has_idx else (idx.size() / 3)
	var aabb := mi.mesh.get_aabb()
	out.append("    %s verts=%d tris=%d aabb=(%.0f,%.0f,%.0f)" % [str(mi.name), vs.size(), tri, aabb.size.x, aabb.size.y, aabb.size.z])
	var min_d := 1e9
	var sum := 0.0
	var cnt := 0
	for t in range(min(tri, 600)):
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if not has_idx:
			a = vs[t * 3]; b = vs[t * 3 + 1]; c = vs[t * 3 + 2]
		else:
			a = vs[idx[t * 3]]; b = vs[idx[t * 3 + 1]]; c = vs[idx[t * 3 + 2]]
		for d in [a.distance_to(b), b.distance_to(c), c.distance_to(a)]:
			if d > 0.0001:
				min_d = min(min_d, d)
				sum += d
				cnt += 1
	out.append("    edge min=%.2f avg=%.2f" % [min_d, sum / maxf(1.0, float(cnt))])
	if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null:
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		out.append("    COLOR sample: %s" % str(cols.slice(0, 4)))

func _collect_by_shader(n: Node, key: String, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.get_active_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			if (m as ShaderMaterial).shader.resource_path.contains(key):
				acc.append(mi)
	for c in n.get_children(true):
		_collect_by_shader(c, key, acc)

func _prefix(n: Node, pre: String, acc: Array) -> void:
	if n is MeshInstance3D and str(n.name).begins_with(pre):
		acc.append(n)
	for c in n.get_children(true):
		_prefix(c, pre, acc)
