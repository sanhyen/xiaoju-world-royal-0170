extends Node
## 输入模拟探针：验证通过 Input.parse_input_event 发送真实按键事件能否驱动玩家。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.5).timeout
	var out: Array[String] = []
	out.append("start pos=%s yaw=%.3f" % [str(p.global_position), float(p.get("yaw"))])

	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	var p0: Vector3 = p.global_position
	await get_tree().create_timer(1.5).timeout
	var p1: Vector3 = p.global_position
	ev.pressed = false
	Input.parse_input_event(ev)
	out.append("W held 1.5s: %s -> %s dist=%.2f" % [str(p0), str(p1), p0.distance_to(p1)])

	# 转向后再次前进，确认方向随视角
	var ev2 := InputEventMouseMotion.new()
	ev2.relative = Vector2(400, 0)
	Input.parse_input_event(ev2)
	await get_tree().create_timer(0.3).timeout
	ev.pressed = true
	Input.parse_input_event(ev)
	var p2: Vector3 = p.global_position
	await get_tree().create_timer(1.5).timeout
	var p3: Vector3 = p.global_position
	ev.pressed = false
	Input.parse_input_event(ev)
	out.append("after yaw: %s -> %s dist=%.2f yaw=%.3f" % [str(p2), str(p3), p2.distance_to(p3), float(p.get("yaw"))])

	var f := FileAccess.open("user://probe_input.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("PROBE_INPUT_DONE")
	get_tree().quit()
