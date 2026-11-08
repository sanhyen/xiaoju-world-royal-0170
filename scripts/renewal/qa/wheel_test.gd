extends Node
## 摩天轮专项验收：选址视图、站台步行、对位登乘、乘坐一圈、提前退出、存档恢复。

var layer: Node
var mode := ""
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var wheel: Node3D = layer.wheel
	if wheel == null:
		print("WHEEL_MISSING")
		load("res://scripts/renewal/qa/completion.gd").finish(self)
		return
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	out.append("wheel_position=%s" % str(wheel.global_position))

	# 0) 常态自转：静止状态角度必须持续变化，否则玩家会以为设施坏了
	var a0 := float(wheel.get("angle"))
	var st0 := str(wheel.get("state"))
	await get_tree().create_timer(2.0).timeout
	var a1 := float(wheel.get("angle"))
	out.append("idle_rotate state=%s angle %.4f -> %.4f delta=%.4f" % [st0, a0, a1, a1 - a0])

	# 1) 步行接近：从台地东侧走向站台
	var start := wheel.global_position + Vector3(22.0, 0.3, 5.0)
	layer.teleport(start)
	await get_tree().create_timer(1.2).timeout
	out.append("teleport start pos=%s on_floor=%s" % [str(p.global_position), str(p.is_on_floor())])

	# 2) 程序驱动走向站台（-X 方向）
	p.set("program_driven", true)
	p.set("automated_motion", true)
	p.set("automated_horizontal", Vector2(-1.0, 0.0))
	var t0 := Time.get_ticks_msec()
	var reached := false
	while Time.get_ticks_msec() - t0 < 22000:
		await get_tree().create_timer(0.2).timeout
		var d := p.global_position.distance_to(wheel.global_position + Vector3(0, 2.2, 4.0))
		if d < 6.0:
			reached = true
			break
	p.set("program_driven", false)
	p.set("automated_motion", false)
	p.set("automated_horizontal", Vector2.ZERO)
	out.append("walk_to_deck reached=%s pos=%s elapsed=%dms" % [str(reached), str(p.global_position), Time.get_ticks_msec() - t0])

	# 3) 请求登乘并等待对位
	if wheel.has_method("_request_board"):
		wheel.call("_request_board")
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 8000:
		await get_tree().create_timer(0.2).timeout
		if str(wheel.get("state")) == "boarding":
			break
	out.append("align state=%s angle=%.4f door=%.2f" % [str(wheel.get("state")), float(wheel.get("angle")), float(wheel.get("door_open"))])
	out.append("boarding_seat=%s" % str(wheel.call("_cabin_world_seat", int(wheel.get("boarding_index")))))

	# 4) 走进吊舱并入座
	var seat: Vector3 = wheel.call("_cabin_world_seat", int(wheel.get("boarding_index")))
	layer.teleport(seat)
	await get_tree().create_timer(0.8).timeout
	if wheel.has_method("_seat_player"):
		wheel.call("_seat_player")
	await get_tree().create_timer(1.0).timeout
	out.append("seated riding=%s player_pos=%s" % [str(wheel.get("riding")), str(p.global_position)])

	# 5) 观察 12 秒，检查吊舱位移与玩家跟随
	var seat_a: Vector3 = wheel.call("_cabin_world_seat", int(wheel.get("boarding_index")))
	await get_tree().create_timer(12.0).timeout
	var seat_b: Vector3 = wheel.call("_cabin_world_seat", int(wheel.get("boarding_index")))
	out.append("cabin_moved=%.2fm player_follow_err=%.2fm angle=%.3f" % [seat_a.distance_to(seat_b), p.global_position.distance_to(seat_b), float(wheel.get("angle"))])

	# 6) 提前结束
	wheel.call("_end_ride_early")
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 15000:
		await get_tree().create_timer(0.3).timeout
		if str(wheel.get("state")) == "boarding" and not bool(wheel.get("riding")):
			break
	out.append("after_early_exit state=%s riding=%s pos=%s on_floor=%s" % [str(wheel.get("state")), str(wheel.get("riding")), str(p.global_position), str(p.is_on_floor())])

	# 7) 存档
	wheel.call("save_state")
	out.append("save_written=%s" % str(FileAccess.file_exists("user://save/renewal_v1/wheel.json")))

	var f := FileAccess.open("user://wheel_test.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("WHEEL_TEST_DONE")
	load("res://scripts/renewal/qa/completion.gd").finish(self)
