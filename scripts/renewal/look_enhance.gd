extends Node
## 质感增强：色调与海水可选；P4 远、近景坡面分色默认开启。
##
## 三项都实测出副作用，因此改成「默认不动、按需开启」：
##   - 色调：ACES + white=6.0 + Glow + 雾 1.00→0.35 → 整体偏亮、刺眼（--look-tone=1）
##   - 水面：菲涅尔把地平线色混进 ALBEDO → 海面发白像一层牛奶（--look-water=1，已修正）
##   - 地形：草色偏移未排除沙地 → 沙滩被染成黄绿（--terrain=1，已修正）
## P4 只替换材质，不修改地形、顶点色或碰撞。

var layer: Node
var enabled := true
var tone_enabled := false
var water_enabled := false
var applied := false
var _interp_check_at := 0
var _interp_checked := false
var _terrain_enabled := true
# 水面可调参数（-1 表示用 shader 默认值）
var _water_normal := -1.0
var _water_fresnel := -1.0
var _water_sky := -1.0

# 可调参数（集中在此，便于逐项对比）
const TONEMAP := Environment.TONE_MAPPER_ACES
const EXPOSURE := 1.05
const WHITE := 6.0
const GLOW_INTENSITY := 0.55
const GLOW_BLOOM := 0.06
const GLOW_THRESHOLD := 1.15
const CAM_FOV := 62.0
const CAM_NEAR := 0.1
const ARM_MARGIN := 0.12
const SHADOW_DIST := 150.0

func setup(p_layer: Node) -> void:
	layer = p_layer
	for a in OS.get_cmdline_user_args():
		if a == "--look=0":
			enabled = false
		elif a == "--look-tone=1":
			tone_enabled = true
		elif a == "--look-water=1":
			water_enabled = true
		elif a == "--terrain=1":
			_terrain_enabled = true
		elif a == "--terrain=0":
			_terrain_enabled = false
		elif a.begins_with("--water-normal="):
			_water_normal = float(a.substr("--water-normal=".length()))
		elif a.begins_with("--water-fresnel="):
			_water_fresnel = float(a.substr("--water-fresnel=".length()))
		elif a.begins_with("--water-sky="):
			_water_sky = float(a.substr("--water-sky=".length()))

func apply() -> void:
	if not enabled or applied:
		return
	applied = true
	# 色调与水面默认不改，保持原版观感
	if tone_enabled:
		_apply_environment()
	else:
		print("LOOK_ENV skipped (原版色调；需要时加 --look-tone=1)")
	_apply_camera()
	_apply_shadow()
	_apply_interpolation()
	if water_enabled:
		_apply_water()
	else:
		print("LOOK_WATER skipped (原版水面；需要时加 --look-water=1)")
	_apply_terrain()

func _apply_environment() -> void:
	var main: Node = layer.main
	var env_node = main.get("environment")
	if not (env_node is WorldEnvironment):
		print("LOOK_ENV missing")
		return
	var e: Environment = (env_node as WorldEnvironment).environment
	if e == null:
		return
	var before := "tone=%d glow=%s fog=%.2f" % [e.tonemap_mode, str(e.glow_enabled), e.fog_density]
	e.tonemap_mode = TONEMAP
	e.tonemap_exposure = EXPOSURE
	e.tonemap_white = WHITE
	e.glow_enabled = true
	e.glow_intensity = GLOW_INTENSITY
	e.glow_strength = 1.0
	e.glow_bloom = GLOW_BLOOM
	e.glow_hdr_threshold = GLOW_THRESHOLD
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Godot 4 的 glow_levels 是 7 个独立属性，不能整体赋值
	var levels := [0.0, 0.6, 0.9, 1.0, 0.8, 0.5, 0.0]
	for i in range(7):
		e.set("glow_levels/%d" % (i + 1), levels[i])
	# 雾：保留原版风格，只把过浓的密度收到有层次的区间
	if e.fog_density > 0.9:
		e.fog_density = 0.35
	print("LOOK_ENV before(%s) after(tone=%d glow=%s fog=%.2f)" % [before, e.tonemap_mode, str(e.glow_enabled), e.fog_density])

