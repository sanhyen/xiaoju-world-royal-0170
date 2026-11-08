extends Node
## 落水安全验收：深水提示、上岸辅助、安全点恢复。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var safety: Node = layer.safety
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	# 1) 记录一处安全点（岸边）
	var bank := Vector3(-185.0, 1.4, -196.0)
	p.global_position = bank
	await get_tree().create_timer(1.2).timeout
	out.append("bank pos=%s on_floor=%s safe=%s safe_point=%s" % [str(p.global_position), str(p.is_on_floor()), str(safety.get("has_safe")), str(safety.get("safe_point"))])

	# 2) 投入河道（水面 0.6，水深约 1.6m）
	p.global_position = Vector3(-185.0, -0.9, -203.0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(2.2).timeout
	out.append("in_river pos=%s submerged=%s depth=%.2f prompt=%s" % [str(p.global_position), str(safety.get("submerged")), float(safety.call("_water_depth", p.global_position)), str(safety.get("prompt_visible"))])

	# 3) 朝东岸持续前进，检查能否自然上岸
	p.set("yaw", atan2(-1.0, 0.0))
	var t0 := Time.get_ticks_msec()
	_key(true)
	var out_of_water := false
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().create_timer(0.2).timeout
		var depth := float(safety.call("_water_depth", p.global_position))
		if depth < 0.25 and p.is_on_floor():
			out_of_water = true
			break
	_key(false)
	out.append("climb_out=%s elapsed=%dms pos=%s depth=%.2f" % [str(out_of_water), Time.get_ticks_msec() - t0, str(p.global_position), float(safety.call("_water_depth", p.global_position))])

	# 4) 安全点恢复
	var before := p.global_position
	p.global_position = Vector3(-185.0, -1.2, -203.0)
	await get_tree().create_timer(0.6).timeout
	safety.call("recover")
	await get_tree().create_timer(0.6).timeout
	out.append("recover from=%s to=%s safe_point=%s" % [str(before), str(p.global_position), str(safety.get("safe_point"))])

	var f := FileAccess.open("user://water_test.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("WATER_TEST_DONE")
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
