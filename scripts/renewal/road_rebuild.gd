extends Node
## P3 道路重建 mesh + UV + 路缘
##
## 原版路面 31 个 mesh 都没有 UV，`path_axis` 是材质级 uniform —— 一个 cell 里
## 几十条路共用一个方向值，斜街上的砖缝直接横着走。这是数据结构缺失，
## 只调 shader 参数救不回来。
##
## 这里按 `bay_layout.roads` 的 480 条折线重新挤出路面：UV 的 u 沿路走、
## v 横跨路，砖缝天然垂直于路；路缘、中心磨损、近水湿痕全部按 v 做。
## 按 id 前缀分三组材质（石板 / 方砖 / 碎石土径），3 个 draw call。
##
## 本轮为可见路面补匹配承托，并复查顶点和边线接缝。
## 开关：--road=0

const SHADER_PATH := "res://shaders/road_paving.gdshader"

const STEP := 1.5
## 横向顶点位置（-1 左缘 .. +1 右缘）。边缘两点额外下沉，形成路缘压边。
const LATERAL := [-1.0, -0.86, -0.45, 0.0, 0.45, 0.86, 1.0]
const LIFT := 0.018
const EDGE_DROP := 0.025
const U_SCALE := 1.56
const MIN_WIDTH := 0.1
const SEA_Y := -2.4
const CHERRY_REPAIRS := [Vector2i(32,50)]

var layer: Node
var world: Node
var enabled := true
var built := false
var _tris := 0
var _roads := 0
var polish_enabled := true
var depth_layout := {}
var groups: Array = []
var snap_elapsed := 0.0
var snap_origin := Vector3.INF
var last_snap_samples := 0
var last_snap_max_gap := 0.0
var settle_resnap := false
var repaired_paths: Array[Array] = []
var _support_cells:Dictionary={}
var seam_repairs:Array[Vector3]=[]
var _seam_points:=PackedVector3Array()
var _seam_cursor:=0
var _seam_root:Node3D
var _seam_cells:Dictionary={}
var _seam_boxes:Dictionary={}
var _seam_positions:Dictionary={}

func setup(p_layer: Node) -> void:
	layer = p_layer
	world = layer.world
	for a in OS.get_cmdline_user_args():
		if a == "--road=0":
			enabled = false
		elif a == "--environment-polish=0":
			polish_enabled = false

