extends Node3D
## 云岫仙界的游览节点与三枚印记。使用独立进度记录。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const RealmCourt = preload("res://scripts/renewal/rebuild/realm_court.gd")
const SAVE := "user://celestial_realm.json"
const SITES := [
	{"id":"gate","title":"天门","local":Vector3(0,12,48),"note":"跨过天门，沿中庭右侧石桥去洗剑泉。"},
	{"id":"spring","title":"洗剑泉","local":Vector3(48,36,48),"note":"向水庭深处走可去听云亭。回中轴，沿石阶登观星台。"},
	{"id":"stars","title":"观星台","local":Vector3(16,78,64),"note":"站在星盘前，回望天门与云海。"}
]
var island: Node3D
var layer: Node
var stamps: Dictionary = {}
var shrine_awakened := false
var court: Node3D
var _mesh: RefCounted
var _mats: Dictionary = {}
var _seals: Dictionary = {}
var _props: StaticBody3D

func setup(site: Node3D,owner_layer: Node,palace: Node3D) -> void:
	island = site
	layer = owner_layer
	_load()
	_mesh = MeshLib.new()
	_mats = {
		"stone":_material(Color("#adae9d")),
		"base":_material(Color("#6e7b74")),
		"wood":_material(Color("#46443c")),
		"jade":_material(Color("#3c6f65")),
		"gold":_material(Color("#c9ad72")),
		"cloud":_material(Color("#83cfc4"),.52),
		"water":_material(Color("#468c87"),.20)
	}
	_props = StaticBody3D.new()
	_props.name = "RealmProps"
	add_child(_props)
	_build_gate()
	_build_side_link()
	_build_spring()
	_build_stars()
	for site_data in SITES:
		_make_seal(site_data)
	var art := MeshInstance3D.new()
	art.name = "CelestialRealmArt"
	art.mesh = _mesh.build(_mats)
	add_child(art)
	_mesh = null
	court = RealmCourt.new()
	court.name = "CloudCourt"
	add_child(court)
	court.setup(island,palace)
	if shrine_awakened:
		court.reveal_formation(false)
	print("CELESTIAL_REALM sites=",SITES.size())

