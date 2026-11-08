shader_type spatial;
render_mode cull_disabled, blend_mix;
varying float petal_fade;
void vertex(){
 float progress=fract(TIME*.065+INSTANCE_CUSTOM.r);
 VERTEX.y-=progress*6.0;
 VERTEX.x+=.5*sin(TIME*.8+INSTANCE_CUSTOM.r*30.0);
 VERTEX.z+=.25*cos(TIME*.6+INSTANCE_CUSTOM.r*20.0);
 petal_fade=smoothstep(0.0,.08,progress)*(1.0-smoothstep(.88,1.0,progress));
}
void fragment(){ALBEDO=vec3(.92,.61,.70);ALPHA=.85*petal_fade;ROUGHNESS=.85;}
