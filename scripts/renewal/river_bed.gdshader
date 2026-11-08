shader_type spatial;
render_mode cull_disabled;
varying vec2 river_detail;
float hash(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){river_detail=COLOR.rg;}
void fragment(){
 vec2 p=UV*3.2,id=floor(p),q=fract(p)-.5;
 float seed=hash(id);
 vec2 jitter=vec2(seed,hash(id+47.1))*.28-.14;
 float pebble=1.0-smoothstep(.14+seed*.04,.25+seed*.04,length((q-jitter)*vec2(1.0,1.4)));
 vec3 sand=mix(vec3(.44,.42,.31),vec3(.57,.54,.40),noise(UV*.73));
 vec3 stones=mix(vec3(.35,.37,.32),vec3(.58,.57,.48),seed);
 vec3 bed=mix(sand,stones,pebble*.67);
 vec3 soil=mix(vec3(.38,.37,.26),vec3(.48,.45,.31),noise(UV*.4));
 vec3 grass=mix(vec3(.36,.43,.29),vec3(.46,.51,.34),noise(UV*.24));
 ALBEDO=mix(bed,soil,smoothstep(.13,.60,river_detail.y));
 ALBEDO=mix(ALBEDO,grass,smoothstep(.63,1.0,river_detail.y));
 ROUGHNESS=.94;
}
