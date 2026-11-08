shader_type spatial;
render_mode cull_disabled;
varying vec3 world_point;
vec3 linear_color(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	vec2 p=world_point.xz;
	float region=1.0-smoothstep(65.0,110.0,length(p-vec2(-237.0,-169.0)));
	float patches=sin(p.x*0.16+sin(p.y*0.15)*1.9)*sin(p.y*0.19-p.x*0.05);
	float filter=1.0-smoothstep(0.02,0.06,length(fwidth(p)));
	float blades=sin(p.x*34.0+sin(p.y*7.0))*sin(p.y*31.0)*filter;
	vec3 color=COLOR.rgb;
	color=mix(color,color*vec3(1.07,1.025,0.96),region*smoothstep(0.2,0.85,patches)*0.45);
	color*=1.0+region*(patches*0.047+blades*0.005);
	ALBEDO=OUTPUT_IS_SRGB?color:linear_color(color);
	ROUGHNESS=0.98;SPECULAR=0.05;
}
