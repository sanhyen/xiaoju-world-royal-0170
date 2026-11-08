shader_type spatial;
render_mode diffuse_burley;
uniform int surface_kind = 0;
varying vec3 world_point;
varying vec3 world_normal;
vec3 linear_color(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 p = world_point;
	float grain = sin(p.x * 71.0 + p.y * 17.0 + sin(p.z * 4.1) * 2.5);
	float filter = 1.0 - smoothstep(0.006, 0.027, length(fwidth(p)));
	grain *= filter;
	float tone = 1.0;
	float roughness = 0.87;
	if (surface_kind == 1) { // wood: restrained long grain, not noisy photographic texture
		float streak = sin(p.z * 58.0 + sin(p.x * 0.8) * 2.3 + p.y * 36.0);
		tone = 0.98 + streak * filter * 0.018 + grain * 0.004;
		roughness = 0.74;
	} else if (surface_kind == 2) { // fine plaster
		tone = 0.995 + grain * 0.004;
	} else if (surface_kind == 3) { // slate roof
		float rows = smoothstep(0.94, 0.99, fract(p.z * 1.7));
		tone = 0.96 - rows * 0.09 + sin(floor(p.z * 1.7) * 1.37) * 0.035;
		roughness = 0.66;
	} else if (surface_kind == 4) { // stone
		tone = 0.985 + grain * 0.008 + sin(p.x * 2.0 + p.z * 2.7) * 0.012;
		roughness = 0.91;
	} else if (surface_kind == 5) { // fabric weave
		tone = 0.99 + sin(p.x * 160.0) * sin(p.z * 160.0) * filter * 0.009;
		roughness = 1.0;
	}
	if (surface_kind == 6) {
		float fiber=sin(p.z*128.0+sin(p.x*11.0)*0.7);
		float courses=smoothstep(0.85,0.98,fract(p.x*2.4));
		tone=0.98+fiber*filter*0.055-courses*0.055;
		roughness=0.92;
	}
	if(surface_kind==7){
		vec2 uv=vec2(dot(p.xz,abs(world_normal.zx)),p.y);float row=floor(uv.y/.22);vec2 cell=vec2((uv.x+mod(row,2.0)*.30)/.60,uv.y/.22);vec2 aa=max(fwidth(cell),vec2(.001));vec2 edge=min(fract(cell),1.0-fract(cell));vec2 inside=smoothstep(vec2(.025)-aa,vec2(.025)+aa,edge);float seam=(1.0-min(inside.x,inside.y))*(1.0-smoothstep(.12,.6,max(aa.x,aa.y)));tone=1.0-seam*.27+sin(floor(cell.x)*2.0+row)*.04;roughness=.96;
	}else if(surface_kind==8){float line=abs(sin(p.y*8.5));tone=.88+smoothstep(.05,.20,line)*.12;roughness=.88;
	}else if(surface_kind==9){tone=.96+sin(p.y*11.0)*.025+sin(p.x*19.0)*.018;roughness=.92;
	}else if(surface_kind==10){tone=.98+sin(p.y*4.2+p.x*.7)*.018;roughness=.99;}
	ALBEDO = (OUTPUT_IS_SRGB ? COLOR.rgb : linear_color(COLOR.rgb)) * tone;
	ROUGHNESS = roughness;
	SPECULAR = surface_kind == 1 ? 0.25 : 0.13;
}
