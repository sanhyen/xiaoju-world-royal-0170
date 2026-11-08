extends Node
## 水面节点探测：网格尺寸、surface 数、材质类型、是否透明。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var lines: Array[String] = []
	for name in ["BackgroundOcean", "BayConnectedRivers", "CoastalWaterContinuity130", "Landscape150RiverFoam"]:
		var n = layer.world.find_child(name, true, false)
		if n == null:
			lines.append(name + " : NOT FOUND")
			continue
		lines.append(name + " : " + str(n.get_class()) + " visible=" + str((n as Node3D).visible))
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var m := mi.mesh
			if m == null:
				lines.append("   mesh=null")
				continue
			lines.append("   surfaces=%d aabb=%s" % [m.get_surface_count(), str(mi.get_aabb().size)])
			for i in range(m.get_surface_count()):
				var mat := mi.get_active_material(i)
				var desc := "null"
				if mat != null:
					desc = str(mat.get_class())
					if mat is ShaderMaterial:
						desc += " shader=" + str((mat as ShaderMaterial).shader.resource_path)
					elif mat is StandardMaterial3D:
						var sm := mat as StandardMaterial3D
						desc += " albedo=%s alpha=%.2f transp=%s" % [str(sm.albedo_color), sm.albedo_color.a, str(sm.transparency)]
				lines.append("   surface[%d] mat=%s" % [i, desc])
	# 统计所有含 water 的节点
	var all: Array[String] = []
	_scan(layer.world, all)
	lines.append("--- all water-ish nodes ---")
	lines.append(", ".join(all.slice(0, 30)))
	var f := FileAccess.open("user://water_probe.txt", FileAccess.WRITE)
	for l in lines: f.store_line(l)
	f.close()
	print("WATER_PROBE_DONE")
	get_tree().quit()

func _scan(n: Node, acc: Array[String]) -> void:
	if n is MeshInstance3D:
		var nm := str(n.name).to_lower()
		if nm.contains("water") or nm.contains("river") or nm.contains("ocean") or nm.contains("sea") or nm.contains("foam"):
			acc.append(str(n.name))
	for c in n.get_children():
		_scan(c, acc)
