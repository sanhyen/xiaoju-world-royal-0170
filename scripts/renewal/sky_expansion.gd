extends Node3D
const MeshLib=preload("res://scripts/renewal/mesh_lib.gd")
const SAVE="user://sky_journal.json"
const ISLANDS=[
	{"id":"flowers","name":"流霞花屿","p":Vector3(-670,90,70),"r":Vector2(35,27.5)},
	{"id":"spring","name":"听泉水屿","p":Vector3(-870,106,535),"r":Vector2(32.5,25)},
	{"id":"moon","name":"星河望月屿","p":Vector3(490,146,-620),"r":Vector2(37.5,30)}
]
var layer:Node
var islands:Array[Dictionary]=[]
var sites:Array[Dictionary]=[]
var recorded:Dictionary={}
var climb_stations:PackedVector3Array
var _builder:RefCounted
var _mats:Dictionary={}
var _body:StaticBody3D
var _kit_meshes:Dictionary={}
var _extra_anchors:Array[Vector3]=[]
var garden_art:Dictionary={}

func setup(owner_layer:Node)->void:
	layer=owner_layer;_builder=MeshLib.new()
	_body=StaticBody3D.new();_body.name="FloatingIslandSolids";add_child(_body)
	for pair in [["rock",Color("#626e6a")],["rock_light",Color("#89968b")],["grass",Color("#6f9472")],["sand",Color("#c7c4a6")],["wood",Color("#68564a")],["jade",Color("#497970")],["pink",Color("#d59fab")],["leaf",Color("#3f6e56")],["gold",Color("#d8c490")],["water",Color("#69b5af")]]:
		var mat:=StandardMaterial3D.new();mat.albedo_color=pair[1];mat.roughness=.82
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		_mats[pair[0]]=mat
	var spring_water:=ShaderMaterial.new();spring_water.shader=load("res://scripts/renewal/sky_spring_water.gdshader");_mats["water"]=spring_water
	_load()
	_load_kit()
	for row in ISLANDS:
		islands.append(row.duplicate());_island(row.p,row.r,row.id)
		for i in range(3):
			var angle:float=i*TAU/3.0+.4
			if row.id=="moon" and i==1:angle+=.32
			var point:Vector3=row.p+Vector3(cos(angle)*row.r.x*.52,0,sin(angle)*row.r.y*.52)
			var title:String=["花径听风","云亭望山","落霞留影"][i] if row.id=="flowers" else ["临泉听水","石桥观瀑","水庭留影"][i] if row.id=="spring" else ["月门远望","星盘留影","长廊听风"][i]
			sites.append({"id":str(row.id)+str(i),"title":title,"p":point})
	var satellites:Array=[
		[Vector3(395,145,-665),Vector2(9,7)],[Vector3(435,149,-700),Vector2(10,8)],
		[Vector3(505,151,-705),Vector2(11,8)],[Vector3(580,148,-690),Vector2(9,7)],
		[Vector3(610,143,-620),Vector2(8,6)],[Vector3(585,150,-565),Vector2(10,7)],
		[Vector3(380,140,-550),Vector2(9,7)],[Vector3(395,142,-480),Vector2(8,6)],
		[Vector3(-605,79,125),Vector2(11,8)],[Vector3(-740,87,100),Vector2(10,7)],
		[Vector3(-800,96,485),Vector2(11,8)],[Vector3(-925,112,490),Vector2(10,7)]
	]
	for i in range(satellites.size()):
		var row:Dictionary={"id":"cloud_"+str(i),"name":"云礁","p":satellites[i][0],"r":satellites[i][1]}
		islands.append(row);_island(row.p,row.r,"cloud")
	_build_routes(satellites)
	layer.surfaces.box("stone",layer.sky_island.wp(64,70,47.75),Vector3(12,.5,27.985),true)
	_route(PackedVector3Array([layer.sky_island.wp(64,64.6,48),layer.sky_island.wp(64,75.4,48)]),"东殿后庭","stone",27.985)
	_build_climb()
	for row in ISLANDS:_landscape(row)
	for site in sites:
		_box("gold",site.p+Vector3.UP*.55,Vector3(.28,1.1,.28))
		_label(site.p+Vector3.UP*1.8,site.title+"  [Y]",.009)
	layer.surfaces.open_areas=islands
	layer.surfaces.finalize()
	_add_rock_instances()
	var art:=Node3D.new();art.name="SkyIslandArt";add_child(art)
	preload("res://scripts/renewal/spatial_mesh.gd").install(art,_builder.build(_mats),"IslandArt")
	_builder=null
	print("SKY_EXPANSION major=3 satellites=12 journal_sites=",sites.size())

