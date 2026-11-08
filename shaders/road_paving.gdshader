shader_type spatial;
// 道路重建（P3）
//
// 原版路面的 path_axis 是材质级 uniform：一个 cell 里几十条路共用一个方向值，
// 斜路上的砖缝会横着走；而且没有 UV，做不了路缘、磨损、湿痕。
// 重建后的 mesh 带 UV：u 沿路走、v 横跨路，砖缝天然垂直于路。

// 新路面比原路面只高 0.018 m，会整片落在原路面投下的自阴影里，无论怎么调
// base_col 都渲染成沥青黑（实测：改成品红会亮，说明是光照被压掉而不是材质没上）。
// 直接用无光照输出：亮度由材质与砖缝控制，稳定可预期。
render_mode blend_mix, cull_disabled, unshaded;

uniform vec3 base_col : source_color = vec3(0.42, 0.39, 0.33);
uniform vec3 curb_col : source_color = vec3(0.24, 0.24, 0.26);
uniform vec3 foam_col : source_color = vec3(0.86, 0.90, 0.88);
uniform float is_gravel = 0.0;    // 1 = 碎石土径（景观步道）
uniform float brick_w = 1.56;
uniform float brick_h = 0.78;
uniform float seam_strength = 0.22;
uniform float wet_strength = 0.0; // 由顶点色 a 控制，这里只给倍率

varying vec2 v_uv;
varying vec2 v_metric;
varying vec2 v_ground;
varying float v_wet;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stone_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),
		mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	v_uv = UV;
	v_metric = UV2;
	v_ground = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
	v_wet = COLOR.a;
	// 路面是水平带，但挤出时的绕序在弯道处会让法线偏斜，光照忽明忽暗。
	// 直接锁死朝上，亮度就只由材质和砖缝决定。
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec2 uv = v_uv;
	float lat = uv.y * 2.0 - 1.0;         // -1 左缘 .. +1 右缘
	float al = abs(lat);
	float mottling = stone_noise(v_ground*.39)-.5;
	float grain = (stone_noise(v_ground*15.0)-.5)*(1.0-smoothstep(.04,.24,length(fwidth(v_ground))));

	if (is_gravel > 0.5) {
		// 碎石土径：无砖缝，细噪点 + 两条轻微车辙
		vec3 c = base_col * (1.0+mottling*.13+grain*.11);
		float shoulder = smoothstep(.75,1.0,al);
		c = mix(c, c*vec3(.95,.96,.90),shoulder*.55);
		ALBEDO = c;
		ROUGHNESS = 0.97;
	} else {
		// 方砖：沿路方向的错缝排列
		float row = floor(v_metric.y / brick_h);
		float offset = mod(row, 2.0) * 0.5;
		vec2 cell = vec2((v_metric.x + offset * brick_w) / brick_w, v_metric.y / brick_h);
		vec2 f = fract(cell);
		float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float aa = clamp(length(fwidth(cell)),.005,.18);
		float edge = (1.0 - smoothstep(.016,.034+aa,seam))*(1.0-smoothstep(.035,.23,aa));
		float tint = hash21(floor(cell));
		vec3 c = base_col * (.976+tint*.048+mottling*.087+grain*.055);
		c *= 1.0 - edge * seam_strength;

		// 路缘石：|v| > 0.86 的一圈，略偏冷灰、更粗糙
		float curb = smoothstep(0.82, 0.92, al);
		c = mix(c, curb_col * (0.95 + tint * 0.10), curb * 0.22);

		// 中心磨损：常走的地方被踩亮
		float worn = 1.0 - smoothstep(0.0, 0.45, al);
		c *= 1.0 + worn * 0.035;

		ALBEDO = c;
		ROUGHNESS = mix(0.92, 0.99, curb);
	}

	// 近水湿痕：顶点色 a 编码「到最近水体距离」，8 m 内变深变光
	float wet = (1.0 - smoothstep(0.0, 1.0, v_wet)) * wet_strength;
	ALBEDO *= mix(1.0, 0.80, wet);
	ROUGHNESS = mix(ROUGHNESS, 0.40, wet);
	SPECULAR = mix(0.35, 0.62, wet);
	METALLIC = 0.0;
}
