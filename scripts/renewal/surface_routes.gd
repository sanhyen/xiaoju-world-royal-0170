extends Node3D
## Shared source of visible routes, solid support and traversal queries.
const MeshLib=preload("res://scripts/renewal/mesh_lib.gd")
var layer:Node
var paths:Array[Dictionary]=[]
var repairs:Array[Dictionary]=[]
var _builder:RefCounted
var _body:Node3D
var _support_blocks:Dictionary={}
var _mesh:Node3D
var _mats:Dictionary={}
var open_areas:Array[Dictionary]=[]
var _junction_paths:Array=[]
var _building:=false
var _current_path:=-1
var _current_segment:=-1
var _junction_index:Dictionary={}
var _sample_index:Dictionary={}
var _defer_commit:=true
var _drawing_path:=false
var _extra_boxes:Array[Dictionary]=[]
var cloud_guards:Array[Dictionary]=[]

func setup(owner_layer:Node)->void:
	layer=owner_layer
	_builder=MeshLib.new()
	_body=Node3D.new();_body.name="RouteSupports";add_child(_body)
	for pair in [["cloud",Color("#cad8ce")],["wood",Color("#aa8862")],["edge",Color("#4f685f")],["stone",Color("#acaa96")],["light",Color("#9cddd0")]]:
		var mat:=StandardMaterial3D.new();mat.albedo_color=pair[1];mat.roughness=.86
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		if pair[0]=="light":mat.emission_enabled=true;mat.emission=pair[1];mat.emission_energy_multiplier=.28
		_mats[pair[0]]=mat
	var cloud:=ShaderMaterial.new();cloud.shader=load("res://scripts/renewal/cloud_path.gdshader");_mats["cloud"]=cloud
	for pair in [["jade",Color("#d9e5d5")],["gold",Color("#c7b780")]]:
		var mat:=StandardMaterial3D.new();mat.albedo_color=pair[1];mat.roughness=.64
		_mats[pair[0]]=mat
	var ward:=ShaderMaterial.new();ward.shader=load("res://scripts/renewal/cloud_guard.gdshader");_mats["ward"]=ward
	# Existing authored decks: continuous support instead of individual plank gaps.
	var bay:Dictionary=layer.world.get("spec").bay_layout
	for deck in bay.get("decks",[]):
		if deck is Array and deck.size()>=3:
			add_path(PackedVector3Array([_v(deck[0]),_v(deck[1])]),float(deck[2]),"legacy","原有栈道",false,false)
	for area in bay.get("deck_areas",[]):
		var x0:float=area[0];var z0:float=area[1];var x1:float=area[2];var z1:float=area[3];var y:float=area[4]
		if x1-x0<1.0 or z1-z0<1.0:continue
		_box_support(Vector3((x0+x1)*.5,y-.23,(z0+z1)*.5),Vector3(x1-x0,.46,z1-z0))
		paths.append({"points":PackedVector3Array([Vector3(x0,y,(z0+z1)*.5),Vector3(x1,y,(z0+z1)*.5)]),"width":z1-z0,"kind":"legacy","label":"原有露台"})
	commit()

func _v(value:Variant)->Vector3:
	return value if value is Vector3 else Vector3(value[0],value[1],value[2])

func _box_support(p:Vector3,size:Vector3,frame:Basis=Basis.IDENTITY)->void:
	var cs:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;cs.shape=shape
	_support_body(p).add_child(cs);cs.transform=Transform3D(frame,p)
	cs.set_meta("route",str(paths[_current_path].label) if _drawing_path and _current_path>=0 else "platform")
	cs.set_meta("segment",_current_segment)
	cs.set_meta("path_id",_current_path if _drawing_path else -1)

func _support_body(at:Vector3)->StaticBody3D:
	var key:=Vector2i(floori(at.x/72.0),floori(at.z/72.0))
	if not _support_blocks.has(key):
		var body:=StaticBody3D.new();body.name="Supports_%d_%d"%[key.x,key.y]
		_body.add_child(body);_support_blocks[key]=body
	return _support_blocks[key]

func box(key:String,p:Vector3,size:Vector3,solid:bool=false)->void:
	if not _drawing_path and not _building:_extra_boxes.append({"key":key,"p":p,"size":size,"solid":solid})
	_builder.begin(key);_builder.box(Transform3D(Basis.IDENTITY,p),size)
	if solid:_box_support(p,size)

func beam(key:String,a:Vector3,b:Vector3,width:float)->void:
	_builder.begin(key);_builder.beam(a,b,width)

