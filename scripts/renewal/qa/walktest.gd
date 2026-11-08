extends Node
## 入口通行验收 v2：按登记折线（outer → landing → door → inside）逐段行走，
## 用真实按键事件驱动，记录每段是否到达、耗时与卡住位置。

var layer: Node
var out: Array = []
var tag := "base"
var only: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--walktag="):
			tag = a.substr(10)
		if a.begins_with("--walkonly="):
			only = Array(a.substr(11).split(","))
	await get_tree().create_timer(5.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout
	var ents: Array = layer.world.get("metadata/entrances110")
	for e in ents:
		var id := str(e.get("id", ""))
		if only.size() > 0 and not only.has(id):
			continue
		var r := await _test_one(p, e)
		out.append(r)
		print("WALK ", r["id"], " ok=", r["ok"], " t=", r["ms"], " best=", r["best"], " ", r["stuck"])
	var f := FileAccess.open("user://walktest_%s.json" % tag, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("WALKTEST_DONE ", out.size())
	get_tree().quit()

func _test_one(p: CharacterBody3D, e: Dictionary) -> Dictionary:
	var pts: Array = e.get("points", [])
	if pts.size() < 4:
		return {"id": str(e.get("id")), "ok": false, "ms": 0, "best": 99.0, "stuck": "no_points"}
	var v: Array[Vector3] = []
	for q in pts:
		v.append(_pv(q))
	var outer := v[1]
	var door := v[v.size() - 2]
	var inside := v[v.size() - 1]
	p.global_position = outer + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(0.8).timeout
	var t0 := Time.get_ticks_msec()
	var legs: Array = []
	var reached_door := false
	var last := p.global_position
	var stuck_ms := 0
	for i in range(1, v.size()):
		var target := v[i]
		var leg_t0 := Time.get_ticks_msec()
		var ok_leg := false
		while Time.get_ticks_msec() - leg_t0 < 4200:
			var d := p.global_position.distance_to(target)
			if d < 1.0:
				ok_leg = true
				break
			var dir := target - p.global_position
			if Vector2(dir.x, dir.z).length() > 0.25:
				p.set("yaw", atan2(-dir.x, -dir.z))
			_key(true)
			await get_tree().create_timer(0.12).timeout
			if p.global_position.distance_to(last) < 0.03:
				stuck_ms += 120
			else:
				stuck_ms = 0
			last = p.global_position
			if stuck_ms > 1600:
				break
		_key(false)
		await get_tree().create_timer(0.08).timeout
		legs.append(ok_leg)
		if i == v.size() - 2 and ok_leg:
			reached_door = true
		if not ok_leg:
			break
	var best := p.global_position.distance_to(inside)
	var ms := Time.get_ticks_msec() - t0
	var ok := reached_door and best < 2.6
	var stuck := ""
	if not ok:
		stuck = "blocked=%s legs=%s best=%.2f" % [str(p.global_position), str(legs), best]
	return {
		"id": str(e.get("id")),
		"ok": ok,
		"ms": ms,
		"best": snappedf(best, 0.01),
		"stuck": stuck,
		"legs": legs,
		"outer": [outer.x, outer.y, outer.z],
		"inside": [inside.x, inside.y, inside.z],
		"end": [p.global_position.x, p.global_position.y, p.global_position.z],
	}

func _pv(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var s := str(v).strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