func _apply_camera() -> void:
	var p = layer.player
	if p == null:
		return
	var arm = p.get("arm")
	if arm is SpringArm3D:
		(arm as SpringArm3D).margin = ARM_MARGIN
	var cam = p.get("camera")
	if cam is Camera3D:
		var c := cam as Camera3D
		c.fov = CAM_FOV
		c.near = CAM_NEAR
		print("LOOK_CAM set fov=%.1f near=%.2f arm_margin=%.2f" % [c.fov, c.near, ARM_MARGIN])

## 水面：保留原 shader 全部逻辑，只替换为补了法线/菲涅尔/镜面的增强版。
func _apply_water() -> void:
	var shader = load("res://shaders/coastal_water_enhanced.gdshader")
	if shader == null:
		print("LOOK_WATER shader missing")
		return
	var count := 0
	for nm in ["BackgroundOcean", "BayConnectedRivers", "CoastalWaterContinuity130"]:
		var n = layer.world.find_child(nm, true, false)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var src := mi.get_active_material(0)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		if src is ShaderMaterial and (src as ShaderMaterial).shader != null:
			var sm := src as ShaderMaterial
			for u in sm.shader.get_shader_uniform_list():
				var key := str(u.name)
				var v = sm.get_shader_parameter(key)
				if v != null:
					mat.set_shader_parameter(key, v)
		mi.material_override = mat
		count += 1
		if _water_normal >= 0.0:
			mat.set_shader_parameter("wave_normal_strength", _water_normal)
		if _water_fresnel >= 0.0:
			mat.set_shader_parameter("fresnel_strength", _water_fresnel)
		if _water_sky >= 0.0:
			mat.set_shader_parameter("sky_reflection", _water_sky)
	print("LOOK_WATER applied=%d normal=%.3f fresnel=%.2f sky=%.2f" % [count, _water_normal, _water_fresnel, _water_sky])

func _apply_shadow() -> void:
	var sun = layer.main.get("sun")
	if sun is DirectionalLight3D:
		var s := sun as DirectionalLight3D
		s.directional_shadow_max_distance = SHADOW_DIST
		print("LOOK_SUN shadow_dist=%.0f energy=%.2f" % [s.directional_shadow_max_distance, s.light_energy])

## P4：射线确认的远、近景地形，默认开启；--terrain=0 恢复原材质。
func _apply_terrain() -> void:
	if not _terrain_enabled:
		print("LOOK_TERRAIN disabled")
		return
	var appearance: Node = load("res://scripts/renewal/terrain_appearance.gd").new()
	appearance.name = "TerrainAppearance"
	add_child(appearance)
	appearance.setup(layer)

## 物理插值：尝试启用并复核。原版控制器会把 physics_interpolation_mode 锁回 OFF，
## 此处如实记录结果，不假装生效。
func _apply_interpolation() -> void:
	var p = layer.player
	if p is Node3D:
		_set_interp(p as Node3D, 0)
	_interp_check_at = Time.get_ticks_msec() + 2000

func _check_interp() -> void:
	var p = layer.player
	if p is Node3D:
		print("LOOK_INTERP requested=%d actual=%d (原版控制器可能锁定为 OFF)" % [
			Node3D.PHYSICS_INTERPOLATION_MODE_ON, int((p as Node3D).physics_interpolation_mode)])
	_interp_checked = true

func _process(_delta: float) -> void:
	if not _interp_checked and _interp_check_at > 0 and Time.get_ticks_msec() >= _interp_check_at:
		_check_interp()

func _set_interp(n: Node3D, depth: int) -> void:
	n.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON
	if depth >= 4:
		return
	for c in n.get_children():
		if c is Node3D:
			_set_interp(c as Node3D, depth + 1)
