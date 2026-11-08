shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_prepass_alpha;
varying vec2 cloth_uv;
void vertex() {
    cloth_uv=UV;
    float free_edge=1.0-UV.y;
    VERTEX.x+=sin(TIME*0.7+VERTEX.y*1.5)*0.065*free_edge;
    VERTEX.z+=sin(TIME*0.9+VERTEX.y*2.1)*0.045*free_edge;
}
void fragment() {
    float weave=sin(cloth_uv.x*260.0)*sin(cloth_uv.y*180.0);
    ALBEDO=vec3(0.97,0.95,0.91)*(0.97+weave*0.02);
    ROUGHNESS=1.0;
    SPECULAR=0.04;
    ALPHA=0.43+weave*0.06;
}