func _material(color: Color,emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _p(w: float,d: float,h: float) -> Vector3:
	return island.wp(w,d,h)

func _box(key: String,w: float,d: float,h: float,size: Vector3) -> void:
	_mesh.begin(key)
	_mesh.box(Transform3D(Basis.IDENTITY,_p(w,d,h)),Vector3(size.z,size.y,size.x))

func _bar(key: String,a: Vector3,b: Vector3,width: float) -> void:
	_mesh.begin(key)
	_mesh.beam(_p(a.x,a.y,a.z),_p(b.x,b.y,b.z),width)

func _label(w: float,d: float,h: float,content: String,size: float,face_arrival: bool = false) -> void:
	var sign := Label3D.new()
	sign.text = content
	sign.font_size = 64
	sign.pixel_size = size
	sign.outline_size = 9
	sign.modulate = Color("#f5ebc9")
	if face_arrival:
		sign.rotation.y = PI/2.0
	else:
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.visibility_range_end = 108
	add_child(sign)
	sign.global_position = _p(w,d,h)

func _ring(w: float,d: float,h: float,r: float,key: String,thick: float) -> void:
	for i in range(32):
		var a := TAU*i/32
		var b := TAU*(i+1)/32
		_bar(key,Vector3(w+cos(a)*r,d+sin(a)*r,h),Vector3(w+cos(b)*r,d+sin(b)*r,h),thick)

func _lamp(w: float,d: float,h: float) -> void:
	_solid(Vector3(w,d,h+.74),Vector3(.48,.48,1.48))
	_box("base",w,d,h+.15,Vector3(.48,.30,.48))
	_box("wood",w,d,h+.71,Vector3(.16,.85,.16))
	_box("jade",w,d,h+1.25,Vector3(.35,.30,.35))
	_box("cloud",w,d,h+1.26,Vector3(.26,.24,.37))
	_box("gold",w,d,h+1.45,Vector3(.41,.09,.41))

func _build_gate() -> void:
	# Place the realm name on a freestanding marker beside the upper stair.
	_solid(Vector3(8.7,-8.3,49.22),Vector3(4.6,.95,2.44))
	_box("base",8.7,-8.3,48.25,Vector3(4.6,.50,.95))
	_box("base",8.7,-8.3,49.15,Vector3(3.8,1.4,.53))
	_box("jade",8.7,-8.3,50.0,Vector3(4.4,1.35,.36))
	_box("gold",8.7,-8.3,50.67,Vector3(4.48,.12,.42))
	_label(8.7,-8.62,50.12,"云岫仙界",.012,true)
	_label(0,15,50.5,"天门 · Y 收录仙印",.013)
	_ring(0,12,48.025,2.2,"gold",.038)
	for w in [-5.4,5.4]:
		for d in [7.8,14.4,21.5]:
			_lamp(w,d,48)
	# Courtyard directions visible on the ground beside the axial road.
	_label(11,14.5,50.35,"洗剑泉  →",.011)

func _build_side_link() -> void:
	# Bridge the gap between the gate apron and east court, clear of the pond.
	_box("stone",20.75,14.5,47.86,Vector3(11.24,.38,3.45))
	var body := StaticBody3D.new()
	body.name = "SwordSpringApproach"
	add_child(body)
	var s := BoxShape3D.new()
	s.size = Vector3(3.45,.38,11.24)
	var cs := CollisionShape3D.new()
	cs.shape = s
	body.add_child(cs)
	body.global_position = _p(20.75,14.5,47.86)
	for d in [12.82,16.18]:
		_bar("jade",Vector3(15.25,d,48.85),Vector3(26.25,d,48.85),.16)
		var rail := BoxShape3D.new()
		rail.size = Vector3(.18,.97,11.0)
		var rc := CollisionShape3D.new()
		rc.shape = rail
		body.add_child(rc)
		rc.global_position = _p(20.75,d,48.50)
		for w in [15.4,18,20.75,23.5,26.1]:
			_box("base",w,d,48.49,Vector3(.2,.98,.2))

func _build_spring() -> void:
	# Reflecting stone basin alongside the existing garden. Leave its approach open.
	_solid(Vector3(50.7,36.1,48.46),Vector3(4.76,4.76,.92))
	_box("base",50.7,36.1,48.23,Vector3(4.55,.46,4.55))
	_box("water",50.7,36.1,48.54,Vector3(3.91,.08,3.91))
	for side in [-1,1]:
		_box("stone",50.7+2.18*side,36.1,48.64,Vector3(.37,.45,4.76))
		_box("stone",50.7,36.1+2.18*side,48.64,Vector3(4.04,.45,.37))
		_lamp(48.4,36.1+2.4*side,48)
	_box("jade",50.7,36.1,48.8,Vector3(.55,.55,.55))
	_bar("gold",Vector3(50.7,36.1,49),Vector3(51.4,36.1,50.62),.14)
	_label(49.5,36,51.25,"洗剑泉",.014)

func _build_stars() -> void:
	_solid(Vector3(20.1,78.1,64.35),Vector3(1.65,1.65,.70))
	_ring(16,78,64.035,2.5,"gold",.067)
	_ring(16,78,64.041,1.84,"jade",.049)
	for i in range(8):
		var a := TAU*i/8
		_bar("gold",Vector3(16+cos(a)*1.86,78+sin(a)*1.86,64.047),Vector3(16+cos(a)*2.44,78+sin(a)*2.44,64.047),.043)
	# Armillary above the east side of the forecourt. It sits away from the hall door.
	_box("base",20.1,78.1,64.35,Vector3(1.65,.70,1.65))
	for axis in [0,1]:
		for i in range(28):
			var a := TAU*i/28
			var b := TAU*(i+1)/28
			var first := Vector3(cos(a)*1.48,0,sin(a)*1.48)
			var second := Vector3(cos(b)*1.48,0,sin(b)*1.48)
			if axis == 1:
				first = Vector3(0,first.x,first.z)
				second = Vector3(0,second.x,second.z)
			var c := Vector3(20.1,78.1,66.37)
			_bar("gold",c+first,c+second,.09)
	_box("cloud",20.1,78.1,66.37,Vector3(.36,.36,.36))
	_label(17.6,78,67.1,"观星台",.014)

func _solid(center: Vector3,size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.y,size.z,size.x)
	var node := CollisionShape3D.new()
	node.shape = shape
	_props.add_child(node)
	node.global_position = _p(center.x,center.y,center.z)

func _make_seal(site_data: Dictionary) -> void:
	var local: Vector3 = site_data.local
	var light := MeshInstance3D.new()
	var jewel := PrismMesh.new()
	jewel.size = Vector3(.28,.43,.28)
	light.mesh = jewel
	light.material_override = _mats["gold"] if stamps.has(site_data.id) else _mats["cloud"]
	add_child(light)
	light.global_position = _p(local.x-1.85,local.y,local.z+1.45)
	_seals[site_data.id] = light

func _process(delta: float) -> void:
	for seal in _seals.values():
		seal.rotate_y(delta*.8)

func _near_site(pos: Vector3) -> Dictionary:
	for site_data in SITES:
		var local: Vector3 = site_data.local
		if pos.distance_to(_p(local.x,local.y,local.z))<3.4:
			return site_data
	return {}

func hint(pos: Vector3) -> String:
	if pos.distance_to(_p(35,79.6,48)) < 2.5:
		return "Y  敲响云铃"
	if pos.distance_to(_p(0,92.6,64)) < 2.8:
		if shrine_awakened:
			return "Y  再观星阵"
		return "Y  启动观星阵" if stamps.size()==SITES.size() else "Y  查阅聚印石案"
	var site_data := _near_site(pos)
	if site_data.is_empty():
		return ""
	return "Y  "+site_data.title+" · 仙界游记" if stamps.has(site_data.id) else "Y  收录"+site_data.title+"印记"

func interact(pos: Vector3) -> bool:
	if pos.distance_to(_p(35,79.6,48)) < 2.5:
		court.ring_bell()
		layer.main.call("notify","听云亭 · 云铃声落入水庭")
		return true
	if pos.distance_to(_p(0,92.6,64)) < 2.8:
		_interact_shrine()
		return true
	var site_data := _near_site(pos)
	if site_data.is_empty():
		return false
	if not stamps.has(site_data.id):
		var updated := stamps.duplicate()
		updated[site_data.id] = true
		if not _save(updated,shrine_awakened):
			layer.main.call("notify","仙印暂未写入游记，请再试一次")
			return true
		stamps = updated
		_seals[site_data.id].material_override = _mats["gold"]
	var suffix: String = "三印已齐，从观星台中央进入栖霞殿开阵" if stamps.size()==SITES.size() else site_data.note
	layer.main.call("notify","仙界游记 %d/3 · %s"%[stamps.size(),suffix])
	return true

func _interact_shrine() -> void:
	if stamps.size() < SITES.size():
		layer.main.call("notify","已聚 %d/3 枚仙印。天门、洗剑泉和观星台各有一枚。" % stamps.size())
		return
	if not shrine_awakened:
		if not _save(stamps,true):
			layer.main.call("notify","开阵进度暂未写入游记，请再试一次")
			return
		shrine_awakened = true
	court.reveal_formation(true)
	layer.main.call("notify","栖霞殿 · 七星归位，观星阵已开启")

func _save(recorded: Dictionary, awakened: bool) -> bool:
	var temporary := SAVE+".tmp"
	var f := FileAccess.open(temporary,FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version":2,"stamps":recorded,"shrine_awakened":awakened}))
	f.flush()
	var written := f.get_error()==OK
	f.close()
	return written and DirAccess.rename_absolute(temporary,SAVE)==OK

func _load() -> void:
	var f := FileAccess.open(SAVE,FileAccess.READ)
	if f == null:
		return
	var payload = JSON.parse_string(f.get_as_text())
	if not (payload is Dictionary):
		return
	var recorded = payload.get("stamps")
	if recorded is Dictionary:
		for site_data in SITES:
			if bool(recorded.get(site_data.id,false)):
				stamps[site_data.id] = true
	shrine_awakened = stamps.size()==SITES.size() and bool(payload.get("shrine_awakened",false))
