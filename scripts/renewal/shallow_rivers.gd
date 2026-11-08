extends Node3D
## River surface, bed and terrain subtraction share one indexed channel model.
var layer:Node
var channels:Array[Dictionary]=[]
var _buckets:Dictionary={}
var depth:=.726
var player_height:=1.65
var patched_meshes:=0
var patched_shapes:=0
var _seen:Dictionary={}
var _queue:Array[WeakRef]=[]
var _boat_seen:Dictionary={}
var bed_faces:=PackedVector3Array()
var grid_samples:=0
const GRID:=.8
const BUCKET:=32.0
const BANK:=16.0
const CACHE="res://scripts/renewal/rebuild/assets/river_patches/"
var _baking:=false
var _height_cache:Dictionary={}
var envelopes_cleaned:=0
var nature:RefCounted
var _nature_pending:Dictionary={}
var _boat_scan_elapsed:=0.5
var _river_cells:Dictionary={}
var _bed_cells:Dictionary={}

func setup(owner_layer:Node)->void:
	layer=owner_layer
	_baking=OS.get_cmdline_user_args().has("--rectify-bake")
	if _baking:DirAccess.make_dir_recursive_absolute(CACHE)
	for node in layer.player.find_children("*","CollisionShape3D",true,false):
		if node.shape is CapsuleShape3D:player_height=node.shape.height
	depth=player_height*.44
	var rivers:Array=layer.world.get("spec").bay_layout.get("rivers",[])
	for ri in range(rivers.size()):
		var river:Dictionary=rivers[ri]
		var points:Array=river.points
		for i in range(points.size()-1):
			var a:=Vector3(points[i][0],points[i][1],points[i][2]);var b:=Vector3(points[i+1][0],points[i+1][1],points[i+1][2])
			var half:float=float(river.get("width",6))*.5
			var dir:=Vector2(b.x-a.x,b.z-a.z).normalized()
			# The profile uses distance to a segment, hence rounded end caps.
			# Cut the same footprint, with a small conservative outer margin.
			var radius:float=(half+BANK)/cos(PI/24.0)+.025
			var polygon:=PackedVector2Array()
			for endpoint in [0,1]:
				var center:=Vector2(a.x,a.z) if endpoint==0 else Vector2(b.x,b.z)
				var angle:float=dir.angle()+(PI*.5 if endpoint==0 else -PI*.5)
				for j in range(13):polygon.append(center+Vector2.from_angle(angle+PI*float(j)/12.0)*radius)
			var rect:=Rect2(polygon[0],Vector2.ZERO)
			for p in polygon:rect=rect.expand(p)
			var row:Dictionary={"a":a,"b":b,"half":half,"polygon":polygon,"rect":rect,"river":ri,"key":str(river.id)+"_"+str(ri)}
			var index:=channels.size();channels.append(row)
			for x in range(floori(rect.position.x/BUCKET),ceili(rect.end.x/BUCKET)+1):
				for z in range(floori(rect.position.y/BUCKET),ceili(rect.end.y/BUCKET)+1):
					var key:=Vector2i(x,z)
					if not _buckets.has(key):_buckets[key]=[]
					_buckets[key].append(index)
			var padded:=rect.grow(4.0)
			for x in range(floori(padded.position.x/96),floori(padded.end.x/96)+1):
				for z in range(floori(padded.position.y/96),floori(padded.end.y/96)+1):
					_river_cells[Vector2i(x,z)]=true
	_grade_channels()
	_build_bed()
	_mask_ocean()
	nature=preload("res://scripts/renewal/river_nature.gd").new();nature.rivers=self
	for prefix in ["Cell_*","Far_*"]:
		for node in layer.world.find_children(prefix,"Node3D",true,false):_queue_nature(node)
	_install_boat_adapter()
	var old:Node3D=layer.world.find_child("BayConnectedRivers",true,false)
	if old!=null:old.hide()
	var foam:Node3D=layer.world.find_child("Landscape150RiverFoam",true,false)
	if foam!=null:foam.hide()
	# Initial world and each subsequently streamed terrain resource are patched once.
	for node in layer.world.find_children("*","MeshInstance3D",true,false):_consider(node)
	for node in layer.world.find_children("*","CollisionShape3D",true,false):_consider(node)
	get_tree().node_added.connect(_node_added)
	print("SHALLOW_RIVERS river_lines=",rivers.size()," segments=",channels.size()," max_depth=",depth," grid=",grid_samples)

