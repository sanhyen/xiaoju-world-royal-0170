extends Node
## 统计 world 下所有 MeshInstance3D 的材质 / shader 路径，按数量排序。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var counts := {}
	var samples := {}
	var total := 0
	_walk(layer.world, counts, samples)
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var lines: Array[String] = []
	for k in keys:
		total += counts[k]
		lines.append("%5d  %s" % [counts[k], str(k)])
		lines.append("        e.g. " + str(samples.get(k, "")))
	lines.append("TOTAL %d" % total)
	var f := FileAccess.open("user://mat_audit.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("MAT_AUDIT_DONE types=%d" % keys.size())
	get_tree().quit()

func _walk(n: Node, counts: Dictionary, samples: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var key := "none"
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_active_material(0)
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			key = "SHADER " + (sm.shader.resource_path if sm.shader != null else "null")
		elif mat is StandardMaterial3D:
			key = "STD albedo=" + str((mat as StandardMaterial3D).albedo_color)
		elif mat != null:
			key = "MAT " + mat.get_class()
		counts[key] = counts.get(key, 0) + 1
		if not samples.has(key):
			samples[key] = str(mi.get_path())
	for c in n.get_children(true):
		_walk(c, counts, samples)
