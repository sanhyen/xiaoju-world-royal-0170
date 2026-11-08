extends Node
## 地形顶点色侦察：确认 terrain_chunks 结构、mesh 顶点属性（COLOR/UV/NORMAL）、
## 材质是否用顶点色，以及 terrain_color_at 的取值分布。决定坡度混合的实现路径。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var w: Node = layer.world

	var tc = w.get("terrain_chunks")
	out.append("terrain_chunks type=%s" % _tname(tc))
	if tc is Dictionary:
		out.append("terrain_chunks size=%d" % tc.size())
		var ks: Array = tc.keys()
		var shown := 0
		for k in ks:
			if shown >= 4:
				break
			var v = tc[k]
			out.append("  key=%s valtype=%s" % [str(k), _tname(v)])
			if v is Node:
				out.append("    node=%s children=%d" % [str(v.name), v.get_child_count()])
				for c in v.get_children():
					out.append("      child=%s cls=%s" % [str(c.name), c.get_class()])
			shown += 1
	elif tc is Array:
		out.append("terrain_chunks array size=%d" % tc.size())
		for i in range(min(4, tc.size())):
			var v = tc[i]
			out.append("  [%d] type=%s val=%s" % [i, _tname(v), str(v).substr(0, 160)])

	out.append("")
	out.append("=== TERRAIN MESH CANDIDATES ===")
	var cands: Array = []
	_find_terrain(w, cands)
	out.append("count=%d" % cands.size())
	# 路径前缀分组，定位地形 chunk 挂在哪个容器下
	var groups := {}
	for d in cands:
		var p := str(d.path)
		var segs := p.split("/")
		var key := "/".join(segs.slice(0, min(4, segs.size())))
		groups[key] = int(groups.get(key, 0)) + 1
	var gk: Array = groups.keys()
	gk.sort()
	out.append("-- prefix groups --")
	for k in gk:
		out.append("  %-60s x%d" % [k, groups[k]])
	# 名字含 terrain/chunk 的全列
	out.append("-- named terrain/chunk --")
	var named := 0
	for d in cands:
		var nm := str(d.path).to_lower()
		if nm.contains("terrain") or nm.contains("chunk"):
			out.append("  %s verts=%d mat=%s" % [d.path, d.verts, d.mat])
			named += 1
			if named >= 30:
				break
	out.append("  named_total_shown=%d" % named)
	# 顶点数最多的 20 个
	cands.sort_custom(func(a, b): return a.verts > b.verts)
	out.append("-- top 20 by verts --")
	for i in range(min(20, cands.size())):
		var d: Dictionary = cands[i]
		out.append("  %-70s verts=%d mat=%s" % [d.path, d.verts, d.mat])
	out.append("-- detail of top 3 --")
	for i in range(min(3, cands.size())):
		var d: Dictionary = cands[i]
		out.append("--- %s" % d.path)
		out.append("    verts=%d surfaces=%d mat=%s" % [d.verts, d.surf, d.mat])
		out.append("    arrays=%s" % d.arrays)
		out.append("    normal_sample=%s" % d.normals)
		out.append("    color_sample=%s" % d.colors)

	out.append("")
	out.append("=== terrain_color_at SAMPLES ===")
	var pts := [
		Vector2(289, 248), Vector2(0, 0), Vector2(-420, 275), Vector2(120, -180),
		Vector2(-180, 60), Vector2(300, -300), Vector2(-300, -200), Vector2(60, 320),
	]
	for p in pts:
		var c = w.call("terrain_color_at", p.x, p.y)
		var h = w.call("height_at", p.x, p.y)
		out.append("(%.0f,%.0f) h=%.2f color=%s" % [p.x, p.y, float(h), str(c)])

	var f := FileAccess.open("user://terrain_probe2.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("TERRAIN_PROBE2_DONE cands=%d" % cands.size())
	get_tree().quit()

func _find_terrain(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := str(mi.name).to_lower()
		var is_terrain := false
		for k in ["terrain", "chunk", "strata", "island"]:
			if nm.contains(k):
				is_terrain = true
				break
		# 也收 AABB 底面很大且 y 跨度适中的
		if mi.mesh != null and not is_terrain:
			var aabb := mi.mesh.get_aabb()
			if aabb.size.x >= 30.0 and aabb.size.z >= 30.0 and aabb.size.y >= 2.0 and aabb.size.y <= 140.0:
				is_terrain = true
		if is_terrain and mi.mesh != null:
			acc.append(_describe(mi))
	for c in n.get_children():
		_find_terrain(c, acc)

func _describe(mi: MeshInstance3D) -> Dictionary:
	var mesh := mi.mesh
	var d := {
		"path": _rel(mi),
		"verts": 0,
		"surf": mesh.get_surface_count(),
		"mat": "null",
		"arrays": "?",
		"normals": "-",
		"colors": "-",
	}
	var m := mi.get_active_material(0)
	if m is StandardMaterial3D:
		var std := m as StandardMaterial3D
		d.mat = "Standard(vcol_albedo=%s albedo=%s tex=%s rough=%.2f spec=%.2f metal=%.2f)" % [
			str(std.vertex_color_use_as_albedo), str(std.albedo_color), str(std.albedo_texture != null),
			std.roughness, std.metallic_specular, std.metallic]
	elif m is ShaderMaterial:
		d.mat = "ShaderMaterial(%s)" % (str((m as ShaderMaterial).shader.resource_path) if (m as ShaderMaterial).shader != null else "?")
	elif m != null:
		d.mat = m.get_class()
	if mesh.get_surface_count() > 0:
		var arr := mesh.surface_get_arrays(0)
		var names: Array[String] = []
		for i in range(arr.size()):
			if arr[i] != null:
				names.append("%d:%s" % [i, _tname(arr[i])])
		d.arrays = ",".join(names)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		d.verts = verts.size()
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ns: Array[String] = []
			for i in range(min(5, nr.size())):
				ns.append("(%.2f,%.2f,%.2f)" % [nr[i].x, nr[i].y, nr[i].z])
			d.normals = " ".join(ns)
		if arr[Mesh.ARRAY_COLOR] != null:
			var cr: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var cs: Array[String] = []
			for i in range(min(5, cr.size())):
				cs.append("(%.3f,%.3f,%.3f)" % [cr[i].r, cr[i].g, cr[i].b])
			d.colors = " ".join(cs)
	return d

func _tname(v) -> String:
	if v == null:
		return "null"
	if v is Object:
		return (v as Object).get_class()
	if v is Array:
		return "Array(%d)" % (v as Array).size()
	if v is Dictionary:
		return "Dictionary(%d)" % (v as Dictionary).size()
	return type_string(typeof(v))

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 6:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
