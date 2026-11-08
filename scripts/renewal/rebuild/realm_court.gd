extends Node3D
## 建筑增量、听云亭桥面和仙阵表现。游记由 celestial_realm 管理。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const WALL = preload("res://scripts/renewal/rebuild/realm_wall.gdshader")
const CLOUD = preload("res://scripts/renewal/rebuild/cloud_sea.gdshader")
var _island: Node3D
var _mesh: RefCounted
var _mats: Dictionary
var _bell: Node3D
var _formation: Node3D
var _chime: AudioStreamWAV
var _pulse: Tween
var _formation_tween: Tween

func setup(island: Node3D, palace: Node3D) -> void:
	_island = island
	_mats = {
		"stone": _surface("#c6c8b6"),
		"shadow": _surface("#86928c"),
		"jade": _surface("#34786e"),
		"jade_deep": _surface("#285451"),
		"wood": _surface("#403d32"),
		"gold": _surface("#d3ae63", .58),
		"paper": _surface("#ad8c55", .82, .12),
		"light": _surface("#95edd7", .34, .8),
		"amber": _surface("#ffe4ad", .45, .57),
	}
	var walls := ShaderMaterial.new()
	walls.shader = WALL
	palace.get_node("S2_plaster").material_override = walls
	_mesh = MeshLib.new()
	_build_gate_details()
	_build_hall()
	_commit(self, "CourtArchitecture")
	_build_cloud_pavilion()
	_build_formation()
	_build_clouds()
	_mesh = null

