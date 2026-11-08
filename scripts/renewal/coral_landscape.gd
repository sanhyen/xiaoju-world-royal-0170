extends Node3D
## 星海珊瑚岛改造。保留原有地图登记、甲板、亲水梯和网床互动。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const CENTERS := [Vector3(276,-.8,426),Vector3(280,-.8,441),Vector3(280,-.8,456),Vector3(276,-.8,471)]
const CLOSE_CELL := "Cell_2_4"
const FAR_CELL := "Far_2_4"
const PALETTE := {"wood":Color("#694838"),"beam":Color("#9c7257"),"stone":Color("#b9ac92"),
	"tile":Color("#356361"),"edge":Color("#244642"),"rock":Color("#827d68"),"light_rock":Color("#aaa38b"),
	"leaf":Color("#5e7845"),"grass":Color("#86965a")}

var layer: Node
var _geometry: RefCounted
var _scan_in := 0.0
var hidden_instances := 0
var cleared_shapes := 0

func setup(owner_layer: Node) -> void:
	layer = owner_layer
	_geometry = MeshLib.new()
	_retained_house()
	_pavilion()
	_deck_seating()
	_shore_clusters()
	var mats := {}
	for key in PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = PALETTE[key]
		m.roughness = .89
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats[key] = m
	var mesh := MeshInstance3D.new()
	mesh.name = "CoralArtGeometry"
	mesh.mesh = _geometry.build(mats)
	add_child(mesh)
	_geometry = null
	_sync_cells()

