extends Node
## 主题外壳 AABB 复核：逐栋列出实际包围盒，与配置 h / floor_y 对照。
## 输出 user://theme_aabb.txt

var layer: Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	var out: Array[String] = []
	var root: Node = null
	for n in layer.world.find_children("RenewalThemeBuildings", "Node3D", true, false):
		root = n
		break
	if root == null:
		out.append("RenewalThemeBuildings NOT FOUND")
		_flush(out)
		return
	# 配置
	var cfg := {}
	var f := FileAccess.open("res://data/renewal/buildings_0170.json", FileAccess.READ)
	if f != null:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(data) == TYPE_DICTIONARY:
			for b in data["buildings"]:
				cfg[str(b["id"])] = b
	out.append("id                     floor_y     h  |  aabb_w  aabb_h  aabb_d   base_y   top_y   verdict")
	var bad := 0
	var w_max := 45.0
	for c in root.get_children():
		var id := str(c.name).trim_prefix("Theme_")
		var b: Dictionary = cfg.get(id, {})
		var fy := float(b.get("floor_y", 0.0))
		var h := float(b.get("h", 0.0))
		# 闭包按值捕获局部变量，用数组做可变累加器
		var acc: Array = []
		_collect_aabb(c, acc)
		if acc.is_empty():
			continue
		var box: AABB = acc[0]
		for k in range(1, acc.size()):
			box = box.merge(acc[k])
		var top := box.position.y + box.size.y
		var over := top - (fy + h + 2.0)
		var verdict := "ok"
		if over > 4.0:
			verdict = "TOO_TALL +%.1f" % over
			bad += 1
		out.append("%-22s %6.1f %6.1f  | %6.1f %6.1f %6.1f  %6.1f  %6.1f   %s" % [
			id, fy, h, box.size.x, box.size.y, box.size.z, box.position.y, top, verdict])
		# 异常尺寸：列出越界的子网格，定位是哪一段几何跑飞了
		if box.size.x > w_max or box.size.z > w_max:
			for k in acc.size():
				var a2: AABB = acc[k]
				if a2.size.x > 60.0 or a2.size.z > 60.0:
					out.append("    OUTLIER mesh#%d aabb=(%.1f,%.1f,%.1f) at=(%.1f,%.1f,%.1f)" % [
						k, a2.size.x, a2.size.y, a2.size.z,
						a2.position.x, a2.position.y, a2.position.z])
	out.append("")
	out.append("total=%d too_tall=%d" % [root.get_child_count(), bad])
	_flush(out)

func _collect_aabb(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		acc.append(mi.global_transform * mi.mesh.get_aabb())
	for c in n.get_children(true):
		_collect_aabb(c, acc)

func _flush(out: Array[String]) -> void:
	var f := FileAccess.open("user://theme_aabb.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()
	print("THEME_AABB_DONE %d" % out.size())
	get_tree().quit()
