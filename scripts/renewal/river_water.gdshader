shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying vec4 detail;
varying vec2 flow;
varying vec2 pos;
void vertex(){
 detail=COLOR; flow=UV2; pos=UV;
 VERTEX.y+=(sin(dot(UV,UV2)*2.1-TIME*1.7)+cos(UV.x*1.7+UV.y*.8-TIME*.7))*.009*COLOR.a;
}
void fragment(){
 float ripple=sin(dot(pos,flow)*4.0-TIME*1.8+sin(pos.y*1.6))*.5+.5;
 float edge=(1.0-smoothstep(.03,.25,detail.r))*detail.a;
 vec3 shallow=vec3(.30,.63,.57);vec3 deep=vec3(.13,.40,.39);
 ALBEDO=mix(shallow,deep,smoothstep(.05,.95,detail.r));
 ALBEDO=mix(ALBEDO,vec3(.78,.88,.78),edge*.25*ripple);
 ROUGHNESS=.34;SPECULAR=.25;
 ALPHA=clamp(mix(.20,.53,detail.r)*detail.a,0.0,.58);
 NORMAL_MAP=vec3(.5+sin(dot(pos,flow)*3.0-TIME*1.8)*.018,.5+cos(pos.y*2.7+TIME)*.018,1.0);
}
