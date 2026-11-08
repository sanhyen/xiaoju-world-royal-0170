shader_type spatial;
render_mode cull_disabled, blend_mix;
varying vec3 water_world;
void vertex(){
 water_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 VERTEX.y+=.009*sin(water_world.x*2.1+TIME*1.3)+.006*cos(water_world.z*2.7-TIME*1.1);
}
void fragment(){
 float wave=.5+.5*sin(water_world.x*3.0+water_world.z*4.0-TIME*1.4);
 ALBEDO=mix(vec3(.22,.53,.51),vec3(.45,.72,.67),wave*.42);
 ALPHA=.52;ROUGHNESS=.20;SPECULAR=.60;
}
