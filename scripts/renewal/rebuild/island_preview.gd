extends Node3D
## Current island incremental implementation; stage names are internal authoring milestones.
var stage := "s1"
var layer: Node
var shore := PackedVector2Array()
var stats: Dictionary = {}
var celestial_realm: Node3D
const CENTER := Vector3(-770,0,300)

func wp(width: float, depth: float, height: float) -> Vector3:
	return CENTER+Vector3(-depth,height,-width)

func setup(owner_layer: Node) -> void:
	layer=owner_layer
	for i in range(96):
		var a: float = TAU*i/96.0
		var noise: float = 1.0+0.055*sin(a*5.0+0.7)+0.035*sin(a*9.0)
		shore.append(Vector2(cos(a)*205.0*noise,sin(a)*151.0*noise))
	_build_land()
	_build_route()
	_blockout()
	if stage=="s2":
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var error := doc.append_from_file("res://scripts/renewal/rebuild/assets/palace_traversal_20261107.glb",state)
		if error != OK:
			push_error("S2 asset cannot load: "+str(error))
			return
		var asset: Node3D = doc.generate_scene(state)
		asset.name="AuthoredGateSlice"
		add_child(asset)
		asset.position=CENTER
		asset.rotation.y=PI/2
		# Shadow/material checks are in the game renderer, no unshaded presentation pass.
		for mi in asset.find_children("*","MeshInstance3D",true,false):
			if mi.name in ["S2_rock","S2_rock_light"]:
				var cliff:=ShaderMaterial.new()
				cliff.shader=load("res://scripts/renewal/rebuild/cliff_surface.gdshader")
				mi.material_override=cliff
			if "cascade" in mi.name:
				var cascade:=ShaderMaterial.new()
				cascade.shader=load("res://scripts/renewal/rebuild/cascade.gdshader")
				mi.material_override=cascade
			if "water" in mi.name:
				var water := ShaderMaterial.new()
				water.shader=load("res://scripts/renewal/rebuild/slice_water.gdshader")
				mi.material_override=water
		_add_figure_details()
		_gate_collisions()
		_palace_collisions()
		var structure: Node3D = load("res://scripts/renewal/rebuild/island_collisions.gd").new()
		structure.name = "IslandStructureCollision"
		add_child(structure)
		structure.setup(self,asset)
		celestial_realm = load("res://scripts/renewal/rebuild/celestial_realm.gd").new()
		celestial_realm.name = "CelestialRealm"
		add_child(celestial_realm)
		celestial_realm.setup(self,layer,asset)
	print("REBUILD_PREVIEW ",stage," ",JSON.stringify(stats))

func contains_land(p: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(300-p.z,-770-p.x),shore)

func _surface_height(x: float,d: float,r: float) -> float:
	if stage == "s2":
		return maxf(-2.4,(1.0-pow(r,3))*5.0+sin(x*.08)*cos(d*.06)*1.4)
	var main_peak: float=78.0*exp(-pow(x/72.0,2)-pow((d-82.0)/57.0,2))
	var west_peak: float=43.0*exp(-pow((x+78.0)/40.0,2)-pow((d-32.0)/58.0,2))
	var east_peak: float=55.0*exp(-pow((x-76.0)/45.0,2)-pow((d-53.0)/42.0,2))
	var height: float=maxf(main_peak,maxf(west_peak,east_peak))*(1-pow(r,8))
	height+=maxf(0,1-r)*3.0
	if absf(x)<40 and d>-124 and d<25:
		height=minf(height,maxf(1.0,route_height(d)-14.0))
	if absf(x)<35 and d>20 and d<76:height=minf(height,47.4)
	if absf(x)<25 and d>=76 and d<110:height=minf(height,63.4)
	return maxf(-2.4,height)

func route_height(d: float) -> float:
	if d< -123: return lerpf(2.44,4.0,clampf((d+218)/95.0,0,1))
	if d< -115: return 4
	if d< -85: return lerpf(4,18,(d+115)/30)
	if d< -81: return 18
	if d< -51: return lerpf(18,33,(d+81)/30)
	if d< -47: return 33
	if d< -15: return lerpf(33,48,(d+47)/32)
	return 48

