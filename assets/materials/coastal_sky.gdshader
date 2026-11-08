shader_type sky;
// Mobile radiance storage is half luminance; the active renderer supplies decoding.
uniform float cloud_cover = 0.0;
uniform float radiance_decode = 1.0;
uniform vec3 top_color : source_color = vec3(0.40,0.67,0.83);
uniform vec3 horizon_color : source_color = vec3(0.82,0.90,0.88);
uniform vec3 cloud_color : source_color = vec3(0.96,0.96,0.91);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void sky(){
	// Static cloud calculation only when the cubemap changes; regular frames reuse it.
	if(!AT_CUBEMAP_PASS){COLOR=texture(RADIANCE,EYEDIR).rgb*radiance_decode;}
	else{
		float y=max(EYEDIR.y,0.0);
		vec3 color=mix(horizon_color,top_color,pow(smoothstep(0.0,0.85,y),0.6));
		vec2 p=EYEDIR.xz/max(EYEDIR.y,0.10)*1.8+vec2(7.1,2.3);
		float mass=noise(p)*0.69+noise(p*2.1)*0.22+noise(p*4.3)*0.09;
		float cloud=smoothstep(0.60-cloud_cover*0.52,0.74-cloud_cover*0.45,mass)*smoothstep(0.08,0.22,y)*(1.0-smoothstep(0.83,0.97,y));
		color=mix(color,cloud_color,cloud*0.95);
		// A continuous lower hemisphere avoids a hard grey band at y=0.
        // Visible water covers the downward view; this transition also fills far clipping.
        if(EYEDIR.y<0.0)color=horizon_color*mix(1.0,0.72,smoothstep(0.0,0.35,-EYEDIR.y));
		COLOR=color;
	}
}
