extends Node3D
## 山海星轮（0170 新增设施）
## 选址：地图西南海岸空地（世界坐标 -420, 4, 275），紧邻农田、牧场与泳池片区，轮盘面朝海。
## 结构：双轮缘 + 24 全封闭吊舱 + 双侧 A 形支腿 + 山侧石台。
## 乘坐：靠近站台提示 → 按 E 请求 → 轮盘对位停稳开门 → 步行进入吊舱 → 按 E 入座 → 关门运行。
## 存档：user://save/renewal_v1/wheel.json，只记录逻辑状态，不写世界坐标。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const SiteClear = preload("res://scripts/renewal/site_clear.gd")

const SITE := Vector3(-420.0, 4.0, 275.0)
const PAD_SIZE := Vector2(78.0, 30.0)
const WHEEL_RADIUS := 40.0
const HUB_HEIGHT := 45.0
const CABIN_COUNT := 24
const CABIN_SIZE := Vector3(3.0, 2.8, 2.6)
const DECK_Y := 2.2
const RIM_OFFSET := 3.2
const LEG_Z := 7.5
const LEG_BASE_X := 24.0

const SLOW_PERIOD := 50.0
const FAST_PERIOD := 50.0
## 常态自转：与乘坐同速，一圈 50 秒。摩天轮停着不动会让人以为坏了。
const IDLE_PERIOD := 50.0
const DOOR_TIME := 1.1
const BOARD_ANGLE := -PI * 0.5
## 对位角速度（rad/s）。0.9 约等于 1.4 秒转 90°，不会让人等太久。
const ALIGN_RATE := 0.9

var layer: Node
var main: Node
var player: CharacterBody3D

var rotor: Node3D
var cabins: Array[Node3D] = []
var door_nodes: Array[Node3D] = []
var seat_anchors: Array[Vector3] = []

var angle := 0.0
var speed := 0.0
var target_period := SLOW_PERIOD
var state := "idle"          # idle / aligning / boarding / riding / returning
var boarding_index := 0
var _align_target := BOARD_ANGLE
var _board_wait := 0.0
var door_open := 0.0
var riding := false
var _saved_zoom := 6.0
## 舱内独立相机：原脚本每帧强制接管玩家相机（pitch / pivot / SpringArm 都改不动），
## 所以乘坐期间另起一个 Camera3D，位置跟着吊舱走、朝向交给鼠标。
var _ride_cam: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _saved_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _saved_figure_visible := true
var ride_elapsed := 0.0
var ride_total := 0.0
var prompt_label: Label
var hint_panel: PanelContainer
var lamps: Array[OmniLight3D] = []

var _ui: CanvasLayer
var _prompt_timer := 0.0
var _msg := ""
var _msg_timer := 0.0
var _near_deck := false
var _in_cabin := false
var _e_was_down := false

func _ready() -> void:
	main = layer.main
	player = layer.player
	_build_all()
	_load_state()
	_build_ui()
	set_process(true)
	set_physics_process(true)

# ---------------------------------------------------------------- 构建

func _build_all() -> void:
	var root := Node3D.new()
	root.name = "ShanhaiStarWheel"
	add_child(root)
	_build_terrace(root)
	_build_plaza_details(root)
	_build_access_path(root)
	_build_deck(root)
	_build_wheel(root)
	_build_cabins(root)
	_build_lighting(root)
	_clear_site()

