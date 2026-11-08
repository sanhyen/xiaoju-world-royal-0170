extends Node
## 地形侦察：找出所有大体量网格（地形/山体/远景），记录节点名、AABB、材质类型与 shader uniform。
## 目的：判断能否用 material_override 套一层"坡度混合"着色，而不改动原网格。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var w: Node = layer.world
	var list: Array = []
	_collect(w, list)
	# 按 AABB 体积降序
	list.sort_custom(func(a, b): return a.vol > b.vol)
	out.append("TOTAL_MESH=%d" % list.size())
	out.append("")
	out.append("=== TOP 40 BY VOLUME ===")
	for i in range(min(40, list.size())):
		var d: Dictionary = list[i]
		out.append("%-46s vol=%10.0f aabb=(%.0f,%.0f,%.0f) surf=%d mat=%s" % [
			d.path, d.vol, d.size.x, d.size.y, d.size.z, d.surf, d.mat])
	out.append("")
	out.append("=== NAME KEYWORD MATCH ===")
	for i in range(list.size()):
		var d: Dictionary = list[i]
		var nm := str(d.name).to_lower()
		var hit := false
		for k in ["terrain", "strata", "partition", "ground", "land", "hill", "mountain", "cliff", "rock", "far", "island", "coast"]:
			if nm.contains(k):
				hit = true
				break
		if hit:
			out.append("%-46s vol=%10.0f mat=%s" % [d.path, d.vol, d.mat])
	out.append("")
	out.append("=== MATERIAL DEDUP ===")
	var seen := {}
	for i in range(list.size()):
		var d: Dictionary = list[i]
		var key := str(d.mat)
		if seen.has(key):
			seen[key] = int(seen[key]) + 1
		else:
			seen[key] = 1
	var ks := seen.keys()
	ks.sort()
	for k in ks:
		out.append("%-70s x%d" % [k, seen[k]])

	var f := FileAccess.open("user://terrain_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("TERRAIN_PROBE_DONE nodes=%d" % list.size())
	get_tree().quit()

func _collect(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			var aabb: AABB = mesh.get_aabb()
			var s := aabb.size * mi.global_transform.basis.get_scale()
			var d := {
				"name": str(mi.name),
				"path": _rel(mi),
				"vol": absf(s.x * s.y * s.z),
				"size": s,
				"surf": mesh.get_surface_count(),
				"mat": _mat_desc(mi),
			}
			acc.append(d)
	for c in n.get_children():
		_collect(c, acc)

func _mat_desc(mi: MeshInstance3D) -> String:
	var m := mi.get_active_material(0)
	if m == null:
		return "null"
	var cls := m.get_class()
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var p := "?"
		if sm.shader != null:
			p = sm.shader.resource_path
		return "ShaderMaterial(%s)" % p
	if m is StandardMaterial3D:
		var std := m as StandardMaterial3D
		return "Standard(albedo=%s rough=%.2f tex=%s)" % [str(std.albedo_color), std.roughness, str(std.albedo_texture != null)]
	return cls

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 6:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
