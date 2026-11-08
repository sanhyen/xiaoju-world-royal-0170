shader_type spatial;
render_mode cull_disabled;
uniform sampler2D portrait : source_color, filter_linear_mipmap;
uniform vec3 portrait_center=vec3(0.0,14.5,39.44);
uniform vec2 portrait_size=vec2(11.92,16.0);
varying vec3 pool_position;
void vertex(){pool_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment() {
    vec3 ray=pool_position-CAMERA_POSITION_WORLD;
    float t=(portrait_center.z-CAMERA_POSITION_WORLD.z)/min(ray.z,-0.001);
    vec3 reflected_point=CAMERA_POSITION_WORLD+ray*t;
    float mirror_y=2.0*pool_position.y-portrait_center.y;
    vec2 uv=vec2((reflected_point.x-portrait_center.x)/portrait_size.x+0.5,(reflected_point.y-mirror_y)/portrait_size.y+0.5);
    uv.x+=sin(pool_position.z*8.0+TIME*.7)*.0015;
    float valid=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0)*step(1.0,t);
    vec3 reflected=texture(portrait,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
    ALBEDO=mix(vec3(.30,.47,.44),reflected,valid*.80);
    ROUGHNESS=.12;
    SPECULAR=.48;
}
