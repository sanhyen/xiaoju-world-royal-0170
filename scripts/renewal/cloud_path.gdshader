shader_type spatial;
render_mode cull_disabled;
void fragment(){
 vec2 p=UV;float swirls=sin(p.x*.8+sin(p.y*.65+TIME*.10)*2.0)*sin(p.y*1.4-p.x*.25);
 vec3 cloud=mix(vec3(.54,.69,.64),vec3(.81,.87,.79),swirls*.5+.5);
 float vein=pow(1.0-abs(sin(p.y*1.1+sin(p.x*.32)*2.0)),12.0);
 ALBEDO=mix(cloud,vec3(.82,.87,.64),vein*.45);ROUGHNESS=.8;
 EMISSION=vec3(.15,.28,.22)*vein*.12;
}
