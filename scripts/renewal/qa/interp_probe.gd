extends Node
## 物理插值效果量化：连续渲染帧的相机位移是否连续。
## 不插值时，60Hz 物理与高渲染帧率错位，会出现大量「零位移帧」。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	var cam: Camera3D = layer.cam
	p.global_position = Vector3(289.0, 4.5, 248.0)
	# 强制给玩家与相机链打开插值，并记录设置前后的模式
	var before_p := int(p.physics_interpolation_mode)
	p.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON
	var cam_before := int(cam.physics_interpolation_mode)
	cam.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON
	await get_tree().create_timer(0.4).timeout
	print("INTERP_MODE player %d->%d cam %d->%d" % [before_p, int(p.physics_interpolation_mode), cam_before, int(cam.physics_interpolation_mode)])
	await get_tree().create_timer(0.4).timeout
	_key(true)
	var pos: Array[Vector3] = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		pos.append(cam.global_position)
	_key(false)
	var zero := 0
	var total := 0
	var steps: Array[float] = []
	for i in range(1, pos.size()):
		var d := pos[i].distance_to(pos[i - 1])
		steps.append(d)
		total += 1
		if d < 0.0005:
			zero += 1
	var sum := 0.0
	for s in steps:
		sum += s
	var mean := sum / maxf(1.0, float(steps.size()))
	var var_sum := 0.0
	for s in steps:
		var_sum += (s - mean) * (s - mean)
	var std := sqrt(var_sum / maxf(1.0, float(steps.size())))
	var lines: Array[String] = []
	lines.append("frames=%d zero_move=%d (%.1f%%) mean=%.5f std=%.5f cv=%.2f" % [
		total, zero, 100.0 * float(zero) / maxf(1.0, float(total)), mean, std, std / maxf(0.00001, mean)])
	lines.append("interp_setting=%s" % str(ProjectSettings.get_setting("physics/common/physics_interpolation")))
	lines.append("player_interp_mode=%d" % int(p.physics_interpolation_mode))
	var f := FileAccess.open("user://interp_probe.txt", FileAccess.WRITE)
	for l in lines: f.store_line(l)
	f.close()
	print("INTERP_PROBE_DONE")
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