func add_path(points:PackedVector3Array,width:float,kind:String,label:String,visible:bool=true,rails:bool=true)->void:
	paths.append({"points":points,"width":width,"kind":kind,"label":label,"visible":visible,"rails":rails,"id":paths.size()})
	_sample_index.clear()
	_current_path=paths.size()-1
	_drawing_path=true
	var along_distance:=0.0
	var next_post:=[0.0,0.0]
	for i in range(points.size()-1):
		_current_segment=i
		var a:=points[i];var b:=points[i+1]
		var dir:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
		if dir.length_squared()<.01:continue
		var side:=dir.cross(Vector3.UP)*width*.5
		var previous:=points[maxi(0,i-1)];var next:=points[mini(points.size()-1,i+2)]
		var tangent_a:=Vector3(b.x-previous.x,0,b.z-previous.z).normalized()
		var tangent_b:=Vector3(next.x-a.x,0,next.z-a.z).normalized()
		var side_a:=tangent_a.cross(Vector3.UP)*width*.5
		var side_b:=tangent_b.cross(Vector3.UP)*width*.5
		var top:=PackedVector3Array([a-side_a,a+side_a,b-side_b,b+side_b])
		# A narrow continuous spine closes numerical ray/contact seams on the
		# shared diagonal without changing the visible walking surface.
		var along:=(b-a).normalized()
		var across:=Vector3.UP.cross(along).normalized()
		_box_support((a+b)*.5+Vector3.DOWN*.10,Vector3(.40,.20,a.distance_to(b)+.02),Basis(across,along.cross(across),along))
		# A curved ramp's four top corners are not coplanar. Extrude the same two
		# triangles used by the renderer; one quad hull could choose another diagonal.
		for face in [PackedVector3Array([top[0],top[2],top[3]]),PackedVector3Array([top[0],top[3],top[1]])]:
			var hull:PackedVector3Array=face.duplicate()
			for v in face:hull.append(v+Vector3.DOWN*.42)
			var shape:=ConvexPolygonShape3D.new();shape.points=hull
			var cs:=CollisionShape3D.new();cs.shape=shape;_support_body((a+b)*.5).add_child(cs)
			cs.set_meta("route",label);cs.set_meta("segment",i);cs.set_meta("path_id",_current_path)
		if not visible:continue
		var key:="wood" if kind=="wood" else "cloud" if kind=="cloud" else "stone"
		_builder.begin(key)
		_builder.add_quad(a-side_a,b-side_b,b+side_b,a+side_a)
		for sign_value in [-1,1]:
			_builder.begin("edge")
			_builder.add_quad(a+side_a*sign_value,b+side_b*sign_value,b+side_b*sign_value+Vector3.DOWN*.42,a+side_a*sign_value+Vector3.DOWN*.42)
		if kind=="wood":
			var count:=maxi(1,ceili(a.distance_to(b)/.7))
			for j in range(count):
				var p:=a.lerp(b,float(j)/count)+Vector3.UP*.012
				beam("edge",p-side,p+side,.028)
			for j in range(1,maxi(1,ceili(a.distance_to(b)/10))):
				var p:=a.lerp(b,float(j)/maxi(2,ceili(a.distance_to(b)/10)))
				for sign_value in [-1,1]:
					beam("edge",p+side*sign_value,p+side*sign_value*.3+Vector3.DOWN*3.0,.22)
		if rails:
			for sign_value in [-1,1]:
				var ra:Vector3=a+side_a*sign_value+Vector3.UP*.52
				var rb:Vector3=b+side_b*sign_value+Vector3.UP*.52
				var rail_dir:Vector3=(rb-ra).normalized()
				var right:=Vector3.UP.cross(rail_dir).normalized()
				var steps:=maxi(1,ceili(ra.distance_to(rb)/.5))
				var start:=-1
				for k in range(steps+1):
					var blocked:=k==steps or _junction(ra.lerp(rb,(float(k)+.5)/steps))
					if not blocked and start<0:start=k
					if blocked and start>=0:
						var u:=ra.lerp(rb,float(start)/steps);var v:=ra.lerp(rb,float(k)/steps)
						if kind=="cloud":
							cloud_guards.append({"a":u,"b":v,"outside":(side_a+side_b).normalized()*sign_value,"label":label})
							_box_support((u+v)*.5+Vector3.UP*.15,Vector3(.16,1.34,u.distance_to(v)),Basis(right,rail_dir.cross(right),rail_dir))
							beam("jade",u+Vector3.UP*.74,v+Vector3.UP*.74,.11)
							beam("gold",u+Vector3.UP*.81,v+Vector3.UP*.81,.035)
							beam("jade",u-Vector3.UP*.37,v-Vector3.UP*.37,.12)
							_cloud_guard_face(u-Vector3.UP*.32,v-Vector3.UP*.32,along_distance+float(start)/steps*a.distance_to(b))
						else:
							_box_support((u+v)*.5,Vector3(.16,1.04,u.distance_to(v)),Basis(right,rail_dir.cross(right),rail_dir))
							beam("edge",u+Vector3.UP*.46,v+Vector3.UP*.46,.12)
						start=-1
				var side_index:=0 if sign_value==-1 else 1
				while next_post[side_index]<=along_distance+a.distance_to(b):
					var fraction:float=(next_post[side_index]-along_distance)/maxf(.001,a.distance_to(b))
					var p:Vector3=ra.lerp(rb,clampf(fraction,0,1))
					if not _junction(p):
						if kind=="cloud":
							box("jade",p+Vector3.UP*.10,Vector3(.18,1.24,.18))
							box("jade",p-Vector3.UP*.44,Vector3(.31,.16,.31))
							box("gold",p+Vector3.UP*.78,Vector3(.29,.08,.29))
							box("light",p+Vector3.UP*.88,Vector3(.19,.14,.19))
						else:
							box("edge",p,Vector3(.15,1.04,.15))
							if int(next_post[side_index]/4)%4==0:box("light",p+Vector3.UP*.56,Vector3(.23,.13,.23))
					next_post[side_index]+=4.0
		along_distance+=a.distance_to(b)
	for i in range(1,points.size()-1):
		var direction:=Vector3(points[i+1].x-points[i-1].x,0,points[i+1].z-points[i-1].z).normalized()
		if direction.length_squared()>.01:
			_box_support(points[i]+Vector3.DOWN*.09,Vector3(width,.2,.14),Basis.looking_at(-direction,Vector3.UP))
	_drawing_path=false;commit()