func _indices(p:Vector2)->Array:
	return _buckets.get(Vector2i(floori(p.x/BUCKET),floori(p.y/BUCKET)),[])

func _grade_channels()->void:
	for row in channels:
		var a:Vector3=row.a;var b:Vector3=row.b
		var dir:=Vector3(b.x-a.x,0,b.z-a.z).normalized();var side:=Vector3(dir.z,0,-dir.x)
		var count:=maxi(2,ceili(a.distance_to(b)/3.0));var heights:=PackedFloat32Array()
		for i in range(count+1):
			var p:=a.lerp(b,float(i)/count)
			var left:=p+side*(float(row.half)+12.0);var right:=p-side*(float(row.half)+12.0)
			heights.append(maxf(-2.4,minf(p.y,minf(_terrain_height(Vector2(left.x,left.z)),_terrain_height(Vector2(right.x,right.z)))-.08)))
		var smooth:=heights.duplicate()
		for i in range(heights.size()):
			var total:=0.0;var weight:=0.0
			for j in range(-2,3):
				var w:=3-absi(j);total+=heights[clampi(i+j,0,heights.size()-1)]*w;weight+=w
			smooth[i]=total/weight
		row["water_samples"]=smooth
	# Incident segments share one water level at their common authored endpoint.
	var junctions:Dictionary={}
	for row in channels:
		for endpoint in [0,1]:
			var p:Vector3=row.a if endpoint==0 else row.b
			var key:=Vector2(snappedf(p.x,.01),snappedf(p.z,.01))
			if not junctions.has(key):junctions[key]=[]
			junctions[key].append({"row":row,"index":0 if endpoint==0 else row.water_samples.size()-1})
	for entries in junctions.values():
		var total:=0.0
		for entry in entries:total+=entry.row.water_samples[entry.index]
		for entry in entries:
			var values:PackedFloat32Array=entry.row.water_samples
			values[entry.index]=total/entries.size();entry.row.water_samples=values

func _terrain_height(at:Vector2)->float:
	var key:=Vector2(snappedf(at.x,.01),snappedf(at.y,.01))
	if not _height_cache.has(key):_height_cache[key]=float(layer.world.call("height_at",at.x,at.y))
	return _height_cache[key]

func _water(row:Dictionary,t:float)->float:
	var values:PackedFloat32Array=row.water_samples
	var sample:=clampf(t,0,1)*(values.size()-1);var index:=mini(floori(sample),values.size()-2)
	return lerpf(values[index],values[index+1],sample-index)