func _box(key:String,p:Vector3,size:Vector3)->void:
	_builder.begin(key);_builder.box(Transform3D(Basis.IDENTITY,p),size)
	if key in ["wood","gold","rock_light"]:
		var shape:=BoxShape3D.new();shape.size=size
		var cs:=CollisionShape3D.new();cs.shape=shape;_body.add_child(cs);cs.position=p

func _island(p:Vector3,r:Vector2,kind:String)->void:
	var top:=PackedVector3Array();var hull:=PackedVector3Array()
	for i in range(48):
		var angle:=TAU*i/48.0
		var wobble:=1.0+.035*sin(angle*5+.7)
		var edge:=p+Vector3(cos(angle)*r.x*wobble,0,sin(angle)*r.y*wobble)
		top.append(edge);hull.append(edge)
		hull.append(p+Vector3(cos(angle)*r.x*.45,-minf(24,r.x*.7),sin(angle)*r.y*.45))
	for i in range(48):
		var a:=top[i];var b:=top[(i+1)%48]
		_builder.begin("sand" if kind in ["spring","moon"] else "grass")
		_builder.add_tri(p,a,b)
		_builder.begin("rock_light" if sin(i*.31)>.65 else "rock")
		var low_a:=p+(a-p)*.45+Vector3.DOWN*minf(24,r.x*.7)
		var low_b:=p+(b-p)*.45+Vector3.DOWN*minf(24,r.x*.7)
		_builder.add_quad(a,low_a,low_b,b)
		_builder.add_tri(low_a,p+Vector3.DOWN*minf(33,r.x),low_b)
	var shape:=ConvexPolygonShape3D.new();shape.points=hull
	var cs:=CollisionShape3D.new();cs.shape=shape;_body.add_child(cs)

func _landscape(row:Dictionary)->void:
	var p:Vector3=row.p
	# Instanced crowns keep repeated vegetation out of the large static mesh.
	var crown:=SphereMesh.new();crown.radial_segments=8;crown.rings=4;crown.radius=1;crown.height=1.6
	var instances:=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.mesh=crown
	var crown_name:="BlossomCrown" if row.id=="flowers" else "PineCrown"
	if _kit_meshes.has(crown_name):instances.mesh=_kit_meshes[crown_name]
	var center:=p+Vector3(-14,0,-11)
	for offset in [Vector3(-14,0,-11),Vector3(14,0,-11),Vector3(-14,0,11),Vector3(14,0,11),Vector3(0,0,-18),Vector3(0,0,16)]:
		if layer.surfaces.sample(p+offset,4.5).is_empty():center=p+offset;break
	var feature:=Vector3.INF
	if row.id in ["spring","moon"]:feature=_garden_position(row,center,Vector2(6,8) if row.id=="spring" else Vector2(7.4,2.6))
	var positions:Array[Vector3]=[]
	var wanted:=16 if row.id=="flowers" else 5 if row.id=="moon" else 7
	for i in range(128):
		var angle:=i*2.39996;var radius:=.62+.18*sin(i*1.71)
		var point:=p+Vector3(cos(angle)*row.r.x*radius,0,sin(angle)*row.r.y*radius)
		if not layer.surfaces.sample(point,1.3).is_empty() or point.distance_to(center)<7 or (feature!=Vector3.INF and point.distance_to(feature)<10):continue
		positions.append(point)
		if positions.size()>=wanted:break
	instances.instance_count=positions.size()
	for i in range(positions.size()):
		var point:=positions[i]
		_box("wood",point+Vector3.UP*1.8,Vector3(.36,3.6,.36))
		instances.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3(2.4,2.0,2.4) if row.id=="flowers" else Vector3(1.5,1.4,1.5)),point+Vector3.UP*3.6))
	var crowns:=MultiMeshInstance3D.new();crowns.multimesh=instances;crowns.material_override=_mats["pink" if row.id=="flowers" else "leaf"]
	crowns.visibility_range_end=650;add_child(crowns)
	# A small open pavilion, never a solid building occupying the route.
	for x in [-2.5,2.5]:
		for z in [-2.5,2.5]:_box("wood",center+Vector3(x,2.1,z),Vector3(.25,4.2,.25))
	_builder.begin("jade");_builder.gable_roof(center+Vector3.UP*4.2,6.5,6.5,1.8)
	var roof_points:=PackedVector3Array()
	for x in [-3.85,3.85]:
		for z in [-3.85,3.85]:
			roof_points.append(center+Vector3(x,4.2,z));roof_points.append(center+Vector3(x,4.1,z))
		roof_points.append(center+Vector3(x,6.0,0))
	var roof_shape:=ConvexPolygonShape3D.new();roof_shape.points=roof_points
	var roof_cs:=CollisionShape3D.new();roof_cs.shape=roof_shape;_body.add_child(roof_cs)
	if row.id=="spring":
		_water_garden(row,feature)
	if row.id=="moon":
		_builder.begin("gold");_builder.ring(p+Vector3(9,3,0),Vector3.FORWARD,3,.16,48,6)
		_builder.ring(p+Vector3(0,.025,4),Vector3.UP,3.2,.045,48,5)
		_moon_gallery(feature)
	if row.id=="flowers":_falling_petals(p)
	_label(p+Vector3.UP*7,str(row.name),.019)

