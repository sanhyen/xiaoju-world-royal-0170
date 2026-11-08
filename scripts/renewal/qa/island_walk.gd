extends Node
## 云岫仙山通行验收：从主岛岸边一路向西，走过跨海长桥、五级天梯、山巅大阶梯，
## 记录高度曲线，确认没有断桥、没有卡步、没有掉水。

var layer: Node
var out: Array[String] = []
var samples: Array = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout
	var w: Node = layer.world

	# 起点：主岛岸边（长桥东端）
	var sx := -445.0 if layer.sky_island.has_method("on_connection") else -545.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--startx="):
			sx = float(a.substr(9))
	var sh := float(w.call("height_at", sx, 300.0))
	p.global_position = Vector3(sx, 30.0, 300.0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(2.2).timeout
	out.append("start pos=(%.2f,%.2f,%.2f) ground_h=%.2f" % [p.global_position.x, p.global_position.y, p.global_position.z, sh])

	var target := Vector3(-800.0, 44.0, 300.0)
	var t0 := Time.get_ticks_msec()
	var max_y := p.global_position.y
	var last := p.global_position
	var stuck := 0
	var i := 0
	while Time.get_ticks_msec() - t0 < 75000:
		var dir := target - p.global_position
		if Vector2(dir.x, dir.z).length() > 0.3:
			p.set("yaw", atan2(-dir.x, -dir.z))
		_key(true)
		await get_tree().create_timer(0.12).timeout
		i += 1
		max_y = maxf(max_y, p.global_position.y)
		if p.global_position.distance_to(last) < 0.02:
			stuck += 1
		else:
			stuck = 0
		last = p.global_position
		if i % 6 == 0:
			var fwd := Vector3(-sin(float(p.get("yaw"))), 0, -cos(float(p.get("yaw"))))
			var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 1.0, 0),
				p.global_position + Vector3(0, 1.0, 0) + fwd * 2.5)
			var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
			var hd := "none"
			if not hit.is_empty():
				hd = "%s@%.2f" % [str((hit.get("collider") as Node).name) if hit.get("collider") != null else "?", float(hit.get("position").y)]
			samples.append("t=%.1fs x=%.1f y=%.2f z=%.1f v=(%.2f,%.2f,%.2f) floor=%s hit=%s" % [
				(Time.get_ticks_msec() - t0) / 1000.0, p.global_position.x,
				p.global_position.y, p.global_position.z,
				p.velocity.x, p.velocity.y, p.velocity.z, str(p.is_on_floor()), hd])
			var cols: Array[String] = []
			for ci in range(p.get_slide_collision_count()):
				var c := p.get_slide_collision(ci)
				var col := c.get_collider()
				cols.append("%s n=(%.2f,%.2f,%.2f)" % [
					str((col as Node).name) if col != null else "?",
					c.get_normal().x, c.get_normal().y, c.get_normal().z])
			samples.append("        slide_cols=%d %s" % [p.get_slide_collision_count(), ", ".join(cols)])
			var fwd2 := Vector3(-sin(float(p.get("yaw"))), 0, -cos(float(p.get("yaw"))))
			var nx := p.global_position + fwd2 * 0.8
			samples.append("        blocked=%s allowed_here=%s allowed_ahead=%s" % [
				str(p.get("water_edge_blocked")),
				str(p.call("foot_destination_allowed", p.global_position)),
				str(p.call("foot_destination_allowed", Vector3(nx.x, p.global_position.y, nx.z)))])
		if stuck > 25:
			out.append("STUCK at x=%.1f y=%.2f z=%.1f" % [p.global_position.x, p.global_position.y, p.global_position.z])
			out.append("  floor_normal=" + str(p.get_floor_normal()) + " on_floor=" + str(p.is_on_floor()))
			var sp2 := p.global_position
			var spc := p.get_world_3d().direct_space_state
			for dy in [0.05, 0.5, 1.0, 1.6]:
				var sq := PhysicsShapeQueryParameters3D.new()
				var shp := SphereShape3D.new()
				shp.radius = 0.32
				sq.shape = shp
				sq.transform = Transform3D(Basis.IDENTITY, sp2 + Vector3(0, dy, 0))
				var hh: Array = spc.intersect_shape(sq, 8)
				var nn: Array[String] = []
				for h in hh:
					var cc = (h as Dictionary).get("collider")
					nn.append(str((cc as Node).name) if cc != null else "?")
				out.append("  shape y+%.2f hits=%d %s" % [dy, hh.size(), ",".join(nn)])
			var dq := PhysicsRayQueryParameters3D.create(sp2 + Vector3(0, 2.0, 0), sp2 - Vector3(0, 1.0, 0))
			var dh := spc.intersect_ray(dq)
			out.append("  ground_below=" + ("none" if dh.is_empty() else "%s@%.2f" % [str((dh.get("collider") as Node).name), float((dh.get("position") as Vector3).y)]))
			break
		if p.global_position.x < -790.0 and p.global_position.y > 42.0:
			out.append("SUMMIT_REACHED t=%.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
			break
	_key(false)

	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	out.append("end pos=(%.2f,%.2f,%.2f) elapsed=%.1fs max_y=%.2f" % [
		p.global_position.x, p.global_position.y, p.global_position.z, elapsed, max_y])
	out.append("--- samples ---")
	for s in samples:
		out.append("  " + s)

	# 判定
	var reached := max_y > 42.0
	if layer.sky_island.has_method("contains_land"):
		# New preview must finish the full bridge/stair/gate route, not merely touch height.
		reached = reached and p.global_position.x < -790.0 and p.global_position.y > 47.0 and stuck <= 25
	out.append("VERDICT bridge_and_stairs=%s" % ("PASS" if reached else "FAIL"))

	var f := FileAccess.open("user://island_walk.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("ISLAND_WALK_DONE reached=", reached)
	load("res://scripts/renewal/qa/completion.gd").finish(self)

func _key(down: bool) -> void:
	if OS.get_cmdline_user_args().has("--test-sprint"):
		var shift:=InputEventKey.new()
		shift.keycode=KEY_SHIFT;shift.physical_keycode=KEY_SHIFT;shift.pressed=down
		Input.parse_input_event(shift)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