func _box(material: String, p: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	_geometry.begin(material)
	_geometry.box(Transform3D(basis,p),size)

func _beam(material: String, a: Vector3, b: Vector3, width: float) -> void:
	_geometry.begin(material)
	_geometry.beam(a,b,width)

func _retained_house() -> void:
	var c: Vector3 = CENTERS[0]
	# Existing wall infill is thin glass. Build a deep frame around the clear panel
	# and retain the original entrance and floor on the west and south sides.
	for side in [-1.0,1.0]:
		for dz in [-4.0,4.0]:
			_box("stone",c+Vector3(side*4,.14,dz),Vector3(.66,.28,.66))
			_box("wood",c+Vector3(side*4,1.71,dz),Vector3(.42,3.28,.42))
		_box("wood",c+Vector3(side*4,3.24,0),Vector3(.46,.38,8.38))
	for dz in [-3.91,3.91]:
		_box("wood",c+Vector3(0,3.24,dz),Vector3(8.4,.38,.44))
	for dz in [-2.6,0.0,2.6]:
		_box("beam",c+Vector3(4,1.99,dz),Vector3(.43,.20,2.48))
		_box("wood",c+Vector3(4,2.91,dz),Vector3(.41,.22,2.52))
		for edge in [-1.0,1.0]:
			_box("wood",c+Vector3(4,2.46,dz+edge*1.23),Vector3(.42,.99,.18))
	for dx in [-2.75,2.75]:
		_box("wood",c+Vector3(dx,3.06,4),Vector3(2.2,.26,.42))

func _pavilion() -> void:
	var c: Vector3 = CENTERS[1]
	# Two outer pairs of columns, no wall across the old doors.
	for x in [-3.9,3.9]:
		for z in [-3.9,3.9]:
			_box("stone",c+Vector3(x,.12,z),Vector3(.61,.24,.61))
			_box("wood",c+Vector3(x,1.56,z),Vector3(.35,2.92,.35))
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(.36,3.0,.36)
			shape.shape = box
			body.add_child(shape)
			add_child(body)
			body.global_position = c+Vector3(x,1.5,z)
		_box("wood",c+Vector3(x,2.91,0),Vector3(.35,.38,8.5))
	for z in [-4.05,4.05]:
		_box("wood",c+Vector3(0,2.93,z),Vector3(8.6,.37,.37))
	# Solid pitched roof and eaves. Low silhouette leaves the island's shoreline visible.
	var slope := .27
	for side in [-1.0,1.0]:
		var z: float = side*2.34
		_box("tile",c+Vector3(0,3.63,z),Vector3(9.6,.24,4.86),Basis(Vector3.RIGHT,side*slope))
		for i in range(23):
			var x := -4.62+float(i)*.42
			_beam("tile",c+Vector3(x,4.42,0),c+Vector3(x,3.15,side*4.67),.105)
		_box("edge",c+Vector3(0,3.02,side*4.64),Vector3(9.64,.23,.23))
	_box("edge",c+Vector3(0,4.38,0),Vector3(9.75,.25,.25))

func _deck_seating() -> void:
	for i in [2,3]:
		var c: Vector3 = CENTERS[i]
		# Low seats sit outside the retained travel-entry and net-bed path.
		for dz in [-1.7,.2]:
			_box("stone",c+Vector3(3.43,.18,dz),Vector3(.56,.36,.34))
		_box("wood",c+Vector3(3.43,.42,-.75),Vector3(.60,.16,2.37))
		_box("beam",c+Vector3(3.68,.65,-.75),Vector3(.15,.33,2.32))

func _shore_clusters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42106
	# Shoreline pockets are outside the known pier, wading steps and the west beach landing.
	for point in [Vector2(207,429),Vector2(201,449),Vector2(209,461),Vector2(235,466),Vector2(244,453),Vector2(234,427)]:
		for j in range(8):
			var p: Vector2 = point + Vector2(rng.randf_range(-2.7,2.7),rng.randf_range(-2.2,2.2))
			var h: float = layer.world.call("height_at",p.x,p.y)
			if h < -1.65 or h > 4.0:
				continue
			var s := rng.randf_range(.25,1.35) if j<3 else rng.randf_range(.20,.47)
			var wp := Vector3(p.x,h,p.y)
			_rock(wp,s,rng)
			if j%2 == 0:
				for k in range(8):
					var a := rng.randf()*TAU
					var root := wp+Vector3(cos(a)*s*.55,.04,sin(a)*s*.55)
					var end := root+Vector3(cos(a)*.26,rng.randf_range(.24,.48),sin(a)*.26)
					_beam("grass" if k%3==0 else "leaf",root,end,.045)

func _rock(p: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for i in range(7):
		var angle := TAU*float(i)/7.0
		var v := Vector3(cos(angle),0,sin(angle)*.72)
		lower.append(p+v*radius*rng.randf_range(.8,1.1)-Vector3.UP*.15)
		upper.append(p+v*radius*.61+Vector3.UP*radius*rng.randf_range(.32,.66))
	for i in range(7):
		var j := (i+1)%7
		_geometry.begin("rock")
		_geometry.add_quad(lower[i],upper[i],upper[j],lower[j])
		_geometry.begin("light_rock")
		_geometry.add_tri(upper[j],upper[i],p+Vector3.UP*radius*.56)

func _process(delta: float) -> void:
	_scan_in -= delta
	if _scan_in <= 0.0:
		_scan_in = .65
		_sync_cells()

func _sync_cells() -> void:
	var stream: Node = layer.stream
	var close := stream.get_node_or_null(CLOSE_CELL)
	var far := stream.get_node_or_null("DistantWorld/"+FAR_CELL)
	for cell in [close,far]:
		if cell == null:
			continue
		for n in cell.get_children():
			if n.has_meta("coral_art_checked"):
				continue
			n.set_meta("coral_art_checked",true)
			if n is MultiMeshInstance3D:
				_filter_batch(n)
			elif n is MeshInstance3D:
				var b: AABB = n.global_transform*n.get_aabb()
				if b.size.x < 8.5 and b.size.z < 8.5 and _shell_piece(b.get_center()):
					n.hide()
			elif n is Label3D and _shell_piece(n.global_position):
				n.hide()
			elif n is StaticBody3D and cell == close:
				for child in n.get_children():
					if child is CollisionShape3D and child.shape is BoxShape3D:
						if _old_room_collision(child.global_position,child.shape.size):
							child.set_deferred("disabled",true)
							cleared_shapes += 1

func _shell_piece(p: Vector3) -> bool:
	for i in range(1,CENTERS.size()):
		var d: Vector3 = p-CENTERS[i]
		# Roof and eaves extend beyond the occupied floor. Low deck rails and
		# props past the door plane belong to the retained water access.
		if p.y >= 2.28 and p.y < 6.8 and absf(d.x) < 6.1 and absf(d.z) < 6.0:
			return true
		# Palace facade overlays sit just beyond the original 8 m room walls.
		if p.y > .38 and p.y < 2.28 and absf(d.x) < 4.84 and absf(d.z) < 4.88:
			return true
		if p.y > -.76 and p.y < 2.28 and absf(d.x) < 4.12 and absf(d.z) < 4.11:
			return true
	return false

func _old_room_collision(p: Vector3, size: Vector3) -> bool:
	if not _shell_piece(p):
		return false
	# Room columns, partitions, window planes, header and movable furniture.
	# Leave all original floor, stair, net bed and narrow deck railing shapes.
	return (size.y >= 1.18 or (size.x >= .9 and size.z >= .82 and size.y <= .82 and p.y > -.6))

func _filter_batch(node: MultiMeshInstance3D) -> void:
	var source := node.multimesh
	if source == null or source.mesh == null or source.instance_count == 0:
		return
	var aabb := source.mesh.get_aabb()
	var keep: PackedInt32Array = []
	for i in range(source.instance_count):
		var local := source.get_instance_transform(i)
		var b: AABB = (node.global_transform * local) * aabb
		if not _shell_piece(b.get_center()) or b.size.x > 13 or b.size.z > 12:
			keep.append(i)
	if keep.size() == source.instance_count:
		return
	hidden_instances += source.instance_count - keep.size()
	if keep.is_empty():
		node.hide()
		return
	var target := MultiMesh.new()
	target.transform_format = source.transform_format
	target.use_colors = source.use_colors
	target.use_custom_data = source.use_custom_data
	target.mesh = source.mesh
	target.instance_count = keep.size()
	for i in range(keep.size()):
		var old := keep[i]
		target.set_instance_transform(i,source.get_instance_transform(old))
		if source.use_colors:
			target.set_instance_color(i,source.get_instance_color(old))
		if source.use_custom_data:
			target.set_instance_custom_data(i,source.get_instance_custom_data(old))
	node.multimesh = target