func build() -> void:
	if not enabled or world == null or built:
		return
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		push_error("road shader missing")
		return
	var spec = world.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var bay = (spec as Dictionary).get("bay_layout", {})
	if typeof(bay) != TYPE_DICTIONARY:
		return
	var roads = (bay as Dictionary).get("roads", [])
	if not (roads is Array):
		return

	# 三个材质组：0 石板 / 1 方砖 / 2 碎石土径
	var mats: Array[ShaderMaterial] = []
	var params := [
		{"base_col": Color(0.53, 0.50, 0.43), "brick_w": 2.0, "brick_h": 1.0, "seam_strength": 0.12, "is_gravel": 0.0},
		{"base_col": Color(0.50, 0.46, 0.39), "brick_w": 1.56, "brick_h": 0.78, "seam_strength": 0.12, "is_gravel": 0.0},
		{"base_col": Color(0.43, 0.38, 0.30), "brick_w": 1.0, "brick_h": 1.0, "seam_strength": 0.0, "is_gravel": 1.0},
	]
	for pr in params:
		var m := ShaderMaterial.new()
		m.shader = sh
		for k in (pr as Dictionary).keys():
			m.set_shader_parameter(str(k), (pr as Dictionary)[k])
		m.set_shader_parameter("wet_strength", 0.0)
		mats.append(m)

	# 累积三组几何
	var acc := []
	for i in range(3):
		acc.append({"v": PackedVector3Array(), "source": PackedVector3Array(), "ground": PackedFloat32Array(), "bridges": PackedByteArray(), "offsets": PackedFloat32Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()})

	var ordered: Array = (roads as Array).duplicate()
	_build_road_supports(ordered)
	if polish_enabled:
		ordered.sort_custom(func(a,b):return str(a.get("id",""))<str(b.get("id","")))
		depth_layout = preload("res://scripts/renewal/road_depth.gd").assign(ordered)
		print("ROAD_JUNCTION roads=%d overlaps=%d layers=%d max_lift=%.4fm" % [depth_layout.roads,depth_layout.edges,depth_layout.max_rank+1,depth_layout.max_lift_m])
	for r in ordered:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var w := float((r as Dictionary).get("width", 0.0))
		if w < MIN_WIDTH:
			continue
		var pts = (r as Dictionary).get("points", [])
		if not (pts is Array) or (pts as Array).size() < 2:
			continue
		var raw: Array[Vector3] = []
		for p in pts:
			if p is Array and (p as Array).size() >= 3:
				raw.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if raw.size() < 2:
			continue
		var line := _resample(raw, STEP)
		if line.size() < 2:
			continue
		var kind := _kind_of(str((r as Dictionary).get("id", "")))
		var lift := 0.0
		if polish_enabled:
			lift = float(depth_layout.ranks.get(str(r.get("id","")),0))*float(depth_layout.step_m)
		_emit(line, w, acc[kind],lift,bool(r.get("bridge",false)))
		_roads += 1

	for i in range(3):
		_commit(acc[i], mats[i], i)

	groups = acc
	_seam_root=Node3D.new();_seam_root.name="RoadVertexSeams";layer.world.add_child(_seam_root)
	for g in groups:
		_seam_points.append_array(g.v)
		var neighbors:Dictionary={};var edges:Dictionary={};var ids:PackedInt32Array=g.i
		for triangle in range(0,ids.size(),3):
			for pair in [[ids[triangle],ids[triangle+1]],[ids[triangle+1],ids[triangle+2]],[ids[triangle+2],ids[triangle]]]:
				var a:int=mini(pair[0],pair[1]);var b:int=maxi(pair[0],pair[1]);var key:=Vector2i(a,b)
				if edges.has(key):continue
				edges[key]=true
				if not neighbors.has(a):neighbors[a]=[]
				if not neighbors.has(b):neighbors[b]=[]
				neighbors[a].append(b);neighbors[b].append(a)
				_queue_edge(g.v[a],g.v[b])
		g["neighbors"]=neighbors
	built = true
	print("ROAD_REBUILT roads=%d tris=%d" % [_roads, _tris])

func _queue_edge(a:Vector3,b:Vector3)->void:
	var steps:=maxi(2,ceili(a.distance_to(b)))
	for i in range(1,steps):_seam_points.append(a.lerp(b,float(i)/steps))

func _kind_of(id: String) -> int:
	if id.begins_with("coast_") or id.begins_with("vehicle_"):
		return 0
	if id.begins_with("landscape150_"):
		return 2
	return 1

func _emit(line: Array[Vector3], width: float, g: Dictionary, depth_lift: float, bridge: bool) -> void:
	var verts: PackedVector3Array = g["v"]
	var uvs: PackedVector2Array = g["uv"]
	var uv2: PackedVector2Array = g["uv2"]
	var cols: PackedColorArray = g["c"]
	var idx: PackedInt32Array = g["i"]
	var source: PackedVector3Array = g["source"]
	var offsets: PackedFloat32Array = g["offsets"]
	var ground: PackedFloat32Array = g["ground"]
	var bridges: PackedByteArray = g["bridges"]
	var base := verts.size()
	var half := width * 0.5 + 0.15
	var n := line.size()
	var dist := 0.0

	for i in range(n):
		var c := line[i]
		var t := _tangent(i, line)
		var side := Vector3(t.z, 0.0, -t.x)
		if i > 0:
			dist += line[i - 1].distance_to(c)
		for k in range(LATERAL.size()):
			var lat: float = LATERAL[k]
			var p := c + side * (half * lat)
			var terrain_y := float(world.call("height_at",p.x,p.z))
			ground.append(terrain_y)
			bridges.append(1 if bridge else 0)
			p.y = c.y if bridge else terrain_y
			p.y += LIFT + depth_lift
			verts.append(p)
			source.append(p)
			offsets.append(depth_lift)
			uvs.append(Vector2(dist / U_SCALE, (lat + 1.0) * 0.5))
			uv2.append(Vector2(dist,(lat+1.0)*half))
			cols.append(Color(1, 1, 1, clampf((p.y-(SEA_Y+2.0))/26.0,0,1)))

	var rows := LATERAL.size()
	for i in range(n - 1):
		for k in range(rows - 1):
			var i0 := base + i * rows + k
			var i1 := i0 + 1
			var i2 := i0 + rows
			var i3 := i2 + 1
			idx.append_array([i0, i2, i1, i1, i2, i3])
	_tris += (n - 1) * (rows - 1) * 2
	# PackedArray 是值类型，必须写回字典，否则累加结果全部丢失
	g["source"] = source
	g["offsets"] = offsets
	g["ground"] = ground
	g["bridges"] = bridges
	g["v"] = verts
	g["uv"] = uvs
	g["uv2"] = uv2
	g["c"] = cols
	g["i"] = idx

