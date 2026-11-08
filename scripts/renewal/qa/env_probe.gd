extends Node
## 质感优化可行性侦察：渲染后端能力、环境后处理现状、水面材质、相机参数、物理插值。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var main: Node = layer.main
	var w: Node = layer.world
	out.append("renderer=%s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method")))
	out.append("physics_interpolation=%s" % str(ProjectSettings.get_setting("physics/common/physics_interpolation")))
	out.append("physics_ticks=%s" % str(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")))
	out.append("max_fps=%s vsync=%s" % [str(Engine.max_fps), str(DisplayServer.window_get_vsync_mode())])

	var env_node = main.get("environment")
	if env_node is WorldEnvironment and (env_node as WorldEnvironment).environment != null:
		var e: Environment = (env_node as WorldEnvironment).environment
		out.append("ENV tone_mapper=%d exposure=%.2f white=%.2f" % [e.tonemap_mode, e.tonemap_exposure, e.tonemap_white])
		out.append("ENV ssao=%s ssil=%s sdfgi=%s glow=%s fog=%s volfog=%s" % [
			str(e.ssao_enabled), str(e.ssil_enabled), str(e.sdfgi_enabled), str(e.glow_enabled), str(e.fog_enabled), str(e.volumetric_fog_enabled)])
		out.append("ENV ambient=%s energy=%.2f sky=%s" % [str(e.ambient_light_source), e.ambient_light_energy, str(e.sky != null)])
		if e.sky != null and e.sky.sky_material != null:
			out.append("ENV sky_material=%s" % str(e.sky.sky_material.get_class()))
		out.append("ENV fog_light_color=%s density=%.4f" % [str(e.fog_light_color), e.fog_density])
	var sun = main.get("sun")
	if sun is DirectionalLight3D:
		var s := sun as DirectionalLight3D
		out.append("SUN energy=%.2f shadow=%s mode=%d dist=%.0f" % [s.light_energy, str(s.shadow_enabled), s.directional_shadow_mode, s.directional_shadow_max_distance])

	var wm = w.get("water_material")
	out.append("water_material=%s" % str(wm))
	if wm is Material:
		out.append("water_material class=%s" % str((wm as Material).get_class()))
		if wm is ShaderMaterial:
			out.append("water shader=%s" % str((wm as ShaderMaterial).shader.resource_path if (wm as ShaderMaterial).shader != null else "null"))

	# 水面节点
	var waters: Array[String] = []
	_find_water(w, waters)
	out.append("water nodes: " + ", ".join(waters.slice(0, 12)))

	var p: CharacterBody3D = layer.player
	out.append("PLAYER walk=%.2f run=%.2f zoom=%.2f snap=%.2f maxangle=%.3f" % [
		float(p.get("walk_speed")), float(p.get("run_multiplier")), float(p.get("zoom")),
		float(p.get("floor_snap_length")), float(p.get("floor_max_angle"))])
	var arm = p.get("arm")
	if arm is SpringArm3D:
		var a := arm as SpringArm3D
		out.append("ARM len=%.2f margin=%.2f mask=%d" % [a.spring_length, a.margin, a.collision_mask])
	var cam = p.get("camera")
	if cam is Camera3D:
		var c := cam as Camera3D
		out.append("CAM fov=%.1f near=%.2f far=%.0f" % [c.fov, c.near, c.far])

	var f := FileAccess.open("user://env_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("ENV_PROBE_DONE")
	get_tree().quit()

func _find_water(n: Node, acc: Array[String]) -> void:
	if n is MeshInstance3D:
		var nm := str(n.name).to_lower()
		if nm.contains("water") or nm.contains("river") or nm.contains("ocean") or nm.contains("sea"):
			acc.append(str(n.name))
	for c in n.get_children():
		_find_water(c, acc)
