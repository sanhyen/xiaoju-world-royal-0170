shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int season=0;
uniform float composition=0.0;
void fragment() {
    vec3 sky=season==0 ? vec3(.82,.89,.85) : season==1 ? vec3(.64,.83,.87) : season==2 ? vec3(.89,.79,.62) : vec3(.78,.84,.88);
    vec3 land=season==0 ? vec3(.76,.57,.65) : season==1 ? vec3(.27,.64,.66) : season==2 ? vec3(.66,.43,.29) : vec3(.91,.91,.87);
    float ridge=.38+sin(UV.x*6.0+composition)*.12+sin(UV.x*13.0)*.035;
    float bands=smoothstep(ridge-.015,ridge+.015,UV.y);
    vec3 color=mix(sky,land,bands);
    float foreground=smoothstep(.73,.75,UV.y+sin(UV.x*8.0)*.06);
    color=mix(color,land*.74,foreground*.5);
    float sun=1.0-smoothstep(.038,.042,length(UV-vec2(.73-composition*.13,.22)));
    ALBEDO=mix(color,vec3(.98,.92,.73),sun);
}