func _mat(c: Color) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_color=c
	m.roughness=.9
	return m

func _build_land() -> void:
	var verts:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var rings:=28
	for j in range(rings+1):
		var r: float = maxf(.001,float(j)/rings)
		for p in shore:
			var x: float=p.x*r
			var d: float=p.y*r
			var h: float = _surface_height(x,d,r)
			# Actual shoreline at sea level; outer cliff skirt below water.
			if j==rings: h=-2.4
			verts.append(wp(x,d,h))
			colors.append(Color(.20,.28,.14).lerp(Color(.36,.39,.25),clampf(h/90,0,1)))
	for j in range(rings):
		for i in range(96):
			var a:=j*96+i
			var b:=j*96+(i+1)%96
			for tri in [[a,b,a+96],[b,b+96,a+96]]:
				indices.append_array(PackedInt32Array(tri))
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in indices:
		st.set_color(colors[k]);st.add_vertex(verts[k])
	st.generate_normals()
	var mesh:=st.commit()
	var node:=MeshInstance3D.new()
	node.name="S1_FullIslandLandform"
	node.mesh=mesh
	var m:=_mat(Color.WHITE)
	m.vertex_color_use_as_albedo=true
	m.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=m
	add_child(node)
	node.create_trimesh_collision()
	var area:=0.0
	var min_x:=9999.0
	var max_x:=-9999.0
	for i in range(shore.size()):
		var a:=shore[i];var b:=shore[(i+1)%shore.size()]
		area+=a.cross(b)
		min_x=minf(min_x,-770-a.y);max_x=maxf(max_x,-770-a.y)
	stats={"stage":stage,"land_projection_m2":absf(area)*.5,"world_x_min":min_x,"world_x_max":max_x,"shore_vertices":shore.size(),"west_boundary_ok":min_x>=-960,"remaining_land_art":"S1 blockout, not final environment"}

func _box(label: String, center: Vector3,size: Vector3,color: Color,collision: bool=false) -> MeshInstance3D:
	var n:=MeshInstance3D.new();n.name=label
	var b:=BoxMesh.new();b.size=size;n.mesh=b;n.material_override=_mat(color)
	add_child(n);n.position=center
	if collision:n.create_trimesh_collision()
	if collision:
		for child in n.get_children():
			if child is StaticBody3D:
				for shape_node in child.get_children():
					if shape_node is CollisionShape3D:
						var box_shape := BoxShape3D.new()
						box_shape.size=size
						shape_node.shape=box_shape
	return n

func _build_route() -> void:
	var bridge_h:float=float(layer.world.call("height_at",-552.0,300.0))+.06
	var points:Array = [[-218,bridge_h],[-123,4],[-115,4],[-85,18],[-81,18],[-51,33],[-47,33],[-15,48],[48,48],[76,64],[100,64]]
	var route_faces := PackedVector3Array()
	for i in range(points.size()-1):
		var a:Vector3=wp(0,points[i][0],points[i][1])
		var b:Vector3=wp(0,points[i+1][0],points[i+1][1])
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var side:=Vector3(0,0,4)
		for v in [a-side,b-side,a+side,a+side,b-side,b+side]:st.add_vertex(v)
		st.generate_normals()
		var n:=MeshInstance3D.new();n.name="WalkSurface_%d"%i;n.mesh=st.commit();add_child(n)
		n.material_override=_mat(Color(.66,.64,.57))
		# S2 authored steps cover this collision surface; keep exact incline.
		if stage=="s2" and i>0:n.visible=false
		if i==0:
			n.visible=false
			_bridge_span(a,b,"SeaBridge",true)
		else:
			route_faces.append_array(PackedVector3Array([a-side,b-side,a+side,a+side,b-side,b+side]))
	var route := StaticBody3D.new()
	route.name = "ContinuousStairSupport"
	add_child(route)
	var support := ConcavePolygonShape3D.new()
	support.set_faces(route_faces)
	support.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = support
	route.add_child(collider)
	# Extend the shore approach to the visible coast path south of the wheel.
	# Sampling avoids burying the approach into the ridge at x=-530.
	var last:=Vector3(-445,float(layer.world.call("height_at",-445,300))+.08,300)
	for x in range(-447,-553,-2):
		var ground:=float(layer.world.call("height_at",x,300))
		var design_y:float=lerpf(2.15,4.15,clampf(float(-x-445)/20.0,0,1))
		if x < -501:design_y=lerpf(4.15,bridge_h,clampf(float(-x-501)/51.0,0,1))
		var y:=maxf(ground+.06,design_y)
		var next:=Vector3(x,y,300)
		_bridge_span(last,next,"CoastApproach",false)
		last=next
	_bridge_span(last,Vector3(-552,bridge_h,300),"CoastJoin",false)
	var sign:=Label3D.new();sign.name="IslandBridgeSign"
	sign.text="云岫仙山  ←\n沿桥直行登山";sign.font_size=64;sign.pixel_size=.015
	sign.outline_size=8;sign.position=Vector3(-445,5.8,295)
	add_child(sign)
	# Open apron behind gate, walkable and matched to authored mesh top.
	_box("GateApron",wp(0,5,47.8),Vector3(31,.4,34),Color(.62,.61,.56),true).visible=stage=="s1"

