extends Node
## 玩家 API 行为探针：先打印自定义方法签名，再验证 sit_at / program_driven 语义。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var out: Array[String] = []
	var base := {}
	for m in Node.new().get_method_list():
		base[str(m.name)] = true
	Node.new().free()
	out.append("=== CUSTOM METHODS ===")
	for m in p.get_method_list():
		if not base.has(str(m.name)):
			var args_desc: Array[String] = []
			for a in m.args:
				args_desc.append("%s:%s" % [a.name, type_string(a.type)])
			var ret := type_string(m.return.type) if m.has("return") else "?"
			out.append("  %s(%s) -> %s" % [m.name, ", ".join(args_desc), ret])

	out.append("=== BEHAVIOUR ===")
	out.append("start pos=%s seated=%s enabled=%s" % [str(p.global_position), str(p.get("seated")), str(p.get("enabled"))])
	p.set("enabled", true)
	await get_tree().create_timer(0.5).timeout
	out.append("after enabled pos=%s on_floor=%s" % [str(p.global_position), str(p.is_on_floor())])

	var target := p.global_position + Vector3(1.0, 0.0, 0.0)
	if p.has_method("sit_at"):
		var r = p.call("sit_at", target, 0.0)
		await get_tree().create_timer(0.6).timeout
		out.append("sit_at(target,0) -> %s seated=%s pos=%s" % [str(r), str(p.get("seated")), str(p.global_position)])
		await get_tree().create_timer(0.8).timeout
		out.append("sit_at hold pos=%s" % str(p.global_position))
		if p.has_method("stand_up"):
			var r2 = p.call("stand_up")
			await get_tree().create_timer(0.6).timeout
			out.append("stand_up -> %s seated=%s pos=%s" % [str(r2), str(p.get("seated")), str(p.global_position)])

	p.set("program_driven", true)
	p.set("automated_motion", true)
	p.set("automated_horizontal", Vector2(0.0, 1.0))
	var p0: Vector3 = p.global_position
	await get_tree().create_timer(1.5).timeout
	var p1: Vector3 = p.global_position
	out.append("program_driven: %s -> %s dist=%.2f" % [str(p0), str(p1), p0.distance_to(p1)])
	p.set("program_driven", false)
	p.set("automated_motion", false)
	p.set("automated_horizontal", Vector2.ZERO)

	for a in ["move_forward", "move_back", "move_left", "move_right", "run", "jump", "interact"]:
		out.append("action %s exists=%s" % [a, str(InputMap.has_action(a))])
	var f := FileAccess.open("user://probe_api.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("PROBE_API_DONE")
	get_tree().quit()
