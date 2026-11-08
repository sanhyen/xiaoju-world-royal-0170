extends Node
## 验证 bay_layout.bounds 是否是西侧禁步边界，并测试改写后的通行变化。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var w: Node = layer.world
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	out.append("bay_layout.bounds = " + JSON.stringify(bay.get("bounds")))
	out.append("spec.planning_bounds = " + JSON.stringify(spec.get("planning_bounds")))
	out.append("bay_layout.shore = " + JSON.stringify(bay.get("shore")))
	out.append("")

	out.append("=== WORLD members mentioning bounds ===")
	for pr in w.get_property_list():
		var nm := str(pr.get("name"))
		if nm.to_lower().contains("bound"):
			out.append("  prop %s = %s" % [nm, str(w.get(nm)).substr(0, 120)])
	for m in w.get_method_list():
		var mn := str(m.get("name"))
		if mn.to_lower().contains("bound") or mn.to_lower().contains("allow") or mn.to_lower().contains("walk"):
			out.append("  method " + mn)
	out.append("")

	var probes := [-600.0, -640.0, -641.0, -660.0, -700.0, -770.0, -850.0]
	out.append("=== foot_destination_allowed before/after widening bounds[0] ===")
	var before: Array[String] = []
	for x in probes:
		before.append("%.0f=%s" % [x, "T" if bool(p.call("foot_destination_allowed", Vector3(x, 3.86, 300.0))) else "F"])
	out.append("  before: " + " ".join(before))

	var b: Array = (bay.get("bounds") as Array).duplicate()
	b[0] = -920.0
	bay["bounds"] = b
	spec["bay_layout"] = bay
	w.set("spec", spec)
	await get_tree().process_frame
	var after: Array[String] = []
	for x in probes:
		after.append("%.0f=%s" % [x, "T" if bool(p.call("foot_destination_allowed", Vector3(x, 3.86, 300.0))) else "F"])
	out.append("  after : " + " ".join(after))
	out.append("  bounds now = " + JSON.stringify(((w.get("spec") as Dictionary).get("bay_layout", {}) as Dictionary).get("bounds")))

	out.append("")
	out.append("=== walk test with widened bounds ===")
	p.global_position = Vector3(-545.0, 30.0, 300.0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	p.set("yaw", PI * 0.5)
	var t0 := Time.get_ticks_msec()
	_key(true)
	var max_y := p.global_position.y
	var last := p.global_position
	var stuck := 0
	while Time.get_ticks_msec() - t0 < 45000:
		await get_tree().create_timer(0.12).timeout
		max_y = maxf(max_y, p.global_position.y)
		if p.global_position.distance_to(last) < 0.02:
			stuck += 1
		else:
			stuck = 0
		last = p.global_position
		if stuck > 20:
			break
		if p.global_position.x < -790.0 and p.global_position.y > 42.0:
			break
	_key(false)
	out.append("  end pos=(%.1f,%.2f,%.1f) max_y=%.2f elapsed=%.1fs" % [
		p.global_position.x, p.global_position.y, p.global_position.z, max_y,
		(Time.get_ticks_msec() - t0) / 1000.0])
	out.append("  VERDICT=%s" % ("PASS" if max_y > 42.0 else "FAIL"))

	var f := FileAccess.open("user://bounds_test.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("BOUNDS_TEST_DONE max_y=", max_y)
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