func _garden_position(row:Dictionary,pavilion:Vector3,half_size:Vector2)->Vector3:
	var best:=Vector3.INF;var best_score:=INF
	for index in range(441):
		var candidate:Vector3=row.p+Vector3((index%21-10)*row.r.x*.07,0,(index/21-10)*row.r.y*.07)
		var score:=0.0
		for x in [-1.0,-.5,0.0,.5,1.0]:
			for z in [-1.0,-.5,0.0,.5,1.0]:
				var point:Vector3=candidate+Vector3(x*half_size.x,0,z*half_size.y)
				if Vector2((point.x-row.p.x)/row.r.x,(point.z-row.p.z)/row.r.y).length()>.95:score+=500
				if not layer.surfaces.sample(point,1.0).is_empty():score+=1
		if candidate.distance_to(pavilion)<14:score+=100
		for site in sites:
			if not str(site.id).begins_with(str(row.id)) and candidate.distance_to(site.p)<half_size.length()+2:score+=100
		if score<best_score:best=candidate;best_score=score
	if best_score>0:push_error("Sky garden has no clear footprint: "+str(row.id)+" score="+str(best_score))
	print("SKY_GARDEN_POSITION ",row.id," center=",best," score=",best_score)
	return best

func _solid_garden_box(p:Vector3,size:Vector3,basis:Basis=Basis.IDENTITY)->void:
	_builder.begin("rock_light");_builder.box(Transform3D(basis,p),size)
	var shape:=BoxShape3D.new();shape.size=size
	var cs:=CollisionShape3D.new();cs.shape=shape;cs.transform=Transform3D(basis,p);_body.add_child(cs)

func _water_garden(row:Dictionary,center:Vector3)->void:
	_solid_garden_box(center+Vector3.UP*.015,Vector3(10.8,.03,7.2))
	var flow_sign:=1.0 if center.x>=row.p.x else -1.0
	for x in [-5.4,5.4]:
		if x*flow_sign>0:
			for z in [-2.25,2.25]:_solid_garden_box(center+Vector3(x,.25,z),Vector3(.3,.5,2.7))
		else:_solid_garden_box(center+Vector3(x,.25,0),Vector3(.3,.5,7.5))
	for z in [-3.6,3.6]:_solid_garden_box(center+Vector3(0,.25,z),Vector3(10.8,.5,.3))
	_builder.begin("water")
	_builder.add_quad(center+Vector3(-5.25,.42,-3.45),center+Vector3(5.25,.42,-3.45),center+Vector3(5.25,.42,3.45),center+Vector3(-5.25,.42,3.45))
	for x in [-3.7,-1.4,1.9,3.5]:
		for z in [-2.1,2.0]:_box("rock",center+Vector3(x,.075,z),Vector3(.32,.09,.23))
	var bridge:=PackedVector3Array()
	for i in range(21):
		var t:=float(i)/20.0;bridge.append(center+Vector3(0,.035+sin(t*PI)*.90,lerpf(-7,7,t)))
	layer.surfaces.add_path(bridge,3.0,"stone","听泉石桥")
	var direction:=Vector3(flow_sign,0,0)
	var radius:float=float(row.r.x)*sqrt(maxf(0.0,1.0-pow((center.z-row.p.z)/float(row.r.y),2)))
	var edge:Vector3=Vector3(row.p.x+flow_sign*(radius+1.3),row.p.y,center.z)
	var from:Vector3=center+direction*5.25;var to:Vector3=edge
	var side:=direction.cross(Vector3.UP)
	var basis:=Basis.looking_at(-direction,Vector3.UP)
	_solid_garden_box((from+to)*.5+Vector3.UP*.015,Vector3(1.8,.03,from.distance_to(to)),basis)
	for sign_value in [-1,1]:_solid_garden_box((from+to)*.5+side*.9*sign_value+Vector3.UP*.25,Vector3(.16,.5,from.distance_to(to)),basis)
	_builder.begin("water")
	_builder.add_quad(from-side*.8+Vector3.UP*.42,from+side*.8+Vector3.UP*.42,to+side*.8+Vector3.UP*.42,to-side*.8+Vector3.UP*.42)
	_builder.add_quad(to-side*.8+Vector3.UP*.42,to+side*.8+Vector3.UP*.42,to+direction*.7+side*.65-Vector3.UP*4.2,to+direction*.7-side*.65-Vector3.UP*4.2)
	garden_art["spring"]={"center":center,"water_y":center.y+.42,"bed_y":center.y+.03,"fall_top":to+Vector3.UP*.42,"fall_bottom":to+direction*.7-Vector3.UP*4.2,"bridge":bridge}
	for site in sites:
		if site.id=="spring0":site.p=center+Vector3(-3.4,0,4.8)
		if site.id=="spring1":site.p=center+Vector3(1.8,0,-7)
		if site.id=="spring2":site.p=center+Vector3(4.8,0,4.8)