func _mat(key: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match key:
		"stone":
			m.albedo_color = Color(0.78, 0.75, 0.69)
			m.roughness = 0.92
		"stone_dark":
			m.albedo_color = Color(0.55, 0.53, 0.49)
			m.roughness = 0.95
		"metal":
			m.albedo_color = Color(0.93, 0.91, 0.86)
			m.metallic = 0.55
			m.roughness = 0.32
		"green":
			m.albedo_color = Color(0.13, 0.27, 0.22)
			m.metallic = 0.25
			m.roughness = 0.55
		"gold":
			m.albedo_color = Color(0.85, 0.72, 0.44)
			m.metallic = 0.85
			m.roughness = 0.28
		"glass":
			m.albedo_color = Color(0.72, 0.86, 0.92, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.06
			m.metallic = 0.1
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"wood":
			m.albedo_color = Color(0.66, 0.49, 0.34)
			m.roughness = 0.8
		"lamp":
			m.albedo_color = Color(1.0, 0.94, 0.8)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(1.0, 0.88, 0.64)
			m.emission_energy_multiplier = 2.6
		"canvas":
			m.albedo_color = Color(0.86, 0.82, 0.72)
			m.roughness = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.albedo_color = Color(0.7, 0.7, 0.7)
	# 程序化几何的绕序不完全统一，关闭背面剔除以免局部缺失
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _add_mesh(parent: Node3D, mesh: ArrayMesh, name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi

func _static_box(parent: Node3D, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY, name: String = "col") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(basis, center)
	parent.add_child(body)
	return body

func _build_terrace(root: Node3D) -> void:
	var b := MeshLib.new()
	b.begin("stone")
	# 台面
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0)), Vector3(PAD_SIZE.x, 1.2, PAD_SIZE.y), 0.1)
	# 台缘压顶
	b.begin("stone_dark")
	var half_x := PAD_SIZE.x * 0.5
	var half_z := PAD_SIZE.y * 0.5
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.05, -half_z + 0.35)), Vector3(PAD_SIZE.x, 0.5, 0.7), 0.2)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.05, half_z - 0.35)), Vector3(PAD_SIZE.x, 0.5, 0.7), 0.2)
	# 山侧挡土墙：沿四周向下延伸，贴合坡面
	var perimeter: Array[Vector3] = []
	var steps := 44
	for i in range(steps):
		var t := float(i) / float(steps) * TAU
		perimeter.append(Vector3(cos(t) * half_x, 0, sin(t) * half_z))
	b.begin("stone_dark")
	for p in perimeter:
		b.box(Transform3D(Basis.IDENTITY, Vector3(p.x, -7.0, p.z)), Vector3(3.2, 14.0, 1.2), 0.2)
	var mesh := b.build({"stone": _mat("stone"), "stone_dark": _mat("stone_dark")})
	_add_mesh(root, mesh, "TerraceMesh")
	# 台面碰撞（略低于可见面，避免与地形冲突）
	_static_box(root, Vector3(0, -0.62, 0), Vector3(PAD_SIZE.x, 1.2, PAD_SIZE.y), Basis.IDENTITY, "TerraceCollision")
	# 台缘矮墙碰撞（防止从台地边缘跌落）
	var rail_h := 1.05
	var rail_t := 0.5
	_static_box(root, Vector3(0, rail_h * 0.5, -half_z + 0.3), Vector3(PAD_SIZE.x, rail_h, rail_t), Basis.IDENTITY, "ParapetNorth")
	_static_box(root, Vector3(-half_x + 0.3, rail_h * 0.5, 0), Vector3(rail_t, rail_h, PAD_SIZE.y), Basis.IDENTITY, "ParapetWest")
	_static_box(root, Vector3(half_x - 0.3, rail_h * 0.5, 0), Vector3(rail_t, rail_h, PAD_SIZE.y), Basis.IDENTITY, "ParapetEast")

## 广场细节：铺装分格、花池、标牌
func _build_plaza_details(root: Node3D) -> void:
	var b := MeshLib.new()
	b.begin("stone_dark")
	var hx := PAD_SIZE.x * 0.5
	var hz := PAD_SIZE.y * 0.5
	var x := -hx + 4.0
	while x < hx - 2.0:
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.02, 0)), Vector3(0.18, 0.06, PAD_SIZE.y - 3.0), 0.3)
		x += 4.0
	var z := -hz + 4.0
	while z < hz - 2.0:
		b.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, z)), Vector3(PAD_SIZE.x - 3.0, 0.06, 0.18), 0.3)
		z += 4.0
	# 花池
	var planters := [Vector3(-30, 0, -11), Vector3(30, 0, -11), Vector3(-30, 0, 11), Vector3(30, 0, 11)]
	for p in planters:
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.35, 0)), Vector3(3.2, 0.7, 3.2), 0.3)
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.72, 0)), Vector3(2.8, 0.1, 2.8), 0.3)
	var mesh := b.build({"stone_dark": _mat("stone_dark")})
	_add_mesh(root, mesh, "PlazaDetailMesh")
	# 花池种植（简单体块，避免透明叠层）
	var g := MeshLib.new()
	g.begin("green")
	for p in planters:
		g.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.05, 0)), Vector3(2.4, 0.7, 2.4), 0.3)
		g.box(Transform3D(Basis.IDENTITY, p + Vector3(0.4, 1.55, -0.3)), Vector3(1.2, 0.5, 1.2), 0.3)
	var gm := g.build({"green": _mat("green")})
	_add_mesh(root, gm, "PlazaPlantingMesh")
	# 标牌
	var label := Label3D.new()
	label.text = "山海星轮"
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(0.98, 0.94, 0.84)
	label.outline_size = 12
	label.outline_modulate = Color(0.08, 0.14, 0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = Vector3(0, DECK_Y + 5.4, 7.9)
	root.add_child(label)
	var label2 := Label3D.new()
	label2.text = "SHANHAI STAR WHEEL"
	label2.font_size = 40
	label2.pixel_size = 0.009
	label2.modulate = Color(0.92, 0.88, 0.76)
	label2.position = Vector3(0, DECK_Y + 4.95, 7.85)
	root.add_child(label2)

func _build_access_path(root: Node3D) -> void:
	# 从台地西端接至 landscape150_cherry_loop 步道（世界坐标 -452.7, 58.8, -426.7）
	var pts: Array[Vector3] = [
		Vector3(-440.0, 4.0, 290.0),
		Vector3(-443.5, 4.15, 293.2),
		Vector3(-446.5, 4.3, 295.8),
		Vector3(-448.5, 4.5, 298.1),
	]
	var b := MeshLib.new()
	b.begin("stone")
	var width := 3.6
	for i in range(pts.size() - 1):
		_segment_steps(b, pts[i], pts[i + 1], width)
	var mesh := b.build({"stone": _mat("stone")})
	_add_mesh(root, mesh, "AccessPathMesh")
	# 连续坡面碰撞（贴合踏步范围，避免逐级台阶卡住）
	for i in range(pts.size() - 1):
		_segment_ramp(root, pts[i], pts[i + 1], width, i)
	# 外侧矮护栏
	var rb := MeshLib.new()
	rb.begin("stone_dark")
	for i in range(pts.size() - 1):
		var a := pts[i]
		var c := pts[i + 1]
		var dir := (c - a)
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var side := flat.cross(Vector3.UP).normalized()
		var n := int(maxf(2.0, flat.length() * 0.0 + dir.length() / 2.2))
		for k in range(n):
			var t := (float(k) + 0.5) / float(n)
			var p := a.lerp(c, t) + side * (width * 0.5)
			rb.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.45, 0)), Vector3(0.28, 0.9, 0.28))
	var rmesh := rb.build({"stone_dark": _mat("stone_dark")})
	_add_mesh(root, rmesh, "AccessRailMesh")

