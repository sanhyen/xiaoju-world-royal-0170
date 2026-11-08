extends Node
## 单个 cell 内容侦察：列出 Cell_0_0 下所有 MeshInstance3D 的名称、顶点数、AABB、材质，
## 确认近景地形主体是哪一个网格。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var w: Node = layer.world
	var targets := ["Cell_0_0", "Cell_1_1", "Cell_-1_0"]
	for t in targets:
		var n: Node = w.find_child(t, true, false)
		if n == null:
			out.append("=== %s NOT FOUND ===" % t)
			continue
		out.append("=== %s children=%d ===" % [t, n.get_child_count()])
		for c in n.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var aabb := mi.mesh.get_aabb() if mi.mesh != null else AABB()
				var verts := 0
				var has_color := false
				if mi.mesh != null and mi.mesh.get_surface_count() > 0:
					var arr := mi.mesh.surface_get_arrays(0)
					if arr[Mesh.ARRAY_VERTEX] != null:
						verts = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					has_color = arr[Mesh.ARRAY_COLOR] != null
				out.append("  %-28s cls=%-22s verts=%6d aabb=(%.1f,%.1f,%.1f) vcol=%s mat=%s" % [
					str(c.name), c.get_class(), verts, aabb.size.x, aabb.size.y, aabb.size.z,
					str(has_color), _mat_desc(mi)])
			else:
				out.append("  %-28s cls=%s" % [str(c.name), c.get_class()])
		out.append("")

	# 远景 FarStrata 顶点色分布（取一个样本，统计坡度与颜色的相关性）
	var far: Node = w.find_child("FarStrata_0_-3", true, false)
	if far is MeshInstance3D:
		var mi2 := far as MeshInstance3D
		var arr2 := mi2.mesh.surface_get_arrays(0)
		var nrm: PackedVector3Array = arr2[Mesh.ARRAY_NORMAL]
		var col: PackedColorArray = arr2[Mesh.ARRAY_COLOR]
		out.append("=== FarStrata_0_-3 slope vs color ===")
		out.append("verts=%d colors=%d" % [nrm.size(), col.size()])
		var buckets := {}
		for i in range(nrm.size()):
			var ny := absf(nrm[i].y)
			var b := int(ny * 10.0)
			if not buckets.has(b):
				buckets[b] = [0, Color(0, 0, 0, 1)]
			var rec: Array = buckets[b]
			rec[0] = int(rec[0]) + 1
			var cc: Color = rec[1]
			rec[1] = Color(cc.r + col[i].r, cc.g + col[i].g, cc.b + col[i].b, 1.0)
			buckets[b] = rec
		var bs: Array = buckets.keys()
		bs.sort()
		for b in bs:
			var rec: Array = buckets[b]
			var cnt := int(rec[0])
			var avg: Color = rec[1]
			out.append("  ny=%.1f-%.1f n=%5d avg=(%.3f,%.3f,%.3f)" % [
				float(b) / 10.0, float(b + 1) / 10.0, cnt, avg.r / cnt, avg.g / cnt, avg.b / cnt])

	var f := FileAccess.open("user://terrain_probe3.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("TERRAIN_PROBE3_DONE")
	get_tree().quit()

func _mat_desc(mi: MeshInstance3D) -> String:
	var m := mi.get_active_material(0)
	if m == null:
		return "null"
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		return "Std(vcol=%s tex=%s)" % [str(s.vertex_color_use_as_albedo), str(s.albedo_texture != null)]
	if m is ShaderMaterial:
		return "Shader(%s)" % (str((m as ShaderMaterial).shader.resource_path) if (m as ShaderMaterial).shader != null else "?")
	return m.get_class()
