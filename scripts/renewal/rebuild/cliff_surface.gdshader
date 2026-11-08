shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
varying vec3 wn;
float hash3(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise3(vec3 p){
 vec3 i=floor(p);vec3 f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 float broad=noise3(wp*.24);
 float fine=noise3(wp*2.8);
 float streak=noise3(wp*vec3(1.1,.065,1.1));
 vec3 rock=mix(vec3(.20,.215,.19),vec3(.40,.40,.35),broad*.7+fine*.3);
 rock*=.84+.22*streak;
 float moss=smoothstep(.5,.85,wn.y)*smoothstep(.45,.72,noise3(wp*.5));
 ALBEDO=mix(rock,vec3(.12,.19,.07),moss*.65);
 ROUGHNESS=.94;
}