func _segment_steps(b: MeshLib, a: Vector3, c: Vector3, width: float) -> void:
	var dir := c - a
	var flat := Vector3(dir.x, 0, dir.z)
	var length := flat.length()
	if length < 0.01:
		return
	var rise := c.y - a.y
	var step_run := 0.34
	var n := int(maxf(1.0, length / step_run))
	var step_len := length / float(n)
	var step_rise := rise / float(n)
	var d := flat / length
	var side := d.cross(Vector3.UP).normalized()
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var p := a + flat * t + Vector3(0, step_rise * (float(i) + 0.5), 0)
		b.box(Transform3D(Basis(side, Vector3.UP, d), p), Vector3(width, maxf(0.14, absf(step_rise) + 0.06), step_len * 1.02))

func _segment_ramp(root: Node3D, a: Vector3, c: Vector3, width: float, idx: int) -> void:
	var dir := c - a
	var flat := Vector3(dir.x, 0, dir.z)
	var length := flat.length()
	if length < 0.01:
		return
	var d := flat / length
	var side := d.cross(Vector3.UP).normalized()
	var up := side.cross(d).normalized()
	var basis := Basis(side, up, d)
	var center := (a + c) * 0.5 + Vector3(0, -0.12, 0)
	var thickness := 0.3
	_static_box(root, center, Vector3(width, thickness, length), basis, "PathRamp%d" % idx)

