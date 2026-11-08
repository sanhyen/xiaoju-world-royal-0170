extends Node
## 定位桥面上第二处禁步：走到卡住点后，逐项放宽 shallow_policy，找出真正生效的字段；
## 同时用形状查询确认卡住点前方是否存在实体阻挡。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var w: Node = layer.world
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	# 先一路走到卡住
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
	await get_tree().create_timer(0.3).timeout
	var stuck_pos := p.global_position
	out.append("=== STUCK POINT ===")
	out.append("pos=(%.2f,%.2f,%.2f) local=(%.2f,%.2f,%.2f) floor=%s vel=(%.2f,%.2f,%.2f)" % [
		stuck_pos.x, stuck_pos.y, stuck_pos.z,
		stuck_pos.x + 770.0, stuck_pos.y, stuck_pos.z - 300.0,
		str(p.is_on_floor()), p.velocity.x, p.velocity.y, p.velocity.z])
	out.append("water_edge_blocked=%s" % str(p.get("water_edge_blocked")))
	out.append("")
	out.append("=== POLICY AT STUCK ===")
	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	out.append("  shallow_policy = " + JSON.stringify(bay.get("shallow_policy", {})))
	out.append("")
	out.append("=== SHAPE QUERY AROUND PLAYER ===")
	var space := p.get_world_3d().direct_space_state
	for probe in [
		["fwd+1.5", Vector3(1.5, 0.9, 0)],
		["fwd+3.0", Vector3(3.0, 0.9, 0)],
		["fwd+6.0", Vector3(6.0, 0.9, 0)],
		["fwd+10.0", Vector3(10.0, 0.9, 0)],
	]:
		var c: Vector3 = stuck_pos + (probe[1] as Vector3)
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.45
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, c)
		var hits: Array = space.intersect_shape(q, 8)
		var names: Array[String] = []
		for h in hits:
			var col = (h as Dictionary).get("collider")
			names.append(str((col as Node).name) if col != null else "?")
		out.append("  %-10s center=(%.1f,%.2f,%.1f) hits=%d %s" % [
			str(probe[0]), c.x, c.y, c.z, hits.size(), ", ".join(names)])
	out.append("")
	out.append("=== GROUND / HEIGHT ===")
	out.append("  height_at=%.2f raw=%.2f land=%.2f" % [
		float(w.call("height_at", stuck_pos.x, stuck_pos.z)),
		float(w.call("raw_height", stuck_pos.x, stuck_pos.z)),
		float(w.call("land_height", stuck_pos.x, stuck_pos.z))])
	for dx in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		out.append("  h(x%+.0f)=%.2f" % [dx, float(w.call("height_at", stuck_pos.x + dx, stuck_pos.z))])
	out.append("")

	# 逐项放宽，每次从卡住点起测
	out.append("=== RELAX TRIALS (each 1.3s forward) ===")
	var trials := [
		["baseline", func(): pass],
		["band=9999", func(): pol_set(w, "mainland_wade_band_m", 9999.0)],
		["depth=99", func(): pol_set(w, "max_wade_depth_m", 99.0)],
		["both", func(): pol_set(w, "mainland_wade_band_m", 9999.0); pol_set(w, "max_wade_depth_m", 99.0)],
		["radius=99", func(): pol_set(w, "island_outer_radius", 99.0); pol_set(w, "island_wade_radius", 99.0)],
		["erase_policy", func(): erase_policy(w)],
	]
	for t in trials:
		var nm: String = t[0]
		var fn: Callable = t[1]
		fn.call()
		await get_tree().create_timer(0.15).timeout
		p.global_position = stuck_pos + Vector3(0, 0.2, 0)
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(0.5).timeout
		var x0 := p.global_position.x
		p.set("yaw", PI * 0.5)
		_key(true)
		await get_tree().create_timer(1.3).timeout
		_key(false)
		out.append("  %-14s moved=%.2f m  pos=(%.1f,%.2f,%.1f) blocked=%s policy=%s" % [
			nm, absf(p.global_position.x - x0), p.global_position.x, p.global_position.y,
			p.global_position.z, str(p.get("water_edge_blocked")),
			JSON.stringify((w.get("spec") as Dictionary).get("bay_layout", {}).get("shallow_policy", {}))])
		await get_tree().create_timer(0.2).timeout
		# 复位策略
		reset_policy(w)

	var f := FileAccess.open("user://stuck_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("STUCK_PROBE_DONE stuck_x=", stuck_pos.x)
	get_tree().quit()

func pol_set(w: Node, key: String, val: float) -> void:
	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	var pol: Dictionary = bay.get("shallow_policy", {})
	pol[key] = val
	bay["shallow_policy"] = pol
	spec["bay_layout"] = bay
	w.set("spec", spec)

func erase_policy(w: Node) -> void:
	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	bay.erase("shallow_policy")
	spec["bay_layout"] = bay
	w.set("spec", spec)

func reset_policy(w: Node) -> void:
	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	bay["shallow_policy"] = {
		"deep_water_recovery": false, "edge_mode": "stop_in_place",
		"island_outer_radius": 1.55, "island_wade_radius": 1.45,
		"mainland_wade_band_m": 28.0, "max_wade_depth_m": 1.35,
	}
	spec["bay_layout"] = bay
	w.set("spec", spec)

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
