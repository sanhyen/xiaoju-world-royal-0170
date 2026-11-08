extends Node
## 第三版：卡点处逐 0.25 m 做向下射线 + 脚部形状查询，找出 -640 与 -640.5 的差别。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var w: Node = layer.world
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	p.global_position = Vector3(-545.0, 30.0, 300.0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	p.set("yaw", PI * 0.5)
	_key(true)
	var t0 := Time.get_ticks_msec()
	var last := p.global_position
	var stuck := 0
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().create_timer(0.12).timeout
		if p.global_position.distance_to(last) < 0.02:
			stuck += 1
		else:
			stuck = 0
		last = p.global_position
		if stuck > 20:
			break
	_key(false)
	await get_tree().create_timer(0.4).timeout
	var sp := p.global_position
	out.append("STUCK pos=(%.3f,%.3f,%.3f)" % [sp.x, sp.y, sp.z])

	var space := p.get_world_3d().direct_space_state
	out.append("")
	out.append("=== DOWN RAY + FOOT SHAPE, step 0.25 m ===")
	out.append("  x        foot_ray_hit            h_at     shape(y=foot+0.35)   allowed")
	for i in range(25):
		var x := -638.0 - float(i) * 0.25
		# 向下射线
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 30.0, 300.0), Vector3(x, -20.0, 300.0))
		rq.collision_mask = 0xFFFFFFFF
		var hit := space.intersect_ray(rq)
		var hs := "none"
		if not hit.is_empty():
			var col = hit.get("collider")
			hs = "%s@%.2f" % [str((col as Node).name) if col != null else "?", float((hit.get("position") as Vector3).y)]
		# 脚部形状
		var sq := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.32
		sq.shape = sh
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(x, sp.y + 0.35, 300.0))
		var hits: Array = space.intersect_shape(sq, 6)
		var nm: Array[String] = []
		for h in hits:
			var c2 = (h as Dictionary).get("collider")
			nm.append(str((c2 as Node).name) if c2 != null else "?")
		var ok = p.call("foot_destination_allowed", Vector3(x, sp.y, 300.0))
		out.append("  %-8.2f %-24s %-8.2f %-24s %s" % [
			x, hs, float(w.call("height_at", x, 300.0)), ",".join(nm), "T" if bool(ok) else "F"])

	out.append("")
	out.append("=== BRIDGE COLLIDER EXTENT ===")
	var found := 0
	_walk_bodies(p.get_parent(), p, out, found)

	var f := FileAccess.open("user://stuck3.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("STUCK3_DONE stuck_x=", sp.x)
	get_tree().quit()

func _walk_bodies(n: Node, p: Node, lines: Array[String], found: int) -> void:
	for c in n.get_children(true):
		if c is StaticBody3D or c is AnimatableBody3D:
			var b := c as Node3D
			var nm := str(c.name)
			if nm.contains("Bridge") or nm.contains("Terrace") or nm.contains("Summit") or nm.contains("TStair"):
				var txt := "  %s pos=(%.1f,%.1f,%.1f)" % [nm, b.global_position.x, b.global_position.y, b.global_position.z]
				for ch in b.get_children(true):
					if ch is CollisionShape3D:
						var cs := ch as CollisionShape3D
						txt += " shape=%s scale=%s" % [cs.shape.get_class(), str(cs.scale)]
						if cs.shape is BoxShape3D:
							var bx := cs.shape as BoxShape3D
							txt += " box=%.1fx%.1fx%.1f" % [bx.size.x, bx.size.y, bx.size.z]
						elif cs.shape is CylinderShape3D:
							var cy := cs.shape as CylinderShape3D
							txt += " cyl r=%.2f h=%.2f" % [cy.radius, cy.height]
						# 世界 AABB
						var xf := cs.global_transform
						var mn := Vector3(INF, INF, INF)
						var mx := Vector3(-INF, -INF, -INF)
						var ext := Vector3(0.5, 0.5, 0.5)
						if cs.shape is BoxShape3D:
							ext = (cs.shape as BoxShape3D).size * 0.5
						elif cs.shape is CylinderShape3D:
							var cy2 := cs.shape as CylinderShape3D
							ext = Vector3(cy2.radius, cy2.height * 0.5, cy2.radius)
						ext *= cs.scale
						for sx in [-1.0, 1.0]:
							for sy in [-1.0, 1.0]:
								for sz in [-1.0, 1.0]:
									var pt: Vector3 = xf * Vector3(ext.x * sx, ext.y * sy, ext.z * sz)
									mn = Vector3(minf(mn.x, pt.x), minf(mn.y, pt.y), minf(mn.z, pt.z))
									mx = Vector3(maxf(mx.x, pt.x), maxf(mx.y, pt.y), maxf(mx.z, pt.z))
						txt += " world_x[%.1f..%.1f] y[%.1f..%.1f] z[%.1f..%.1f]" % [mn.x, mx.x, mn.y, mx.y, mn.z, mx.z]
				lines.append(txt)
		_walk_bodies(c, p, lines, found)

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
