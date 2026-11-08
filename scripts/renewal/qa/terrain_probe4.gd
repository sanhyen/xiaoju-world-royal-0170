extends Node
## 全局定位：谁在用 terrain_strata.gdshader，几何到底挂在哪。
## 同时统计 MultiMeshInstance3D / GridMap / CSG 等可能承载地形的类型。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(9.0).timeout
	var root: Node = get_tree().root
	var classes := {}
	var strata_hits: Array = []
	var mm_hits: Array = []
	_walk(root, classes, strata_hits, mm_hits)

	out.append("=== CLASS COUNTS ===")
	var ks: Array = classes.keys()
	ks.sort()
	for k in ks:
		out.append("  %-30s %d" % [k, classes[k]])

	out.append("")
	out.append("=== terrain_strata MATERIAL USERS (%d) ===" % strata_hits.size())
	for d in strata_hits.slice(0, 24):
		out.append("  %-58s cls=%-20s mesh=%s surf=%d aabb=(%.1f,%.1f,%.1f) verts=%d" % [
			d.path, d.cls, str(d.has_mesh), d.surf, d.size.x, d.size.y, d.size.z, d.verts])

	out.append("")
	out.append("=== MULTIMESH (%d) ===" % mm_hits.size())
	for d in mm_hits.slice(0, 20):
		out.append("  %-58s count=%d aabb=(%.1f,%.1f,%.1f) mat=%s" % [
			d.path, d.count, d.size.x, d.size.y, d.size.z, d.mat])

	out.append("")
	out.append("=== BIG MESH (>=40m footprint, y>=3) ===")
	var big: Array = []
	_collect_big(root, big)
	big.sort_custom(func(a, b): return a.vol > b.vol)
	for d in big.slice(0, 24):
		out.append("  %-58s aabb=(%.0f,%.0f,%.0f) verts=%d mat=%s" % [
			d.path, d.size.x, d.size.y, d.size.z, d.verts, d.mat])

	var f := FileAccess.open("user://terrain_probe4.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("TERRAIN_PROBE4_DONE strata=%d mm=%d big=%d" % [strata_hits.size(), mm_hits.size(), big.size()])
	get_tree().quit()

func _walk(n: Node, classes: Dictionary, strata: Array, mm: Array) -> void:
	var c := n.get_class()
	classes[c] = int(classes.get(c, 0)) + 1
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.get_active_material(0)
		var is_strata := false
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			if (m as ShaderMaterial).shader.resource_path.contains("terrain_strata"):
				is_strata = true
		if is_strata:
			var d := {
				"path": _rel(mi), "cls": mi.get_class(),
				"has_mesh": mi.mesh != null,
				"surf": mi.mesh.get_surface_count() if mi.mesh != null else -1,
				"size": mi.mesh.get_aabb().size if mi.mesh != null else Vector3.ZERO,
				"verts": _verts(mi),
			}
			strata.append(d)
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var m2: Material = mmi.material_override
		if m2 == null and mmi.multimesh != null and mmi.multimesh.mesh != null and mmi.multimesh.mesh.get_surface_count() > 0:
			m2 = mmi.multimesh.mesh.surface_get_material(0)
		mm.append({
			"path": _rel(mmi),
			"count": mmi.multimesh.instance_count if mmi.multimesh != null else -1,
			"size": mmi.multimesh.mesh.get_aabb().size if (mmi.multimesh != null and mmi.multimesh.mesh != null) else Vector3.ZERO,
			"mat": m2.get_class() if m2 != null else "null",
		})
	for ch in n.get_children(true):
		_walk(ch, classes, strata, mm)

func _collect_big(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var s := mi.mesh.get_aabb().size
			if s.x >= 40.0 and s.z >= 40.0 and s.y >= 3.0:
				var m := mi.get_active_material(0)
				var desc := "null"
				if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
					desc = "Shader(" + (m as ShaderMaterial).shader.resource_path.get_file() + ")"
				elif m is StandardMaterial3D:
					desc = "Std(vcol=%s)" % str((m as StandardMaterial3D).vertex_color_use_as_albedo)
				acc.append({
					"path": _rel(mi), "vol": s.x * s.y * s.z, "size": s,
					"verts": _verts(mi), "mat": desc,
				})
	for ch in n.get_children(true):
		_collect_big(ch, acc)

func _verts(mi: MeshInstance3D) -> int:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	var arr := mi.mesh.surface_get_arrays(0)
	if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
		return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return 0

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 7:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