func _moon_gallery(center:Vector3)->void:
	_solid_garden_box(center-Vector3.UP*.065,Vector3(14.2,.16,4.2))
	for z in [-1.85,1.85]:
		for x in [-6,-2,2,6]:_box("wood",center+Vector3(x,1.9,z),Vector3(.22,3.8,.22))
	_builder.begin("jade");_builder.gable_roof(center+Vector3.UP*3.8,15.0,4.8,1.2)
	for z in [-2.15,2.15]:
		_builder.begin("gold");_builder.beam(center+Vector3(-7,3.75,z),center+Vector3(7,3.75,z),.07)
	var roof:=ConvexPolygonShape3D.new();var corners:=PackedVector3Array()
	for x in [-7.5,7.5]:
		for z in [-2.4,2.4]:corners.append(center+Vector3(x,3.8,z));corners.append(center+Vector3(x,3.7,z))
		corners.append(center+Vector3(x,5,0))
	roof.points=corners
	var cs:=CollisionShape3D.new();cs.shape=roof;_body.add_child(cs)
	garden_art["moon"]={"center":center,"length_m":14.2,"clear_width_m":3.48,"ceiling_m":3.7}
	layer.surfaces.add_path(PackedVector3Array([center+Vector3(-6.8,.015,0),center+Vector3(6.8,.015,0)]),3.3,"stone","望月观景长廊",false,false)
	for site in sites:
		if site.id=="moon2":site.p=center+Vector3(6.2,0,1.1)

func _falling_petals(center:Vector3)->void:
	var mesh:=SphereMesh.new();mesh.radius=.07;mesh.height=.025;mesh.radial_segments=6;mesh.rings=3
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_custom_data=true;batch.mesh=mesh;batch.instance_count=48
	for i in range(48):
		var angle:=i*2.39996;var radius:=9.0+float(i%9)*1.7
		batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(cos(angle)*radius,6,sin(angle)*radius*.75)))
		batch.set_instance_custom_data(i,Color(float(i)/48.0,float(i%7)/7.0,0,1))
	var material:=ShaderMaterial.new();material.shader=load("res://scripts/renewal/sky_petals.gdshader")
	var petals:=MultiMeshInstance3D.new();petals.name="FallingBlossomPetals";petals.position=center;petals.multimesh=batch;petals.material_override=material;petals.visibility_range_end=180;petals.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;petals.extra_cull_margin=7;add_child(petals)
	garden_art["flowers"]={"petals":48}

