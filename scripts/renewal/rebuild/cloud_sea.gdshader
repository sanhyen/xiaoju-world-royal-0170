shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float density = .72;
varying vec3 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float noise2(vec2 p) {
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
	vec2 travel = vec2(TIME*.072,-TIME*.028);
	vec2 p = world_pos.xz*vec2(.071,.042)+travel;
	float broad = noise2(p+noise2(p*.52));
	float lace = noise2(p*2.5+vec2(3.2,-1.1));
	float wisp = noise2(p*5.2-travel*.76);
	float coverage = broad*.67+lace*.23+wisp*.10;
	float edge = 1.0-smoothstep(.23,.51,length(UV-vec2(.5)));
	ALBEDO = mix(vec3(.53,.69,.76),vec3(.95,.98,.97),smoothstep(.25,.74,coverage));
	ALPHA = density*edge*smoothstep(.23,.70,coverage);
}
