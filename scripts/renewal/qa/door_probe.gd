extends Node
## 门口碰撞诊断：在花音商店街共用门口区域打网格射线 + 水平射线，
## 找出玩家到底被什么挡住、地面高程怎么变化。

var layer: Node
var out: Array[String] = []

const CX := -111.9
const CZ := 217.2

func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var space := (layer.player as Node3D).get_world_3d().direct_space_state

	out.append("=== 垂直射线网格（地面高程 / 命中体）===")
	out.append("        z=216.4   216.8   217.2   217.6   218.0")
	var zs := [216.4, 216.8, 217.2, 217.6, 218.0]
	for xi in range(14):
		var x := -115.4 + float(xi) * 0.5
		var row := "x=%7.2f" % x
		for z in zs:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 6.2, z), Vector3(x, 3.0, z))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				row += "   -----"
			else:
				row += "  %6.3f" % (hit["position"] as Vector3).y
		out.append(row)

	out.append("")
	out.append("=== 命中体名称（沿 x 扫，z=217.2）===")
	for xi in range(14):
		var x := -115.4 + float(xi) * 0.5
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 6.2, CZ), Vector3(x, 3.0, CZ))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			out.append("x=%7.2f  no hit" % x)
			continue
		var col: Object = hit["collider"]
		var nm := "?"
		if col is Node:
			nm = str((col as Node).name)
			var par := (col as Node).get_parent()
			if par != null:
				nm += " <- " + str(par.name)
		out.append("x=%7.2f  y=%.3f  %s" % [x, (hit["position"] as Vector3).y, nm])

	out.append("")
	out.append("=== 水平射线（从玩家卡住点朝 +x 推）===")
	for dy in [0.3, 0.6, 0.9, 1.2]:
		var from := Vector3(CX, 4.40 + dy, CZ)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(4.0, 0, 0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			out.append("dy=%.1f  clear" % dy)
		else:
			var col: Object = hit["collider"]
			var nm := "?"
			if col is Node:
				nm = str((col as Node).name) + " <- " + str((col as Node).get_parent().name if (col as Node).get_parent() != null else "")
			out.append("dy=%.1f  hit at x=%.2f  %s" % [dy, (hit["position"] as Vector3).x, nm])

	out.append("")
	out.append("=== SiteFixCollision 子节点 ===")
	var sc: Node = layer.find_child("SiteFixCollision", true, false)
	if sc == null:
		out.append("not found")
	else:
		for c in sc.get_children():
			if c is CollisionShape3D:
				var cs := c as CollisionShape3D
				var t := cs.transform
				out.append("  %s shape=%s origin=(%.2f,%.2f,%.2f)" % [
					str(c.name), cs.shape.get_class() if cs.shape != null else "null",
					t.origin.x, t.origin.y, t.origin.z])

	var f := FileAccess.open("user://door_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("DOOR_PROBE_DONE")
	get_tree().quit()
