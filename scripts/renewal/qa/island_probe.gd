extends Node
## 补探：两个海岛的高度剖面、网格顶点精度、道路与地形的顶点属性。
## 目的：确认"能不能做顶点级改动"，还是只能走片元。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(10.0).timeout
	var w: Node = layer.world

	out.append("=== ISLAND A (main, center 225,450 radius 42x28) ===")
	_profile(w, Vector2(225.0, 450.0), 90.0, 6.0, true)
	out.append("")
	out.append("=== ISLAND B (forest, center -60,490 radius 60x39.2) ===")
	_profile(w, Vector2(-60.0, 490.0), 110.0, 6.0, false)
	out.append("")
	out.append("=== REEF ELLIPSE (232.5,452.5 r 77.5x47.5) cross-section ===")
	_reef(w)

	out.append("")
	out.append("=== MESH VERTEX DENSITY ===")
	var root: Node = get_tree().root
	_density(root, "BackgroundOcean")
	_density(root, "CoastalWaterContinuity130")
	_density(root, "BayConnectedRivers")

	out.append("")
	out.append("=== VERTEX ATTRIBUTES ===")
	_attrs(root, "BackgroundOcean", "water")
	_attrs(root, "CoastalWaterContinuity130", "water")
	_attrs(root, "Cell_0_1", "path?")
	_attrs(root, "TerrainPartition110", "terrain")

	out.append("")
	out.append("=== STRUCTURES NORTH OF z=430 ===")
	var north: Array = []
	_collect_north(root, north)
	out.append("count=%d" % north.size())
	for d in north.slice(0, 40):
		out.append("  %-56s aabb=(%.0f,%.0f,%.0f) at=(%.0f,%.0f,%.0f)" % [
			d.path, d.size.x, d.size.y, d.size.z, d.pos.x, d.pos.y, d.pos.z])

	var f := FileAccess.open("user://island_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("ISLAND_PROBE_DONE")
	get_tree().quit()

func _profile(w: Node, c: Vector2, half: float, step: float, is_main: bool) -> void:
	var y_sea := -2.4
	# X 向剖面（过中心，z 固定）
	var line_x: Array[String] = []
	var x := c.x - half
	while x <= c.x + half:
		var h := float(w.call("height_at", x, c.y))
		var mark := "~" if h < y_sea else ("#" if h > 8.0 else "+")
		line_x.append("%s%.0f:%.1f" % [mark, x, h])
		x += step
	out.append("  X-profile z=%.0f: %s" % [c.y, " ".join(line_x)])
	# Z 向剖面
	var line_z: Array[String] = []
	var z := c.y - half
	while z <= c.y + half:
		var h2 := float(w.call("height_at", c.x, z))
		var mark2 := "~" if h2 < y_sea else ("#" if h2 > 8.0 else "+")
		line_z.append("%s%.0f:%.1f" % [mark2, z, h2])
		z += step
	out.append("  Z-profile x=%.0f: %s" % [c.x, " ".join(line_z)])

func _reef(w: Node) -> void:
	var cx := 232.5
	var cz := 452.5
	var line: Array[String] = []
	var x := cx - 100.0
	while x <= cx + 100.0:
		var h := float(w.call("height_at", x, cz))
		line.append("%.0f:%.1f" % [x, h])
		x += 10.0
	out.append("  across x: %s" % " ".join(line))
	var line2: Array[String] = []
	var z := cz - 70.0
	while z <= cz + 70.0:
		var h2 := float(w.call("height_at", cx, z))
		line2.append("%.0f:%.1f" % [z, h2])
		z += 10.0
	out.append("  across z: %s" % " ".join(line2))

func _find(root: Node, nm: String) -> Node:
	return root.find_child(nm, true, false)

func _density(root: Node, nm: String) -> void:
	var n := _find(root, nm)
	if n == null or not (n is MeshInstance3D):
		out.append("  %s: NOT FOUND" % nm)
		return
	var mi := n as MeshInstance3D
	if mi.mesh == null:
		out.append("  %s: mesh=null" % nm)
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var min_d := 1e9
	var max_d := 0.0
	var sum := 0.0
	var cnt := 0
	for i in range(0, min(1200, idx.size() / 3)):
		var a := vs[idx[i * 3]]
		var b := vs[idx[i * 3 + 1]]
		var c2 := vs[idx[i * 3 + 2]]
		for d in [a.distance_to(b), b.distance_to(c2), c2.distance_to(a)]:
			if d > 0.001:
				min_d = min(min_d, d)
				max_d = max(max_d, d)
				sum += d
				cnt += 1
	var aabb := mi.mesh.get_aabb()
	out.append("  %-28s verts=%d tris=%d aabb=(%.0f,%.0f,%.0f) edge min=%.2f avg=%.2f max=%.2f" % [
		nm, vs.size(), idx.size() / 3, aabb.size.x, aabb.size.y, aabb.size.z,
		min_d, (sum / max(1, cnt)), max_d])

func _attrs(root: Node, nm: String, tag: String) -> void:
	var n := _find(root, nm)
	if n == null or not (n is MeshInstance3D):
		# 对 Cell 前缀做包含匹配
		var hits: Array = []
		_prefix(root, nm, hits)
		if hits.is_empty():
			out.append("  %s: NOT FOUND" % nm)
			return
		n = hits[0]
	var mi := n as MeshInstance3D
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		out.append("  %s: no mesh" % nm)
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var names: Array[String] = []
	if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
		names.append("VERTEX")
	if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null:
		names.append("NORMAL")
	if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null:
		names.append("COLOR")
	if arr.size() > Mesh.ARRAY_TEX_UV and arr[Mesh.ARRAY_TEX_UV] != null:
		names.append("UV")
	if arr.size() > Mesh.ARRAY_TANGENT and arr[Mesh.ARRAY_TANGENT] != null:
		names.append("TANGENT")
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
		names.append("INDEX")
	out.append("  %-24s [%s] surfaces=%d arrays=%s" % [str(mi.name), tag, mi.mesh.get_surface_count(), ",".join(names)])

func _prefix(n: Node, pre: String, acc: Array) -> void:
	if n is MeshInstance3D and str(n.name).begins_with(pre):
		acc.append(n)
	for c in n.get_children(true):
		_prefix(c, pre, acc)

func _collect_north(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var p := mi.global_position
		if p.z > 430.0 and mi.mesh.get_aabb().size.length() > 1.0:
			acc.append({
				"path": _rel(mi), "size": mi.mesh.get_aabb().size, "pos": p,
			})
	for c in n.get_children(true):
		_collect_north(c, acc)

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 4:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