func profile(at:Vector2,bank:bool=true,terrain_height:bool=true)->Dictionary:
	var result:Dictionary={};var best:=INF
	var water_total:=0.0;var water_weight:=0.0
	var closest_edge:=INF;var deepest:=0.0;var banks:Array=[]
	for index in _indices(at):
		var row:Dictionary=channels[index]
		var a:Vector3=row.a;var b:Vector3=row.b
		var a2:=Vector2(a.x,a.z);var b2:=Vector2(b.x,b.z)
		var near:=Geometry2D.get_closest_point_to_segment(at,a2,b2)
		var distance:=at.distance_to(near)
		if distance>float(row.half)+(BANK if bank else 0):continue
		var t:=a2.distance_to(near)/maxf(.001,a2.distance_to(b2))
		var water:=_water(row,t)
		# Nearest normalized centre line defines confluences; stable index breaks ties.
		var score:=distance/float(row.half)
		var weight:=exp(-score*score*4.0)
		water_total+=water*weight;water_weight+=weight
		var u:=clampf(distance/float(row.half),0,1)
		var local_depth:=depth*(1.0-smoothstep(.45,1.0,u))
		deepest=maxf(deepest,local_depth)
		var edge:float=distance-float(row.half)
		closest_edge=minf(closest_edge,edge)
		if bank and edge>0:
			banks.append({"outer":near+(at-near).normalized()*(float(row.half)+BANK),"edge":edge})
		if score>=best:continue
		best=score
		var flow:Vector2=(b2-a2).normalized()
		if _water(row,minf(1,t+.01))>_water(row,maxf(0,t-.01))+.001:flow=-flow
		result={"water":water,"depth":local_depth,"distance":distance,"half":row.half,"river":row.river,"flow":flow}
	if not result.is_empty():
		var level:float=water_total/water_weight if water_weight>0 else float(result.water)
		result.water=level;result.depth=deepest;result.bank_distance=closest_edge
		result.bed=level-deepest
		if closest_edge>0:
			var height_total:=0.0;var height_weight:=0.0
			for candidate in banks:
				var w:float=pow(maxf(0.0,1.0-float(candidate.edge)/BANK),4.0)
				var target:float=maxf(level+.06,_terrain_height(candidate.outer)) if terrain_height else level+.06
				height_total+=target*w;height_weight+=w
			var target:float=height_total/height_weight if height_weight>0 else _terrain_height(at) if terrain_height else level+.06
			# One continuous union bank, graded to the uncut outer terrain.
			# Using the already-carved local height doubled the bank gradient.
			result.bed=lerpf(level,target,clampf(closest_edge/BANK,0,1))
	return result

func contains(p:Vector3)->bool:
	if not _bed_cells.has(Vector2i(floori(p.x/GRID),floori(p.z/GRID))):return false
	var row:=profile(Vector2(p.x,p.z))
	if not row.is_empty():return p.y<maxf(float(row.water)+4,float(row.bed)+3) and p.y>float(row.bed)-3
	# The visible replacement includes a terrain overlap collar outside the
	# analytic channel. Keep its walking/jump owner until that collar ends.
	var ground:=_terrain_height(Vector2(p.x,p.z))
	return p.y> -3.7 and p.y>ground-1 and p.y<ground+3

func river_shore(p:CharacterBody3D)->Vector3:
	# The original shore search uses the old deep-channel terrain. Query the
	# replacement bank, with actual capsule clearance, before native docking.
	var origin:=p.global_position
	var space:=p.get_world_3d().direct_space_state
	for radius in range(3,25):
		for direction in range(16):
			var angle:=TAU*float(direction)/16.0
			var at:=Vector2(origin.x,origin.z)+Vector2(cos(angle),sin(angle))*radius
			var bank:=profile(at)
			if bank.is_empty() or float(bank.bank_distance)<.5:continue
			var expected:float=bank.bed
			if expected<float(bank.water)+.03:continue
			var q:=PhysicsRayQueryParameters3D.create(Vector3(at.x,expected+.5,at.y),Vector3(at.x,expected-.3,at.y),1,[p.get_rid()])
			var hit:=space.intersect_ray(q)
			if hit.is_empty() or hit.normal.y<.7:continue
			var landing:Vector3=hit.position
			if layer.safety._valid_safe(landing):return landing+Vector3.UP*.06
	return Vector3.INF

