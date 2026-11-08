shader_type spatial;
render_mode cull_disabled;
void fragment(){
 float threads=sin(UV.x*29.0+sin(UV.y*28.0-TIME*5.0)*2.0+sin(UV.x*19.0)*3.0)*.5+.5;
 float pulse=sin(UV.y*39.0-TIME*8.0+sin(UV.x*17.0)*2.0)*.5+.5;
 float foam=smoothstep(.35,.85,threads*pulse);
 ALBEDO=mix(vec3(.32,.45,.42),vec3(.72,.79,.75),foam*.7+threads*.18);
 ROUGHNESS=.38;
}
