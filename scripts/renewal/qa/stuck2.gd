extends Node
## 第二版卡点诊断：走到卡住后，直接询问 foot_destination_allowed 在附近逐点的判定，
## 并尝试越过卡点继续前进，区分「局部障碍」与「区域禁步」。

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
	out.append("STUCK pos=(%.2f,%.2f,%.2f) blocked=%s" % [sp.x, sp.y, sp.z, str(p.get("water_edge_blocked"))])

	var spec: Dictionary = w.get("spec")
	var bay: Dictionary = spec.get("bay_layout", {})
	out.append("policy=" + JSON.stringify(bay.get("shallow_policy", {})))
	out.append("")
	out.append("=== foot_destination_allowed ahead of stuck point (y=%.2f) ===" % sp.y)
	var line := ""
	for i in range(25):
		var x := sp.x - float(i) * 0.5
		var ok = p.call("foot_destination_allowed", Vector3(x, sp.y, sp.z))
		var h := float(w.call("height_at", x, sp.z))
		line += "%s%.1f:%s(d%.1f) " % ["!" if not bool(ok) else "", x, "T" if bool(ok) else "F", -2.4 - h]
		if i % 5 == 4:
			out.append("  " + line)
			line = ""
	if line != "":
		out.append("  " + line)

	out.append("")
	out.append("=== teleport-jump test ===")
	for tx in [-645.0, -650.0, -655.0, -660.0, -670.0, -690.0]:
		p.global_position = Vector3(tx, 30.0, 300.0)
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(1.4).timeout
		var x0 := p.global_position.x
		var y0 := p.global_position.y
		p.set("yaw", PI * 0.5)
		_key(true)
		await get_tree().create_timer(1.2).timeout
		_key(false)
		out.append("  start x=%.0f -> landed=(%.1f,%.2f,%.1f) moved=%.2f blocked=%s" % [
			tx, x0, y0, p.global_position.z, absf(p.global_position.x - x0),
			str(p.get("water_edge_blocked"))])
		await get_tree().create_timer(0.2).timeout

	var f := FileAccess.open("user://stuck2.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("STUCK2_DONE stuck_x=", sp.x)
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
