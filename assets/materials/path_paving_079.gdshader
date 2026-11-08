shader_type spatial;
render_mode diffuse_burley;
uniform vec2 path_axis = vec2(0.0, 1.0);
uniform float seam_strength = 0.16;
varying vec3 world_point;
vec3 linear_color(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 sideways = vec2(-path_axis.y, path_axis.x);
	vec2 meters = vec2(dot(world_point.xz, path_axis), dot(world_point.xz, sideways));
	float row = floor(meters.y / 0.78);
	vec2 paving = vec2((meters.x + mod(row, 2.0) * 0.78) / 1.56, meters.y / 0.78);
	vec2 cells = floor(paving);
	vec2 local = fract(paving);
	vec2 edge = min(local, vec2(1.0) - local);
	vec2 aa = max(fwidth(paving), vec2(0.0001));
	vec2 interior = smoothstep(vec2(0.009) - aa, vec2(0.009) + aa, edge);
	float resolved = 1.0 - smoothstep(0.16, 0.65, max(aa.x, aa.y));
	float seam = (1.0 - min(interior.x, interior.y)) * resolved;
	float variation = sin(cells.x * 1.7 + cells.y * 2.3) * sin(cells.x * 0.71 - cells.y * 0.53);
	float tone = 0.98 + variation * 0.035 * resolved - seam * seam_strength;
	ALBEDO = (OUTPUT_IS_SRGB ? COLOR.rgb : linear_color(COLOR.rgb)) * tone;
	ROUGHNESS = 0.96;
	SPECULAR = 0.10;
}
