extends Node3D
## Physical counterparts of palace_collision_20261107.glb. Dimensions are in authored
## metres: x across the court, y up the island, z elevation (same as island.wp).
var island: Node3D
var _body: StaticBody3D
var shape_count := 0

func setup(site: Node3D, palace: Node3D) -> void:
	island = site
	_body = StaticBody3D.new()
	_body.name = "PalaceStructure"
	_body.collision_layer = 1
	_body.collision_mask = 1
	add_child(_body)
	# Plaster includes the gate's closed side panels and upstairs walls, which
	# cannot be inferred from the old four ground-floor hall proxies.
	# Roof shells catch jumps; no collision is generated for foliage or water.
	for label in ["S2_plaster","S2_tile"]:
		var visual: MeshInstance3D = palace.get_node(label)
		var shell := visual.mesh.create_trimesh_shape()
		shell.backface_collision = true
		_add(shell,visual.global_transform)
	_gate()
	for hall in [[0,94,64,46,22],[-46,66,48,25,16],[61,17,48,18,15],[64,54,48,21,15]]:
		_hall(hall[0],hall[1],hall[2],hall[3],hall[4])
	_guardrails()
	for x in [31,39]:
		for depth in [77,83]:
			_box(Vector3(x,depth,48.20),Vector3(.73,.73,.40))
			_column(Vector3(x,depth,48.4),Vector3(x,depth,53),.18)
		# Visible pavilion benches.
		_box(Vector3(x,82.22,48.67),Vector3(.55,2.63,.16))
		for depth in [81.22,83.15]:
			_box(Vector3(x,depth,48.31),Vector3(.48,.36,.62))
	print("ISLAND_STRUCTURE_COLLISION shapes=",shape_count)

func _world(point: Vector3) -> Vector3:
	return island.wp(point.x,point.y,point.z)

func _add(shape: Shape3D, at: Transform3D) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	_body.add_child(node)
	node.global_transform = at
	shape_count += 1

func _box(center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.y,size.z,size.x)
	_add(shape,Transform3D(Basis.IDENTITY,_world(center)))

func _column(bottom: Vector3, top: Vector3, radius: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = top.z-bottom.z
	_add(shape,Transform3D(Basis.IDENTITY,_world((bottom+top)*.5)))

func _rail(a: Vector3, b: Vector3) -> void:
	var start := _world(a)
	var end := _world(b)
	var direction := (end-start).normalized()
	var across := Vector3.UP.cross(direction).normalized()
	var frame := Basis(across,direction.cross(across),direction)
	var shape := BoxShape3D.new()
	# Continuous solid band fills the baluster gaps for the player's capsule.
	shape.size = Vector3(.30,1.36,start.distance_to(end)+.30)
	_add(shape,Transform3D(frame,(start+end)*.5+Vector3.UP*.64))

func _gate() -> void:
	for depth in [-3,3]:
		for x in [-7,-2.5,2.5,7]:
			_box(Vector3(x,depth,48.22),Vector3(.85,.85,.44))
			_column(Vector3(x,depth,48.4),Vector3(x,depth,54.5),.25)
	_box(Vector3(0,0,54.2),Vector3(14.6,6.4,.46))
	for side in [-1,1]:
		var x: float = side*11
		_box(Vector3(x,0,48.25),Vector3(5,7,.5))
		for dx in [-1.6,1.6]:
			for depth in [-2,2]:
				_column(Vector3(x+dx,depth,48.5),Vector3(x+dx,depth,52.3),.17)

func _hall(cx: float, depth: float, height: float, width: float, length: float) -> void:
	for i in range(7):
		var x := cx-width*.5+width*i/6.0
		for d in [depth-length*.5-1,depth+length*.5]:
			# The front centre post was removed from the authored doorway.
			if i==3 and d<depth:
				continue
			_box(Vector3(x,d,height+.23),Vector3(.9,.9,.46))
			_column(Vector3(x,d,height+.46),Vector3(x,d,height+6.7),.25)
	for dx in [-3.15,3.15]:
		_box(Vector3(cx+dx,depth-length*.5,height+2.64),Vector3(.32,.64,5.28))
	_box(Vector3(cx,depth-length*.5,height+5.52),Vector3(6.1,.64,.64))
	_box(Vector3(cx,depth,height+6.35),Vector3(width,length,.22))
	_box(Vector3(cx,depth+length*.22,height+.9),Vector3(3.5,1.2,1.8))
	for dx in [-width*.32,width*.32]:
		_box(Vector3(cx+dx,depth,height+.5),Vector3(1.1,length*.5,1))

func _guardrails() -> void:
	# All visible stair and courtyard rails from build_slice.py/build_palace.py.
	for flight in [[-115,-85,4,18],[-81,-51,18,33],[-47,-15,33,48],[48,76,48,64]]:
		for side in [-1,1]:
			var x: float = side*(4.3 if flight[0]==48 else 4.5)
			_rail(Vector3(x,flight[0],flight[2]),Vector3(x,flight[1],flight[3]))
	for side in [-1,1]:
		if side==1:
			# Side bridge: a visible opening, aligned with its 3.45 m deck.
			_rail(Vector3(17.2,-10,48),Vector3(17.2,12.142857,48))
			_rail(Vector3(17.2,16.571429,48),Vector3(17.2,21,48))
		else:
			_rail(Vector3(-17.2,-10,48),Vector3(-17.2,21,48))
		for span in ([[12,27.5],[32.5,57]] if side==1 else [[12,37.5],[42.5,57]]):
			_rail(Vector3(side*68,span[0],48),Vector3(side*68,span[1],48))
		_rail(Vector3(side*18,17,48),Vector3(side*18,47,48))
	for span in [[-17,-5],[5,17]]:
		_rail(Vector3(span[0],-10,48),Vector3(span[1],-10,48))
	for span in [[-68,-20],[20,68]]:
		_rail(Vector3(span[0],12,48),Vector3(span[1],12,48))
	for x in [32.4,35.6]:
		_rail(Vector3(x,42,48.7),Vector3(x,72,48.7))