func _build_road_supports(records: Array) -> void:
	# Restore physical support on the two cherry ridge runs measured with missing road support.
	var by_id := {}
	for road in records:
		by_id[str(road.get("id",""))] = road
	for extent in CHERRY_REPAIRS:
		var line: Array[Vector3] = []
		for i in range(extent.x,extent.y+1):
			var road = by_id.get("landscape150_cherry_loop_%03d"%i)
			if road == null:
				line.clear()
				break
			for p in road.points:
				var point := Vector3(p[0],p[1],p[2])
				if line.is_empty() or line[-1].distance_to(point)>.01:
					line.append(point)
		if line.size()<2:
			continue
		repaired_paths.append(line)
		var faces := PackedVector3Array()
		var rows: Array[Vector3] = []
		# Keep landing lips short and clear of the next native span.
		line[0] += (line[0]-line[1]).normalized()*.38
		line[-1] += (line[-1]-line[-2]).normalized()*.38
		for i in range(line.size()):
			var d := _tangent(i,line)
			var side := d.cross(Vector3.UP)*2.9
			rows.append(line[i]+side+Vector3.UP*.009)
			rows.append(line[i]-side+Vector3.UP*.009)
		for i in range(0,rows.size()-2,2):
			faces.append_array(PackedVector3Array([rows[i],rows[i+2],rows[i+3],rows[i],rows[i+3],rows[i+1]]))
		var body := StaticBody3D.new()
		body.name = "CherryRidgeSupport%d"%extent.x
		add_child(body)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		for i in range(1,line.size()-1):
			var tangent := (line[i+1]-line[i-1]).normalized()
			var joint := BoxShape3D.new()
			joint.size = Vector3(4.25,.22,1.12)
			var plate := CollisionShape3D.new()
			plate.shape = joint
			plate.transform = Transform3D(Basis.looking_at(-tangent,Vector3.UP),line[i]+Vector3.DOWN*.19)
			body.add_child(plate)
		print("ROAD_SUPPORT cherry %d-%d points=%d"%[extent.x,extent.y,line.size()])

func on_repaired_road(p: Vector3) -> bool:
	if p.x < -455 or p.x > -267 or p.z < -541 or p.z > -425:
		return false
	for line in repaired_paths:
		for i in range(line.size()-1):
			var a: Vector3 = line[i]
			var b: Vector3 = line[i+1]
			var start := Vector2(a.x,a.z)
			var end := Vector2(b.x,b.z)
			var pos := Vector2(p.x,p.z)
			var near := Geometry2D.get_closest_point_to_segment(pos,start,end)
			var fraction := start.distance_to(near)/maxf(.01,start.distance_to(end))
			var height := lerpf(a.y,b.y,fraction)
			if pos.distance_to(near)<2.55 and p.y>height-.65 and p.y<height+3.7:
				return true
	return false

