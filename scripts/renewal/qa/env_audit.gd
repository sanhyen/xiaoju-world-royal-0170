extends Node
## 环境审计：海水 / 道路 / 山体 三项的真实渲染结构与数值分布。
## 只读，不修改任何东西。

var layer: Node
var out: Array[String] = []

const WATER_SHADERS := ["coastal_water", "coral_water_bay"]
const PATH_SHADERS := ["path_paving_079"]

func _ready() -> void:
	await get_tree().create_timer(10.0).timeout
	var root: Node = get_tree().root

	var water: Array = []
	var paths: Array = []
	var terrain: Array = []
	_scan(root, water, paths, terrain)

	out.append("=== WATER NODES (%d) ===" % water.size())
	for d in water:
		out.append("  %-52s shader=%-22s aabb=(%.0f,%.0f,%.0f) tris=%d matid=%d" % [
			d.path, d.shader, d.size.x, d.size.y, d.size.z, d.tris, d.matid])
	out.append("")
	out.append("=== WATER UNIFORMS ===")
	for d in water:
		out.append("  --- %s" % d.path)
		for k in d.uniforms:
			out.append("      %s = %s" % [k, d.uniforms[k]])

	out.append("")
	out.append("=== PATH NODES (%d) ===" % paths.size())
	var total_tris := 0
	var mats := {}
	for d in paths:
		total_tris += int(d.tris)
		mats[d.matid] = int(mats.get(d.matid, 0)) + 1
	out.append("  total_tris=%d distinct_materials=%d" % [total_tris, mats.size()])
	for d in paths.slice(0, 40):
		out.append("  %-52s aabb=(%.0f,%.1f,%.0f) tris=%d axis=%s matid=%d" % [
			d.path, d.size.x, d.size.y, d.size.z, d.tris, d.axis, d.matid])

	out.append("")
	out.append("=== PATH MATERIAL SHARING ===")
	var mk: Array = mats.keys()
	for m in mk:
		out.append("  matid=%d used_by=%d nodes" % [m, mats[m]])

	# ---- 地形：高度与坡度分布 ----
	out.append("")
	out.append("=== TERRAIN HEIGHT / SLOPE FIELD ===")
	var w: Node = layer.world
	if w == null:
		out.append("  world=null")
	else:
		var xs := [-460.0, 460.0]
		var zs := [-440.0, 620.0]
		var step := 12.0
		var hist := {}
		var slope_hist := {}
		var samples := 0
		var x := float(xs[0])
		while x <= float(xs[1]):
			var z := float(zs[0])
			while z <= float(zs[1]):
				var h := float(w.call("height_at", x, z))
				if h > -2.3:
					samples += 1
					var bucket := int(floor(h / 10.0)) * 10
					hist[bucket] = int(hist.get(bucket, 0)) + 1
					var hx := float(w.call("height_at", x + step, z))
					var hz := float(w.call("height_at", x, z + step))
					var grad := sqrt(pow((hx - h) / step, 2.0) + pow((hz - h) / step, 2.0))
					var deg := rad_to_deg(atan(grad))
					var sb := int(floor(deg / 5.0)) * 5
					slope_hist[sb] = int(slope_hist.get(sb, 0)) + 1
				z += step
			x += step
		out.append("  land_samples=%d (step=%.0fm)" % [samples, step])
		out.append("  -- height histogram (10m buckets) --")
		var hk: Array = hist.keys()
		hk.sort()
		for b in hk:
			out.append("    %+4d ~ %+4d m : %5d  %s" % [b, b + 10, hist[b], _bar(int(hist[b]), samples, 40)])
		out.append("  -- slope histogram (5deg buckets) --")
		var sk: Array = slope_hist.keys()
		sk.sort()
		var slope_sum := 0
		for b in sk:
			slope_sum += int(slope_hist[b])
		for b in sk:
			out.append("    %2d ~ %2d deg : %5d  %s" % [b, b + 5, slope_hist[b], _bar(int(slope_hist[b]), slope_sum, 40)])

	# ---- 海岛可见性 ----
	out.append("")
	out.append("=== ISLAND NODES ===")
	var isl: Array = []
	_find_name(root, ["Island", "island", "Reef", "reef", "Forest", "forest", "萤火", "森屿"], isl)
	out.append("  matches=%d" % isl.size())
	for d in isl.slice(0, 30):
		out.append("  %-56s cls=%-20s vis=%s" % [d.path, d.cls, d.vis])

	# ---- 场景类统计 ----
	out.append("")
	out.append("=== SCENE SCALE ===")
	out.append("  water_nodes=%d path_nodes=%d terrain_blocks=%d" % [water.size(), paths.size(), terrain.size()])

	var f := FileAccess.open("user://env_audit.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("ENV_AUDIT_DONE water=%d paths=%d terrain=%d" % [water.size(), paths.size(), terrain.size()])
	get_tree().quit()

func _bar(v: int, total: int, width: int) -> String:
	if total <= 0:
		return ""
	var n := int(round(float(v) / float(total) * float(width)))
	var s := ""
	for i in range(n):
		s += "#"
	return s

func _scan(n: Node, water: Array, paths: Array, terrain: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if str(n.name).begins_with("TerrainPartition110"):
			terrain.append(n)
		var m: Material = mi.get_active_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			var sp := (m as ShaderMaterial).shader.resource_path.get_file()
			var tris := _tris(mi)
			if _matches(sp, WATER_SHADERS):
				water.append({
					"path": _rel(mi), "shader": sp, "tris": tris,
					"size": mi.mesh.get_aabb().size if mi.mesh != null else Vector3.ZERO,
					"matid": m.get_instance_id(), "uniforms": _uniforms(m as ShaderMaterial),
				})
			elif _matches(sp, PATH_SHADERS):
				var axis := "?"
				var av = (m as ShaderMaterial).get_shader_parameter("path_axis")
				if av != null:
					axis = "(%.2f,%.2f)" % [av.x, av.y]
				paths.append({
					"path": _rel(mi), "tris": tris, "axis": axis,
					"size": mi.mesh.get_aabb().size if mi.mesh != null else Vector3.ZERO,
					"matid": m.get_instance_id(),
				})
	for c in n.get_children(true):
		_scan(c, water, paths, terrain)

func _matches(sp: String, keys: Array) -> bool:
	for k in keys:
		if sp.contains(k):
			return true
	return false

func _uniforms(sm: ShaderMaterial) -> Dictionary:
	var d := {}
	if sm.shader == null:
		return d
	for u in sm.shader.get_shader_uniform_list():
		var key := str(u.name)
		var v = sm.get_shader_parameter(key)
		if v == null:
			continue
		if v is Color:
			d[key] = "(%.3f,%.3f,%.3f)" % [v.r, v.g, v.b]
		elif v is Vector2:
			d[key] = "(%.2f,%.2f)" % [v.x, v.y]
		elif v is float:
			d[key] = "%.3f" % v
		else:
			d[key] = str(v).substr(0, 40)
	return d

func _tris(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var t := 0
	for i in range(mi.mesh.get_surface_count()):
		var arr := mi.mesh.surface_get_arrays(i)
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

func _find_name(n: Node, keys: Array, acc: Array) -> void:
	var nm := str(n.name)
	for k in keys:
		if nm.contains(k):
			acc.append({"path": _rel(n), "cls": n.get_class(), "vis": str(n.visible if n is Node3D else "-")})
			break
	for c in n.get_children(true):
		_find_name(c, keys, acc)

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 5:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
