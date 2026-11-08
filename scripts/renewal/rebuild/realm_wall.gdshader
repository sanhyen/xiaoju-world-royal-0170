shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float stone_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),
		mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 grain_pos = vec2(world_pos.x*.81+world_pos.z*.74,world_pos.y);
	float limewash = stone_noise(grain_pos*.63);
	float fine = (stone_noise(grain_pos*16.0)-.5)*(1.0-smoothstep(.035,.17,length(fwidth(grain_pos))));
	float base_height = world_pos.y >= 63.9 ? 64.0 : 48.0;
	float weathering = 1.0-smoothstep(.08,1.78,world_pos.y-base_height+limewash*.38);
	vec3 lime = mix(vec3(.63,.62,.54),vec3(.76,.75,.67),limewash);
	vec3 damp = vec3(.52,.57,.49);
	ALBEDO = mix(lime,damp,.35*weathering)+fine*.043;
	ROUGHNESS = .92;
}