func _commit(g: Dictionary, mat: ShaderMaterial, kind: int) -> void:
	var idx: PackedInt32Array = g["i"]
	if idx.size() < 3:
		return
	var art:=Node3D.new();art.name="RoadRebuild%d"%kind;layer.world.add_child(art)
	g["art_root"]=art;g["material"]=mat;g["art_chunks"]={}
	var support:=Node3D.new();support.name="RoadWalkingSupport%d"%kind;layer.world.add_child(support)
	g["support_root"]=support
	g["support_chunks"]={};g["vertex_chunks"]={};g["chunk_nodes"]={};g["snap_cells"]={}
	var vertices:PackedVector3Array=g.v
	var source:PackedVector3Array=g.source
	for index in range(source.size()):
		var vertex:=source[index]
		var cell:=Vector2i(floori(vertex.x/32),floori(vertex.z/32))
		if not g.snap_cells.has(cell):g.snap_cells[cell]=[]
		g.snap_cells[cell].append(index)
	for triangle in range(0,idx.size(),3):
		var center:Vector3=(vertices[idx[triangle]]+vertices[idx[triangle+1]]+vertices[idx[triangle+2]])/3.0
		var key:=Vector2i(floori(center.x/72),floori(center.z/72))
		if not g.support_chunks.has(key):g.support_chunks[key]=[]
		for corner in range(3):
			var vertex_index:int=idx[triangle+corner];g.support_chunks[key].append(vertex_index)
			if not g.vertex_chunks.has(vertex_index):g.vertex_chunks[vertex_index]={}
			g.vertex_chunks[vertex_index][key]=true
	for key in g.support_chunks:g.support_chunks[key]=PackedInt32Array(g.support_chunks[key])
	var indices_by_art_cell:Dictionary={}
	for cell in g.support_chunks:
		var key:=_art_cell(cell)
		if not indices_by_art_cell.has(key):indices_by_art_cell[key]=[]
		indices_by_art_cell[key].append_array(Array(g.support_chunks[cell]))
	for key in indices_by_art_cell:
		_prepare_art_chunk(g,key,indices_by_art_cell[key])
	_refresh_support(g,support,g.support_chunks.keys())
	_refresh_art(g,g.art_chunks.keys())
	print("ROAD_GROUP %d tris=%d" % [kind, idx.size() / 3])

func _art_cell(support_cell:Vector2i)->Vector2i:
	return Vector2i(floori(float(support_cell.x)/2.0),floori(float(support_cell.y)/2.0))

func _prepare_art_chunk(group:Dictionary,key:Vector2i,source_indices:Array)->void:
	var remap:Dictionary={}
	var vertex_ids:=PackedInt32Array()
	var local_indices:=PackedInt32Array()
	var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var colors:=PackedColorArray()
	for source_index in source_indices:
		if not remap.has(source_index):
			remap[source_index]=vertex_ids.size()
			vertex_ids.append(source_index)
			uv.append(group.uv[source_index]);uv2.append(group.uv2[source_index]);colors.append(group.c[source_index])
		local_indices.append(remap[source_index])
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=local_indices
	var node:=MeshInstance3D.new()
	node.name="Paving_%d_%d"%[key.x,key.y]
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin=2.0
	group.art_root.add_child(node)
	group.art_chunks[key]={"node":node,"vertices":vertex_ids,"arrays":arrays}

func _refresh_art(group:Dictionary,keys:Array)->void:
	var world_vertices:PackedVector3Array=group.v
	for key in keys:
		var chunk:Dictionary=group.art_chunks[key]
		var local_vertices:=PackedVector3Array()
		for source_index in chunk.vertices:local_vertices.append(world_vertices[source_index])
		var arrays:Array=chunk.arrays
		arrays[Mesh.ARRAY_VERTEX]=local_vertices
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,group.material)
		chunk.node.mesh=mesh

