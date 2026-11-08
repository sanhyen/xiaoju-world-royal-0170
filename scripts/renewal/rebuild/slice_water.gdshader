shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	vec2 p = world_pos.xz;
	float swell = sin(dot(p,vec2(.53,.34))+TIME*.84);
	float lace = sin(dot(p,vec2(-.28,1.25))-TIME*.67);
	float wave = swell*.64+lace*.36;
	float fresnel = pow(1.0-clamp(abs(dot(normalize(NORMAL),VIEW)),0.0,1.0),3.0);
	float shimmer = smoothstep(.72,.98,wave)*(0.42+0.58*fresnel);
	float aa = length(fwidth(p));
	shimmer *= 1.0-smoothstep(.20,.73,aa);
	vec3 depth = mix(vec3(.06,.19,.17),vec3(.12,.28,.26),wave*.11+.5);
	ALBEDO = mix(depth,vec3(.34,.53,.51),fresnel*.26)+vec3(.22,.28,.24)*shimmer*.18;
	ROUGHNESS = .29;
	METALLIC = .10;
	NORMAL = normalize(NORMAL+vec3(wave*.036,0.0,sin(p.x*1.64+TIME)*.026));
}