func _build_deck(root: Node3D) -> void:
	var b := MeshLib.new()
	b.begin("wood")
	# 站台主体：x∈[-10,10]，z∈[1.35,6.9]
	b.box(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y - 0.15, 2.75)), Vector3(20.0, 0.3, 8.25), 0.2)
	# 入口平台
	b.box(Transform3D(Basis.IDENTITY, Vector3(14.0, DECK_Y - 0.15, 5.05)), Vector3(8.0, 0.3, 7.4), 0.2)
	# 引道坡面（x 从 34 到 18）
	var ramp_len := 16.0
	var ramp_rise := DECK_Y
	var ramp_angle := atan2(ramp_rise, ramp_len)
	var ramp_basis := Basis(Vector3(0, 0, 1), -ramp_angle)
	b.begin("stone")
	b.box(Transform3D(ramp_basis, Vector3(26.0, DECK_Y * 0.5 + 0.06, 5.05)), Vector3(ramp_len, 0.3, 4.4), 0.2)
	# 西侧主坡道：正对广场来路，从地面直接上到站台。
	# 原来只有东侧一条 16 m 长坡，藏在甲板下方，玩家从入口进来完全看不到，
	# 会以为站台上不去（实测步行探针走到坡下就被甲板挡住了）。
	var wlen := 8.0
	var wang := atan2(DECK_Y, wlen)
	var wbasis := Basis(Vector3(0, 0, 1), wang)
	b.box(Transform3D(wbasis, Vector3(-14.0, DECK_Y * 0.5 + 0.06, 4.2)), Vector3(wlen, 0.3, 6.0), 0.2)
	var mesh := b.build({"wood": _mat("wood"), "stone": _mat("stone")})
	_add_mesh(root, mesh, "DeckMesh")

	_static_box(root, Vector3(0, DECK_Y - 0.15, 2.75), Vector3(20.0, 0.3, 8.25), Basis.IDENTITY, "DeckCollision")
	_static_box(root, Vector3(14.0, DECK_Y - 0.15, 5.05), Vector3(8.0, 0.3, 7.4), Basis.IDENTITY, "DeckEntryCollision")
	# 引道：坡面碰撞（8% 左右）
	_static_box(root, Vector3(26.0, DECK_Y * 0.5 + 0.06, 5.05), Vector3(ramp_len, 0.3, 4.4), ramp_basis, "DeckRampCollision")
	_static_box(root, Vector3(-14.0, DECK_Y * 0.5 + 0.06, 4.2), Vector3(wlen, 0.3, 6.0), wbasis, "DeckRampWest")
	# 栏杆
	var q := MeshLib.new()
	q.begin("metal")
	var rail_pts: Array[Vector3] = [
		Vector3(-10, DECK_Y, 1.4), Vector3(-10, DECK_Y, 6.9),
		Vector3(18, DECK_Y, 6.9), Vector3(18, DECK_Y, 1.4),
	]
	for i in range(rail_pts.size() - 1):
		var a := rail_pts[i]
		var c := rail_pts[i + 1]
		var n := int(maxf(2.0, a.distance_to(c) / 2.0))
		for k in range(n + 1):
			var p := a.lerp(c, float(k) / float(n))
			q.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.5, 0)), Vector3(0.12, 1.0, 0.12))
		q.beam(a + Vector3(0, 1.02, 0), c + Vector3(0, 1.02, 0), 0.1)
		q.beam(a + Vector3(0, 0.55, 0), c + Vector3(0, 0.55, 0), 0.08)
	var qm := q.build({"metal": _mat("metal")})
	_add_mesh(root, qm, "DeckRailMesh")
	# 排队栏（不做封死迷宫，单向通道）
	var qq := MeshLib.new()
	qq.begin("green")
	for i in range(4):
		var z := 2.0 + float(i) * 1.1
		qq.beam(Vector3(6.0, DECK_Y + 0.5, z), Vector3(9.6, DECK_Y + 0.5, z), 0.08)
		qq.box(Transform3D(Basis.IDENTITY, Vector3(6.0, DECK_Y + 0.5, z)), Vector3(0.1, 1.0, 0.1))
		qq.box(Transform3D(Basis.IDENTITY, Vector3(9.6, DECK_Y + 0.5, z)), Vector3(0.1, 1.0, 0.1))
	var qqm := qq.build({"green": _mat("green")})
	_add_mesh(root, qqm, "QueueRailMesh")
	# 雨棚
	var c := MeshLib.new()
	c.begin("metal")
	for x in [-8.0, -2.0, 2.0, 8.0]:
		c.box(Transform3D(Basis.IDENTITY, Vector3(x, DECK_Y + 2.2, 2.0)), Vector3(0.24, 4.4, 0.24))
		c.box(Transform3D(Basis.IDENTITY, Vector3(x, DECK_Y + 2.2, 6.4)), Vector3(0.24, 4.4, 0.24))
	c.begin("canvas")
	c.gable_roof(Vector3(0, DECK_Y + 4.5, 4.2), 19.4, 6.8, 1.15, 0.35)
	c.begin("gold")
	c.beam(Vector3(-9.7, DECK_Y + 4.55, 1.0), Vector3(9.7, DECK_Y + 4.55, 1.0), 0.14)
	c.beam(Vector3(-9.7, DECK_Y + 4.55, 7.4), Vector3(9.7, DECK_Y + 4.55, 7.4), 0.14)
	var cm := c.build({"metal": _mat("metal"), "canvas": _mat("canvas")})
	_add_mesh(root, cm, "CanopyMesh")
	# 设备间
	var h := MeshLib.new()
	h.begin("stone")
	h.box(Transform3D(Basis.IDENTITY, Vector3(-15.0, DECK_Y + 1.3, 4.5)), Vector3(6.0, 2.6, 4.6), 0.2)
	h.begin("green")
	h.box(Transform3D(Basis.IDENTITY, Vector3(-15.0, DECK_Y + 2.75, 4.5)), Vector3(6.6, 0.3, 5.2), 0.2)
	var hm := h.build({"stone": _mat("stone"), "green": _mat("green")})
	_add_mesh(root, hm, "EquipmentRoomMesh")
	_static_box(root, Vector3(-15.0, DECK_Y + 1.3, 4.5), Vector3(6.0, 2.6, 4.6), Basis.IDENTITY, "EquipmentCollision")

func _build_wheel(root: Node3D) -> void:
	var hub_y := DECK_Y + WHEEL_RADIUS + CABIN_SIZE.y + 1.35
	var structure := Node3D.new()
	structure.name = "WheelFrame"
	root.add_child(structure)

	var b := MeshLib.new()
	# 轮毂
	b.begin("metal")
	b.cylinder(Vector3(0, hub_y, -RIM_OFFSET - 1.4), Vector3(0, hub_y, RIM_OFFSET + 1.4), 3.2, 20, true)
	b.begin("gold")
	b.cylinder(Vector3(0, hub_y, -1.0), Vector3(0, hub_y, 1.0), 3.6, 20, true)
	# 双轮缘
	b.begin("metal")
	for z in [-RIM_OFFSET, RIM_OFFSET]:
		b.ring(Vector3(0, hub_y, z), Vector3(0, 0, 1), WHEEL_RADIUS, 0.42, 96, 6)
	# 辐条（双侧，交替布置）
	b.begin("metal")
	for i in range(CABIN_COUNT):
		var a := TAU * float(i) / float(CABIN_COUNT)
		var z := -RIM_OFFSET if (i % 2 == 0) else RIM_OFFSET
		var inner := Vector3(cos(a) * 3.4, hub_y + sin(a) * 3.4, z)
		var outer := Vector3(cos(a) * (WHEEL_RADIUS - 0.5), hub_y + sin(a) * (WHEEL_RADIUS - 0.5), z)
		b.beam(inner, outer, 0.14, Vector3(0, 0, 1))
	# 轮缘横向连系
	b.begin("gold")
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * WHEEL_RADIUS, hub_y + sin(a) * WHEEL_RADIUS, 0)
		b.cylinder(p + Vector3(0, 0, -RIM_OFFSET), p + Vector3(0, 0, RIM_OFFSET), 0.14, 8, false)
	# 支腿：双侧 A 形
	b.begin("green")
	for z in [-LEG_Z, LEG_Z]:
		for sx in [-1.0, 1.0]:
			var top := Vector3(0, hub_y - 1.0, z)
			var foot := Vector3(LEG_BASE_X * sx, 0.0, z)
			b.beam(top, foot, 1.5, Vector3(0, 0, 1))
			# 斜撑
			b.beam(Vector3(0, hub_y * 0.45, z), foot * 0.55 + Vector3(0, 0, 0), 0.55, Vector3(0, 0, 1))
		b.beam(Vector3(-LEG_BASE_X, 2.2, z), Vector3(LEG_BASE_X, 2.2, z), 0.7, Vector3(0, 0, 1))
	# 基础
	b.begin("stone_dark")
	for z in [-LEG_Z, LEG_Z]:
		for sx in [-1.0, 1.0]:
			b.box(Transform3D(Basis.IDENTITY, Vector3(LEG_BASE_X * sx, 0.45, z)), Vector3(7.0, 1.5, 7.0), 0.2)
	var mesh := b.build({
		"metal": _mat("metal"), "gold": _mat("gold"),
		"green": _mat("green"), "stone_dark": _mat("stone_dark"),
	})
	_add_mesh(structure, mesh, "WheelFrameMesh")
	# 支腿基础碰撞（可站立，但不可穿越）
	for z in [-LEG_Z, LEG_Z]:
		for sx in [-1.0, 1.0]:
			_static_box(root, Vector3(LEG_BASE_X * sx, 0.75, z), Vector3(7.0, 1.5, 7.0), Basis.IDENTITY, "Footing")

	# 旋转部分
	rotor = Node3D.new()
	rotor.name = "WheelRotor"
	rotor.position = Vector3(0, hub_y, 0)
	structure.add_child(rotor)

