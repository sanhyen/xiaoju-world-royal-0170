extends Node
## 找出 player.gdc 里缓存的水域判定参数：完整 dump 玩家属性 + 方法，
## 并对 foot_destination_allowed 做位置扫描，反推阈值。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	var w: Node = layer.world
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	out.append("=== PLAYER PROPERTIES ===")
	for pr in p.get_property_list():
		var nm := str(pr.get("name"))
		var ty: int = int(pr.get("type"))
		var usage: int = int(pr.get("usage"))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 and usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var val = p.get(nm)
		var vs := ""
		if val is Dictionary:
			vs = "Dict(%d) %s" % [(val as Dictionary).size(), JSON.stringify(val).substr(0, 300)]
		elif val is Array:
			vs = "Array(%d)" % (val as Array).size()
		elif ty == TYPE_OBJECT or ty == TYPE_NIL:
			vs = str(val)
		else:
			vs = str(val)
		out.append("  %-26s type=%-2d %s" % [nm, ty, vs.substr(0, 160)])

	out.append("")
	out.append("=== PLAYER METHODS ===")
	var ms: Array[String] = []
	for m in p.get_method_list():
		var mn := str(m.get("name"))
		if mn.begins_with("_"):
			continue
		ms.append(mn)
	ms.sort()
	out.append("  " + ", ".join(ms))

	out.append("")
	out.append("=== PLAYER SCRIPT VARS (via script) ===")
	var scr = p.get_script()
	if scr != null:
		for c in (scr as Script).get_script_property_list():
			out.append("  %-26s type=%-2d hint=%s" % [str(c.get("name")), int(c.get("type")), str(c.get("hint_string"))])

	# 在桥面/岛区各点调用 foot_destination_allowed
	out.append("")
	out.append("=== foot_destination_allowed SCAN (y=3.86 on bridge) ===")
	for x in [-560.0, -580.0, -590.0, -600.0, -605.0, -610.0, -615.0, -620.0, -630.0, -640.0, -650.0, -660.0, -680.0]:
		var r = null
		if p.has_method("foot_destination_allowed"):
			r = p.call("foot_destination_allowed", Vector3(x, 3.86, 300.0))
		out.append("  x=%.0f -> %s   (dist_to_shore=%.1f)" % [x, str(r), absf(x + 578.0)])

	out.append("")
	out.append("=== foot_destination_allowed SCAN (varying y at x=-640) ===")
	for y in [-14.0, -8.0, -3.0, 0.0, 3.86, 10.0, 44.0]:
		var r2 = null
		if p.has_method("foot_destination_allowed"):
			r2 = p.call("foot_destination_allowed", Vector3(-640.0, y, 300.0))
		out.append("  y=%.2f -> %s" % [y, str(r2)])

	out.append("")
	out.append("=== A/B: POLICY FIELD vs foot_destination_allowed ===")
	var probes := [-580.0, -585.0, -590.0, -600.0, -640.0, -700.0, -770.0]
	var dline: Array[String] = []
	for x in probes:
		dline.append("%.0f:%.2f" % [x, -2.4 - float(w.call("height_at", x, 300.0))])
	out.append("  depth at those x: " + ", ".join(dline))
	var trials := [
		["base", {}],
		["depth=99", {"max_wade_depth_m": 99.0}],
		["depth=3", {"max_wade_depth_m": 3.0}],
		["band=9999", {"mainland_wade_band_m": 9999.0}],
		["edge=free", {"edge_mode": "free"}],
		["depth99+band9999", {"max_wade_depth_m": 99.0, "mainland_wade_band_m": 9999.0}],
	]
	for t in trials:
		var nm: String = t[0]
		var patch: Dictionary = t[1]
		var spec2: Dictionary = w.get("spec")
		var bay2: Dictionary = spec2.get("bay_layout", {})
		var pol2: Dictionary = (bay2.get("shallow_policy", {}) as Dictionary).duplicate()
		for k in patch.keys():
			pol2[k] = patch[k]
		bay2["shallow_policy"] = pol2
		spec2["bay_layout"] = bay2
		w.set("spec", spec2)
		var cells: Array[String] = []
		for x in probes:
			var r = p.call("foot_destination_allowed", Vector3(x, 3.86, 300.0))
			cells.append("%.0f=%s" % [x, "T" if bool(r) else "F"])
		out.append("  %-18s %s" % [nm, " ".join(cells)])
	# 复位
	var spec3: Dictionary = w.get("spec")
	var bay3: Dictionary = spec3.get("bay_layout", {})
	(bay3 as Dictionary)["shallow_policy"] = {
		"deep_water_recovery": false, "edge_mode": "stop_in_place",
		"island_outer_radius": 1.55, "island_wade_radius": 1.45,
		"mainland_wade_band_m": 28.0, "max_wade_depth_m": 1.35,
	}
	spec3["bay_layout"] = bay3
	w.set("spec", spec3)

	out.append("")
	out.append("=== WORLD spec identity check ===")
	var s1 = w.get("spec")
	var s2 = w.get("spec")
	out.append("  same_ref=%s" % str(s1 == s2))
	var b1 = (s1 as Dictionary).get("bay_layout", {})
	var b2 = (s2 as Dictionary).get("bay_layout", {})
	out.append("  bay_same=%s  b1_pol=%s" % [str(b1 == b2), JSON.stringify((b1 as Dictionary).get("shallow_policy", {}))])
	# 写入一个标记键，看是否持久
	(b1 as Dictionary)["__probe_mark"] = 12345
	var b3 = ((w.get("spec") as Dictionary).get("bay_layout", {}) as Dictionary)
	out.append("  mark_visible=%s" % str(b3.get("__probe_mark", "MISSING")))
	b3.erase("__probe_mark")

	var f := FileAccess.open("user://player_dump.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("PLAYER_DUMP_DONE")
	get_tree().quit()