func _route(points:PackedVector3Array,label:String,kind:String="cloud",width:float=4.0)->void:
	if kind=="cloud":
		var joined:=PackedVector3Array([points[0]])
		for i in range(points.size()-1):
			var a:=_island_edge(points[i],points[i+1]);var b:=_island_edge(points[i+1],points[i])
			if i==0 and a==points[i]:a+=Vector3(points[i+1].x-a.x,0,points[i+1].z-a.z).normalized()*minf(6,a.distance_to(b)*.2)
			if i==points.size()-2 and b==points[i+1]:b+=Vector3(points[i].x-b.x,0,points[i].z-b.z).normalized()*minf(6,a.distance_to(b)*.2)
			if a.distance_to(joined[-1])>.05:joined.append(a)
			var flat:=Vector2(a.x-b.x,a.z-b.z).length();var required:=absf(a.y-b.y)/tan(deg_to_rad(12.0))
			if flat<required and flat>.1:
				var side:=Vector3(b.z-a.z,0,a.x-b.x).normalized()
				var forward:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
				var offset:float=(required-flat)*.5+10.0
				var extension:=maxf(6,(16-flat)*.5)
				var left_a:=a+side*offset-forward*extension;var left_b:=b+side*offset+forward*extension
				var right_a:=a-side*offset-forward*extension;var right_b:=b-side*offset+forward*extension
				if _island_overlap(left_a)+_island_overlap(left_b)>_island_overlap(right_a)+_island_overlap(right_b):left_a=right_a;left_b=right_b
				var first_length:=Vector2(left_a.x-a.x,left_a.z-a.z).length()
				var top_length:=Vector2(left_b.x-left_a.x,left_b.z-left_a.z).length()
				var total_length:=first_length*2+top_length
				left_a.y=lerpf(a.y,b.y,first_length/total_length);left_b.y=lerpf(a.y,b.y,(first_length+top_length)/total_length)
				joined.append(left_a);joined.append(left_b)
			if b.distance_to(joined[-1])>.05:joined.append(b)
			if points[i+1].distance_to(joined[-1])>.05:joined.append(points[i+1])
		points=joined
	points=_flat_junctions(points)
	points=_smooth_path(points)
	for i in range(points.size()):
		for row in islands:
			var d:=Vector2((points[i].x-row.p.x)/(row.r.x+5),(points[i].z-row.p.z)/(row.r.y+5))
			if d.length()<1.04 and absf(points[i].y-row.p.y)<4:points[i].y=row.p.y
	# The level island apron must blend into the slope over real distance.
	# A two-pass upper envelope removes sudden height jumps introduced by snapping.
	var grade:=tan(deg_to_rad(12.0))
	for i in range(1,points.size()):
		var flat:=Vector2(points[i].x-points[i-1].x,points[i].z-points[i-1].z).length()
		points[i].y=maxf(points[i].y,points[i-1].y-flat*grade)
	for i in range(points.size()-2,-1,-1):
		var flat:=Vector2(points[i].x-points[i+1].x,points[i].z-points[i+1].z).length()
		points[i].y=maxf(points[i].y,points[i+1].y-flat*grade)
	layer.surfaces.add_path(points,width,kind,label)

func _smooth_path(points:PackedVector3Array)->PackedVector3Array:
	if points.size()<3:return points
	var out:=PackedVector3Array([points[0]])
	for i in range(1,points.size()-1):
		var incoming:=points[i]-points[i-1];var outgoing:=points[i+1]-points[i]
		var flat_in:=Vector3(incoming.x,0,incoming.z).normalized();var flat_out:=Vector3(outgoing.x,0,outgoing.z).normalized()
		var half_angle:=acos(clampf(flat_in.dot(flat_out),-1,1))*.5
		var needed:=4.0*sin(half_angle)/maxf(.04,pow(cos(half_angle),2))
		var trim:=minf(maxf(12,needed),minf(incoming.length(),outgoing.length())*.44)
		if trim<.2 or incoming.normalized().dot(outgoing.normalized())>.995:
			out.append(points[i]);continue
		var a:=points[i]-incoming.normalized()*trim;var b:=points[i]+outgoing.normalized()*trim
		out.append(a)
		var steps:=maxi(3,ceili(trim*1.5))
		var arc:=PackedVector3Array([a]);var distances:=PackedFloat32Array([0.0]);var total:=0.0
		for j in range(1,steps+1):
			var t:=float(j)/steps
			var q:=a*(1-t)*(1-t)+points[i]*2*t*(1-t)+b*t*t
			total+=Vector2(q.x-arc[-1].x,q.z-arc[-1].z).length();arc.append(q);distances.append(total)
		for j in range(1,arc.size()):
			var q:=arc[j];q.y=lerpf(a.y,b.y,distances[j]/maxf(.001,total));out.append(q)
	out.append(points[-1]);return out