func _build_bed()->void:
	if ResourceLoader.exists(CACHE+"bed_v7.res") and ResourceLoader.exists(CACHE+"water_v7.res"):
		var cached:Mesh=load(CACHE+"bed_v7.res")
		grid_samples=cached.get_meta("grid_samples",0)
		_install_bed(cached,load(CACHE+"water_v7.res"))
		return
	var cells:Dictionary={}
	for row in channels:
		var rect:Rect2=row.rect
		for x in range(floori(rect.position.x/GRID)-1,ceili(rect.end.x/GRID)+1):
			for z in range(floori(rect.position.y/GRID)-1,ceili(rect.end.y/GRID)+1):
				var at:=Vector2((x+.5)*GRID,(z+.5)*GRID)
				if not profile(at,true,false).is_empty():cells[Vector2i(x,z)]=true
	# Overlap the cut terrain by two grid cells. A centre-only raster leaves
	# triangular cracks where the cut boundary crosses the outermost cells.
	var boundary:Array=[]
	for cell in cells:
		for off in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not cells.has(cell+off):boundary.append(cell);break
	for cell in boundary:
		for x in range(-2,3):
			for z in range(-2,3):cells[cell+Vector2i(x,z)]=true
	var bed:=SurfaceTool.new();bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water:=SurfaceTool.new();water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_cache:Dictionary={}
	for cell in cells:
		var points:Array[Vector3]=[];var data:Array[Dictionary]=[]
		for off in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
			var at:=Vector2((cell.x+off.x)*GRID,(cell.y+off.y)*GRID)
			var grid_key:=Vector2i(cell.x+int(off.x),cell.y+int(off.y))
			if not vertex_cache.has(grid_key):vertex_cache[grid_key]=profile(at)
			var row:Dictionary=vertex_cache[grid_key]
			if row.is_empty():
				row={"bed":float(layer.world.call("height_at",at.x,at.y))-.018,"water":0.0,"depth":-1.0,"flow":Vector2.RIGHT,"distance":1000.0,"half":1.0}
			points.append(Vector3(at.x,float(row.bed)-.018,at.y));data.append(row)
		for index in [0,2,1,0,3,2]:
			var p:=points[index]
			bed.set_uv(Vector2(p.x,p.z));bed.set_color(Color(.66,.63,.49));bed.add_vertex(p);bed_faces.append(p)
		var center:=profile(Vector2((cell.x+.5)*GRID,(cell.y+.5)*GRID),false)
		if center.is_empty():continue
		for index in [0,2,1,0,3,2]:
			var p:=points[index];var row:Dictionary=data[index]
			p.y=float(center.water) if row.depth<0 else float(row.water)
			water.set_uv(Vector2(p.x,p.z));water.set_uv2(row.flow)
			water.set_color(Color(clampf(float(row.depth)/depth,0,1),float(row.river) if row.has("river") else 0,0,clampf(float(row.depth)/.13,0,1)))
			water.add_vertex(p)
	grid_samples=cells.size()
	bed.generate_normals();bed.index();water.generate_normals();water.index()
	var bed_mesh:=bed.commit();var water_mesh:=water.commit()
	bed_mesh.set_meta("grid_samples",grid_samples)
	if _baking:
		ResourceSaver.save(bed_mesh,CACHE+"bed_v7.res");ResourceSaver.save(water_mesh,CACHE+"water_v7.res")
	_install_bed(bed_mesh,water_mesh)

func _install_bed(bed_mesh:Mesh,water_mesh:Mesh)->void:
	if ResourceLoader.exists(CACHE+"bed_tinted_union_v7.res"):
		bed_mesh=load(CACHE+"bed_tinted_union_v7.res")
	else:
		var tinted:=ArrayMesh.new()
		for surface in range(bed_mesh.get_surface_count()):
			var arrays:=bed_mesh.surface_get_arrays(surface)
			var colors:=PackedColorArray()
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var row:=profile(Vector2(vertex.x,vertex.z),true,false)
				colors.append(Color(clampf(float(row.depth)/depth,0,1),clampf(float(row.bank_distance)/BANK,0,1),0,1) if not row.is_empty() else Color(0,1,0,1))
			arrays[Mesh.ARRAY_COLOR]=colors;tinted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		tinted.set_meta("grid_samples",grid_samples);bed_mesh=tinted
		if _baking:ResourceSaver.save(bed_mesh,CACHE+"bed_tinted_union_v7.res")
	bed_faces=bed_mesh.get_faces()
	for i in range(0,bed_faces.size(),3):
		var center:Vector3=(bed_faces[i]+bed_faces[i+1]+bed_faces[i+2])/3.0
		_bed_cells[Vector2i(floori(center.x/GRID),floori(center.z/GRID))]=true
	var bed_mat:=ShaderMaterial.new();bed_mat.shader=load("res://scripts/renewal/river_bed.gdshader")
	var bed_tiles:=preload("res://scripts/renewal/spatial_mesh.gd").install(self,bed_mesh,"ShallowRiverBed",bed_mat,CACHE+"bed_chunks_union_v7")
	var water_mat:=ShaderMaterial.new();water_mat.shader=load("res://scripts/renewal/river_water.gdshader")
	for node in preload("res://scripts/renewal/spatial_mesh.gd").install(self,water_mesh,"ShallowRiverWater",water_mat,CACHE+"water_chunks_v7"):node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var support:=Node3D.new();support.name="ShallowRiverBedSupport";add_child(support)
	for tile in bed_tiles:
		var body:=StaticBody3D.new();support.add_child(body)
		var shape:=ConcavePolygonShape3D.new()
		shape.set_faces(tile.mesh.get_faces())
		shape.backface_collision=true
		var cs:=CollisionShape3D.new();cs.shape=shape;body.add_child(cs)

