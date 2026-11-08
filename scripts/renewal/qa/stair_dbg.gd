extends Node
## 天梯卡点精确定位：卡住后列出玩家胶囊周围所有碰撞体，并做抬升/侧移对照。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	p.global_position = Vector3(-664.0, 17.0, 300.0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(1.2).timeout
	out.append("start pos=(%.2f,%.2f,%.2f) floor=%s" % [p.global_position.x, p.global_position.y, p.global_position.z, str(p.is_on_floor())])
	p.set("yaw", PI * 0.5)
	_key(true)
	await get_tree().create_timer(3.0).timeout
	_key(false)
	await get_tree().create_timer(0.3).timeout
	var sp := p.global_position
	out.append("stuck pos=(%.2f,%.2f,%.2f) local_x=%.2f floor=%s" % [sp.x, sp.y, sp.z, sp.x + 770.0, str(p.is_on_floor())])
	out.append("  floor_normal=" + str(p.get_floor_normal()))

	var space := p.get_world_3d().direct_space_state
	out.append("")
	out.append("=== SHAPES AT PLAYER (capsule r=0.35 h=1.8) ===")
	for dy in [0.05, 0.45, 0.9, 1.4, 1.75]:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.34
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, sp + Vector3(0, dy, 0))
		var hits: Array = space.intersect_shape(q, 8)
		var nm: Array[String] = []
		for h in hits:
			var c = (h as Dictionary).get("collider")
			nm.append(str((c as Node).name) if c != null else "?")
		out.append("  y+%.2f hits=%d %s" % [dy, hits.size(), ",".join(nm)])

	out.append("")
	out.append("=== PROBE AHEAD (capsule center, step 0.5) ===")
	for i in range(12):
		var x := sp.x - float(i) * 0.5
		var q2 := PhysicsShapeQueryParameters3D.new()
		var sh2 := SphereShape3D.new()
		sh2.radius = 0.34
		q2.shape = sh2
		q2.transform = Transform3D(Basis.IDENTITY, Vector3(x, sp.y + 0.45, sp.z))
		var h2: Array = space.intersect_shape(q2, 8)
		var nm2: Array[String] = []
		for h in h2:
			var c = (h as Dictionary).get("collider")
			nm2.append(str((c as Node).name) if c != null else "?")
		out.append("  x=%.1f hits=%d %s" % [x, h2.size(), ",".join(nm2)])

	out.append("")
	out.append("=== METHOD SIGNATURE ===")
	for m in p.get_method_list():
		if str(m.get("name")) == "foot_destination_allowed":
			out.append("  " + JSON.stringify(m))

	var w: Node = layer.world
	out.append("")
	out.append("=== allowed() SCAN along z=300 at y=23.8 ===")
	var ln := ""
	for i in range(60):
		var x := -650.0 - float(i) * 1.0
		var ok = p.call("foot_destination_allowed", Vector3(x, 23.8, 300.0))
		ln += "%.0f:%s " % [x, "T" if bool(ok) else "F"]
		if i % 10 == 9:
			out.append("  " + ln)
			ln = ""
	if ln != "":
		out.append("  " + ln)

	out.append("")
	out.append("=== BOUNDS / POLICY NOW ===")
	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	out.append("  bay.bounds=" + JSON.stringify(bay.get("bounds")))
	out.append("  planning_bounds=" + JSON.stringify(spec.get("planning_bounds")))
	out.append("  shallow=" + JSON.stringify(bay.get("shallow_policy")))

	# 试改 planning_bounds
	var pb: Array = (spec.get("planning_bounds") as Array).duplicate()
	pb[0] = -960.0
	spec["planning_bounds"] = pb
	w.set("spec", spec)
	await get_tree().process_frame
	var ln2 := ""
	for i in range(30):
		var x2 := -650.0 - float(i) * 1.0
		var ok2 = p.call("foot_destination_allowed", Vector3(x2, 23.8, 300.0))
		ln2 += "%.0f:%s " % [x2, "T" if bool(ok2) else "F"]
	out.append("  after planning_bounds[0]=-960: " + ln2)

	out.append("")
	out.append("=== FLOOR FLAG TRIALS (2s forward from -664) ===")
	var flags := [
		["base", {}],
		["stop_on_slope=off", {"floor_stop_on_slope": false}],
		["const_speed=on", {"floor_constant_speed": true}],
		["both", {"floor_stop_on_slope": false, "floor_constant_speed": true}],
		["max_angle=60", {"floor_max_angle": deg_to_rad(60.0)}],
		["snap=2.0", {"floor_snap_length": 2.0}],
	]
	for fl in flags:
		var tag: String = fl[0]
		var patch: Dictionary = fl[1]
		for k in patch.keys():
			p.set(str(k), patch[k])
		p.global_position = Vector3(-664.0, 17.0, 300.0)
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(1.0).timeout
		var xf := p.global_position.x
		p.set("yaw", PI * 0.5)
		_key(true)
		await get_tree().create_timer(2.4).timeout
		_key(false)
		await get_tree().create_timer(0.2).timeout
		out.append("  %-18s dx=%.2f end=(%.1f,%.2f)" % [tag, p.global_position.x - xf, p.global_position.x, p.global_position.y])
		# 复位
		p.set("floor_stop_on_slope", true)
		p.set("floor_constant_speed", false)
		p.set("floor_max_angle", deg_to_rad(48.0))
		p.set("floor_snap_length", 0.6)

	out.append("")
	out.append("=== COUNTERFACTUALS (2s forward each) ===")
	var cases := [
		["raise_0.6", Vector3(sp.x, sp.y + 0.6, sp.z)],
		["side_z+3", Vector3(sp.x, sp.y, sp.z + 3.0)],
		["side_z-3", Vector3(sp.x, sp.y, sp.z - 3.0)],
		["back_6", Vector3(sp.x + 6.0, sp.y + 4.0, sp.z)],
		["fwd_4", Vector3(sp.x - 4.0, sp.y + 4.0, sp.z)],
		["fwd_10", Vector3(sp.x - 10.0, sp.y + 6.0, sp.z)],
		["fwd_20", Vector3(sp.x - 20.0, sp.y + 8.0, sp.z)],
		["fwd_40", Vector3(sp.x - 40.0, sp.y + 10.0, sp.z)],
	]
	for c in cases:
		var tag: String = c[0]
		var pos: Vector3 = c[1]
		p.global_position = pos
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(0.7).timeout
		var x0 := p.global_position.x
		p.set("yaw", PI * 0.5)
		_key(true)
		await get_tree().create_timer(2.0).timeout
		_key(false)
		await get_tree().create_timer(0.2).timeout
		out.append("  %-10s dx=%.2f end=(%.1f,%.2f,%.1f)" % [
			tag, p.global_position.x - x0, p.global_position.x, p.global_position.y, p.global_position.z])

	var f := FileAccess.open("user://stair_dbg.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("STAIR_DBG_DONE")
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