func _flat_junctions(points:PackedVector3Array)->PackedVector3Array:
	var out:=PackedVector3Array([points[0]])
	var anchors:Array=[Vector3(-875,48,440),Vector3(-875,48,390),Vector3(-800,48,220),Vector3(-630,112,-200),Vector3(-490,138,-520),Vector3(-180,148,-635),Vector3(180,150,-650)]
	anchors.append_array(_extra_anchors)
	for i in range(1,points.size()-1):
		var is_anchor:=false
		for anchor in anchors:
			if points[i].distance_to(anchor)<.05:is_anchor=true;break
		if is_anchor:
			var incoming:=points[i]-points[i-1];var outgoing:=points[i+1]-points[i]
			var before:=points[i]-incoming.normalized()*minf(8,incoming.length()*.3);before.y=points[i].y
			var after:=points[i]+outgoing.normalized()*minf(8,outgoing.length()*.3);after.y=points[i].y
			out.append(before);out.append(points[i]);out.append(after)
		else:out.append(points[i])
	out.append(points[-1]);return out

func _island_edge(p:Vector3,towards:Vector3)->Vector3:
	var direction:=Vector3(towards.x-p.x,0,towards.z-p.z).normalized()
	for row in islands:
		if absf(p.y-row.p.y)>.15:continue
		var q:=Vector2((p.x-row.p.x)/row.r.x,(p.z-row.p.z)/row.r.y)
		if q.length()>1.04:continue
		var v:=Vector2(direction.x/row.r.x,direction.z/row.r.y)
		var a:=v.dot(v);var b:=2*q.dot(v);var c:=q.dot(q)-1
		if a<1e-8:continue
		var distance:=(-b+sqrt(maxf(0,b*b-4*a*c)))/(2*a)+8.0
		return p+direction*distance
	return p

func _island_overlap(p:Vector3)->int:
	var cost:=0
	if p.x< -955 or p.x>635 or p.z< -715 or p.z>715:cost+=100
	for row in islands:
		var q:=Vector2((p.x-row.p.x)/row.r.x,(p.z-row.p.z)/row.r.y)
		if q.length()<1.06 and p.y<row.p.y+2 and p.y>row.p.y-35:cost+=1
	return cost

