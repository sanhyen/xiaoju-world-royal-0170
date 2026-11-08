extends Node
## 试探 shallow_policy 的可写性：改 edge_mode / wade 参数后，看桥上能否移动。

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
	var pol: Dictionary = bay.get("shallow_policy", {})
	out.append("before: " + JSON.stringify(pol))

	# 基线
	await _try(p, Vector3(-600, 12, 300), "baseline")

	# 各种候选
	var trials := [
		["edge_mode=wade", func(): pol["edge_mode"] = "wade"],
		["edge_mode=free", func(): pol["edge_mode"] = "free"],
		["edge_mode=none", func(): pol["edge_mode"] = "none"],
		["edge_mode=allow", func(): pol["edge_mode"] = "allow"],
		["wade_band=9999", func(): pol["mainland_wade_band_m"] = 9999.0],
		["depth=99", func(): pol["max_wade_depth_m"] = 99.0],
		["erase_edge_mode", func(): pol.erase("edge_mode")],
		["erase_policy", func(): bay.erase("shallow_policy")],
	]
	for t in trials:
		var nm: String = t[0]
		var fn: Callable = t[1]
		fn.call()
		bay["shallow_policy"] = pol
		spec["bay_layout"] = bay
		w.set("spec", spec)
		await _try(p, Vector3(-600, 12, 300), nm)
		# 复原
		pol = bay.get("shallow_policy", {})
		if pol.is_empty():
			pol = {"edge_mode": "stop_in_place", "max_wade_depth_m": 1.35, "mainland_wade_band_m": 28.0,
				"island_wade_radius": 1.45, "island_outer_radius": 1.55, "deep_water_recovery": false}
			bay["shallow_policy"] = pol

	var f := FileAccess.open("user://shallow_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("SHALLOW_PROBE_DONE")
	get_tree().quit()

func _try(p: CharacterBody3D, pos: Vector3, tag: String) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(1.6).timeout
	var y0 := p.global_position.y
	p.set("yaw", PI * 0.5)
	_key(true)
	await get_tree().create_timer(1.4).timeout
	_key(false)
	var moved := absf(p.global_position.x - pos.x)
	out.append("%-18s moved=%.2f m  y=%.2f->%.2f  blocked=%s  pos=(%.1f,%.1f,%.1f)" % [
		tag, moved, y0, p.global_position.y, str(p.get("water_edge_blocked")),
		p.global_position.x, p.global_position.y, p.global_position.z])
	await get_tree().create_timer(0.3).timeout

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