func _bridge_span(a:Vector3,b:Vector3,label:String,piers:bool) -> void:
	var dir:Vector3=(b-a).normalized()
	var right:=Vector3.UP.cross(dir).normalized()
	var up:=dir.cross(right).normalized()
	var frame:=Basis(right,up,dir)
	var deck:=_box(label+"Deck",(a+b)*.5-up*.25,Vector3(8,.5,a.distance_to(b)+.04),Color(.59,.57,.50),false)
	deck.basis=frame
	var body:=StaticBody3D.new();deck.add_child(body)
	var cs:=CollisionShape3D.new();var shape:=BoxShape3D.new()
	shape.size=Vector3(8,.5,a.distance_to(b)+.04);cs.shape=shape;body.add_child(cs)
	for side in [-1,1]:
		var rail:=_box(label+"Rail",(a+b)*.5+right*side*3.85+up*.85,Vector3(.18,.24,a.distance_to(b)+.04),Color(.43,.42,.36),true)
		rail.basis=frame
		var count:=maxi(1,ceili(a.distance_to(b)/4))
		for i in range(count):
			var p:Vector3=a.lerp(b,float(i)/count)+right*side*3.85
			_box(label+"Post",p+Vector3(0,.55,0),Vector3(.26,1.1,.26),Color(.55,.53,.46))
	if piers:
		for i in range(1,8):
			var p:=a.lerp(b,float(i)/8)
			var bottom:=float(layer.world.call("height_at",p.x,p.z))-1.0
			_box("SeaBridgePier",Vector3(p.x,(p.y+bottom)*.5,p.z),Vector3(1.6,p.y-bottom,5.5),Color(.43,.45,.41))

func on_connection(p:Vector3) -> bool:
	return p.x < -443 and p.x > -650 and absf(p.z-300)<4.4 and p.y > 1.0

func _blockout() -> void:
	if stage == "s2":
		return
	# Remaining buildings explicitly grey. Main axis remains unobstructed.
	_box("S1_MainPlatform",wp(0,92,61),Vector3(38,6,48),Color(.52,.54,.5),true)
	_box("S1_MainHallMass",wp(0,94,73),Vector3(22,18,37),Color(.59,.60,.56))
	for x in [-60,60]:
		_box("S1_CourtFoundation",wp(x,38,38),Vector3(32,20,28),Color(.48,.5,.46))
		_box("S1_CourtMass",wp(x,38,54),Vector3(26,12,18),Color(.52,.55,.52))
	if stage=="s1":
		for x in [-7,-2.5,2.5,7]:_box("S1_GateColumn",wp(x,0,51),Vector3(.5,6,.5),Color(.4,.42,.39))
		_box("S1_GateRoofMass",wp(0,0,55),Vector3(10,1.3,19),Color(.37,.4,.38))