func _mask_ocean()->void:
	var texture:Texture2D
	if ResourceLoader.exists(CACHE+"sea_mask_v7.res"):
		texture=load(CACHE+"sea_mask_v7.res")
	else:
		var img:=Image.create(2048,2048,false,Image.FORMAT_L8);img.fill(Color.BLACK)
		for row in channels:
			var rect:Rect2=row.rect
			var lo:Vector2=(rect.position-Vector2(-640,-720))/Vector2(1280,1440)*2048
			var hi:Vector2=(rect.end-Vector2(-640,-720))/Vector2(1280,1440)*2048
			for x in range(maxi(0,floori(lo.x)),mini(2048,ceili(hi.x)+1)):
				for z in range(maxi(0,floori(lo.y)),mini(2048,ceili(hi.y)+1)):
					var p:=Vector2(-640+(x+.5)/2048.0*1280,-720+(z+.5)/2048.0*1440)
					var a:Vector3=row.a;var b:Vector3=row.b
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(a.x,a.z),Vector2(b.x,b.z)))<float(row.half)+.45:img.set_pixel(x,z,Color.WHITE)
		texture=ImageTexture.create_from_image(img)
		if _baking:ResourceSaver.save(texture,CACHE+"sea_mask_v7.res")
	var code:="uniform sampler2D renewal_river_mask : filter_linear, repeat_disable;\n"
	for name_text in ["BackgroundOcean","CoastalWaterContinuity130"]:
		var node:MeshInstance3D=layer.world.find_child(name_text,true,false)
		if node==null:continue
		if preload("res://scripts/renewal/river_ocean.gd").apply(self,node,_baking):continue
		var original:ShaderMaterial=node.get_active_material(0)
		if original==null:continue
		var material:ShaderMaterial=original.duplicate(true)
		var shader:=Shader.new()
		shader.code=original.shader.code.replace("void fragment()",code+"\nvoid fragment()")
		shader.code=shader.code.replace("void fragment() {","void fragment() {\n vec2 renewal_uv=(world_position.xz-vec2(-640.0,-720.0))/vec2(1280.0,1440.0);\n if(all(greaterThanEqual(renewal_uv,vec2(0.0))) && all(lessThanEqual(renewal_uv,vec2(1.0))) && texture(renewal_river_mask,renewal_uv).r>0.5){discard;}\n")
		material.shader=shader;material.set_shader_parameter("renewal_river_mask",texture);node.material_override=material

func _node_added(node:Node)->void:
	if node is Node3D and (str(node.name).begins_with("Cell_") or str(node.name).begins_with("Far_")):_queue_nature(node)
	if (node is MeshInstance3D or node is CollisionShape3D) and node.is_inside_tree() and _terrain(node):
		_queue.append(weakref(node))

func _queue_nature(node:Node)->void:
	if nature==null:return
	if nature.relevant(node):_nature_pending[node.get_instance_id()]={"ref":weakref(node),"frame":Engine.get_process_frames()+3}

func _process(delta:float)->void:
	var count:=0
	while not _queue.is_empty() and count<5:
		var ref:WeakRef=_queue.pop_front()
		var node:Node=ref.get_ref()
		if is_instance_valid(node):_consider(node)
		count+=1
	_boat_scan_elapsed+=delta
	var scan_parked:=_boat_scan_elapsed>=.5
	if scan_parked:_boat_scan_elapsed=0.0
	_adapt_boats(scan_parked)
	for key in _nature_pending.keys():
		var row:Dictionary=_nature_pending[key]
		if Engine.get_process_frames()<int(row.frame):continue
		_nature_pending.erase(key)
		var cell:Node3D=row.ref.get_ref()
		if is_instance_valid(cell):nature.adapt(cell)
		break

