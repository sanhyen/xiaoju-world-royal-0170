shader_type spatial;
render_mode cull_disabled;
// 地形坡度混合增强版：完整保留原 terrain_strata.gdshader 全部逻辑，
// 仅在 fragment 末尾追加"坡度三段分色 + 岩层条纹 + 海拔冷化 + 草甸全域斑块 + 草叶细节"。
// 所有新增项均受 uniform 控制，可单独关闭做 A/B。
uniform bool bay_enabled=false;
uniform bool scenic_biomes_enabled=false;
uniform sampler2D scenic_biome_field: source_color, filter_linear, repeat_disable;
uniform int shore_count=0;
uniform vec2 shore_points[24];
float bay_shore(float x){
    float result=344.0;
    for(int i=0;i<23;i++){
        if(i>=shore_count-1)break;
        vec2 a=shore_points[i];vec2 b=shore_points[i+1];
        if(x>=a.x && x<=b.x){float t=clamp((x-a.x)/(b.x-a.x),0.0,1.0);t=t*t*(3.0-2.0*t);result=mix(a.y,b.y,t);break;}
    }
    return result;
}
uniform bool terrain_field_enabled110=false;
uniform sampler2D terrain_field110: filter_linear, repeat_disable;
uniform vec4 terrain_field_bounds110=vec4(-800.0,-800.0,1600.0,1600.0);
uniform vec2 terrain_field_size110=vec2(4096.0);
vec2 low_frequency_field110(vec2 p){
    vec2 t=(p-terrain_field_bounds110.xy)/terrain_field_bounds110.zw;
    if(!terrain_field_enabled110 || any(lessThan(t,vec2(0.0))) || any(greaterThan(t,vec2(1.0)))){
        return vec2(sin(p.x*0.81+sin(p.y*1.17))*sin(p.y*0.74),sin(p.x*0.087+sin(p.y*0.067)*1.4)*sin(p.y*0.104-p.x*0.027));
    }
    vec2 uv=(t*(terrain_field_size110-vec2(1.0))+vec2(0.5))/terrain_field_size110;
    return textureLod(terrain_field110,uv,0.0).rg;
}

// ===== 新增可调参数 =====
uniform bool slope_blend_enabled = true;
// v3 收敛后的强度：起点从 0.30 提到 0.42（约 25° 才起判），强度从 0.55 降到 0.42。
// v2 的问题是 15° 就开始泛灰，整个山坡都被染色。
uniform float slope_tint_strength = 0.30;
uniform float rock_band_strength = 1.0;
// 海拔冷化与草叶细节在 v3 里明确不做：前者和雾叠加后发灰，后者 2.28 m 网格承载不了
uniform float altitude_cool = 0.0;
uniform float meadow_reach = 1.0;
uniform float leaf_detail = 0.0;