func _cloud_guard_face(a:Vector3,b:Vector3,along:float)->void:
	_builder.begin("ward")
	var st:SurfaceTool=_builder._st()
	var points:PackedVector3Array=PackedVector3Array([a,b,b+Vector3.UP*1.05,a+Vector3.UP*1.05])
	var coords:PackedVector2Array=PackedVector2Array([Vector2(along,0),Vector2(along+a.distance_to(b),0),Vector2(along+a.distance_to(b),1),Vector2(along,1)])
	var normal:Vector3=(b-a).cross(Vector3.UP).normalized()
	for index in [0,2,1,0,3,2]:
		st.set_normal(normal);st.set_uv(coords[index]);st.add_vertex(points[index])

func commit()->void:
	if _building or _defer_commit:return
	if _builder.groups.is_empty():return
	if _mesh==null:
		_mesh=Node3D.new();_mesh.name="ConnectedRouteArt";add_child(_mesh)
	var mesh:Mesh=_builder.build(_mats)
	for child in _mesh.get_children():_mesh.remove_child(child);child.queue_free()
	var signature:=HashingContext.new();signature.start(HashingContext.HASH_SHA256)
	for surface in range(mesh.get_surface_count()):
		var arrays:=mesh.surface_get_arrays(surface)
		for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR]:signature.update(var_to_bytes(arrays[slot]))
	var cache:="res://scripts/renewal/rebuild/assets/river_patches/route_chunks_v3_"+signature.finish().hex_encode().substr(0,20)
	preload("res://scripts/renewal/spatial_mesh.gd").install(_mesh,mesh,"RouteArt",null,cache)

func _junction(p:Vector3)->bool:
	for area in open_areas:
		var d:Vector3=p-area.p
		if absf(d.y-.52)<.4 and Vector2(d.x/area.r.x,d.z/area.r.y).length()<.97:return true
	for row in _junction_index.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		# Adjacent segments of this same curve are one continuous road, not
		# junction mouths. Opening their rails left gaps along curved spans.
		if row.path==_current_path:continue
		var a:=Vector2(row.a.x,row.a.z);var b:=Vector2(row.b.x,row.b.z)
		var near:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),a,b)
		if near.distance_to(Vector2(p.x,p.z))>float(row.width)*.5+.28:continue
		var t:=a.distance_to(near)/maxf(.001,a.distance_to(b))
		if absf(p.y-.52-lerpf(row.a.y,row.b.y,t))<.45:return true
	return false