func _build_cabins(root: Node3D) -> void:
	var body_mat := _mat("metal")
	var glass_mat := _mat("glass")
	var gold_mat := _mat("gold")
	for i in range(CABIN_COUNT):
		var a := TAU * float(i) / float(CABIN_COUNT)
		var holder := Node3D.new()
		holder.name = "Cabin%d" % i
		holder.position = Vector3(cos(a) * WHEEL_RADIUS, sin(a) * WHEEL_RADIUS, 0)
		rotor.add_child(holder)
		# 吊臂
		var arm := MeshLib.new()
		arm.begin("metal")
		arm.beam(Vector3(0, 0, 0), Vector3(0, -1.35, 0), 0.22)
		var arm_mesh := arm.build({"metal": body_mat})
		_add_mesh(holder, arm_mesh, "Hanger")

		var cab := Node3D.new()
		cab.name = "Body"
		cab.position = Vector3(0, -1.35 - CABIN_SIZE.y * 0.5, 0)
		holder.add_child(cab)

		var cb := MeshLib.new()
		# 底盘与顶盖
		cb.begin("green")
		cb.box(Transform3D(Basis.IDENTITY, Vector3(0, -CABIN_SIZE.y * 0.5 + 0.06, 0)), Vector3(CABIN_SIZE.x, 0.12, CABIN_SIZE.z), 0.2)
		cb.begin("metal")
		cb.box(Transform3D(Basis.IDENTITY, Vector3(0, CABIN_SIZE.y * 0.5 - 0.1, 0)), Vector3(CABIN_SIZE.x + 0.2, 0.2, CABIN_SIZE.z + 0.2), 0.2)
		# 四角立柱
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx * (CABIN_SIZE.x * 0.5 - 0.09), 0, sz * (CABIN_SIZE.z * 0.5 - 0.09))
				cb.box(Transform3D(Basis.IDENTITY, p), Vector3(0.16, CABIN_SIZE.y - 0.3, 0.16))
		# 玻璃
		cb.begin("glass")
		cb.box(Transform3D(Basis.IDENTITY, Vector3(-CABIN_SIZE.x * 0.5, 0.05, 0)), Vector3(0.06, CABIN_SIZE.y - 0.5, CABIN_SIZE.z - 0.24))
		cb.box(Transform3D(Basis.IDENTITY, Vector3(CABIN_SIZE.x * 0.5, 0.05, 0)), Vector3(0.06, CABIN_SIZE.y - 0.5, CABIN_SIZE.z - 0.24))
		cb.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -CABIN_SIZE.z * 0.5)), Vector3(CABIN_SIZE.x - 0.24, CABIN_SIZE.y - 0.5, 0.06))
		# 座席（视觉）
		cb.begin("wood")
		cb.box(Transform3D(Basis.IDENTITY, Vector3(0, -CABIN_SIZE.y * 0.5 + 0.62, -0.55)), Vector3(2.2, 0.18, 0.7))
		cb.box(Transform3D(Basis.IDENTITY, Vector3(0, -CABIN_SIZE.y * 0.5 + 0.95, -0.92)), Vector3(2.2, 0.6, 0.14))
		var cmesh := cb.build({"metal": body_mat, "glass": glass_mat, "green": _mat("green"), "wood": _mat("wood")})
		_add_mesh(cab, cmesh, "CabinMesh")

		# 门（+Z 侧，绕左侧铰链旋转）
		var hinge := Node3D.new()
		hinge.name = "DoorHinge"
		hinge.position = Vector3(-CABIN_SIZE.x * 0.5 + 0.08, 0.0, CABIN_SIZE.z * 0.5)
		cab.add_child(hinge)
		var db := MeshLib.new()
		db.begin("glass")
		db.box(Transform3D(Basis.IDENTITY, Vector3(CABIN_SIZE.x * 0.5 - 0.08, 0.05, 0)), Vector3(CABIN_SIZE.x - 0.3, CABIN_SIZE.y - 0.5, 0.05))
		db.begin("gold")
		db.box(Transform3D(Basis.IDENTITY, Vector3(CABIN_SIZE.x * 0.5 - 0.08, -CABIN_SIZE.y * 0.5 + 0.42, 0.05)), Vector3(CABIN_SIZE.x - 0.3, 0.1, 0.08))
		var dmesh := db.build({"glass": glass_mat, "gold": gold_mat})
		_add_mesh(hinge, dmesh, "DoorMesh")

		cabins.append(holder)
		door_nodes.append(hinge)
		# 座位高度必须让「玩家位置 + 相机高度(约 1.45 m)」落在舱内。
		# 原来 +0.75 会把相机顶到舱顶之外，第一人称什么都看不到。
		seat_anchors.append(Vector3(0, -1.35 - CABIN_SIZE.y * 0.5 - 0.15, -0.15))

