extends Node
## 性能测量：按固定路线用真实按键驱动玩家，记录逐帧耗时与流式加载统计。
## 输出：平均 FPS、P50/P95/P99 帧耗时、>50/>100/>200ms 帧数、峰值内存。

var layer: Node
var tag := "base"
var route_filter := ""

var _frames: Array[float] = []
var _recording := false
var _last_usec := 0

const ROUTES := [
	{"id": "dense_street", "name": "主城郭密集街区", "start": [289.0, 4.0, 248.0], "path": [[280.0, 240.0], [262.0, 232.0], [244.0, 236.0], [228.0, 246.0]], "secs": 45.0},
	{"id": "creek_cross", "name": "溪谷跨区", "start": [95.0, 6.0, 26.0], "path": [[108.0, 14.0], [120.0, 2.0], [132.0, -12.0]], "secs": 45.0},
	{"id": "hill_slope", "name": "山侧上下坡", "start": [-215.0, 18.0, -215.0], "path": [[-224.0, -226.0], [-236.0, -238.0], [-248.0, -226.0]], "secs": 45.0},
	{"id": "cluster_z09", "name": "高密度组团", "start": [300.0, 6.0, 40.0], "path": [[310.0, 52.0], [322.0, 62.0], [334.0, 54.0]], "secs": 45.0},
	{"id": "wheel_plaza", "name": "摩天轮广场", "start": [-330.0, 75.0, -392.0], "path": [[-344.0, -398.0], [-356.0, -404.0], [-368.0, -398.0]], "secs": 45.0},
]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perftag="):
			tag = a.substr(10)
		if a.begins_with("--perfroute="):
			route_filter = a.substr(12)
	await get_tree().create_timer(5.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.5).timeout
	var results: Array = []
	for r in ROUTES:
		if route_filter != "" and str(r["id"]) != route_filter:
			continue
		var res := await _run_route(p, r)
		results.append(res)
		print("PERF ", r["id"], " avg=", res["avg"], " p95=", res["p95"], " over100=", res["over100"])
	var f := FileAccess.open("user://perf_%s.json" % tag, FileAccess.WRITE)
	f.store_string(JSON.stringify(results))
	f.close()
	print("PERF_DONE ", results.size())
	get_tree().quit()

func _run_route(p: CharacterBody3D, r: Dictionary) -> Dictionary:
	var start: Array = r["start"]
	p.global_position = Vector3(start[0], start[1] + 0.4, start[2])
	p.velocity = Vector3.ZERO
	# 预热：先跑一段不记录，避开冷启动的着色器准备与区块加载
	var warm := 12.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--warmup="):
			warm = float(a.substr(9))
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < int(warm * 1000.0):
		await get_tree().process_frame
	_frames.clear()
	_last_usec = Time.get_ticks_usec()
	_recording = true
	var secs := float(r["secs"])
	var t0 := Time.get_ticks_msec()
	var path: Array = r["path"]
	var idx := 0
	var static_mode := false
	for a in OS.get_cmdline_user_args():
		if a == "--static=1":
			static_mode = true
	if not static_mode:
		_key(true)
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
		if idx < path.size():
			var wp: Array = path[idx]
			var target := Vector3(wp[0], p.global_position.y, wp[1])
			var d := p.global_position.distance_to(target)
			if d < 3.0:
				idx += 1
			else:
				var dir := target - p.global_position
				p.set("yaw", atan2(-dir.x, -dir.z))
	_recording = false
	_key(false)
	var stats := _stats()
	stats["id"] = r["id"]
	stats["name"] = r["name"]
	stats["secs"] = secs
	if layer.stream != null:
		stats["load_events"] = layer.stream.get("load_events")
		stats["peak_cells"] = layer.stream.get("peak_cells")
		stats["loaded_now"] = layer.stream.get("loaded").size()
	stats["mem_mb"] = snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)
	return stats

func _process(_delta: float) -> void:
	if not _recording:
		return
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_usec) / 1000.0
	_last_usec = now
	if dt > 0.0 and dt < 2000.0:
		_frames.append(dt)

func _stats() -> Dictionary:
	var n := _frames.size()
	if n == 0:
		return {"frames": 0, "avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "over50": 0, "over100": 0, "over200": 0, "fps": 0.0}
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	var over50 := 0
	var over100 := 0
	var over200 := 0
	for v in _frames:
		total += v
		if v > 50.0: over50 += 1
		if v > 100.0: over100 += 1
		if v > 200.0: over200 += 1
	var avg := total / float(n)
	return {
		"frames": n,
		"avg": snappedf(avg, 0.1),
		"fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"p50": snappedf(sorted[int(n * 0.50)], 0.1),
		"p95": snappedf(sorted[mini(n - 1, int(n * 0.95))], 0.1),
		"p99": snappedf(sorted[mini(n - 1, int(n * 0.99))], 0.1),
		"max": snappedf(sorted[n - 1], 0.1),
		"over50": over50,
		"over100": over100,
		"over200": over200,
	}

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
