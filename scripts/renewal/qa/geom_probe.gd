extends Node
## 诊断：B05 附近所有可见几何节点的类型/名称/AABB，以及 theme/hide 之后的节点状态。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	var p: CharacterBody3D = layer.player
	p.global_position = Vector3(188.0, 24.0, -205.0)
	await get_tree().create_timer(2.5).timeout
	var c := Vector3(188.0, 20.6, -225.0)
	var counts := {}
	var lines: Array[String] = []
	_walk(layer.world, c, counts, lines)
	out.append("=== TYPE COUNTS ===")
	for k in counts.keys():
		out.append("%s=%d" % [k, counts[k]])
	out.append("=== NODES (first 60) ===")
	out.append_array(lines.slice(0, 60))
	if layer.get("themes") != null:
		out.append("themes built=" + str((layer.get("themes") as Node).get("built")))
	if layer.get("hide_original") != null:
		out.append("hidden_total=" + str((layer.get("hide_original") as Node).get("hidden_total")))
	var f := FileAccess.open("user://geom_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("GEOM_PROBE_DONE")
	get_tree().quit()

func _walk(n: Node, c: Vector3, counts: Dictionary, lines: Array[String]) -> void:
	if n is GeometryInstance3D:
		var gp: Vector3 = (n as GeometryInstance3D).global_transform.origin
		if Vector2(gp.x - c.x, gp.z - c.z).length() < 26.0:
			var cls := str(n.get_class())
			counts[cls] = int(counts.get(cls, 0)) + 1
			var aabb: AABB = (n as GeometryInstance3D).get_aabb()
			var w := aabb.get_center()
			lines.append("%s | %s | vis=%s | pos=(%.1f,%.1f,%.1f) | aabb=(%.1f,%.1f,%.1f) sz=(%.1f,%.1f,%.1f)" % [
				cls, str(n.name), str((n as GeometryInstance3D).visible),
				gp.x, gp.y, gp.z, w.x, w.y, w.z, aabb.size.x, aabb.size.y, aabb.size.z])
	for ch in n.get_children():
		_walk(ch, c, counts, lines)