func _build_lighting(root: Node3D) -> void:
	var b := MeshLib.new()
	b.begin("lamp")
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var p := Vector3(cos(a) * 30.0, 0.0, sin(a) * 14.0)
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.5, 0)), Vector3(0.22, 3.0, 0.22))
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.05, 0)), Vector3(0.5, 0.5, 0.5))
	b.begin("metal")
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var p := Vector3(cos(a) * 30.0, 0.0, sin(a) * 14.0)
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.15, 0)), Vector3(0.7, 0.3, 0.7))
	var mesh := b.build({"lamp": _mat("lamp"), "metal": _mat("metal")})
	_add_mesh(root, mesh, "LampMesh")
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.62)
		l.light_energy = 0.0
		l.omni_range = 16.0
		l.position = Vector3(cos(a) * 24.0, 3.4, sin(a) * 11.0)
		root.add_child(l)
		lamps.append(l)

## 施工清障：移除台地范围内的植被实例。流式区块重新加载后需再次执行。
func _clear_site() -> void:
	if layer == null or layer.world == null:
		return
	var removed := SiteClear.clear_rect(layer.world, global_position, PAD_SIZE + Vector2(16.0, 16.0), global_position.y - 14.0, global_position.y + 26.0)
	if removed > 0:
		print("WHEEL_SITE_CLEARED removed=", removed)

# ---------------------------------------------------------------- 状态

var _clear_tick := 0
var _last_clear_events := -1

## 只在“玩家靠近场地 + 流式区块有新加载”时清障，避免全图周期性扫描造成掉帧。
func _maybe_clear_site() -> void:
	if layer == null or layer.stream == null or player == null:
		return
	if player.global_position.distance_to(global_position) > 320.0:
		return
	var ev := int(layer.stream.get("load_events"))
	if ev == _last_clear_events:
		return
	_last_clear_events = ev
	_clear_site()

func _physics_process(delta: float) -> void:
	_clear_tick += 1
	if _clear_tick % 30 == 0:
		_maybe_clear_site()
	_update_night()
	match state:
		"idle":
			_idle_rotate(delta)
		"boarding":
			# 没人上舱就自动恢复运转，避免一直停在登舱位
			_board_wait += delta
			if _board_wait > 30.0:
				_board_wait = 0.0
				door_open = 0.0
				state = "idle"
		"aligning":
			_align_to_boarding(delta)
		"riding":
			_ride_step(delta)
		"returning":
			_return_step(delta)
	_update_doors(delta)
	_apply_rotation()
	_update_player_binding()

func _process(delta: float) -> void:
	_check_proximity()
	_handle_input()
	_update_prompt(delta)

func _apply_rotation() -> void:
	if rotor == null:
		return
	rotor.rotation = Vector3(0, 0, angle)
	for i in range(cabins.size()):
		cabins[i].rotation = Vector3(0, 0, -angle)

func _update_doors(delta: float) -> void:
	var target := 1.0 if state == "boarding" else 0.0
	door_open = move_toward(door_open, target, delta / DOOR_TIME)
	for d in door_nodes:
		d.rotation.y = -deg_to_rad(95.0) * door_open

func _update_night() -> void:
	var night := false
	if main != null and main.get("sun") != null:
		var sun: DirectionalLight3D = main.get("sun")
		night = sun.light_energy < 0.35
	for l in lamps:
		l.light_energy = 2.4 if night else 0.0

# ---------------------------------------------------------------- 乘坐

func _deck_anchor() -> Vector3:
	return global_position + Vector3(0, DECK_Y, 4.0)

func _boarding_marker() -> Vector3:
	return global_position + Vector3(0, DECK_Y, 2.6)