func _add_figure_details() -> void:
	var fig: Node3D = layer.player.get("figure")
	if fig==null:return
	var parts:Array=[]
	for c in fig.get_children():
		if c is MeshInstance3D:parts.append(c)
	if parts.size()<12:return
	# Retain native meshes, original colours and native joint/animation ownership.
	for pair in [[0,Vector3(0,.19,-.146),Vector3(.12,.16,.016),Color(.92,.88,.81)], [0,Vector3(0,-.22,-.147),Vector3(.56,.045,.018),Color(.52,.43,.57)], [0,Vector3(0,.05,-.15),Vector3(.018,.18,.02),Color(.67,.57,.67)], [2,Vector3(-.13,-.07,-.252),Vector3(.12,.15,.06),Color(.286,.274,.259)], [2,Vector3(.15,-.045,-.252),Vector3(.09,.10,.06),Color(.286,.274,.259)], [11,Vector3(0,0,.105),Vector3(.3,.045,.022),Color(.69,.65,.5)]]:
		var mi:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=pair[2];mi.mesh=box
		mi.material_override=_mat(pair[3]);parts[pair[0]].add_child(mi);mi.position=pair[1]
	stats["figure_style"]="native_box_meshes_original_palette_plus_clothing_details"

func _gate_collisions() -> void:
	for d in [-3.0,3.0]:
		for x in [-7.0,-2.5,2.5,7.0]:
			var n:=_box("GateColumnProxy",wp(x,d,51),Vector3(.5,6,.5),Color.WHITE,true)
			n.visible=false

func _palace_collisions() -> void:
	# Width/depth are swapped by wp; hidden proxies match authored paving surfaces.
	# The axial stair support reaches full height at depth 76. Start the
	# terrace's centre proxy on its flat section so its front lip cannot block it.
	for p in [[0,36,48,42,32],[0,94,64,51,27],[-44,35,48,48,46],[47,32,48,42,40],[-46,66,48,30,21],[61,17,48,23,20],[64,54,48,26,20],[35,80,48,12,9]]:
		# Paving tiles are snapped outward to a 2 m grid in the authored model.
		var lo_x:float=floor((p[0]-p[3]*.5)/2.0)*2.0+.0075
		var hi_x:float=ceil((p[0]+p[3]*.5)/2.0)*2.0-.0075
		var lo_d:float=floor((p[1]-p[4]*.5)/2.0)*2.0+.0075
		var hi_d:float=ceil((p[1]+p[4]*.5)/2.0)*2.0-.0075
		_box("PalaceFloor",wp((lo_x+hi_x)*.5,(lo_d+hi_d)*.5,p[2]-.25),Vector3(hi_d-lo_d,.5,hi_x-lo_x),Color.WHITE,true).hide()
	for p in [[0,79,64,51.985,6],[-15,75,64,21.985,1.985],[15,75,64,21.985,1.985],[34,57,48.68,3,31]]:
		_box("PalaceFloor",wp(p[0],p[1],p[2]-.25),Vector3(p[4],.5,p[3]),Color.WHITE,true).hide()
	for h in [[0,94,64,46,22],[-46,66,48,25,16],[61,17,48,18,15],[64,54,48,21,15]]:
		var x:float=h[0];var d:float=h[1];var z:float=h[2];var w:float=h[3];var depth:float=h[4]
		_box("HallRear",wp(x,d+depth/2,z+3.1),Vector3(.55,6.2,w),Color.WHITE,true).hide()
		for side in [-1,1]:
			_box("HallSide",wp(x+side*w/2,d,z+3.1),Vector3(depth,6.2,.52),Color.WHITE,true).hide()
			_box("HallFront",wp(x+side*(w/4+1.5),d-depth/2,z+2.9),Vector3(.52,5.8,w/2-3),Color.WHITE,true).hide()
	stats["composition"]="main hall, left practice court, right water garden, side halls, cliff shoulders and cloud sea"

