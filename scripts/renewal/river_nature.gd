extends RefCounted
## Re-anchor natural riverbank props as complete trees; retain built structures.
var rivers:Node
var adjusted_instances:=0
var adjusted_colliders:=0
var seen:Dictionary={}
const CACHE="res://scripts/renewal/rebuild/assets/river_patches/nature_"

func relevant(cell:Node3D)->bool:
	var parts:=str(cell.name).split("_")
	if parts.size()!=3:return false
	var box:=AABB(Vector3(float(parts[1])*96,-100,float(parts[2])*96),Vector3(96,300,96))
	return rivers._overlaps(box)

func adapt(cell:Node3D)->void:
	if not relevant(cell) or seen.has(cell.get_instance_id()):return
	seen[cell.get_instance_id()]=true
	var cache:=CACHE+str(cell.name)+"_v5.json"
	var data:Dictionary={}
	if FileAccess.file_exists(cache):data=JSON.parse_string(FileAccess.get_file_as_string(cache))
	elif DisplayServer.get_name()=="headless":return
	else:
		data=_measure(cell)
		if OS.get_cmdline_user_args().has("--rectify-bake"):FileAccess.open(cache,FileAccess.WRITE).store_string(JSON.stringify(data))
	var baking:=OS.get_cmdline_user_args().has("--rectify-bake")
	for key in data.meshes:
		var node:=cell.get_node_or_null(NodePath(key)) as MultiMeshInstance3D
		if node==null or node.multimesh==null:continue
		var batch_path:=cache.trim_suffix(".json")+"_"+str(key).sha256_text().substr(0,16)+".bin"
		if FileAccess.file_exists(batch_path):
			var original:=node.multimesh
			var buffer:=FileAccess.get_file_as_bytes(batch_path).to_float32_array()
			var mm:=MultiMesh.new()
			mm.transform_format=original.transform_format
			mm.use_colors=original.use_colors
			mm.use_custom_data=original.use_custom_data
			mm.mesh=original.mesh
			mm.instance_count=original.instance_count
			mm.buffer=buffer
			mm.visible_instance_count=original.visible_instance_count
			node.multimesh=mm
		else:
			var mm:MultiMesh=node.multimesh.duplicate()
			for edit in data.meshes[key]:
				var transform:=mm.get_instance_transform(int(edit[0]))
				transform.origin.y+=float(edit[1])
				mm.set_instance_transform(int(edit[0]),transform)
			node.multimesh=mm
			if baking:
				var file:=FileAccess.open(batch_path,FileAccess.WRITE)
				if file!=null:file.store_buffer(mm.buffer.to_byte_array())
		adjusted_instances+=data.meshes[key].size()
	for key in data.colliders:
		var shape:=cell.get_node_or_null(NodePath(key)) as CollisionShape3D
		if shape==null:continue
		shape.global_position.y+=float(data.colliders[key])
		adjusted_colliders+=1

func _color(node:MultiMeshInstance3D,index:int)->Color:
	if node.multimesh.use_colors:return node.multimesh.get_instance_color(index)
	var material:Material=node.material_override if node.material_override!=null else node.multimesh.mesh.surface_get_material(0)
	return material.albedo_color if material is StandardMaterial3D else Color.WHITE

func _bark(color:Color)->bool:
	return color.r<.75 and color.r>color.g*1.18 and color.r<color.g*1.75 and color.g>color.b*1.15

func _leaf(color:Color)->bool:
	return color.g>color.r*1.07 and color.g>color.b*1.08

func _measure(cell:Node3D)->Dictionary:
	var rows:Array=[];var anchors:Array=[]
	for node in cell.find_children("*","MultiMeshInstance3D",true,false):
		if node.multimesh==null or node.multimesh.mesh==null:continue
		var mm:MultiMesh=node.multimesh
		for i in range(mm.instance_count):
			var transform:Transform3D=node.global_transform*mm.get_instance_transform(i)
			var box:AABB=transform*mm.mesh.get_aabb();var center:=box.get_center()
			var river:Dictionary=rivers.profile(Vector2(center.x,center.z))
			if river.is_empty():continue
			var color:=_color(node,i)
			var row:Dictionary={"key":str(cell.get_path_to(node)),"index":i,"box":box,"color":color,"mesh":mm.mesh,"delta":0.0}
			rows.append(row)
			# Forest trunks have this brown palette. Red architectural columns,
			# wide roof members, railings and branches do not qualify as anchors.
			if _bark(color) and box.size.y>.9 and box.size.y<8 and maxf(box.size.x,box.size.z)<.85 and transform.basis.y.normalized().dot(Vector3.UP)>.94:
				var delta:float=float(river.bed)-box.position.y-.025
				if delta<-.18:
					var candidate:=Vector3(center.x,box.position.y,center.z);var merged:=false
					for anchor in anchors:
						if Vector2(candidate.x-anchor.p.x,candidate.z-anchor.p.z).length()<.9 and absf(candidate.y-anchor.p.y)<10:
							if candidate.y<anchor.p.y:anchor.p=candidate;anchor.delta=delta
							merged=true;break
					if not merged:anchors.append({"p":candidate,"delta":delta,"leaves":0})
	for row in rows:
		var color:Color=row.color;var box:AABB=row.box;var center:=box.get_center()
		if not _leaf(color) or maxf(box.size.x,box.size.z)>8:continue
		for anchor in anchors:
			if Vector2(center.x-anchor.p.x,center.z-anchor.p.z).length()<3.5 and box.position.y>anchor.p.y+.7 and box.end.y<anchor.p.y+18:anchor.leaves+=1
	var data:Dictionary={"meshes":{},"colliders":{},"trees":0,"rocks":0}
	for row in rows:
		var box:AABB=row.box;var center:=box.get_center();var color:Color=row.color
		var nearest:=INF
		for anchor in anchors:
			if anchor.leaves<2:continue
			var distance:=Vector2(center.x-anchor.p.x,center.z-anchor.p.z).length()
			var leaf:bool=_leaf(color) and maxf(box.size.x,box.size.z)<8
			var stem:bool=_bark(color) and maxf(box.size.x,box.size.z)<4
			if (leaf or stem) and distance<3.5 and distance<nearest and box.position.y>anchor.p.y-.2 and box.end.y<anchor.p.y+18:
				nearest=distance;row.delta=anchor.delta
		if row.delta==0 and row.mesh is SphereMesh and box.size.y<1.5 and maxf(box.size.x,box.size.z)<5 and color.g>color.b*1.08:
			var river:Dictionary=rivers.profile(Vector2(center.x,center.z))
			row.delta=minf(0,float(river.bed)-box.position.y-.04)
			if row.delta<-.18:data.rocks+=1
		if row.delta>=-.18:continue
		if not data.meshes.has(row.key):data.meshes[row.key]=[]
		data.meshes[row.key].append([row.index,row.delta])
	for anchor in anchors:
		if anchor.leaves<2:continue
		data.trees+=1
		for shape in cell.find_children("*","CollisionShape3D",true,false):
			var p:Vector3=shape.global_position
			if Vector2(p.x-anchor.p.x,p.z-anchor.p.z).length()>.45 or p.y<anchor.p.y or p.y>anchor.p.y+7:continue
			if shape.shape is CylinderShape3D or shape.shape is CapsuleShape3D or (shape.shape is BoxShape3D and maxf(shape.shape.size.x,shape.shape.size.z)<1.2):data.colliders[str(cell.get_path_to(shape))]=anchor.delta
	return data