func _check_proximity() -> void:
	if player == null:
		return
	# 判定放宽到 9 m，并且"站在甲板上"也算——原来只认一个点，玩家站在
	# 站台边缘（离点位 6.5 m 外）就看不到提示，实际体验像按键失灵。
	var d := player.global_position.distance_to(_boarding_marker())
	var deck_y := global_position.y + DECK_Y
	var on_deck := absf(player.global_position.y - deck_y) < 1.6 \
		and absf(player.global_position.x - global_position.x) < 12.0 \
		and absf(player.global_position.z - (global_position.z + 4.0)) < 6.0
	_near_deck = d < 9.0 or on_deck
	_in_cabin = false
	if state == "boarding":
		var cab := _cabin_world_seat(boarding_index)
		_in_cabin = player.global_position.distance_to(cab) < 4.5

func _handle_input() -> void:
	var e_down := Input.is_key_pressed(KEY_E)
	var pressed := e_down and not _e_was_down
	_e_was_down = e_down
	if not pressed:
		return
	if riding:
		_end_ride_early()
		return
	if state == "idle" and _near_deck:
		_request_board()
	elif state == "boarding" and _near_deck:
		# 不再要求"必须走进舱内"：吊舱停在甲板上，按 E 直接落座。
		# 原来要精确走到舱里才判定，实际很难踩准，表现为"按 E 没反应"。
		_seat_player()

func _request_board() -> void:
	if state != "idle":
		return
	# 先挑离登舱位最近的吊舱，再算对位目标角，避免总是转大半圈
	boarding_index = _nearest_cabin_to_board()
	_align_target = _angle_for_cabin(boarding_index)
	state = "aligning"
	speed = 0.0
	_say("摩天轮正在对位，请稍候…")

## 常态缓慢自转，让设施看起来是活的
func _idle_rotate(delta: float) -> void:
	speed = TAU / IDLE_PERIOD
	angle = fmod(angle + speed * delta, TAU)

## 让 0 号舱（或任意舱）停在正下方所需的角度
func _angle_for_cabin(i: int) -> float:
	return BOARD_ANGLE - TAU * float(i) / float(CABIN_COUNT)

## 当前哪个舱最接近正下方
func _nearest_cabin_to_board() -> int:
	var best := 0
	var best_d := 1e9
	for i in range(CABIN_COUNT):
		var d := absf(_short_delta(angle, _angle_for_cabin(i)))
		if d < best_d:
			best_d = d
			best = i
	return best

## 两个角度之间的最短带符号差
func _short_delta(from_a: float, to_a: float) -> float:
	var d := fmod(to_a - from_a + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI

func _align_to_boarding(delta: float) -> void:
	var d := _short_delta(angle, _align_target)
	var step := ALIGN_RATE * delta
	if absf(d) <= step:
		angle = fmod(_align_target + TAU, TAU)
		state = "boarding"
		_board_wait = 0.0
		door_open = 0.0
		_say("吊舱已停稳 · 走到吊舱前按 E 入座")
	else:
		angle = fmod(angle + signf(d) * step + TAU, TAU)

func _seat_player() -> void:
	if player == null:
		return
	riding = true
	ride_elapsed = 0.0
	ride_total = target_period
	var seat := _cabin_world_seat(boarding_index)
	player.global_position = seat
	if player.has_method("sit_at"):
		player.call("sit_at", seat, 0.0)
	# 乘坐期间由本设施接管位置，关闭原控制器物理，避免被地面吸附或二次位移
	player.set_physics_process(false)
	# 相机收进舱内：原版是第三人称（SpringArm 拉出 6 m），坐进吊舱后必须贴到
	# 头部位置，否则镜头留在舱外，看到的是「人在小房间里、镜头却飘在外面」。
	_saved_zoom = float(player.get("zoom"))
	player.set("zoom", 0.0)
	var arm = player.get("arm")
	if arm is SpringArm3D:
		(arm as SpringArm3D).spring_length = 0.0
	# 允许环视：解除坐姿可能带来的视角锁定
	player.set("enabled", true)
	_build_ride_camera()
	state = "riding"
	door_open = 0.0
	_say("山海星轮启程 · 按 E 可提前结束")
	save_state()

func _cabin_world_seat(i: int) -> Vector3:
	if i < 0 or i >= cabins.size():
		return global_position
	var c: Node3D = cabins[i]
	return c.global_transform * seat_anchors[i]

func _ride_step(delta: float) -> void:
	ride_elapsed += delta
	speed = TAU / maxf(1.0, ride_total)
	angle = fmod(angle + speed * delta, TAU)
	if ride_elapsed >= ride_total:
		_return_to_station()

func _return_to_station() -> void:
	state = "returning"
	speed = 0.0
	_say("正在返回站台…")

func _return_step(delta: float) -> void:
	var d := _short_delta(angle, _align_target)
	var step := ALIGN_RATE * delta
	if absf(d) <= step:
		angle = fmod(_align_target + TAU, TAU)
		state = "boarding"
		_board_wait = 0.0
		door_open = 1.0
		_release_player()
	else:
		angle = fmod(angle + signf(d) * step + TAU, TAU)

func _release_player() -> void:
	if player == null:
		return
	riding = false
	player.set_physics_process(true)
	_drop_ride_camera()
	_restore_camera()
	var exit_pos := global_position + Vector3(0, DECK_Y + 0.05, 4.2)
	player.global_position = exit_pos
	if player.has_method("stand_up"):
		player.call("stand_up")
		player.global_position = exit_pos
	_say("已回到摩天轮站台")
	save_state()

func _end_ride_early() -> void:
	if not riding:
		return
	_say("提前结束观景，正在返回站台…")
	_return_to_station()

func _update_player_binding() -> void:
	if not riding or player == null:
		return
	var seat := _cabin_world_seat(boarding_index)
	player.global_position = seat
	player.velocity = Vector3.ZERO
	_update_ride_camera()

## 舱内相机：挂在摩天轮节点下，每帧把位置对到吊舱座位上方，朝向由鼠标控制
func _build_ride_camera() -> void:
	if _ride_cam != null:
		return
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var figure: Node3D = player.get("figure")
	if figure != null:
		_saved_figure_visible = figure.visible
		figure.hide()
	_ride_cam = Camera3D.new()
	_ride_cam.name = "RideCamera"
	_ride_cam.fov = 74.0
	_ride_cam.near = 0.05
	_ride_cam.far = 2500.0
	add_child(_ride_cam)
	_cam_pitch = 0.0
	# 初始朝向「背离轮心」：吊舱挂在轮缘，轮辐在内侧，朝外看才不会被辐条糊住。
	var a := TAU * float(maxi(0, boarding_index)) / float(CABIN_COUNT)
	_cam_yaw = atan2(-cos(a), -sin(a))
	_ride_cam.current = true

func _update_ride_camera() -> void:
	if _ride_cam == null or boarding_index < 0 or boarding_index >= cabins.size():
		return
	var figure: Node3D = player.get("figure")
	if figure != null:
		figure.hide()
	var cab: Node3D = cabins[boarding_index]
	var seat: Vector3 = cab.global_transform * seat_anchors[boarding_index]
	# 往舱的外侧偏 0.45 m：吊舱挂在轮缘上，轮缘（tube 0.42）就在头顶，
	# 相机贴舱中心时那圈钢环会糊掉三分之一画面。
	var a := TAU * float(maxi(0, boarding_index)) / float(CABIN_COUNT)
	var radial := Vector3(cos(a), 0.0, sin(a))
	_ride_cam.global_position = seat + Vector3(0.0, 1.05, 0.0) + radial * 0.45
	_ride_cam.global_rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	if not _ride_cam.current:
		_ride_cam.current = true

func _drop_ride_camera() -> void:
	if _ride_cam != null:
		Input.mouse_mode = _saved_mouse_mode
		var figure: Node3D = player.get("figure")
		if figure != null:
			figure.visible = _saved_figure_visible
		_ride_cam.queue_free()
		_ride_cam = null

## 乘坐期间鼠标环视
func _input(event: InputEvent) -> void:
	if _ride_cam == null or not riding:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.0032
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.0032, -1.15, 1.15)
		get_viewport().set_input_as_handled()