func _surface(color: String, roughness: float = .83, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	if glow > 0:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = glow
	return material

# Local x crosses the stair, y is elevation and z follows the stair.
func _p(at: Vector3) -> Vector3:
	return _island.wp(at.x,at.z,at.y)

func _box(key: String, at: Vector3, size: Vector3) -> void:
	_mesh.begin(key)
	_mesh.box(Transform3D(Basis.IDENTITY,_p(at)),Vector3(size.z,size.y,size.x))

func _post(key: String, from: Vector3, to: Vector3, radius: float) -> void:
	_mesh.begin(key)
	_mesh.cylinder(_p(from),_p(to),radius,12)

func _bar(key: String, from: Vector3, to: Vector3, width: float) -> void:
	_mesh.begin(key)
	_mesh.beam(_p(from),_p(to),width)

func _commit(parent: Node3D, label: String) -> void:
	var art := MeshInstance3D.new()
	art.name = label
	art.mesh = _mesh.build(_mats)
	parent.add_child(art)
	art.global_position = Vector3.ZERO
	_mesh = MeshLib.new()

func _plaque(title: String, at: Vector3, width: float) -> void:
	_box("wood",at,Vector3(width,1.01,.24))
	_box("jade_deep",at+Vector3(0,0,-.12),Vector3(width-.26,.75,.10))
	for side in [-1,1]:
		_box("gold",at+Vector3(0,side*.45,-.13),Vector3(width-.16,.065,.095))
	var label := Label3D.new()
	label.text = title
	label.font_size = 64
	label.pixel_size = .010
	label.outline_size = 4
	label.modulate = Color("#f4d991")
	label.visibility_range_end = 95.0
	add_child(label)
	label.rotation.y = PI/2.0
	label.global_position = _p(at+Vector3(0,.03,-.205))

func _lantern(at: Vector3) -> void:
	_box("wood",at+Vector3(0,.50,0),Vector3(.085,.94,.085))
	_box("jade_deep",at+Vector3(0,.13,0),Vector3(.48,.14,.48))
	_box("amber",at+Vector3(0,-.14,0),Vector3(.34,.47,.34))
	_box("gold",at+Vector3(0,-.40,0),Vector3(.42,.09,.42))
	for x in [-1,1]:
		for z in [-1,1]:
			_box("wood",at+Vector3(x*.17,-.14,z*.17),Vector3(.055,.48,.055))

func _crest(at: Vector3, size: float) -> void:
	_post("gold",at,at+Vector3.UP*size,.075*size)
	_mesh.begin("gold")
	_mesh.ring(_p(at+Vector3.UP*.61*size),Vector3.RIGHT,.44*size,.045*size,28,5)
	_box("jade",at+Vector3.UP*.60*size,Vector3(.24,.29,.24)*size)
	_box("gold",at+Vector3.UP*size,Vector3(.16,.15,.16)*size)

func _build_gate_details() -> void:
	_crest(Vector3(0,58.58,0),1.12)
	for x in [-6.2,6.2]:
		_lantern(Vector3(x,53.14,-3.16))
		_box("gold",Vector3(x,53.62,-3.24),Vector3(1.18,.075,.09))

func _build_hall() -> void:
	_crest(Vector3(0,81.93,94),1.62)
	_plaque("栖霞殿",Vector3(0,69.52,81.65),4.32)
	_box("wood",Vector3(0,69.53,82.07),Vector3(4.03,.53,.79))
	var furniture := StaticBody3D.new()
	furniture.name = "HallFurniture"
	add_child(furniture)
	for side in [-1,1]:
		var x: float = side*3.45
		_box("shadow",Vector3(x,64.17,82.62),Vector3(.91,.34,.75))
		_box("stone",Vector3(x,64.35,82.62),Vector3(.72,.19,.62))
		_post("wood",Vector3(x,64.43,82.62),Vector3(x,69.28,82.62),.20)
		_solid(furniture,Vector3(x,66.63,82.62),Vector3(.46,5.26,.46))
		for height in [64.52,68.90]:
			_post("gold",Vector3(x,height,82.62),Vector3(x,height+.13,82.62),.213)
		_lantern(Vector3(side*5.20,68.58,81.96))
		for z in [89.5,96.0,102.0]:
			_box("shadow",Vector3(side*8,64.16,z),Vector3(.80,.32,.80))
			_post("wood",Vector3(side*8,64.30,z),Vector3(side*8,69.95,z),.19)
			_solid(furniture,Vector3(side*8,66.92,z),Vector3(.46,5.84,.46))
			_lantern(Vector3(side*7.72,68.57,z))
		_box("wood",Vector3(side*8,69.89,95.45),Vector3(.53,.50,19.45))
		# Side of the hall above its stone plinth. The central doorway stays open.
		_box("shadow",Vector3(side*13.23,64.37,82.72),Vector3(19.38,.70,.18))
		_box("stone",Vector3(side*13.23,64.72,82.61),Vector3(19.40,.11,.26))
		for x_rel in [10.0,14.0,18.0]:
			_box("jade_deep",Vector3(side*x_rel,66.76,104.25),Vector3(3.28,3.00,.25))
			_relief(Vector3(side*x_rel,66.75,104.08),1.15)
	for i in range(9):
		var x := -18.4+i*4.6
		_box("wood",Vector3(x,74.72,86.22),Vector3(1.28,1.87,.22))
		_box("paper",Vector3(x,74.72,86.08),Vector3(1.06,1.61,.09))
		for offset in [-.30,0,.30]:
			_box("wood",Vector3(x+offset,74.72,86.008),Vector3(.065,1.65,.075))
		_box("wood",Vector3(x,74.72,86.007),Vector3(1.15,.078,.075))
	for z in [88.4,93.2,98.0,102.8]:
		_box("wood",Vector3(0,70.10,z),Vector3(16.53,.24,.42))
		_box("gold",Vector3(0,69.964,z),Vector3(15.92,.045,.075))
	_box("jade_deep",Vector3(0,64.027,90.64),Vector3(4.35,.036,10.68))
	for side in [-1,1]:
		_box("gold",Vector3(side*2.05,64.051,90.64),Vector3(.072,.026,10.28))
		_box("gold",Vector3(0,64.052,90.64+side*5.14),Vector3(4.17,.027,.072))
	_box("wood",Vector3(0,69.29,82.58),Vector3(7.52,.39,.51))
	_box("gold",Vector3(0,69.16,82.30),Vector3(6.46,.06,.065))
	_box("shadow",Vector3(0,65.83,96.45),Vector3(3.37,.13,1.25))
	_solid(furniture,Vector3(0,64.96,96.45),Vector3(3.48,1.92,1.24))
	_box("jade",Vector3(0,65.97,96.45),Vector3(1.62,.22,1.02))
	for i in range(8):
		var angle := TAU*i/8.0
		var from := Vector3(0,66.10,96.45)
		var to := from+Vector3(cos(angle)*.87,.30,sin(angle)*.64)
		_bar("gold",from,to,.11)
	_box("jade_deep",Vector3(0,66.39,96.45),Vector3(.48,.43,.48))
	_plaque("聚三印 · 开观星阵",Vector3(0,68.72,104.03),7.20)

func _relief(at: Vector3, radius: float) -> void:
	_mesh.begin("gold")
	_mesh.ring(_p(at),Vector3.RIGHT,radius,.036,30,5)
	for i in range(4):
		var start := at+Vector3(-.82,-.38+i*.22,-.018)
		_bar("gold",start,start+Vector3(1.40,.0,0),.039)
		_bar("gold",start+Vector3(1.40,0,0),start+Vector3(1.64,.12,0),.039)

func _bridge(from: Vector3, to: Vector3) -> void:
	var a := _p(from)
	var b := _p(to)
	var forward := (b-a).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var normal := forward.cross(right)
	var frame := Basis(right,normal,forward)
	var size := Vector3(3.12,.28,a.distance_to(b)+.04)
	var center := (a+b)*.5-normal*.14
	_mesh.begin("stone")
	_mesh.box(Transform3D(frame,center),size)
	var support := StaticBody3D.new()
	support.name = "CloudPavilionBridge"
	add_child(support)
	var deck := BoxShape3D.new()
	deck.size = size
	_add_shape(support,deck,Transform3D(frame,center))
	for side in [-1,1]:
		var offset := Vector3(side*1.49,.79,0)
		_bar("jade",from+offset,to+offset,.16)
		for t in [0.1,.57,.94]:
			var foot := from.lerp(to,t)+Vector3(side*1.49,0,0)
			_post("shadow",foot,foot+Vector3.UP*.83,.10)
		var rail := BoxShape3D.new()
		rail.size = Vector3(.17,.82,size.z)
		_add_shape(support,rail,Transform3D(frame,center+right*1.49*side+Vector3.UP*.55))

func _add_shape(body: StaticBody3D, shape: Shape3D, transform_world: Transform3D) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	body.add_child(node)
	node.global_transform = transform_world

func _solid(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(size.z,size.y,size.x)
	_add_shape(body,box,Transform3D(Basis.IDENTITY,_p(at)))

func _build_cloud_pavilion() -> void:
	# Both ends overlap the authored deck/paving so no jump is required.
	_bridge(Vector3(34,48.025,39.0),Vector3(34,48.69,41.52))
	_bridge(Vector3(34,48.69,72.47),Vector3(34,48.025,75.64))
	_plaque("听云亭",Vector3(35,52.64,76.71),3.80)
	for x in [31.0,39.0]:
		for z in [77.0,83.0]:
			_box("stone",Vector3(x,48.20,z),Vector3(.73,.40,.73))
			_post("gold",Vector3(x,48.40,z),Vector3(x,48.53,z),.21)
		_box("wood",Vector3(x,52.67,80),Vector3(.25,.32,6.22))
		_box("jade",Vector3(x,48.67,82.22),Vector3(.55,.16,2.63))
		for d in [81.22,83.15]:
			_box("shadow",Vector3(x,48.31,d),Vector3(.48,.62,.36))
		_lantern(Vector3(x,51.64,80.0))
	_box("wood",Vector3(35,52.77,80),Vector3(8.1,.27,.27))
	_commit(self,"PavilionTimber")
	_bell = Node3D.new()
	_bell.name = "CloudChime"
	add_child(_bell)
	# Bell geometry is local to the hook so it can sway as one object.
	_mesh.begin("gold")
	_mesh.cylinder(Vector3.ZERO,Vector3.DOWN*.45,.039,8)
	for i in range(6):
		var angle := TAU*i/6.0
		var top := Vector3(cos(angle)*.43,-.47,sin(angle)*.43)
		_mesh.cylinder(top,top+Vector3.DOWN*(.54+i*.047),.055,9)
	_mesh.disc(Vector3.DOWN*.46,.52,.075,18)
	_mesh.begin("jade")
	_mesh.cylinder(Vector3.DOWN*.51,Vector3.DOWN*1.42,.027,8)
	_mesh.disc(Vector3.DOWN*1.42,.18,.09,12)
	_commit(_bell,"ChimeTubes")
	_bell.global_position = _p(Vector3(35,52.60,80))

func _build_formation() -> void:
	_formation = Node3D.new()
	_formation.name = "StarFormation"
	add_child(_formation)
	var stars := [
		Vector3(-3.45,1.0,.32),Vector3(-2.41,1.48,.23),Vector3(-1.24,1.23,.11),
		Vector3(-.12,1.92,.0),Vector3(1.60,2.30,-.06),Vector3(2.47,1.15,-.03),
		Vector3(.91,.84,.14),
	]
	var axis := Vector3.FORWARD
	_mesh.begin("light")
	for i in range(stars.size()):
		var point: Vector3 = stars[i]
		_mesh.ring(point,axis,.12 if i!=3 else .19,.036,18,5)
		if i > 0:
			_mesh.beam(stars[i-1],point,.035)
	_mesh.beam(stars[3],stars[6],.035)
	_mesh.ring(Vector3(0,.79,0),Vector3.UP,1.63,.034,40,5)
	_mesh.ring(Vector3(0,.78,0),Vector3.UP,2.04,.026,44,5)
	_commit(_formation,"SevenStars")
	_formation.global_position = _p(Vector3(0,65.89,96.44))
	_formation.rotation.y = PI/2
	_formation.hide()

func _build_clouds() -> void:
	var cloud_layers := [
		[Vector3(-91,16,-20),Vector2(128,118),.78],
		[Vector3(90,17,-20),Vector2(129,120),.78],
		[Vector3(-109,29,36),Vector2(130,133),.76],
		[Vector3(108,30,37),Vector2(127,137),.78],
		[Vector3(-105,39,83),Vector2(104,143),.65],
		[Vector3(104,39,85),Vector2(110,138),.65],
		[Vector3(-65,21,116),Vector2(96,129),.60],
		[Vector3(67,21,115),Vector2(96,132),.60],
		[Vector3(-121,46,110),Vector2(77,114),.33],
		[Vector3(120,47,114),Vector2(77,110),.34],
		[Vector3(-95,37,7),Vector2(69,94),.73],
		[Vector3(95,36,17),Vector2(79,94),.69],
	]
	for row in cloud_layers:
		var plane := PlaneMesh.new()
		plane.size = row[1]
		var patch := MeshInstance3D.new()
		patch.name = "ValleyCloud"
		patch.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = CLOUD
		material.set_shader_parameter("density",row[2])
		patch.material_override = material
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.visibility_range_end = 480.0
		add_child(patch)
		patch.global_position = _p(row[0])

func ring_bell() -> void:
	var wave := create_tween()
	if _pulse != null and _pulse.is_running():
		_pulse.kill()
	_pulse = wave
	_bell.rotation.z = 0
	for tilt in [.19,-.15,.10,-.06,0.0]:
		wave.tween_property(_bell,"rotation:z",tilt,.26).set_trans(Tween.TRANS_SINE)
	_play_chime(_bell.global_position)

func reveal_formation(animated: bool) -> void:
	_formation.show()
	if animated:
		if _formation_tween != null and _formation_tween.is_running():
			return
		_formation.scale = Vector3.ONE*.14
		_formation_tween = create_tween()
		_formation_tween.tween_property(_formation,"scale",Vector3.ONE,.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_play_chime(_formation.global_position,.78)

func _play_chime(point: Vector3, pitch: float = 1.0) -> void:
	if _chime == null:
		_chime = AudioStreamWAV.new()
		_chime.format = AudioStreamWAV.FORMAT_16_BITS
		_chime.mix_rate = 22050
		const FRAMES := 33075
		var data := PackedByteArray()
		data.resize(FRAMES*2)
		for i in range(FRAMES):
			var time := i/22050.0
			var sample := 0.0
			for note in range(3):
				var t := time-note*.13
				if t >= 0:
					var f: float = [659.26,880.0,987.77][note]
					sample += minf(t*240.0,1.0)*exp(-t*5.6)*(sin(TAU*f*t)*.45+sin(TAU*f*2.76*t)*.16)
			data.encode_s16(i*2,roundi(clampf(sample,-1,1)*22000))
		_chime.data = data
	var audio := AudioStreamPlayer3D.new()
	audio.stream = _chime
	audio.pitch_scale = pitch
	audio.max_distance = 20.0
	audio.unit_size = 4.0
	audio.volume_db = -12
	add_child(audio)
	audio.global_position = point
	audio.finished.connect(audio.queue_free)
	audio.play()
