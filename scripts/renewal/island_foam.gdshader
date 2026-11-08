shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_never;
varying vec3 foam_position;
void vertex() {
    foam_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    VERTEX.y += sin(TIME*1.5+VERTEX.x*0.8+VERTEX.z*0.7)*0.025;
}
void fragment() {
    float broken = 0.5+0.5*sin(foam_position.x*2.7+sin(foam_position.z*2.1)+TIME*1.8);
    ALBEDO = vec3(0.69,0.84,0.83);
    ALPHA = 0.18+broken*0.35;
}
