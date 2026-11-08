shader_type spatial;
// 近岸水面带（P2 / P5 共用）
//
// 原版主海面是一张 1480 m 的粗网格，近岸什么细节都放不下；而近岸是玩家停留
// 最久的地方。这条带子沿岸线生成，UV 的 u 是沿岸距离、v 是离岸距离，
// 于是「离岸多远」变成可直接用的参数：透底、分色、泡沫、涌浪全部按 v 走。
//
// P5 的礁盘复用同一个材质，靠 is_reef 分支切到椭圆归一化半径判定。

render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform float qa_time = -1.0;
float water_time() { return qa_time < 0.0 ? TIME : qa_time; }

uniform vec3 shallow_col : source_color = vec3(0.36, 0.72, 0.70);
uniform vec3 mid_col : source_color = vec3(0.22, 0.55, 0.62);
uniform vec3 deep_col : source_color = vec3(0.13, 0.38, 0.52);
uniform vec3 foam_col : source_color = vec3(0.86, 0.90, 0.88);
uniform vec3 reef_shallow : source_color = vec3(0.42, 0.86, 0.82);
uniform vec3 reef_deep : source_color = vec3(0.20, 0.66, 0.74);

uniform float foam_width = 0.13;    // v 方向泡沫带宽（0.13 × 30 m ≈ 3.9 m）
uniform float alpha_near = 0.30;    // 岸线透明度
uniform float alpha_far = 0.94;     // 30 m 外透明度
uniform float swell_amp = 1.0;      // 涌浪幅度倍率

// 礁盘：xy = 中心，zw = 半径
uniform vec4 reef_ellipse = vec4(232.5, 452.5, 77.5, 47.5);
uniform float is_reef = 0.0;
uniform bool natural_coral = false;

varying vec2 v_uv;
varying vec3 v_world;
varying float v_under;   // 顶点处是否在水下（0/1）

void vertex() {
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_under = COLOR.a;
	// 涌浪：波长 > 15 m，总幅度不超过 8 cm，避免穿插地形
	float swell = sin(UV.x * 0.42 - water_time() * 0.55) * 0.045
		+ sin(UV.x * 0.17 + UV.y * 2.1 - water_time() * 0.31) * 0.028;
	VERTEX.y += swell * swell_amp * (1.0 - UV.y * 0.6) * v_under;
}

void fragment() {
	if (v_under < 0.5) {
		discard;
	}
	float u = v_uv.x;
	float v = v_uv.y;

	float depth_fade = smoothstep(0.0, 0.55, v);
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.35, v));
	col = mix(col, deep_col, smoothstep(0.30, 0.85, v));
	float a = mix(alpha_near, alpha_far, depth_fade);

	if (is_reef > 0.5) {
		// 礁盘：按椭圆归一化半径给透明度与颜色，让水下珊瑚沙透出来
		vec2 d = (v_world.xz - reef_ellipse.xy) / reef_ellipse.zw;
		float r = length(d);
		float rd = smoothstep(0.0, 0.85, r);
		a = mix(0.24, 0.58, rd);
		col = mix(reef_shallow, reef_deep, rd);
		float coral = sin(u * 3.1) * sin(v * 5.7);
		col *= 1.0 + coral * 0.10;
		col += vec3(0.018,-0.003,-0.015)*coral;
		// 礁盘边缘的泡沫环：只留 r ∈ [0.86, 1.06] 的一圈。
		// 原来写成 1-smoothstep(0.86,1,r)，r 小时 rim=1，泡沫反而铺满礁盘内部。
		float rim = smoothstep(0.86, 1.0, r) * (1.0 - smoothstep(1.02, 1.12, r));
		float rn = sin(u * 9.1 + water_time() * 0.5) * sin(v * 13.0 - water_time() * 0.3);
		col = mix(col, foam_col, rim * (0.35 + 0.35 * smoothstep(-0.3, 0.6, rn)));
		if (natural_coral) {
			vec2 p = v_world.xz;
			float variation = sin(p.x*.14 + sin(p.y*.21))*sin(p.y*.19 - sin(p.x*.27));
			float uneven = smoothstep(.18,.93,r+variation*.06);
			col = mix(vec3(.34,.66,.59),vec3(.13,.42,.50),uneven);
			col += .036*variation;
			a = mix(.26,.56,uneven);
			float edge = r + variation*.041;
			float foam = smoothstep(.80,.93,edge)*(1.0-smoothstep(.94,1.05,edge));
			float breakup = smoothstep(.12,.84,sin(p.x*.21+p.y*.25+TIME*.26)*.5+.5);
			col = mix(col,foam_col,foam*breakup*.25);
		}
	} else {
		// 岸线泡沫：用 v 而不是世界坐标，岸线不规则处也不会错位
		float front = foam_width*(0.90+0.35*sin(water_time()*0.65+u*0.38));
		float band = 1.0 - smoothstep(0.0, front, v);
		float noise = sin(u * 7.3 + water_time() * 0.6) * sin(u * 2.1 - water_time() * 0.35);
		float swash = smoothstep(-0.25, 0.55, noise);
		float foam = band * (0.55 + 0.45 * swash);
		col = mix(col, foam_col, foam * 0.88);
	}

	// 外缘渐隐：近岸带只有 30 m 宽，若在 v=1 处仍然不透明，会与原版海面
	// 形成一条明显的色带断裂。让它在 18~30 m 之间淡出，交给原版海面接管。
	float edge_fade = 1.0 - smoothstep(0.60, 1.0, v);
	ALBEDO = col;
	ALPHA = a * edge_fade;
	ROUGHNESS = natural_coral ? mix(.33,.55,depth_fade) : mix(0.10, 0.42, depth_fade);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	if (!natural_coral) {
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
}
