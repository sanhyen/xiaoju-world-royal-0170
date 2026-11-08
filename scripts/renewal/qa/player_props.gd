extends Node
## 找出"站在桥上但不能移动"的原因：在两个位置各记录一次玩家全部属性，输出差异。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	var a := await _snap(p, Vector3(-545.0, 12.0, 300.0), "A_shore")
	var b := await _snap(p, Vector3(-600.0, 12.0, 300.0), "B_bridge")
	var c := await _snap(p, Vector3(-720.0, 60.0, 300.0), "C_terrace")

	out.append("=== DIFF A(shore) vs B(bridge) ===")
	_diff(a, b)
	out.append("")
	out.append("=== DIFF A(shore) vs C(terrace) ===")
	_diff(a, c)

	out.append("")
	out.append("=== WORLD PROPERTIES ===")
	var w: Node = layer.world
	for pr in w.get_property_list():
		var nm := str(pr.get("name"))
		var ty: int = int(pr.get("type"))
		var val = w.get(nm)
		var vs := ""
		if val is Dictionary:
			vs = "Dictionary size=%d" % (val as Dictionary).size()
		elif val is Array:
			vs = "Array size=%d" % (val as Array).size()
		elif val is PackedFloat32Array or val is PackedFloat64Array:
			vs = "PackedFloat size=%d" % (val as Variant).size()
		elif ty == TYPE_OBJECT or ty == TYPE_NIL:
			continue
		else:
			vs = str(val)
		if vs.length() > 60:
			vs = vs.substr(0, 60) + "..."
		out.append("  %-30s type=%d %s" % [nm, ty, vs])
	out.append("")
	out.append("=== SPEC KEYS ===")
	var spec = w.get("spec")
	if spec is Dictionary:
		for k in (spec as Dictionary).keys():
			var v = spec[k]
			var vs := ""
			if v is Dictionary:
				vs = "Dict(%d) keys=%s" % [(v as Dictionary).size(), str((v as Dictionary).keys()).substr(0, 200)]
			elif v is Array:
				vs = "Array(%d)" % (v as Array).size()
			else:
				vs = str(v).substr(0, 80)
			out.append("  %-24s %s" % [str(k), vs])
	out.append("")
	out.append("=== BAY_LAYOUT DETAIL ===")
	var bay = (spec as Dictionary).get("bay_layout", {})
	if bay is Dictionary:
		for k in (bay as Dictionary).keys():
			var v = bay[k]
			var vs := ""
			if v is Array:
				vs = "Array(%d)" % (v as Array).size()
				if (v as Array).size() > 0:
					vs += " first=" + str((v as Array)[0]).substr(0, 400)
			elif v is Dictionary:
				vs = "Dict(%d) %s" % [(v as Dictionary).size(), JSON.stringify(v).substr(0, 400)]
			else:
				vs = str(v)
			out.append("  [%s] %s" % [str(k), vs])
	out.append("")
	out.append("=== HEIGHT PROBE (baseline) ===")
	for q in [Vector2(-600,300), Vector2(-500,300), Vector2(-770,300)]:
		out.append("  h(%0.0f,%0.0f)=%.2f raw=%.2f land=%.2f" % [q.x, q.y,
			float(w.call("height_at", q.x, q.y)), float(w.call("raw_height", q.x, q.y)),
			float(w.call("land_height", q.x, q.y))])
	out.append("")
	out.append("=== WORLD METHODS (height related) ===")
	for m in w.get_method_list():
		var mn := str(m.get("name"))
		if mn.contains("height") or mn.contains("water") or mn.contains("ground") or mn.contains("terrain"):
			out.append("  " + mn)
	var f := FileAccess.open("user://player_props.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("PLAYER_PROPS_DONE")
	get_tree().quit()

func _snap(p: CharacterBody3D, pos: Vector3, tag: String) -> Dictionary:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	var d := {}
	for pr in p.get_property_list():
		var nm := str(pr.get("name"))
		var ty: int = int(pr.get("type"))
		if ty == TYPE_BOOL or ty == TYPE_INT or ty == TYPE_FLOAT or ty == TYPE_STRING:
			d[nm] = p.get(nm)
	out.append("%s pos=(%.1f,%.1f,%.1f) on_floor=%s" % [tag, p.global_position.x, p.global_position.y, p.global_position.z, str(p.is_on_floor())])
	return d

func _diff(a: Dictionary, b: Dictionary) -> void:
	var keys := a.keys()
	keys.sort()
	for k in keys:
		if not b.has(k):
			continue
		if str(a[k]) != str(b[k]):
			out.append("  %-28s %s -> %s" % [k, str(a[k]), str(b[k])])