func _refresh_support(g:Dictionary,root:Node3D,keys:Array)->void:
	var vertices:PackedVector3Array=g.v
	for key in keys:
		var faces:=PackedVector3Array()
		for index in g.support_chunks[key]:faces.append(vertices[index])
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
		if not g.chunk_nodes.has(key):
			var body:=StaticBody3D.new()
			body.name="Support_%d_%d"%[key.x,key.y]
			root.add_child(body)
			if not _support_cells.has(key):_support_cells[key]=[]
			_support_cells[key].append(body.get_rid())
			var cs:=CollisionShape3D.new();body.add_child(cs);g.chunk_nodes[key]=cs
		g.chunk_nodes[key].shape=shape

func _resample(raw: Array[Vector3], step: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := raw.size()
	if n < 2:
		return out
	for i in range(n - 1):
		var p0 := raw[maxi(0, i - 1)]
		var p1 := raw[i]
		var p2 := raw[i + 1]
		var p3 := raw[mini(n - 1, i + 2)]
		var seg := p1.distance_to(p2)
		var steps: int = maxi(1, int(round(seg / step)))
		for s in range(steps):
			var t := float(s)/float(steps)
			var p := _cr(p0,p1,p2,p3,t)
			p.y = lerpf(p1.y,p2.y,t)
			out.append(p)
	out.append(raw[n - 1])
	return out

func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _tangent(i: int, line: Array[Vector3]) -> Vector3:
	var prev := line[maxi(0, i - 1)]
	var nxt := line[mini(line.size() - 1, i + 1)]
	var t := nxt - prev
	t.y = 0.0
	if t.length() < 0.0001:
		return Vector3(1, 0, 0)
	return t.normalized()

func _physics_process(delta:float) -> void:
	if not built or layer.player==null:return
	if _seam_cursor<_seam_points.size():
		var space:PhysicsDirectSpaceState3D=layer.player.get_world_3d().direct_space_state
		var query:=PhysicsRayQueryParameters3D.new();query.exclude=[layer.player.get_rid()];query.collision_mask=1
		var dirty:Dictionary={}
		for i in range(_seam_cursor,mini(_seam_cursor+900,_seam_points.size())):
			var p:=_seam_points[i]
			if _seam_positions.has(p):continue
			query.from=p+Vector3.UP*.08;query.to=p-Vector3.UP*.12
			if not space.intersect_ray(query).is_empty():continue
			var cell:=Vector2i(floori(p.x/72),floori(p.z/72))
			if not _seam_cells.has(cell):
				var body:=StaticBody3D.new()
				body.name="Seams_%d_%d"%[cell.x,cell.y]
				_seam_root.add_child(body)
				_seam_cells[cell]=body
				var cs:=CollisionShape3D.new();cs.name="BatchedSeamFaces";body.add_child(cs)
				_seam_boxes[cell]=[]
			_seam_boxes[cell].append(p)
			_seam_positions[p]=true;dirty[cell]=true
			seam_repairs.append(p)
		for cell in dirty:_refresh_seam_cell(cell)
		_seam_cursor=mini(_seam_cursor+900,_seam_points.size())
	snap_elapsed+=delta
	if snap_elapsed<1.5:return
	snap_elapsed=0
	var origin:Vector3=layer.player.global_position
	if origin.distance_to(snap_origin)<12:
		if settle_resnap:
			snap_nearby()
			settle_resnap=false
		return
	snap_origin=origin
	snap_nearby()
	settle_resnap=true

func _refresh_seam_cell(cell:Vector2i)->void:
	# Keep the exact 6 cm x 12 cm support boxes, but one static face tree per
	# spatial cell avoids thousands of separate small physics shapes/nodes.
	var faces:=PackedVector3Array()
	for p:Vector3 in _seam_boxes[cell]:
		var origin:Vector3=p+Vector3.DOWN*.055
		var corners:=PackedVector3Array([
			origin+Vector3(-.03,-.06,-.03),origin+Vector3(.03,-.06,-.03),
			origin+Vector3(.03,-.06,.03),origin+Vector3(-.03,-.06,.03),
			origin+Vector3(-.03,.06,-.03),origin+Vector3(.03,.06,-.03),
			origin+Vector3(.03,.06,.03),origin+Vector3(-.03,.06,.03)])
		# An off-centre coplanar fan keeps the diagnostic ray at p inside a
		# triangle, rather than exactly on the usual shared top diagonal.
		var centre:Vector3=origin+Vector3(.011,.06,.007)
		for edge in [[4,7],[7,6],[6,5],[5,4]]:
			faces.append_array(PackedVector3Array([corners[edge[0]],corners[edge[1]],centre]))
		for face in [[0,1,2,3],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]]:
			faces.append_array(PackedVector3Array([corners[face[0]],corners[face[1]],corners[face[2]],corners[face[0]],corners[face[2]],corners[face[3]]]))
	var shape:=ConcavePolygonShape3D.new();shape.backface_collision=true;shape.set_faces(faces)
	_seam_cells[cell].get_node("BatchedSeamFaces").shape=shape

