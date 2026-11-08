shader_type spatial;
render_mode cull_disabled, fog_disabled, depth_draw_always;
uniform vec4 shallow_tone : source_color = vec4(0.408,0.616,0.659,1.0);
uniform vec4 offshore_tone : source_color = vec4(0.255,0.482,0.573,1.0);
uniform vec4 foam_tone : source_color = vec4(0.786,0.843,0.788,1.0);
uniform vec3 horizon_tone : source_color = vec3(0.839,0.910,0.875);
uniform bool island_window=false;
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
    if(reef_radius>1.0){discard;}
    ALPHA=mix(0.30,1.0,smoothstep(0.66,0.99,reef_radius));
    float coast=344.0+15.0*sin(world_position.x*0.017)+4.2;
    float offshore=max(0.0,world_position.z-coast);
    vec3 water=mix(shallow_tone.rgb,offshore_tone.rgb,smoothstep(1.0,80.0,offshore));
    water=mix(mix(vec3(0.486,0.878,0.827),vec3(0.220,0.698,0.769),smoothstep(.1,.65,reef_radius)),water,smoothstep(.62,.99,reef_radius));
    vec2 p=world_position.xz;
    float waves=sin(p.x*0.43+p.y*0.79-TIME*0.55)*sin(p.x*0.13-p.y*0.23+TIME*0.26);
    float attenuation=clamp(1.0-length(fwidth(p))*0.5,0.0,1.0);
    water*=1.0+waves*0.042*attenuation;
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
    ROUGHNESS=mix(0.70,0.82,far_reflection);
    METALLIC=0.03*(1.0-horizon_haze);
    SPECULAR=mix(0.08,0.05,far_reflection)*(1.0-horizon_haze);
}
