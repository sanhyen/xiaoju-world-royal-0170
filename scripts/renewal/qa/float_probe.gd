extends Node
## 定位两类异常：
##  1) 高空中的孤立几何（浮空锥体）
##  2) 主题建筑外壳（是否出现大块纯色体块）
## 只读。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(10.0).timeout
	var root: Node = get_tree().root

	out.append("=== MESHES WITH CENTER Y > 40 AND FOOTPRINT > 8m ===")
	var hi: Array = []
	_walk(root, hi)
	hi.sort_custom(func(a, b): return a.y > b.y)
	out.append("count=%d" % hi.size())
	for d in hi.slice(0, 40):
		out.append("  y=%6.1f  %-54s aabb=(%.0f,%.0f,%.0f) at=(%.0f,%.0f,%.0f) mat=%s" % [
			d.y, d.path, d.size.x, d.size.y, d.size.z, d.pos.x, d.pos.y, d.pos.z, d.mat])

	out.append("")
	out.append("=== THEME SHELL NODES (RenewalTheme / theme_*) ===")
	var th: Array = []
	_theme(root, th)
	out.append("count=%d" % th.size())
	for d in th.slice(0, 30):
		out.append("  %-52s aabb=(%.0f,%.0f,%.0f) at=(%.0f,%.0f,%.0f)" % [
			d.path, d.size.x, d.size.y, d.size.z, d.pos.x, d.pos.y, d.pos.z])

	var f := FileAccess.open("user://float_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("FLOAT_PROBE_DONE hi=%d theme=%d" % [hi.size(), th.size()])
	get_tree().quit()

func _walk(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var sz := mi.mesh.get_aabb().size
		var c := mi.global_position + mi.mesh.get_aabb().get_center()
		if c.y > 40.0 and max(sz.x, sz.z) > 8.0:
			var m := mi.get_active_material(0)
			var desc := "null"
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				desc = (m as ShaderMaterial).shader.resource_path.get_file()
			elif m is StandardMaterial3D:
				desc = "Std"
			acc.append({
				"path": _rel(mi), "y": c.y, "size": sz, "pos": c, "mat": desc,
			})
	for ch in n.get_children(true):
		_walk(ch, acc)

func _theme(n: Node, acc: Array) -> void:
	var nm := str(n.name)
	if nm.begins_with("ThemeShell") or nm.begins_with("RenewalTheme") or nm.contains("Theme"):
		if n is MeshInstance3D and n.mesh != null:
			var mi := n as MeshInstance3D
			acc.append({
				"path": _rel(mi), "size": mi.mesh.get_aabb().size,
				"pos": mi.global_position + mi.mesh.get_aabb().get_center(),
			})
	for ch in n.get_children(true):
		_theme(ch, acc)

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 4:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