## 恢复第三人称相机
func _restore_camera() -> void:
	if player == null:
		return
	var z: float = _saved_zoom if _saved_zoom > 0.01 else 6.0
	player.set("zoom", z)
	var arm = player.get("arm")
	if arm is SpringArm3D:
		(arm as SpringArm3D).spring_length = z

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "WheelUI"
	_ui.layer = 20
	add_child(_ui)
	hint_panel = PanelContainer.new()
	hint_panel.position = Vector2(0, 0)
	hint_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.12, 0.14, 0.82)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	hint_panel.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	hint_panel.add_child(v)
	prompt_label = Label.new()
	prompt_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	prompt_label.add_theme_font_size_override("font_size", 18)
	v.add_child(prompt_label)
	_ui.add_child(hint_panel)

func _update_prompt(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
	var text := ""
	if _msg_timer > 0.0:
		text = _msg
	elif riding:
		text = "乘坐中 · 按 E 提前结束观景"
	elif state == "boarding":
		text = "吊舱已开门 · 步行进入后按 E 入座"
	elif _near_deck:
		text = "按 E 乘坐摩天轮（一圈约 50 秒）"
	if text == "":
		hint_panel.visible = false
		return
	prompt_label.text = text
	hint_panel.visible = true
	var vp := get_viewport().get_visible_rect().size
	hint_panel.reset_size()
	hint_panel.position = Vector2(vp.x * 0.5 - hint_panel.size.x * 0.5, vp.y - 150.0)

func _say(msg: String, seconds: float = 3.5) -> void:
	_msg = msg
	_msg_timer = seconds

# ---------------------------------------------------------------- 存档

func _state_path() -> String:
	return "user://save/renewal_v1/wheel.json"

func _load_state() -> void:
	var path := _state_path()
	angle = BOARD_ANGLE
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	angle = float(data.get("angle", BOARD_ANGLE))
	boarding_index = int(data.get("cabin", 0))
	_align_target = _angle_for_cabin(boarding_index)
	var was_riding := bool(data.get("riding", false))
	if was_riding:
		state = "idle"
		_say("已返回摩天轮站台", 6.0)

func _exit_tree() -> void:
	save_state()

func save_state() -> void:
	var dir := "user://save/renewal_v1"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"angle": angle,
		"riding": riding,
		"cabin": boarding_index,
		"state": state,
		"saved_at": Time.get_datetime_string_from_system(),
	}))
	f.close()
