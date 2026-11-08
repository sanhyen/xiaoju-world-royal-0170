extends Node
## dump 玩家角色：节点、网格、材质颜色，并采样走路时四肢的旋转曲线。

var layer: Node
var lines: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	# 启动菜单中角色不做物理更新，先落地，避免把初始下落当成走路样本。
	await get_tree().create_timer(1.0).timeout
	lines.append("player pos=" + str(p.global_position))
	var fig = p.get("figure")
	lines.append("figure=" + str(fig))
	if fig != null:
		for c in (fig as Node).get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var col := "none"
				if mi.mesh != null and mi.mesh.get_surface_count() > 0:
					var m = mi.mesh.surface_get_material(0)
					if m is StandardMaterial3D:
						col = str((m as StandardMaterial3D).albedo_color)
				lines.append("  %-22s mesh=%-14s size=%s color=%s pos=%s" % [
					str(mi.name), str(mi.mesh.get_class()) if mi.mesh != null else "null",
					str(mi.mesh.get_aabb().size) if mi.mesh != null else "-",
					col, str(mi.position)])

	lines.append("")
	lines.append("=== AFTER FIGURE_LOOK: world AABB per part ===")
	if fig != null:
		for c in (fig as Node).get_children():
			if c is MeshInstance3D:
				var mi2 := c as MeshInstance3D
				var txt := "  %-20s %-14s" % [str(mi2.name), str(mi2.mesh.get_class()) if mi2.mesh != null else "null"]
				if mi2.mesh != null:
					var ab: AABB = mi2.global_transform * mi2.mesh.get_aabb()
					txt += " wsize=(%.2f,%.2f,%.2f) wpos=(%.2f,%.2f,%.2f) vis=%s" % [
						ab.size.x, ab.size.y, ab.size.z, ab.position.x, ab.position.y, ab.position.z,
						str(mi2.visible)]
				if mi2.material_override != null and mi2.material_override is StandardMaterial3D:
					txt += " col=" + str((mi2.material_override as StandardMaterial3D).albedo_color)
				lines.append(txt)

	lines.append("")
	lines.append("=== WALK SAMPLE (2.4s) ===")
	var legs = p.get("legs")
	var arms = p.get("arms")
	p.set("yaw", PI * 0.5)
	_key(true)
	var t0 := Time.get_ticks_msec()
	var i := 0
	while Time.get_ticks_msec() - t0 < 2400:
		await get_tree().create_timer(0.08).timeout
		i += 1
		var l0 := 0.0
		var l1 := 0.0
		var a0 := 0.0
		var a1 := 0.0
		if legs is Array and (legs as Array).size() >= 2:
			l0 = (legs as Array)[0].rotation.x
			l1 = (legs as Array)[1].rotation.x
		if arms is Array and (arms as Array).size() >= 2:
			a0 = (arms as Array)[0].rotation.x
			a1 = (arms as Array)[1].rotation.x
		var air := float(layer.get_node("FigureLook").get("_air_blend"))
		lines.append("  t=%.2f gait=%.3f legL=%+.3f legR=%+.3f armL=%+.3f armR=%+.3f floor=%s air=%.3f" % [
			(Time.get_ticks_msec() - t0) / 1000.0, float(p.get("gait")), l0, l1, a0, a1,str(p.is_on_floor()),air])
	_key(false)

	var f := FileAccess.open("user://figure_dump.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("FIGURE_DUMP_DONE")
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