func flush_pending()->void:
	while not _queue.is_empty():
		var ref:WeakRef=_queue.pop_front()
		var node:Node=ref.get_ref()
		if is_instance_valid(node):_consider(node)

func _terrain(node:Node)->bool:
	var name_text:=str(node.get_path())
	if not ("TerrainPartition110_" in name_text or "TerrainStrata_" in name_text or "FarStrata_" in name_text or "/Terrain/" in name_text):return false
	var cell_start:=name_text.find("/Cell_")
	if cell_start>=0:
		var cell_end:=name_text.find("/",cell_start+1)
		if cell_end>=0:
			var coordinates:=name_text.substr(cell_start+6,cell_end-cell_start-6).split("_")
			if coordinates.size()==2 and coordinates[0].is_valid_int() and coordinates[1].is_valid_int():
				return _river_cells.has(Vector2i(int(coordinates[0]),int(coordinates[1])))
	return true

func _consider(node:Node)->void:
	if not node.is_inside_tree() or _seen.has(node.get_instance_id()) or not _terrain(node):return
	_seen[node.get_instance_id()]=true
	var resource:Resource=node.mesh if node is MeshInstance3D else node.shape
	if resource==null:
		_seen.erase(node.get_instance_id())
		return
	var identity:String=("river_mesh_v7|" if node is MeshInstance3D else "river_v7|")+str(resource.resource_path)+"|"+str(node.global_transform)+"|"+str(node.name)
	var cache_path:=CACHE+identity.sha256_text()+".res"
	if ResourceLoader.exists(cache_path):
		if node is MeshInstance3D:
			var replacement:Mesh=load(cache_path)
			var materials:Array[Material]=[]
			if replacement.get_surface_count()==node.mesh.get_surface_count():
				for i in range(node.mesh.get_surface_count()):materials.append(node.get_active_material(i))
			node.mesh=replacement
			node.material_override=null
			for i in range(node.mesh.get_surface_count()):
				var material:Material=materials[i] if i<materials.size() else node.mesh.surface_get_material(i)
				node.set_surface_override_material(i,material)
			patched_meshes+=1
		else:
			node.shape=load(cache_path);patched_shapes+=1
		return
	if node is MeshInstance3D and node.mesh!=null:
		if not _overlaps(node.global_transform*node.get_aabb()):return
		var before:=patched_meshes
		_patch_mesh(node)
		if _baking and patched_meshes>before:ResourceSaver.save(node.mesh,cache_path)
	elif node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		var faces:PackedVector3Array=node.shape.get_faces()
		var out:=PackedVector3Array()
		for i in range(0,faces.size(),3):
			var tri:PackedVector3Array=PackedVector3Array([node.global_transform*faces[i],node.global_transform*faces[i+1],node.global_transform*faces[i+2]])
			for poly in _subtract(tri):
				for j in range(1,poly.size()-1):
					for p in [poly[0],poly[j],poly[j+1]]:out.append(node.global_transform.affine_inverse()*p)
		if out!=faces:
			var shape:=ConcavePolygonShape3D.new();shape.set_faces(out);shape.backface_collision=true;node.shape=shape;patched_shapes+=1
			if _baking:ResourceSaver.save(shape,cache_path)

func _overlaps(box:AABB)->bool:
	var rect:=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
	for row in channels:
		if rect.intersects(row.rect,true):return true
	return false

