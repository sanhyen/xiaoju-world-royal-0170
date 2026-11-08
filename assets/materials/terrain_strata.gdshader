shader_type spatial;
render_mode cull_disabled;
uniform bool bay_enabled=false;
uniform bool scenic_biomes_enabled=false;
uniform sampler2D scenic_biome_field: source_color, filter_linear, repeat_disable;
uniform int shore_count=0;
uniform vec2 shore_points[24];
float bay_shore(float x){
    float result=344.0;
    for(int i=0;i<23;i++){
        if(i>=shore_count-1)break;
        vec2 a=shore_points[i];vec2 b=shore_points[i+1];
        if(x>=a.x && x<=b.x){float t=clamp((x-a.x)/(b.x-a.x),0.0,1.0);t=t*t*(3.0-2.0*t);result=mix(a.y,b.y,t);break;}
    }
    return result;
}
uniform bool terrain_field_enabled110=false;
uniform sampler2D terrain_field110: filter_linear, repeat_disable;
uniform vec4 terrain_field_bounds110=vec4(-800.0,-800.0,1600.0,1600.0);
uniform vec2 terrain_field_size110=vec2(4096.0);
vec2 low_frequency_field110(vec2 p){
    vec2 t=(p-terrain_field_bounds110.xy)/terrain_field_bounds110.zw;
    if(!terrain_field_enabled110 || any(lessThan(t,vec2(0.0))) || any(greaterThan(t,vec2(1.0)))){
        return vec2(sin(p.x*0.81+sin(p.y*1.17))*sin(p.y*0.74),sin(p.x*0.087+sin(p.y*0.067)*1.4)*sin(p.y*0.104-p.x*0.027));
    }
    vec2 uv=(t*(terrain_field_size110-vec2(1.0))+vec2(0.5))/terrain_field_size110;
    return textureLod(terrain_field110,uv,0.0).rg;
}
varying vec3 world_position;
varying flat vec3 world_normal;
varying flat vec3 constant_base;
varying flat vec4 constant_masks;
varying flat float constant_sand;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
    // Every authored terrain triangle has identical color and normal at all corners.
    vec3 base=COLOR.rgb;
    if (!OUTPUT_IS_SRGB) { base=mix(base/12.92,pow((base+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),base)); }
    constant_base=base;
    float side=1.0-smoothstep(0.25,0.8,abs(world_normal.y));
    float retaining=(1.0-smoothstep(0.75,0.85,COLOR.a))*side;
    float neutral=abs(COLOR.g-COLOR.r)+abs(COLOR.r-COLOR.b);
    constant_masks=vec4(side,(1.0-side)*smoothstep(0.035,0.12,base.g-base.r),retaining,side*(1.0-retaining)*(1.0-smoothstep(0.035,0.085,neutral)));
    constant_sand=(1.0-side)*smoothstep(0.02,0.13,COLOR.r-COLOR.b);
}
void fragment() {
    vec3 base=constant_base;
    float side=constant_masks.x;
    vec2 p=world_position.xz;
    if (side>0.5) p=vec2(dot(world_position.xz,abs(world_normal.zx)),world_position.y);
    vec2 low_frequency=low_frequency_field110(p);
    float macro=low_frequency.x;
    float footprint=max(length(fwidth(p)),0.001);
    float grain_filter=clamp(1.0-footprint*28.0,0.0,1.0);
    float grain=0.0;
    if(grain_filter>0.0) grain=(sin(p.x*29.0)*sin(p.y*41.0))*grain_filter;
    // Broad low-contrast meadow islands; sand and exposed soil/rock retain their palette.
    float grass_mask=constant_masks.y*(1.0-smoothstep(278.0,314.0,world_position.z));
    float meadow=0.0;
    if(grass_mask>0.0) meadow=low_frequency.y;
    float dry=smoothstep(0.10,0.60,-meadow)*grass_mask;
    if(scenic_biomes_enabled && side<0.15){base=texture(scenic_biome_field,(world_position.xz-vec2(-672.0,-752.0))/vec2(1344.0,1504.0)).rgb;}
    vec3 ground=base*mix(vec3(1.0),vec3(1.07,0.97,0.92),dry);
    ALBEDO=ground*(1.0+macro*0.035+grain*0.02+meadow*grass_mask*0.10);
    // Opaque marker from actual existing road-cut faces; no new transparent layer.
    float retaining=constant_masks.z;
    float row=floor(p.y/0.38);
    vec2 blocks=vec2((p.x+mod(row,2.0)*0.55)/1.10,p.y/0.38);
    // Screen derivatives stay outside conditional masks, including primitive-edge helper lanes.
    vec2 aa=max(fwidth(blocks),vec2(0.0001));
    float resolved=1.0-smoothstep(0.14,0.55,max(aa.x,aa.y));
    if(retaining>0.0 && resolved>0.0){
        vec2 edge=min(fract(blocks),vec2(1.0)-fract(blocks));
        vec2 joint=smoothstep(vec2(0.018)-aa,vec2(0.018)+aa,edge);
        ALBEDO*=1.0-retaining*(1.0-min(joint.x,joint.y))*0.11*resolved;
    }
    // Natural rock relief keeps the existing grass cap and dirt geometry readable.
    // This is material variation on real exposed faces, not a replacement heightfield.
    float rock=constant_masks.w;
    float rock_resolved=1.0-smoothstep(0.10,0.38,footprint);
    if(rock>0.0 && rock_resolved>0.0){
        float course=p.y*0.92+sin(p.x*0.24)*0.14+sin(p.x*0.77)*0.06;
        float strata=sin(course*6.283185)*0.050+sin(course*2.1+p.x*0.29)*0.025;
        float cleft=1.0-smoothstep(0.018,0.055,abs(fract(course)-0.5));
        ALBEDO*=1.0+rock*(strata-cleft*0.075)*rock_resolved;
    }
    ROUGHNESS=mix(0.98,0.94,side);
    float sand=constant_sand*(1.0-smoothstep(1.6,4.0,world_position.y));
    float wet=0.0;
    if(bay_enabled && sand>0.0){
        wet=1.0-smoothstep(0.8,4.0,abs(world_position.z-bay_shore(world_position.x)));
        wet=max(wet,1.0-smoothstep(-2.3,-1.3,world_position.y))*sand;
    }
    ALBEDO=mix(ALBEDO,ALBEDO*vec3(0.83,0.81,0.76),wet*0.65);
    ROUGHNESS=mix(ROUGHNESS,mix(0.88,0.30,wet),sand);
    SPECULAR=mix(0.12,0.42,wet);

}