func _build_routes(satellites:Array)->void:
	# Preserve island-to-island travel; rebuild both island ends as cliff routes.
	_route(PackedVector3Array([Vector3(-686,4.1,394),Vector3(-695,4.1,393),Vector3(-695,18,475),Vector3(-780,33,475),Vector3(-875,48,440),Vector3(-875,48,390),Vector3(-810,48,390),Vector3(-810,48,344)]),"南崖木栈道","wood",3.5)
	_route(PackedVector3Array([Vector3(-707,4.1,459),Vector3(-716,4.1,457),Vector3(-735,4.1,442),Vector3(-735,18,365),Vector3(-625,18,410),Vector3(-625,33,325),Vector3(-690,48,220),Vector3(-800,48,220),Vector3(-800,48,242)]),"北崖木栈道","wood",3.5)
	_route(PackedVector3Array([Vector3(-875,48,390),Vector3(-915,56,360),Vector3(-915,64,272),Vector3(-879,64,272)]),"殿后高廊","wood",3.5)
	_route(PackedVector3Array([Vector3(-800,48,220),Vector3(-845,56,180),Vector3(-900,64,235),Vector3(-879,64,272)]),"北崖登殿廊","wood",3.5)
	_route(PackedVector3Array([Vector3(-879,64,272),Vector3(-844,64,272),Vector3(-844,64,290),Vector3(-849,64,290)]),"殿后回廊","wood",3.5)
	# Keep the original forecourt-to-star-dais passage open through the new gallery.
	layer.surfaces.add_path(PackedVector3Array([Vector3(-849,64,300),Vector3(-849,64,284)]),3.5,"stone","观星阵原通道",false,false)
	_route(PackedVector3Array([Vector3(-800,48,220),Vector3(-760,67,200),Vector3(-670,90,70)]),"流霞云径")
	_route(PackedVector3Array([Vector3(-875,48,440),Vector3(-945,70,535),Vector3(-930,88,620),Vector3(-870,106,535)]),"听泉云径")
	_route(PackedVector3Array([Vector3(-670,90,70),Vector3(-630,112,-200),Vector3(-490,138,-520),Vector3(-180,148,-635),Vector3(180,150,-650),Vector3(490,146,-620)]),"北天云路")
	_route(PackedVector3Array([Vector3(490,146,-620),Vector3(380,146,-620),Vector3(350,135,-540),Vector3(360,124,-450),Vector3(420,112.15,-450),Vector3(420,112.15,-500),Vector3(446,112.15,-500)]),"宫苑接云廊")
	for i in range(satellites.size()):
		var p:Vector3=satellites[i][0]
		var anchor:Vector3=Vector3(490,146,-620) if i<8 else Vector3(-670,90,70) if i<10 else Vector3(-870,106,535)
		_route(PackedVector3Array([anchor,p]),"云礁支径", "cloud",3.2)
	# Existing northeast islands: approach from their outside edges, not through halls.
	var existing:Array=[Vector3(402.5,138.05,-532),Vector3(409,125.6,-557),Vector3(433.9,114.05,-481),Vector3(491,114.05,-470),Vector3(521,130.05,-476),Vector3(537,131.6,-540),Vector3(545.7,106.05,-557),Vector3(561,130.05,-503),Vector3(569.5,103.6,-466)]
	for p in existing:
		layer.surfaces.box("cloud",p+Vector3.DOWN*.22,Vector3(4,.44,4),true)
		_extra_anchors.append(p)
	var old_tour:=PackedVector3Array([
		Vector3(490,146,-620),existing[0],existing[5],Vector3(548,131.6,-540),existing[7],existing[4],
		Vector3(400,125.6,-585),existing[1],existing[2],Vector3(433.9,114.05,-460),existing[3],
		Vector3(595,114.05,-450),Vector3(610,110,-535),existing[6],existing[8]
	])
	_route(old_tour,"旧岛巡云长廊","cloud",3.2)
	_station(existing[8],"旧岛巡云 · 返回望月屿")
	layer.travel_play.stops.append({"p":existing[8],"to":Vector3(490,146,-620),"name":"旧岛巡云","dest":"星河望月屿","time":22.0,"rise":45.0,"itinerary":PackedVector3Array([existing[8],Vector3(490,146,-620)])})
	# Fast scenic transit accompanies the fully walkable northern route.
	_station(Vector3(-670,90,70),"流霞花屿 · 御剑接驳")
	_station(Vector3(490,146,-620),"望月屿 · 御剑接驳")
	layer.travel_play.stops.append({"p":Vector3(-670,90,70),"to":Vector3(490,146,-620),"name":"流霞花屿","dest":"星河望月屿","time":100.0,"rise":22.0,"itinerary":PackedVector3Array([Vector3(-670,90,70),Vector3(-630,128,-200),Vector3(-490,158,-520),Vector3(-180,168,-635),Vector3(180,170,-650),Vector3(490,146,-620)])})
	layer.travel_play.stops.append({"p":Vector3(490,146,-620),"to":Vector3(-670,90,70),"name":"望月屿","dest":"流霞花屿","time":100.0,"rise":22.0,"itinerary":PackedVector3Array([Vector3(490,146,-620),Vector3(180,170,-650),Vector3(-180,168,-635),Vector3(-490,158,-520),Vector3(-630,128,-200),Vector3(-670,90,70)])})
	var cloud_stations:=PackedVector3Array([Vector3(-670,90,70),Vector3(-630,112,-200),Vector3(-490,138,-520),Vector3(-180,148,-635),Vector3(180,150,-650),Vector3(490,146,-620)])
	var first:Dictionary=layer.travel_play.stops[-2];first.itinerary=cloud_stations
	var reverse:=cloud_stations.duplicate();reverse.reverse();layer.travel_play.stops[-1].itinerary=reverse
	for i in range(1,5):
		_station(cloud_stations[i],"北天云路 · 御剑接驳")
		var itinerary:=PackedVector3Array()
		for j in range(i,cloud_stations.size()):itinerary.append(cloud_stations[j])
		layer.travel_play.stops.append({"p":cloud_stations[i],"to":cloud_stations[-1],"name":"北天云路","dest":"星河望月屿","time":60.0,"rise":22.0,"itinerary":itinerary})

func _station(p:Vector3,title:String)->void:
	layer.surfaces.box("stone",p+Vector3.DOWN*.22,Vector3(3.8,.44,3.8),true)
	_label(p+Vector3.UP*1.8,title+"  [Y]",.011)