func _subtract(tri:PackedVector3Array)->Array:
	var rect:=Rect2(Vector2(tri[0].x,tri[0].z),Vector2.ZERO)
	for p in tri:rect=rect.expand(Vector2(p.x,p.z))
	var candidates:Dictionary={}
	for x in range(floori(rect.position.x/BUCKET),floori(rect.end.x/BUCKET)+1):
		for z in range(floori(rect.position.y/BUCKET),floori(rect.end.y/BUCKET)+1):
			for index in _buckets.get(Vector2i(x,z),[]):
				if rect.intersects(channels[index].rect,true):candidates[index]=true
	var polygons:Array=[tri]
	for index in candidates:
		var remaining:Array=[]
		for polygon in polygons:remaining.append_array(_difference(polygon,channels[index].polygon))
		polygons=remaining
		if polygons.is_empty():break
	return polygons

func _difference(poly:PackedVector3Array,clip:PackedVector2Array)->Array:
	var inside:=poly;var out:Array=[]
	# Clip polygons are counterclockwise in XZ.
	for edge in range(clip.size()):
		if inside.size()<3:break
		var a:=clip[edge];var b:=clip[(edge+1)%clip.size()]
		var keep:=PackedVector3Array();var discard:=PackedVector3Array()
		for i in range(inside.size()):
			var p:=inside[i];var q:=inside[(i+1)%inside.size()]
			var dp:float=(b-a).cross(Vector2(p.x,p.z)-a);var dq:float=(b-a).cross(Vector2(q.x,q.z)-a)
			if dp>=0:keep.append(p)
			else:discard.append(p)
			if (dp>=0)!=(dq>=0):
				var hit:=p.lerp(q,dp/(dp-dq));keep.append(hit);discard.append(hit)
		if discard.size()>=3:out.append(discard)
		inside=keep
	return out

func _weights(p:Vector3,a:Vector3,b:Vector3,c:Vector3)->Vector3:
	var v0:=b-a;var v1:=c-a;var v2:=p-a
	var d00:=v0.dot(v0);var d01:=v0.dot(v1);var d11:=v1.dot(v1);var d20:=v2.dot(v0);var d21:=v2.dot(v1)
	var denom:=d00*d11-d01*d01
	if absf(denom)<1e-12:return Vector3(1,0,0)
	var v:=(d11*d20-d01*d21)/denom;var w:=(d00*d21-d01*d20)/denom
	return Vector3(1-v-w,v,w)

func _patch_mesh(node:MeshInstance3D)->void:
	var mesh:=ArrayMesh.new();var changed:=false;var mats:Array=[]
	for surface in range(node.mesh.get_surface_count()):
		var arrays:=node.mesh.surface_get_arrays(surface)
		if arrays.is_empty():return
		var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in range(verts.size()):indices.append(i)
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count:=0
		for i in range(0,indices.size(),3):
			var ids:=[indices[i],indices[i+1],indices[i+2]]
			var source:=PackedVector3Array([verts[ids[0]],verts[ids[1]],verts[ids[2]]])
			var tri:=PackedVector3Array([node.global_transform*source[0],node.global_transform*source[1],node.global_transform*source[2]])
			var pieces:=_subtract(tri)
			if pieces.size()!=1 or pieces[0]!=tri:changed=true
			for poly in pieces:
				for j in range(1,poly.size()-1):
					for point in [poly[0],poly[j],poly[j+1]]:
						var p:Vector3=node.global_transform.affine_inverse()*point
						var weights:=_weights(p,source[0],source[1],source[2])
						if arrays[Mesh.ARRAY_COLOR]!=null and not arrays[Mesh.ARRAY_COLOR].is_empty():
							st.set_color(arrays[Mesh.ARRAY_COLOR][ids[0]]*weights.x+arrays[Mesh.ARRAY_COLOR][ids[1]]*weights.y+arrays[Mesh.ARRAY_COLOR][ids[2]]*weights.z)
						if arrays[Mesh.ARRAY_TEX_UV]!=null and not arrays[Mesh.ARRAY_TEX_UV].is_empty():
							st.set_uv(arrays[Mesh.ARRAY_TEX_UV][ids[0]]*weights.x+arrays[Mesh.ARRAY_TEX_UV][ids[1]]*weights.y+arrays[Mesh.ARRAY_TEX_UV][ids[2]]*weights.z)
						if arrays[Mesh.ARRAY_NORMAL]!=null and not arrays[Mesh.ARRAY_NORMAL].is_empty():
							st.set_normal((arrays[Mesh.ARRAY_NORMAL][ids[0]]*weights.x+arrays[Mesh.ARRAY_NORMAL][ids[1]]*weights.y+arrays[Mesh.ARRAY_NORMAL][ids[2]]*weights.z).normalized())
						else:st.set_normal(Vector3.UP)
						st.add_vertex(p);count+=1
		if count==0:continue
		st.index();st.commit(mesh);mats.append(node.get_active_material(surface))
	if changed and mesh.get_surface_count()>0:
		for i in range(mats.size()):mesh.surface_set_material(i,mats[i])
		node.mesh=mesh;node.material_override=null
		for i in range(mats.size()):node.set_surface_override_material(i,mats[i])
		patched_meshes+=1

