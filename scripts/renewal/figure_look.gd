extends Node
## 人物形象与步态优化
##
## 原版角色是 12 个 BoxMesh 拼的方块人：材质全在 mesh 内置、没有配色区分，
## 走路时只有大腿在摆（±0.4 rad），手臂完全不动，看着像"滑行的木偶"。
## 原脚本是字节码改不了，这里用运行时接管：
##   1) 把方块换成胶囊/球体，圆润度立刻上来；
##   2) 按身体部位上色（皮肤 / 头发 / 上衣 / 裤 / 鞋 / 眼睛）；
##   3) 每帧在角色自身动画之后补手臂摆动，并把腿的摆幅放大到接近真人步态。

const SKIN := Color(0.96, 0.80, 0.68)
const HAIR := Color(0.23, 0.16, 0.13)
const CLOTH := Color(0.90, 0.88, 0.82)
const PANTS := Color(0.29, 0.37, 0.45)
const SHOE := Color(0.19, 0.17, 0.16)
const EYE := Color(0.12, 0.11, 0.11)
const PACK := Color(0.42, 0.31, 0.22)

const WALK_GAIN := 1.30
const RUN_GAIN := 1.80

var layer: Node
var player: CharacterBody3D
var legs: Array = []
var arms: Array = []
var shins: Array[Node3D] = []
var _shin_rest: Array[float] = []
var _air_blend := 0.0
var current_gain := WALK_GAIN
var _last_written: Array[float] = [NAN,NAN]
var _native_angles: Array[float] = [0.0,0.0]
var _done := false

func setup(p_layer: Node) -> void:
	layer = p_layer
	player = layer.player
	process_priority = 20   # 必须在角色自身动画之后执行

func _process(delta: float) -> void:
	if player == null:
		if layer != null:
			player = layer.player
		if player == null:
			return
	if not _done:
		_apply()
		if not _done:
			return
	_pose(delta)

# ---------------------------------------------------------------- 造型

func _apply() -> void:
	var fig = player.get("figure")
	if fig == null or not (fig is Node3D):
		return
	var kids: Array = []
	for c in (fig as Node).get_children():
		if c is MeshInstance3D:
			kids.append(c)
	if kids.size() < 12:
		return

	# 顺序与原版生成顺序一致：躯干 / 头 / 发 / 眼 / 眼 / 腿 / 腿 / 小腿 / 小腿 / 臂 / 臂 / 背包
	var torso: MeshInstance3D = kids[0]
	var head: MeshInstance3D = kids[1]
	var hair: MeshInstance3D = kids[2]
	var eye_l: MeshInstance3D = kids[3]
	var eye_r: MeshInstance3D = kids[4]
	var thigh_l: MeshInstance3D = kids[5]
	var thigh_r: MeshInstance3D = kids[6]
	var shin_l: MeshInstance3D = kids[7]
	var shin_r: MeshInstance3D = kids[8]
	var arm_l: MeshInstance3D = kids[9]
	var arm_r: MeshInstance3D = kids[10]
	var pack: MeshInstance3D = kids[11]

	_set_capsule(torso, 0.25, 0.66, CLOTH, 0.62)
	_set_sphere(head, 0.215, SKIN)
	_set_sphere(hair, 0.228, HAIR)
	hair.scale = Vector3(1.02, 0.52, 1.02)
	hair.position.y += 0.06
	_set_sphere(eye_l, 0.028, EYE)
	_set_sphere(eye_r, 0.028, EYE)
	_set_capsule(thigh_l, 0.115, 0.72, PANTS, 1.0)
	_set_capsule(thigh_r, 0.115, 0.72, PANTS, 1.0)
	_set_capsule(shin_l, 0.105, 0.46, PANTS, 1.0)
	_set_capsule(shin_r, 0.105, 0.46, PANTS, 1.0)
	_set_capsule(arm_l, 0.095, 0.64, CLOTH, 1.0)
	_set_capsule(arm_r, 0.095, 0.64, CLOTH, 1.0)
	_set_capsule(pack, 0.16, 0.42, PACK, 0.55)

	legs = player.get("legs") if player.get("legs") is Array else []
	arms = player.get("arms") if player.get("arms") is Array else []
	shins = [shin_l,shin_r]
	_shin_rest = [shin_l.rotation.x,shin_r.rotation.x]
	_done = true
	print("FIGURE_LOOK_APPLIED parts=%d legs=%d arms=%d" % [kids.size(), legs.size(), arms.size()])

func _set_capsule(mi: MeshInstance3D, radius: float, height: float, col: Color, flat: float) -> void:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0 + 0.01)
	cm.radial_segments = 14
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = _mat(col)
	mi.scale = Vector3(1.0, 1.0, flat)

func _set_sphere(mi: MeshInstance3D, radius: float, col: Color, flat: float = 1.0) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = _mat(col)
	mi.scale = Vector3(1.0, 1.0, flat)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.86
	m.metallic = 0.0
	return m

# ---------------------------------------------------------------- 步态

func _pose(delta: float) -> void:
	if legs.size() < 2 or arms.size() < 2:
		return
	# 原版坐姿已经包含大腿和独立小腿，保持原生姿势，避免被步态放大截断。
	if bool(player.get("seated")):
		_air_blend = 0.0
		_last_written = [NAN,NAN]
		return
	var speed := Vector2(player.velocity.x,player.velocity.z).length()
	var walking := maxf(float(player.get("walk_speed")),0.1)
	var running := walking*maxf(float(player.get("run_multiplier")),1.01)
	current_gain = lerpf(WALK_GAIN,RUN_GAIN,smoothstep(walking*0.95,running,speed))
	var airborne := not player.is_on_floor() and absf(player.velocity.y)>0.2
	_air_blend = move_toward(_air_blend,1.0 if airborne else 0.0,delta*8.0)
	var rising := player.velocity.y>0
	var lx := 0.0
	var rx := 0.0
	for i in range(2):
		var l = legs[i]
		if l is Node3D and is_instance_valid(l):
			var cur: float = (l as Node3D).rotation.x
			# 部分静止/程序驱动帧不会重写腿部，不能把上帧输出再次放大。
			if is_finite(_last_written[i]) and is_equal_approx(cur,_last_written[i]):
				cur = _native_angles[i]
			else:
				_native_angles[i] = cur
			if speed<0.05 and player.is_on_floor():
				cur = 0.0
				_native_angles[i] = 0.0
			var amp: float = signf(cur) * minf(absf(cur) * current_gain, 0.90)
			var air_angle := (-0.32 if i==0 else -0.22) if rising else (0.10 if i==0 else 0.06)
			(l as Node3D).rotation.x = lerpf(amp,air_angle,_air_blend)
			_last_written[i] = (l as Node3D).rotation.x
			if i == 0:
				lx = amp
			else:
				rx = amp
	# 手臂与同侧腿反相：腿向前时手向后，这是走路最关键的辨识特征
	for i in range(2):
		var a = arms[i]
		if a is Node3D and is_instance_valid(a):
			var base: float = lx if i == 0 else rx
			var swing := -base*0.72
			var air_angle := -0.40 if rising else (-0.16 if i==0 else 0.16)
			(a as Node3D).rotation.x = lerpf(swing,air_angle,_air_blend)
	for i in range(shins.size()):
		shins[i].rotation.x = lerpf(_shin_rest[i],0.55 if rising else 0.15,_air_blend)