func _build_climb()->void:
	var island:Node=layer.sky_island
	# Register the existing axial bridge as a junction so the new side platform's
	# rail opens across it. Its visible bridge and stair mesh remain the original.
	layer.surfaces.add_path(PackedVector3Array([Vector3(-638,3.85,300),Vector3(-647,4,300),Vector3(-655,4,300)]),8.0,"legacy","仙岛原入口",false,false)
	climb_stations=PackedVector3Array([Vector3(-655,4,311),island.wp(0,-83,18),island.wp(0,-49,33),island.wp(-8,26,48),island.wp(-13,78,64),island.wp(0,80,64)])
	_route(PackedVector3Array([Vector3(-648,4,300),Vector3(-648,4,311),climb_stations[0]]),"入口御剑台","stone",3.8)
	for i in range(climb_stations.size()):
		var p:=climb_stations[i]
		_station(p,"御剑登殿" if i<5 else "御剑下山")
		var itinerary:=PackedVector3Array([p])
		if i<5:
			for j in range(i+1,climb_stations.size()):itinerary.append(climb_stations[j])
		else:
			for j in range(4,-1,-1):itinerary.append(climb_stations[j])
		layer.travel_play.stops.append({"p":p,"to":itinerary[-1],"name":"御剑登殿","dest":"栖霞殿" if i<5 else "仙岛入口","time":20.0,"rise":25.0,"itinerary":itinerary})

func _label(p:Vector3,words:String,size:float)->void:
	var label:=Label3D.new();label.text=words;label.font_size=56;label.pixel_size=minf(size,.0032);label.outline_size=8
	label.visibility_range_begin=3.5
	label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.visibility_range_end=110;add_child(label);label.global_position=p

func _add_rock_instances()->void:
	for variant in range(3):
		if not _kit_meshes.has("SkyRock"+str(variant)):continue
		var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=_kit_meshes["SkyRock"+str(variant)];batch.instance_count=12
		for i in range(12):
			var island:Dictionary=ISLANDS[i/4]
			var angle:float=(i%4)*TAU/4.0+variant*.45
			var at:Vector3=island.p+Vector3(cos(angle)*island.r.x*.94,-1.7,sin(angle)*island.r.y*.94)
			batch.set_instance_transform(i,Transform3D(Basis(Vector3.UP,angle).scaled(Vector3(4,6,4)),at))
		var node:=MultiMeshInstance3D.new();node.multimesh=batch;node.visibility_range_end=850;add_child(node)

func _load_kit()->void:
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	if doc.append_from_file("res://scripts/renewal/rebuild/assets/sky_rock_kit_20261107.glb",state)!=OK:return
	var root:Node3D=doc.generate_scene(state)
	for node in root.find_children("*","MeshInstance3D",true,false):_kit_meshes[str(node.name)]=node.mesh
	root.free()

func contains(p:Vector3,include_routes:bool=true)->bool:
	if include_routes and layer.surfaces.contains(p):return true
	for row in islands:
		var d:Vector3=p-row.p
		if Vector2(d.x/row.r.x,d.z/row.r.y).length()<1.08 and d.y> -12 and d.y<15:return true
	return false

func landing(xz:Vector2)->Vector3:
	for row in islands:
		var d:=xz-Vector2(row.p.x,row.p.z)
		if Vector2(d.x/row.r.x,d.y/row.r.y).length()<1:return row.p+Vector3.UP*.12
	return Vector3.INF

func hint(p:Vector3)->String:
	for row in sites:
		if p.distance_to(row.p)<2.6:return "Y  "+row.title+(" · 已收录" if recorded.has(row.id) else " · 收入天空游记")
	return ""

func interact(p:Vector3)->bool:
	for row in sites:
		if p.distance_to(row.p)>=2.6:continue
		var next:=recorded.duplicate();next[row.id]=true
		var file:=FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
		if file==null:return true
		file.store_string(JSON.stringify({"version":1,"recorded":next}));file.flush();var ok:=file.get_error()==OK;file.close()
		if ok and DirAccess.rename_absolute(SAVE+".tmp",SAVE)==OK:
			recorded=next;layer.main.call("notify","天空游记 %d/9 · %s"%[recorded.size(),row.title])
		else:layer.main.call("notify","游记暂未保存，请再试一次")
		return true
	return false

func _load()->void:
	var file:=FileAccess.open(SAVE,FileAccess.READ)
	if file==null:return
	var data:Variant=JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.get("recorded") is Dictionary:
		for row in ISLANDS:
			for i in range(3):
				var id:=str(row.id)+str(i)
				if data.recorded.get(id,false)==true:recorded[id]=true
