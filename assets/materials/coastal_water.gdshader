shader_type spatial;
render_mode cull_disabled, fog_disabled, depth_draw_always;
uniform vec4 shallow_tone : source_color = vec4(0.408,0.616,0.659,1.0);
uniform vec4 offshore_tone : source_color = vec4(0.255,0.482,0.573,1.0);
uniform vec4 foam_tone : source_color = vec4(0.786,0.843,0.788,1.0);
uniform vec3 horizon_tone : source_color = vec3(0.839,0.910,0.875);
uniform bool island_window=false;
uniform int shore_count=0;
uniform vec2 shore_points[24];
varying vec3 world_position;

void vertex() {
    // Far rings flatten before spacing grows; the original shore wave phase stays.
    vec3 base_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float near_wave = 1.0-smoothstep(800.0,1400.0,max(abs(base_world.x),abs(base_world.z)));
    VERTEX.y += (sin(base_world.x*0.035+TIME*0.6)*0.12 + cos(base_world.z*0.06+TIME*0.5)*0.06)*near_wave;
    world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
    float reef_radius=length((world_position.xz-vec2(232.5,452.5))/vec2(77.5,47.5));
    float reef=island_window ? 1.0-smoothstep(0.55,1.03,reef_radius) : 0.0;
    ALPHA=mix(1.0,0.30,reef);
    float hotel_clear=smoothstep(267.0,271.0,world_position.x)*(1.0-smoothstep(286.0,290.0,world_position.x))*smoothstep(417.0,422.0,world_position.z)*(1.0-smoothstep(480.0,485.0,world_position.z));
    float floor_clear=max(max(1.0-smoothstep(1.5,3.2,length(world_position.xz-vec2(276.0,426.0))),1.0-smoothstep(1.5,3.2,length(world_position.xz-vec2(280.0,441.0)))),max(1.0-smoothstep(1.5,3.2,length(world_position.xz-vec2(280.0,456.0))),1.0-smoothstep(1.5,3.2,length(world_position.xz-vec2(276.0,471.0)))));
    if(island_window){ALPHA=mix(ALPHA,0.16,hotel_clear);ALPHA=mix(ALPHA,0.06,floor_clear);}
    float coast=344.0;
    float bounded_x=clamp(world_position.x,-480.0,480.0);
    for(int i=0;i<23;i++) {
        if(i+1<shore_count && bounded_x>=shore_points[i].x && bounded_x<=shore_points[i+1].x) {
            float f=clamp((bounded_x-shore_points[i].x)/(shore_points[i+1].x-shore_points[i].x),0.0,1.0);
            f=f*f*(3.0-2.0*f);
            coast=mix(shore_points[i].y,shore_points[i+1].y,f);
        }
    }
    float offshore=length(vec2(world_position.x-bounded_x,max(0.0,world_position.z-coast)));
    float forest_radius=length((world_position.xz-vec2(-60.0,490.0))/vec2(60.0,39.2));
    float island_distance=abs(reef_radius-1.0)*47.5;float forest_distance=abs(forest_radius-1.0)*39.2;
    // Distance to bounded coastal segments, never to infinite grid lines.
    float side_x=451.0+7.0*(1.0-smoothstep(-250.0,180.0,world_position.z))-9.0*sin(world_position.z*.018);
    float side_z=clamp(world_position.z,-459.0,340.0);
    float west_distance=length(world_position.xz-vec2(-side_x,side_z));
    float east_distance=length(world_position.xz-vec2(side_x,side_z));
    float north_x=clamp(world_position.x,-451.0,451.0);
    float north_z=-459.0+8.0*sin(world_position.x*.014);
    float north_distance=length(world_position.xz-vec2(north_x,north_z));
    if(world_position.z<coast){offshore=min(west_distance,min(east_distance,north_distance));}
    offshore=min(offshore,min(island_distance,forest_distance));
    vec3 water=mix(shallow_tone.rgb,offshore_tone.rgb,smoothstep(8.0,60.0,offshore));
    vec3 coral=mix(vec3(0.486,0.878,0.827),vec3(0.220,0.698,0.769),smoothstep(.1,.65,reef_radius));
    water=mix(water,coral,reef);
    vec2 p=world_position.xz;
    float waves=sin(p.x*0.43+p.y*0.79-TIME*0.55)*sin(p.x*0.13-p.y*0.23+TIME*0.26);
    float attenuation=clamp(1.0-length(fwidth(p))*0.5,0.0,1.0);
    water*=1.0+waves*0.042*attenuation;
    float warm=max(0.0,horizon_tone.r-horizon_tone.b);float glint=pow(max(0.0,sin(p.x*.035+p.y*.013)),18.0)*smoothstep(2.0,28.0,offshore);water=mix(water,vec3(.82,.64,.43),clamp(warm*glint*.55,0.0,.2));
    // Sparse opaque swash marks sit just offshore; no extra transparent layers or particles.
    float tide=0.65+0.25*sin(p.x*0.23+TIME*0.7);
    float foam=(1.0-smoothstep(0.10,0.38,abs(offshore-tide)))*smoothstep(0.15,0.6,sin(p.x*0.57+sin(p.x*0.13)));
    // Far water tends toward the same actual sky-horizon palette in every light preset.
    // Camera distance also handles water beside the island, not only the southern offshore strip.
    float optical_distance=length(world_position-CAMERA_POSITION_WORLD);
    // Distance-only haze collapses to one raster row at a low shore camera.
    // Grazing rays leave a gradual horizon while close water retains its lit material.
    vec3 sight=normalize(CAMERA_POSITION_WORLD-world_position);
    float grazing_haze=(1.0-smoothstep(0.015,0.18,abs(sight.y)))*smoothstep(24.0,165.0,optical_distance);
    float horizon_haze=max(smoothstep(900.0,6000.0,optical_distance),grazing_haze);
    ALBEDO=mix(water,foam_tone.rgb,foam*0.6*attenuation)*(1.0-horizon_haze);
    EMISSION=horizon_tone*horizon_haze;
    float far_reflection=smoothstep(100.0,500.0,offshore);
    ROUGHNESS=mix(0.14,0.28,far_reflection);
    METALLIC=0.03*(1.0-horizon_haze);
    SPECULAR=mix(0.35,0.22,far_reflection)*(1.0-horizon_haze);
}