varying vec3 world_position;
varying flat vec3 world_normal;
varying flat vec3 constant_base;
varying flat vec4 constant_masks;
varying flat float constant_sand;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
    // Every authored terrain triangle has identical color and normal at all corners.
    vec3 base=COLOR.rgb;
    if (!OUTPUT_IS_SRGB) { base=mix(base/12.92,pow((base+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),base)); }
    constant_base=base;
    float side=1.0-smoothstep(0.25,0.8,abs(world_normal.y));
    float retaining=(1.0-smoothstep(0.75,0.85,COLOR.a))*side;
    float neutral=abs(COLOR.g-COLOR.r)+abs(COLOR.r-COLOR.b);
    constant_masks=vec4(side,(1.0-side)*smoothstep(0.035,0.12,base.g-base.r),retaining,side*(1.0-retaining)*(1.0-smoothstep(0.035,0.085,neutral)));
    constant_sand=(1.0-side)*smoothstep(0.02,0.13,COLOR.r-COLOR.b);
}
void fragment() {
    vec3 base=constant_base;
    float side=constant_masks.x;
    vec2 p=world_position.xz;
    if (side>0.5) p=vec2(dot(world_position.xz,abs(world_normal.zx)),world_position.y);
    vec2 low_frequency=low_frequency_field110(p);
    float macro=low_frequency.x;
    float footprint=max(length(fwidth(p)),0.001);
    float grain_filter=clamp(1.0-footprint*28.0,0.0,1.0);
    float grain=0.0;
    if(grain_filter>0.0) grain=(sin(p.x*29.0)*sin(p.y*41.0))*grain_filter;
    // Broad low-contrast meadow islands; sand and exposed soil/rock retain their palette.
    float grass_mask=constant_masks.y*(1.0-smoothstep(278.0,314.0,world_position.z));
    float meadow=0.0;
    if(grass_mask>0.0) meadow=low_frequency.y;
    float dry=smoothstep(0.10,0.60,-meadow)*grass_mask;
    if(scenic_biomes_enabled && side<0.15){base=texture(scenic_biome_field,(world_position.xz-vec2(-672.0,-752.0))/vec2(1344.0,1504.0)).rgb;}
    vec3 ground=base*mix(vec3(1.0),vec3(1.07,0.97,0.92),dry);
    ALBEDO=ground*(1.0+macro*0.035+grain*0.02+meadow*grass_mask*0.10);
    // Opaque marker from actual existing road-cut faces; no new transparent layer.
    float retaining=constant_masks.z;
    float row=floor(p.y/0.38);
    vec2 blocks=vec2((p.x+mod(row,2.0)*0.55)/1.10,p.y/0.38);
    // Screen derivatives stay outside conditional masks, including primitive-edge helper lanes.
    vec2 aa=max(fwidth(blocks),vec2(0.0001));
    float resolved=1.0-smoothstep(0.14,0.55,max(aa.x,aa.y));
    if(retaining>0.0 && resolved>0.0){
        vec2 edge=min(fract(blocks),vec2(1.0)-fract(blocks));
        vec2 joint=smoothstep(vec2(0.018)-aa,vec2(0.018)+aa,edge);
        ALBEDO*=1.0-retaining*(1.0-min(joint.x,joint.y))*0.11*resolved;
    }
    // Natural rock relief keeps the existing grass cap and dirt geometry readable.
    // This is material variation on real exposed faces, not a replacement heightfield.
    float rock=constant_masks.w;
    float rock_resolved=1.0-smoothstep(0.10,0.38,footprint);
    if(rock>0.0 && rock_resolved>0.0){
        float course=p.y*0.92+sin(p.x*0.24)*0.14+sin(p.x*0.77)*0.06;
        float strata=sin(course*6.283185)*0.050+sin(course*2.1+p.x*0.29)*0.025;
        float cleft=1.0-smoothstep(0.018,0.055,abs(fract(course)-0.5));
        ALBEDO*=1.0+rock*(strata-cleft*0.075)*rock_resolved;
    }
    ROUGHNESS=mix(0.98,0.94,side);
    float sand=constant_sand*(1.0-smoothstep(1.6,4.0,world_position.y));
    float wet=0.0;
    if(bay_enabled && sand>0.0){
        wet=1.0-smoothstep(0.8,4.0,abs(world_position.z-bay_shore(world_position.x)));
        wet=max(wet,1.0-smoothstep(-2.3,-1.3,world_position.y))*sand;
    }
    ALBEDO=mix(ALBEDO,ALBEDO*vec3(0.83,0.81,0.76),wet*0.65);
    ROUGHNESS=mix(ROUGHNESS,mix(0.88,0.30,wet),sand);
    SPECULAR=mix(0.12,0.42,wet);

    // ================= 追加：坡度混合增强 =================
    if (slope_blend_enabled) {
        // 坡度：0=水平面，1=垂直面。world_normal 为逐三角形面法线，分色边界稳定不闪烁。
        float slope_k = clamp(1.0 - abs(world_normal.y), 0.0, 1.0);

        // 这张地图的「陡坡」绝大部分是梯田壁和人工挡土墙，不是自然山崖。
        // 它们接近垂直（slope_k ≈ 1），一旦染成岩石色，整片梯田会变成灰墙。
        // 所以显式排除接近垂直的面，只对 25°~65° 的自然坡生效。
        float not_wall = 1.0 - smoothstep(0.93, 0.995, slope_k);

        // 自然地表权重：排除挡土墙切面、沙滩、湿沙、垂直壁，并加海拔门槛。
        // v2 漏了 sand 与海拔，结果沙滩被整片染成灰绿——这是 v2 失败的直接原因。
        float natural = (1.0 - retaining) * (1.0 - sand) * (1.0 - wet) * not_wall
                      * step(2.0, world_position.y);

        // 只做「露土 / 露岩」两段，不动草地：草地交给原版生物群系分色，
        // 再叠一层绿只会把整体压暗。
        float w_rock  = smoothstep(0.26, 0.52, slope_k) * not_wall;
        float w_soil  = smoothstep(0.07, 0.24, slope_k) * (1.0 - w_rock);
        float w_grass = 0.0;

        float wg = 0.0;
        float ws = w_soil;
        float wr = w_rock;
        float wsum = wg + ws + wr;

        if (wsum > 0.001) {
            // 目标色按坡度加权后，只替换色相、保留原始亮度，避免破坏原版明暗关系
            vec3 grass_col = vec3(0.355, 0.520, 0.255);
            vec3 soil_col  = vec3(0.560, 0.475, 0.345);
            // v2 的岩石色偏暗，整面坡看着像湿泥；v3 去饱和并提亮
            vec3 rock_col  = vec3(0.600, 0.575, 0.535);
            vec3 target = (grass_col * wg + soil_col * ws + rock_col * wr) / wsum;
            float lum_o = dot(ALBEDO, vec3(0.299, 0.587, 0.114));
            float lum_t = max(dot(target, vec3(0.299, 0.587, 0.114)), 0.001);
            vec3 hue_shifted = target * (lum_o / lum_t);
            ALBEDO = mix(ALBEDO, hue_shifted, slope_tint_strength * natural * clamp(wsum, 0.0, 1.0));
        }

        // 陡坡岩层条纹：只在 >38° 的真陡壁上出现（w_rock > 0.6），
        // 强度 0.16（v2 的 0.24 太重），12 m 外衰减
        if (w_rock > 0.6 && rock_band_strength > 0.0) {
            float band_fade = clamp(1.0 - footprint * 12.0, 0.0, 1.0);
            if (band_fade > 0.0) {
                float band = sin(world_position.y * 3.1 + sin(world_position.x * 0.09) * 0.8);
                ALBEDO *= 1.0 + (band - 0.5) * 0.16 * w_rock * natural * rock_band_strength * band_fade;
            }
        }

        // 海拔冷化：高处向灰蓝偏移，形成远近层次
        if (altitude_cool > 0.0) {
            float alt = smoothstep(20.0, 140.0, world_position.y);
            if (alt > 0.0) {
                ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.88, 0.94, 1.03) + vec3(0.015, 0.022, 0.038),
                    alt * altitude_cool * natural);
            }
        }

        // 草甸斑块全域补充：原逻辑在 z>314 处完全关闭，这里补回低频起伏
        if (meadow_reach > 0.0) {
            float far_gate = smoothstep(278.0, 314.0, world_position.z);
            if (far_gate > 0.0) {
                float m2 = sin(world_position.x * 0.037 + sin(world_position.z * 0.029) * 1.6)
                         * sin(world_position.z * 0.033 - sin(world_position.x * 0.026) * 1.2);
                // 必须乘 constant_masks.y（绿地判定），这是 v2 把沙滩染绿的直接原因
                ALBEDO *= 1.0 + constant_masks.y * far_gate * m2 * 0.055 * meadow_reach;
            }
        }

        // 草叶级微观细节：只在近距离可见，远处衰减
        if (leaf_detail > 0.0 && constant_masks.y > 0.0) {
            float leaf_fade = clamp(1.0 - footprint * 20.0, 0.0, 1.0);
            if (leaf_fade > 0.0) {
                float leaf = sin(p.x * 17.0 + sin(p.y * 11.0) * 2.0) * sin(p.y * 19.0 - sin(p.x * 13.0));
                ALBEDO *= 1.0 + leaf * 0.055 * leaf_fade * constant_masks.y * natural * leaf_detail;
            }
        }
    }
}