func _adapt_boats(scan_parked:bool)->void:
	var boat:Node=layer.player.get("boat_controller")
	if not is_instance_valid(boat):return
	# Repeated board/leave sequences can leave an older vessel box attached to
	# the character after the controller has released its latest envelope.
	var active_kind:=not str(boat.get("kind")).is_empty()
	for child in layer.player.get_children():
		if not child is CollisionShape3D or not child.shape is BoxShape3D:continue
		var size:Vector3=child.shape.size
		var vessel_box:bool=child.get_meta("renewal_vessel_envelope",false) or (size.x>=1.0 and size.y<=1.8 and size.z>=3.0)
		if not vessel_box:continue
		if active_kind:child.set_meta("renewal_vessel_envelope",true)
		elif not bool(layer.player.get("seated")):
			if boat.get("envelope")==child:boat.set("envelope",null)
			child.disabled=true;layer.player.remove_child(child);child.queue_free();envelopes_cleaned+=1
	var roots:Array=[]
	var active:Node3D=boat.get("model")
	if is_instance_valid(active):roots.append(active)
	if scan_parked:
		for value in boat.get("moored"):
			if is_instance_valid(value):roots.append(value)
		for value in boat.get("free_models"):
			if is_instance_valid(value):roots.append(value)
		for value in boat.get("public_models").values():
			if is_instance_valid(value):roots.append(value)
	for root in roots:
		var id:int=root.get_instance_id()
		var water:=profile(Vector2(root.global_position.x,root.global_position.z),false)
		if water.is_empty():
			if _boat_seen.has(id):
				for row in _boat_seen[id]:
					var node:MeshInstance3D=row.ref.get_ref()
					if is_instance_valid(node):node.mesh=row.mesh
				_boat_seen.erase(id)
			continue
		if _boat_seen.has(id):continue
		var saved:Array=[]
		var floor_y:float=float(water.water)-root.global_position.y-depth+.15
		for node in root.find_children("*","MeshInstance3D",true,false):
			if node.mesh==null:continue
			var at:Transform3D=root.global_transform.affine_inverse()*node.global_transform
			var mesh:=ArrayMesh.new();var changed:=false
			for surface in range(node.mesh.get_surface_count()):
				var arrays:Array=node.mesh.surface_get_arrays(surface)
				var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
				for i in range(points.size()):
					var p:Vector3=at*points[i]
					if p.y<floor_y:p.y=floor_y;points[i]=at.affine_inverse()*p;changed=true
				arrays[Mesh.ARRAY_VERTEX]=points
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				mesh.surface_set_material(surface,node.mesh.surface_get_material(surface))
			if changed:saved.append({"ref":weakref(node),"mesh":node.mesh});node.mesh=mesh
		_boat_seen[id]=saved
		root.set_meta("river_draft_m",depth-.15)

func _install_boat_adapter()->void:
	var boat:Node=layer.player.get("boat_controller")
	if not is_instance_valid(boat):return
	var saved:Dictionary={}
	for prop in boat.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:saved[prop.name]=boat.get(prop.name)
	var was_physics:=boat.is_physics_processing();var was_process:=boat.is_processing()
	boat.set_script(load("res://scripts/renewal/shallow_boat_adapter.gd"))
	for key in saved:boat.set(key,saved[key])
	boat.set("renewal_river_owner",self)
	boat.set_physics_process(was_physics);boat.set_process(was_process)
