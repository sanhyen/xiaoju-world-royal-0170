extends RefCounted
## Partition static art without changing triangles, materials or draw distance.
const SPAN:=72.0

static func install(parent:Node3D,source:Mesh,prefix:String,override_material:Material=null,cache:String="")->Array[MeshInstance3D]:
	var pieces:Array=[]
	if not cache.is_empty() and FileAccess.file_exists(cache+".json"):
		for path in JSON.parse_string(FileAccess.get_file_as_string(cache+".json")):pieces.append(load(path))
	else:
		pieces=partition(source)
		if not cache.is_empty() and OS.get_cmdline_user_args().has("--rectify-bake"):
			var paths:Array=[]
			for i in range(pieces.size()):
				var path:=cache+"_%03d.res"%i
				ResourceSaver.save(pieces[i],path);paths.append(path)
			FileAccess.open(cache+".json",FileAccess.WRITE).store_string(JSON.stringify(paths))
	var nodes:Array[MeshInstance3D]=[]
	for i in range(pieces.size()):
		# Geometry caches must not keep a previous revision's material objects.
		var source_surfaces:PackedInt32Array=pieces[i].get_meta("source_surfaces_v3",PackedInt32Array())
		for surface in range(source_surfaces.size()):pieces[i].surface_set_material(surface,source.surface_get_material(source_surfaces[surface]))
		var node:=MeshInstance3D.new();node.name=prefix+str(i);node.mesh=pieces[i];node.material_override=override_material
		parent.add_child(node);nodes.append(node)
	return nodes

static func partition(source:Mesh)->Array:
	var chunks:Dictionary={}
	var triangles:=0
	for surface in range(source.get_surface_count()):
		var arrays:=source.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var ids:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if ids.is_empty():
			for i in range(vertices.size()):ids.append(i)
		for triangle in range(0,ids.size(),3):
			var center:Vector3=(vertices[ids[triangle]]+vertices[ids[triangle+1]]+vertices[ids[triangle+2]])/3.0
			var key:=Vector2i(floori(center.x/SPAN),floori(center.z/SPAN))
			if not chunks.has(key):chunks[key]={}
			if not chunks[key].has(surface):
				var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);chunks[key][surface]=builder
			var st:SurfaceTool=chunks[key][surface]
			for corner in range(3):
				var index:int=ids[triangle+corner]
				if arrays[Mesh.ARRAY_NORMAL]!=null:st.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
				if arrays[Mesh.ARRAY_TEX_UV]!=null:st.set_uv(arrays[Mesh.ARRAY_TEX_UV][index])
				if arrays[Mesh.ARRAY_TEX_UV2]!=null:st.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][index])
				if arrays[Mesh.ARRAY_COLOR]!=null:st.set_color(arrays[Mesh.ARRAY_COLOR][index])
				if arrays[Mesh.ARRAY_TANGENT]!=null:
					var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
					st.set_tangent(Plane(tangents[index*4],tangents[index*4+1],tangents[index*4+2],tangents[index*4+3]))
				st.add_vertex(vertices[index])
			triangles+=1
	var pieces:Array=[]
	for chunk in chunks.values():
		var mesh:=ArrayMesh.new()
		var source_surfaces:=PackedInt32Array()
		for surface in chunk:
			var st:SurfaceTool=chunk[surface];st.index();st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count()-1,source.surface_get_material(surface))
			source_surfaces.append(surface)
		mesh.set_meta("source_surfaces_v3",source_surfaces)
		pieces.append(mesh)
	print("SPATIAL_MESH chunks=",pieces.size()," triangles=",triangles)
	return pieces
