extends Node
## 构建器隔离实验：验证 world.b 的 box/beam/glass/collision 能否安全增量生成几何。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var w: Node = layer.world
	var b = w.get("b")
	out.append("b class=%s" % str(b.get_class()))
	out.append("root=%s" % str(b.get("root")))
	out.append("visual_only=%s box_count=%s collision_count=%s" % [str(b.get("visual_only")), str(b.get("box_count")), str(b.get("collision_count"))])
	var batches = b.get("batches")
	out.append("batches type=%s size=%s" % [str(typeof(batches)), str(batches.size() if batches != null else -1)])

	var n0 := _count(w)
	var c0 := int(b.get("box_count"))
	# 在一处远离建筑的空地做实验：海面南侧
	var p := Vector3(60.0, 6.0, 300.0)
	var r1 = b.call("box", p, Vector3(4, 3, 4), "D8CFC0", true, 0.0, "stone")
	var r2 = b.call("beam", p + Vector3(-3, 4, 0), p + Vector3(3, 4, 0), 0.4, "8B5A3C", false)
	var r3 = b.call("glass", p + Vector3(0, 3.2, 2.1), Vector3(3, 2, 0.1), 0.0)
	out.append("box ret=%s beam ret=%s glass ret=%s" % [str(r1), str(r2), str(r3)])
	out.append("box_count %d -> %d" % [c0, int(b.get("box_count"))])
	out.append("node count %d -> %d" % [n0, _count(w)])
	out.append("root now=%s" % str(b.get("root")))
	# 检查该位置附近是否有新节点
	var found: Array[String] = []
	_near(w, p, 6.0, found)
	out.append("near nodes: " + ", ".join(found.slice(0, 12)))
	var f := FileAccess.open("user://b_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("B_PROBE_DONE")
	get_tree().quit()

func _count(n: Node) -> int:
	var c := 1
	for x in n.get_children():
		c += _count(x)
	return c

func _near(n: Node, p: Vector3, r: float, acc: Array[String]) -> void:
	if n is MeshInstance3D or n is StaticBody3D:
		var gp: Vector3 = (n as Node3D).global_position
		if Vector2(gp.x - p.x, gp.z - p.z).length() < r:
			acc.append(str(n.name) + "[" + str(n.get_class()) + "]")
	for c in n.get_children():
		_near(c, p, r, acc)
