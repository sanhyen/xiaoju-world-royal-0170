shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled;
varying vec3 fall_position;
void vertex() {
    fall_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    float height_weight = smoothstep(-2.4,44.4,fall_position.y);
    float across = fall_position.x*0.72+fall_position.z*0.91;
    float strands = 0.5+0.5*sin(across*4.2+sin(across*1.7)*1.1);
    float flow = 0.5+0.5*sin(fall_position.y*2.8+TIME*8.0+across*0.5);
    vec3 top = vec3(0.65,0.80,0.84);
    vec3 bottom = vec3(0.25,0.49,0.55);
    ALBEDO = mix(bottom,top,height_weight)*(0.86+0.14*strands);
    ALPHA = mix(0.32,0.83,height_weight)*(0.68+0.22*strands+0.10*flow);
}
