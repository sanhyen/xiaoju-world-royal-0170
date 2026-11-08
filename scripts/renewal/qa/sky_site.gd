extends Node
## 云岫仙山选址探针：采样拟建岛范围的地形高度，确认岛体不悬空、桥不埋地、
## 且该区域没有原版建筑/道路与岛体冲突。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(10.0).timeout
	var w: Node = layer.world

	# 1. 沿 z=300 从陆地到岛心的东西向剖面
	out.append("=== E-W PROFILE z=300 (mainland -> island) ===")
	var line: Array[String] = []
	var x := -300.0
	while x >= -860.0:
		var h := float(w.call("height_at", x, 300.0))
		line.append("%.0f:%.1f" % [x, h])
		x -= 20.0
	out.append("  " + " ".join(line))

	# 2. 沿 z 方向穿过岛心的南北剖面
	out.append("")
	out.append("=== N-S PROFILE x=-660 ===")
	var line2: Array[String] = []
	var z := 140.0
	while z <= 460.0:
		var h2 := float(w.call("height_at", -660.0, z))
		line2.append("%.0f:%.1f" % [z, h2])
		z += 20.0
	out.append("  " + " ".join(line2))

	# 3. 岛台地四角与边缘采样（局部坐标 ±140/±90）
	out.append("")
	out.append("=== PLATEAU FOOTPRINT SAMPLES (world) ===")
	var pts := [
		Vector2(-660.0, 300.0),
		Vector2(-660.0 - 150.0, 300.0 - 100.0),
		Vector2(-660.0 + 150.0, 300.0 - 100.0),
		Vector2(-660.0 - 150.0, 300.0 + 100.0),
		Vector2(-660.0 + 150.0, 300.0 + 100.0),
		Vector2(-660.0, 300.0 - 100.0),
		Vector2(-660.0, 300.0 + 100.0),
		Vector2(-660.0 - 150.0, 300.0),
		Vector2(-660.0 + 150.0, 300.0),
	]
	for p in pts:
		var h3 := float(w.call("height_at", p.x, p.y))
		out.append("  (%.0f,%.0f) h=%.2f" % [p.x, p.y, h3])

	# 4. 桥两端地形
	out.append("")
	out.append("=== BRIDGE ENDS ===")
	for bx in [-430.0, -450.0, -455.0, -470.0, -490.0, -510.0, -520.0]:
		var hb := float(w.call("height_at", bx, 300.0))
		out.append("  x=%.0f z=300 h=%.2f" % [bx, hb])

	# 5. 区域内已有网格（找占地 > 4m 的 MeshInstance3D）
	out.append("")
	out.append("=== EXISTING GEOMETRY IN REGION x[-860,-440] z[160,440] ===")
	var hits: Array = []
	_collect(get_tree().root, hits)
	out.append("count=%d" % hits.size())
	hits.sort_custom(func(a, b): return a.size > b.size)
	for d in hits.slice(0, 30):
		out.append("  %-52s aabb=(%.1f,%.1f,%.1f) at=(%.0f,%.0f,%.0f)" % [
			d.path, d.size.x, d.size.y, d.size.z, d.pos.x, d.pos.y, d.pos.z])

	# 6. 水面节点高度
	out.append("")
	out.append("=== WATER NODES ===")
	var wn: Array = []
	_collect_water(get_tree().root, wn)
	for d in wn:
		out.append("  %-46s y=%.2f aabb=(%.0f,%.0f)" % [d.path, d.pos.y, d.size.x, d.size.z])

	var f := FileAccess.open("user://sky_site.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("SKY_SITE_DONE")
	get_tree().quit()

func _collect(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var bb: AABB = mi.mesh.get_aabb()
		var gp := mi.global_position
		if gp.x > -880.0 and gp.x < -430.0 and gp.z > 150.0 and gp.z < 450.0 and bb.size.length() > 4.0:
			acc.append({"path": _rel(mi), "size": bb.size, "pos": gp})
	for c in n.get_children(true):
		_collect(c, acc)

func _collect_water(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var nm := str(mi.name)
		if nm.contains("Water") or nm.contains("Ocean") or nm.contains("River"):
			var bb: AABB = mi.mesh.get_aabb()
			acc.append({"path": _rel(mi), "pos": mi.global_position, "size": bb.size})
	for c in n.get_children(true):
		_collect_water(c, acc)

func _rel(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	var depth := 0
	while cur != null and depth < 4:
		parts.push_front(str(cur.name))
		cur = cur.get_parent()
		depth += 1
	return "/".join(parts)
