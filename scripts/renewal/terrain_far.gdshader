shader_type spatial;
render_mode cull_disabled, vertex_lighting;
// FarStrata 原材质：per-vertex lighting、sRGB 顶点色、roughness .98、specular .05。
uniform vec4 source_albedo : source_color = vec4(1.0);
uniform float source_roughness = 0.98;
uniform float source_specular = 0.05;
uniform float p4_strength = 0.90;
uniform bool p4_debug = false;
varying vec3 p4_position;
varying flat vec3 p4_normal;
varying vec4 p4_color;

void vertex() {
    p4_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    p4_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
    p4_color = COLOR;
    if (!OUTPUT_IS_SRGB) {
        p4_color.rgb = mix(p4_color.rgb/12.92,pow((p4_color.rgb+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),p4_color.rgb));
    }
    ROUGHNESS = source_roughness;
}

void fragment() {
    vec3 base = p4_color.rgb*source_albedo.rgb;
    float slope_k = 1.0-abs(normalize(p4_normal).y);
    float side = 1.0-smoothstep(0.25,0.8,abs(p4_normal.y));
    float retaining = (1.0-smoothstep(0.75,0.85,p4_color.a))*side;
    float sand = (1.0-side)*smoothstep(0.02,0.13,p4_color.r-p4_color.b)*(1.0-smoothstep(1.6,4.0,p4_position.y));
    float w = smoothstep(0.09369,0.18085,slope_k);
    w *= (1.0-retaining)*(1.0-sand)*step(4.0,p4_position.y);
    vec3 rock = vec3(0.170,0.230,0.340);
    rock *= dot(base,vec3(0.299,0.587,0.114))/dot(rock,vec3(0.299,0.587,0.114));
    ALBEDO = mix(base,rock,w*p4_strength);
    float footprint = max(length(fwidth(p4_position.xz)),0.001);
    float band_fade = clamp(1.0-footprint*12.0,0.0,1.0);
    float band = sin(p4_position.y*3.1+sin(p4_position.x*0.09)*0.8);
    ALBEDO *= 1.0+band*0.08*smoothstep(0.6,1.0,w)*band_fade;
    ROUGHNESS = source_roughness;
    SPECULAR = source_specular;
    if(p4_debug && abs(p4_normal.y)<0.81915 && retaining<0.1 && sand<0.1 && p4_position.y>4.0) {
        ALBEDO = vec3(0.0);
        EMISSION = vec3(1.0,0.0,1.0);
    }
}