func finalize()->void:
	_junction_paths=paths.duplicate(true)
	_junction_index=_make_index(_junction_paths)
	var old_body:=_body;remove_child(old_body);old_body.queue_free()
	_support_blocks.clear()
	cloud_guards.clear()
	_body=Node3D.new();_body.name="RouteSupports";add_child(_body)
	_builder=MeshLib.new();paths.clear();_building=true
	for row in _junction_paths:add_path(row.points,row.width,row.kind,row.label,row.get("visible",false),row.get("rails",false))
	for row in _extra_boxes:box(row.key,row.p,row.size,row.solid)
	_building=false;_defer_commit=false;commit()
	_sample_index=_make_index(paths)
	_cloud_edges()

func _cloud_edges()->void:
	var blocks:Dictionary={}
	for row in paths:
		if row.kind!="cloud":continue
		var line:PackedVector3Array=row.points
		var distance:=0.0;var next_puff:=0.0
		for i in range(line.size()-1):
			var dir:=(line[i+1]-line[i]).normalized();var side:=dir.cross(Vector3.UP).normalized()
			var length:=line[i].distance_to(line[i+1])
			while next_puff<distance+length:
				var p:=line[i].lerp(line[i+1],(next_puff-distance)/maxf(.001,length))
				var on_island:=false
				for area in open_areas:
					var d:Vector3=p-area.p
					if absf(d.y)<.5 and Vector2(d.x/area.r.x,d.z/area.r.y).length()<.94:on_island=true;break
				if not on_island:
					var block:=Vector2i(floori(p.x/72),floori(p.z/72))
					if not blocks.has(block):blocks[block]=[]
					blocks[block].append(p+side*(1.7+sin(next_puff)*.3)+Vector3.DOWN*.8)
					blocks[block].append(p-side*(1.7+cos(next_puff)*.3)+Vector3.DOWN*.8)
				next_puff+=4.0
			distance+=length
	var puff:=SphereMesh.new();puff.radial_segments=8;puff.rings=4;puff.radius=1;puff.height=1.2
	var material:=StandardMaterial3D.new();material.albedo_color=Color("#becfc5");material.roughness=1
	for block in blocks:
		var positions:Array=blocks[block]
		var origin:=Vector3((block.x+.5)*72,0,(block.y+.5)*72)
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=puff
		batch.instance_count=positions.size()
		for i in range(positions.size()):
			batch.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3(2.5,1,2.0)),positions[i]-origin))
		var node:=MultiMeshInstance3D.new()
		node.name="CloudEdge_%d_%d"%[block.x,block.y]
		node.position=origin
		node.multimesh=batch
		node.material_override=material
		node.visibility_range_end=620
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

func sample(p:Vector3,padding:float=.4)->Dictionary:
	if _sample_index.is_empty():_sample_index=_make_index(paths)
	var at:=Vector2(p.x,p.z)
	for row in _sample_index.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		var a:Vector3=row.a;var b:Vector3=row.b
		var a2:=Vector2(a.x,a.z);var b2:=Vector2(b.x,b.z)
		var near:=Geometry2D.get_closest_point_to_segment(at,a2,b2)
		if near.distance_to(at)>float(row.width)*.5+padding:continue
		var t:=a2.distance_to(near)/maxf(.001,a2.distance_to(b2))
		var height:=lerpf(a.y,b.y,t)
		if absf(p.y-height)<12.0:return {"height":height,"kind":row.kind,"label":row.label}
	return {}

func _make_index(rows:Array)->Dictionary:
	var index:Dictionary={}
	for ri in range(rows.size()):
		var row:Dictionary=rows[ri];var line:PackedVector3Array=row.points
		for i in range(line.size()-1):
			var rect:=Rect2(Vector2(line[i].x,line[i].z),Vector2.ZERO).expand(Vector2(line[i+1].x,line[i+1].z)).grow(float(row.width)*.5+5)
			var part:Dictionary={"path":ri,"segment":i,"a":line[i],"b":line[i+1],"width":row.width,"kind":row.kind,"label":row.label}
			for x in range(floori(rect.position.x/32),floori(rect.end.x/32)+1):
				for z in range(floori(rect.position.y/32),floori(rect.end.y/32)+1):
					var key:=Vector2i(x,z)
					if not index.has(key):index[key]=[]
					index[key].append(part)
	return index

func contains(p:Vector3)->bool:
	return not sample(p).is_empty()
