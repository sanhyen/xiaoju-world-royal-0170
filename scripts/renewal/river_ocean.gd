extends RefCounted
## Cut the local channel openings offline. The original sea material can then
## render the remaining surface without testing a mask for every fragment.
const CACHE="res://scripts/renewal/rebuild/assets/river_patches/sea_openings_"

static func apply(rivers:Node, node:MeshInstance3D, baking:bool)->bool:
	var cache:=CACHE+str(node.name)+".res"
	var materials:Array[Material]=[]
	for surface in range(node.mesh.get_surface_count()):
		materials.append(node.get_active_material(surface))
	var mesh:Mesh
	if ResourceLoader.exists(cache):
		mesh=load(cache)
	elif baking:
		mesh=_clip(rivers,node)
		if ResourceSaver.save(mesh,cache)!=OK:return false
	else:
		return false
	if mesh==null or mesh.get_surface_count()!=materials.size():return false
	node.material_override=null
	node.mesh=mesh
	for surface in range(materials.size()):
		node.set_surface_override_material(surface,materials[surface])
	return true

static func _clip(rivers:Node,node:MeshInstance3D)->ArrayMesh:
	var openings:Array[Dictionary]=[]
	for row in rivers.channels:
		var a:=Vector2(row.a.x,row.a.z)
		var b:=Vector2(row.b.x,row.b.z)
		var polygon:=PackedVector2Array()
		var heading:float=(b-a).angle()
		var radius:float=float(row.half)+.45
		for i in range(9):
			polygon.append(a+Vector2.from_angle(heading+PI*.5+PI*i/8.0)*radius)
		for i in range(9):
			polygon.append(b+Vector2.from_angle(heading-PI*.5+PI*i/8.0)*radius)
		var rect:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon:rect=rect.expand(point)
		openings.append({"polygon":polygon,"rect":rect})
	var transform:=node.global_transform
	var inverse:=transform.affine_inverse()
	var mesh:=ArrayMesh.new()
	for surface in range(node.mesh.get_surface_count()):
		var arrays:=node.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for index in range(vertices.size()):indices.append(index)
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0,indices.size(),3):
			var ids:=Vector3i(indices[i],indices[i+1],indices[i+2])
			var a:=vertices[ids.x];var b:=vertices[ids.y];var c:=vertices[ids.z]
			var tri:=PackedVector3Array([transform*a,transform*b,transform*c])
			var rect:=Rect2(Vector2(tri[0].x,tri[0].z),Vector2.ZERO)
			for point in tri:rect=rect.expand(Vector2(point.x,point.z))
			var polygons:Array=[tri]
			for opening in openings:
				if not rect.intersects(opening.rect,true):continue
				var remaining:Array=[]
				for polygon in polygons:
					remaining.append_array(rivers._difference(polygon,opening.polygon))
				polygons=remaining
				if polygons.is_empty():break
			for polygon in polygons:
				for j in range(1,polygon.size()-1):
					for point in [polygon[0],polygon[j],polygon[j+1]]:
						var local:Vector3=inverse*point
						var w:Vector3=rivers._weights(local,a,b,c)
						_emit(st,arrays,ids,w,local)
		st.index()
		st.commit(mesh)
	print("SEA_OPENINGS ",node.name," triangles=",mesh.get_faces().size()/3)
	return mesh

static func _emit(st:SurfaceTool,arrays:Array,ids:Vector3i,w:Vector3,p:Vector3)->void:
	if arrays[Mesh.ARRAY_NORMAL]!=null:
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		st.set_normal((normals[ids.x]*w.x+normals[ids.y]*w.y+normals[ids.z]*w.z).normalized())
	if arrays[Mesh.ARRAY_COLOR]!=null:
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		st.set_color(colors[ids.x]*w.x+colors[ids.y]*w.y+colors[ids.z]*w.z)
	if arrays[Mesh.ARRAY_TEX_UV]!=null:
		var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		st.set_uv(uv[ids.x]*w.x+uv[ids.y]*w.y+uv[ids.z]*w.z)
	if arrays[Mesh.ARRAY_TEX_UV2]!=null:
		var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		st.set_uv2(uv[ids.x]*w.x+uv[ids.y]*w.y+uv[ids.z]*w.z)
	st.add_vertex(p)