func snap_nearby() -> void:
	# Use the streamed walking collision, including intentional elevated links.
	# Sampling each lateral vertex eliminates unsupported flat edges on slopes.
	var space:PhysicsDirectSpaceState3D=layer.player.get_world_3d().direct_space_state
	var origin:Vector3=layer.player.global_position
	last_snap_samples=0;last_snap_max_gap=0
	var exclusion_cache:Dictionary={}
	for group_index in range(groups.size()):
		var g:Dictionary=groups[group_index]
		var verts:PackedVector3Array=g.v
		var source:PackedVector3Array=g.source
		var changed:=false
		var changed_indices:=PackedInt32Array()
		var nearby_indices:Array=[]
		for x in range(floori((origin.x-110)/32),floori((origin.x+110)/32)+1):
			for z in range(floori((origin.z-110)/32),floori((origin.z+110)/32)+1):
				nearby_indices.append_array(g.snap_cells.get(Vector2i(x,z),[]))
		var query:=PhysicsRayQueryParameters3D.new()
		var previous_cell:=Vector2i(100000,100000)
		for i in nearby_indices:
			var p:Vector3=source[i]
			if Vector2(p.x-origin.x,p.z-origin.z).length_squared()>12100:continue
			var is_bridge: bool = g.bridges[i] != 0
			var terrain_y: float = g.ground[i]
			# 普通路只找近地支撑，不吸到屋顶、远高平台或下层水底。
			var low := p.y-3.0 if is_bridge else terrain_y-1.6
			var high := p.y+1.6 if is_bridge else terrain_y+1.35
			var cell:=Vector2i(floori(p.x/72),floori(p.z/72))
			if cell!=previous_cell:
				if not exclusion_cache.has(cell):
					var excluded:Array[RID]=[layer.player.get_rid()]
					for x in range(cell.x-1,cell.x+2):
						for z in range(cell.y-1,cell.y+2):
							var neighbor:=Vector2i(x,z)
							for support in _support_cells.get(neighbor,[]):excluded.append(support)
							if _seam_cells.has(neighbor):excluded.append(_seam_cells[neighbor].get_rid())
					exclusion_cache[cell]=excluded
				query.exclude=exclusion_cache[cell]
				previous_cell=cell
			query.from=Vector3(p.x,high,p.z)
			query.to=Vector3(p.x,low,p.z)
			var hit:=space.intersect_ray(query)
			if hit.is_empty() or hit.normal.y<.68:continue
			var new_y:float=hit.position.y+.025+float(g.offsets[i])
			last_snap_samples+=1
			last_snap_max_gap=maxf(last_snap_max_gap,absf(verts[i].y-new_y))
			if absf(verts[i].y-new_y)>.005:
				verts[i].y=new_y;changed=true
				_seam_points.append(verts[i])
				changed_indices.append(i)
		if changed:
			for index in changed_indices:
				for neighbor in g.neighbors.get(index,[]):_queue_edge(verts[index],verts[neighbor])
			g.v=verts
			var affected:Dictionary={}
			var affected_art:Dictionary={}
			for index in changed_indices:
				for key in g.vertex_chunks.get(index,{}):
					affected[key]=true
					affected_art[_art_cell(key)]=true
			_refresh_support(g,g.support_root,affected.keys())
			_refresh_art(g,affected_art.keys())
