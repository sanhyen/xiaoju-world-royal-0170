extends Node
## 先做物理射线，再核对渲染射线与网格三角形，避免只凭命名猜可见地形。

var layer: Node
var lines: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		trace("active_camera", cam.global_position, cam.global_position - cam.global_basis.z * 1200.0)
	trace("far_slope", Vector3(-350, 110, -420), Vector3(-350, 35, -260))
	trace("vertical_slope", Vector3(-350, 250, -300), Vector3(-350, -30, -300))
	# 枚举所有地形几何的可见状态与材质，不改动网格或材质。
	var families := {}
	var saved := false
	for n in layer.world.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not _terrain(mi):
			continue
		var family := str(mi.name).get_slice("_", 0)
		var material := mi.get_active_material(0)
		if material is StandardMaterial3D and not saved:
			ResourceSaver.save(material, "user://terrain_far_original.tres")
			var arr := mi.mesh.surface_get_arrays(0)
			lines.append("FAR_SAMPLE normals=%s colors=%s" % [str(arr[Mesh.ARRAY_NORMAL].slice(0, 6)), str(arr[Mesh.ARRAY_COLOR].slice(0, 6))])
			saved = true
		var description := material.get_class() if material != null else "null"
		if material is ShaderMaterial:
			description += " " + (material as ShaderMaterial).shader.resource_path
		var key := "%s visible=%s material=%s" % [family, mi.is_visible_in_tree(), description]
		families[key] = int(families.get(key, 0)) + 1
	lines.append("FAMILIES " + str(families))
	var f := FileAccess.open("user://terrain_visible.txt", FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
		print(line)
	f.close()
	get_tree().quit()

func trace(label: String, from: Vector3, to: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [layer.player.get_rid()]
	var hit: Dictionary = layer.player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		lines.append("RAY %s physics=none" % label)
	else:
		var collider: Node = hit.collider
		lines.append("RAY %s collider=%s pos=%s normal=%s" % [label, collider.get_path(), hit.position, hit.normal])
		for sibling in collider.get_parent().get_children(true):
			if sibling is MeshInstance3D:
				lines.append("  sibling %s visible=%s mesh=%s" % [sibling.get_path(), sibling.is_visible_in_tree(), sibling.mesh != null])
	var ids := RenderingServer.instances_cull_ray(from, to, layer.player.get_world_3d().scenario)
	var intersections: Array = []
	for id in ids:
		var obj := instance_from_id(id)
		if not obj is MeshInstance3D:
			continue
		var mi := obj as MeshInstance3D
		if mi.mesh == null or not _terrain(mi) or not mi.is_visible_in_tree():
			continue
		var local_from := mi.to_local(from)
		var local_to := mi.to_local(to)
		var best := INF
		for surface in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var total := indices.size() if not indices.is_empty() else verts.size()
			for i in range(0, total - 2, 3):
				var a := indices[i] if not indices.is_empty() else i
				var b := indices[i + 1] if not indices.is_empty() else i + 1
				var c := indices[i + 2] if not indices.is_empty() else i + 2
				var p = Geometry3D.segment_intersects_triangle(local_from, local_to, verts[a], verts[b], verts[c])
				if p != null:
					best = minf(best, from.distance_to(mi.to_global(p)))
		if is_finite(best):
			var m := mi.get_active_material(0)
			var desc := m.get_class() if m != null else "null"
			if m is StandardMaterial3D:
				desc += " vertex_color=" + str((m as StandardMaterial3D).vertex_color_use_as_albedo)
			elif m is ShaderMaterial:
				desc += " " + (m as ShaderMaterial).shader.resource_path
			intersections.append({"distance": best, "path": str(mi.get_path()), "material": desc})
	intersections.sort_custom(func(a, b): return a.distance < b.distance)
	lines.append("RENDER %s hits=%s" % [label, intersections])

func _terrain(mi: MeshInstance3D) -> bool:
	var name_lower := str(mi.name).to_lower()
	return name_lower.contains("strata") or name_lower.contains("terrain")
