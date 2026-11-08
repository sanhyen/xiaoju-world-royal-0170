extends Node
## P4：同时覆盖射线确认的 FarStrata 远景与流式 TerrainPartition 近景。
## 只替换节点 surface override，原 mesh、顶点色、材质资源和碰撞均不写入。

const FAR_SHADER = preload("res://scripts/renewal/terrain_far.gdshader")
const SLOPE_CODE = """
uniform float p4_strength = 0.90;
uniform bool p4_debug = false;
vec3 p4_rock(vec3 color, vec3 world_pos, vec3 world_n, float retaining, float sand) {
    float slope_k = 1.0 - abs(normalize(world_n).y);
    // 1-cos(25°)=0.09369，1-cos(35°)=0.18085。
    float w = smoothstep(0.09369, 0.18085, slope_k);
    // FarStrata 将自然山坡画成水平台面和竖直崖壁。只排除 alpha 标记的人工挡墙，
    // 不能把所有竖直面排除，否则远景山体再次完全不生效。
    w *= (1.0-retaining)*(1.0-sand)*step(4.0,world_pos.y);
    vec3 rock = vec3(0.170,0.230,0.340);
    float lum = dot(color,vec3(0.299,0.587,0.114));
    rock *= lum / dot(rock,vec3(0.299,0.587,0.114));
    vec3 result = mix(color,rock,w*p4_strength);
    float footprint = max(length(fwidth(world_pos.xz)),0.001);
    float band_fade = clamp(1.0-footprint*12.0,0.0,1.0);
    float band = sin(world_pos.y*3.1+sin(world_pos.x*0.09)*0.8);
    result *= 1.0+band*0.08*smoothstep(0.6,1.0,w)*band_fade;
    return result;
}
"""

var layer: Node
var _cache: Dictionary = {}
var _near_shader: Shader
var _seen: Dictionary = {}
var _last_events := -1
var _next_scan := 0

func setup(owner_layer: Node) -> void:
	layer = owner_layer
	var original: Shader = load("res://assets/materials/terrain_strata.gdshader")
	_near_shader = Shader.new()
	var code := original.code
	code = code.replace("void vertex()", SLOPE_CODE + "\nvoid vertex()")
	var end := code.rfind("}")
	code = code.insert(end, "\nALBEDO = p4_rock(ALBEDO,world_position,world_normal,retaining,sand);\nif(p4_debug && abs(world_normal.y)<0.81915 && retaining<0.1 && sand<0.1 && world_position.y>4.0){ALBEDO=vec3(0.0);EMISSION=vec3(1.0,0.0,1.0);}\n")
	_near_shader.code = code
	_scan()

func _process(_delta: float) -> void:
	if layer == null or layer.stream == null or Time.get_ticks_msec() < _next_scan:
		return
	_next_scan = Time.get_ticks_msec() + 750
	var events := int(layer.stream.get("load_events"))
	if events != _last_events:
		_last_events = events
		_scan()

func _scan() -> void:
	var added := 0
	for n in layer.world.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _seen.has(mi.get_instance_id()):
			continue
		var far := str(mi.name).begins_with("FarStrata_")
		var near := str(mi.name).begins_with("TerrainPartition110_") or str(mi.name).begins_with("TerrainStrata_")
		if not far and not near:
			continue
		var installed := 0
		for surface in range(mi.mesh.get_surface_count()):
			var source := mi.get_active_material(surface)
			if source == null:
				continue
			var key := source.get_instance_id()
			if not _cache.has(key):
				var material := ShaderMaterial.new()
				if far and source is StandardMaterial3D:
					material.shader = FAR_SHADER
					var src := source as StandardMaterial3D
					material.set_shader_parameter("source_albedo", src.albedo_color)
					material.set_shader_parameter("source_roughness", src.roughness)
					material.set_shader_parameter("source_specular", src.metallic_specular)
				elif near and source is ShaderMaterial:
					material.shader = _near_shader
					var src := source as ShaderMaterial
					for uniform in src.shader.get_shader_uniform_list():
						var value = src.get_shader_parameter(uniform.name)
						if value != null:
							material.set_shader_parameter(uniform.name, value)
				else:
					continue
				_cache[key] = material
			mi.set_surface_override_material(surface, _cache[key])
			added += 1
			installed += 1
		# 原版 FarStrata 将 StandardMaterial3D 放在节点 material_override；
		# 它优先于 surface override，所有 surface 准备齐全后才解除这一层。
		if installed == mi.mesh.get_surface_count():
			mi.material_override = null
		_seen[mi.get_instance_id()] = true
	if added > 0:
		print("P4_APPLIED surfaces=%d nodes=%d materials=%d" % [added, _seen.size(), _cache.size()])
