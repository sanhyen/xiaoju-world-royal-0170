extends Node
## 通行修复（门槛 / 入口 / 楼梯转角）
##
## 原始建筑几何由字节码脚本生成，无法直接改写；本模块采用两种工程手段：
##  1) 在既有入口与楼梯的实际坐标上补“连续行走面”（薄坡面碰撞），使踏步范围整体可走；
##  2) 运行时小台阶跨越（≤0.28m），只在前向受阻且上方有净空、落脚有支撑时生效。
## 所有坐标来自 world.metadata/entrances110 与 upper_routes110（原包登记数据）。

const MAX_STEP := 0.28

var layer: Node
var enabled := true
var step_assist := true
var stairs := true
var built := false
var ramp_count := 0
var step_ups := 0

var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _last_pos := Vector3.ZERO
var _lift_cooldown := 0.0
var _lift_from := Vector3.ZERO
var _verify_time := 0.0
var step_reverts := 0
var walking_routes:Array[Dictionary]=[]
var _walking_cells:Dictionary={}

func setup(p_layer: Node) -> void:
	layer = p_layer
	_player = layer.player

func build() -> void:
	if built or layer == null or layer.world == null:
		return
	built = true
	_build_entrances()
	if stairs:
		_build_upper_routes()
	print("PASSABILITY_BUILT entrances_ramps=%d" % ramp_count)

func _build_entrances() -> void:
	var ents: Array = layer.world.get("metadata/entrances110")
	if ents == null:
		return
	var root := Node3D.new()
	root.name = "RenewalEntranceSurfaces"
	add_child(root)
	for e in ents:
		var pts: Array = e.get("points", [])
		if pts.size() < 3:
			continue
		var width := clampf(float(e.get("width", 2.4)), 1.8, 3.4)
		var id := str(e.get("id", "?"))
		var v: Array[Vector3] = []
		for p in pts:
			v.append(_pv(p))
		# 只在存在实际高差的段补连续行走面；平坦门槛保留原地面，避免多余碰撞阻挡
		for i in range(1, v.size() - 1):
			_ramp(root, v[i], v[i + 1], width, "E_%s_%d" % [id, i])
			ramp_count += 1

func _build_upper_routes() -> void:
	var routes: Array = layer.world.get("metadata/upper_routes110")
	if routes == null:
		return
	var root := Node3D.new()
	root.name = "RenewalStairSurfaces"
	add_child(root)
	for r in routes:
		var pts: Array = r.get("points", [])
		if pts.size() < 2:
			continue
		var id := str(r.get("id", "?"))
		var v: Array[Vector3] = []
		for p in pts:
			v.append(_pv(p))
		for i in range(v.size() - 1):
			var dy := absf(v[i + 1].y - v[i].y)
			if dy < 0.12:
				continue
			_ramp(root, v[i], v[i + 1], 1.8, "R_%s_%d" % [id, i])
			ramp_count += 1

## 在两点之间铺一段连续行走面：楔形凸包，起始端为刀口（无竖直台阶），
## 坡度即两点连线，末端向下加厚以贴合原地面。
func _ramp(root: Node3D, a: Vector3, b: Vector3, width: float, name: String) -> void:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := (b-a).length()
	if flat.length() < 0.2:
		return
	var route:Dictionary={"a":a,"b":b,"width":width}
	walking_routes.append(route)
	var reach:=width*.5+.4
	for x in range(floori((minf(a.x,b.x)-reach)/32),floori((maxf(a.x,b.x)+reach)/32)+1):
		for z in range(floori((minf(a.z,b.z)-reach)/32),floori((maxf(a.z,b.z)+reach)/32)+1):
			var cell:=Vector2i(x,z)
			if not _walking_cells.has(cell):_walking_cells[cell]=[]
			_walking_cells[cell].append(route)
	var dir3 := (b - a).normalized()
	var side := dir3.cross(Vector3.UP).normalized()
	var normal := side.cross(dir3).normalized()
	var basis := Basis(side, normal, dir3)
	if basis.determinant() < 0.0:
		basis = Basis(-side, normal, dir3)
	var half := width * 0.5
	var drop := 0.18
	var pts := PackedVector3Array([
		Vector3(-half, 0.0, 0.0),
		Vector3(half, 0.0, 0.0),
		Vector3(half, 0.0, length),
		Vector3(-half, 0.0, length),
		Vector3(-half, -drop, length),
		Vector3(half, -drop, length),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(basis, a)
	root.add_child(body)

func _physics_process(_delta: float) -> void:
	if not enabled or _player == null:
		return
	if not step_assist:
		return
	if _lift_cooldown > 0.0:
		_lift_cooldown -= _delta
	# 跨越后的有效性检查：0.7 秒内必须取得前进量，否则回退并冷却
	if _verify_time > 0.0:
		_verify_time -= _delta
		if _player.global_position.distance_to(_lift_from) > 0.45:
			_verify_time = 0.0
		elif _verify_time <= 0.0:
			_player.global_position = _lift_from
			_lift_cooldown = 3.0
			step_reverts += 1
			_last_pos = _player.global_position
			return
	if not _player.is_on_floor():
		_last_pos = _player.global_position
		return
	# 只对“正在主动前进”的玩家生效，避免站立推墙时被抬起
	if not (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)):
		_last_pos = _player.global_position
		return
	var motion := _player.global_position - _last_pos
	_last_pos = _player.global_position
	if Vector2(motion.x, motion.z).length() < 0.012:
		return
	if _lift_cooldown > 0.0:
		return
	# 仅在前方确实受阻时尝试跨越
	var probe := motion.normalized() * 0.35 + Vector3(0, -0.05, 0)
	if not _player.test_move(_player.global_transform, probe):
		return
	for h in [0.16, 0.22, MAX_STEP]:
		var up := Vector3(0, h, 0)
		if _player.test_move(_player.global_transform, up):
			continue
		var raised := _player.global_transform.translated(up)
		if _player.test_move(raised, motion.normalized() * 0.35):
			continue
		# 上方净空与落脚支撑检查：抬升后近处与前方 0.9m 都要有同一高度的连续支撑，
		# 避免把玩家顶到矮墙、石块等窄顶面上。
		var base := _player.global_position + up
		var fwd := motion.normalized()
		if _has_support(base + fwd * 0.4, h) and _has_support(base + fwd * 0.9, h):
			_lift_from = _player.global_position
			_player.global_position = _player.global_position + up + Vector3(0, 0.02, 0)
			step_ups += 1
			_lift_cooldown = 0.35
			_verify_time = 0.7
			break

func _has_support(p: Vector3, expect_height: float) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.55, 0), p - Vector3(0, 0.75, 0))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	if n.angle_to(Vector3.UP) > deg_to_rad(40.0):
		return false
	var drop := p.y - (hit.position as Vector3).y
	return drop < expect_height + 0.12

func _pv(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var s := str(v).strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func contains(p:Vector3)->bool:
	var at:=Vector2(p.x,p.z)
	for row in _walking_cells.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		var a:Vector3=row.a;var b:Vector3=row.b
		if p.y<minf(a.y,b.y)-.5 or p.y>maxf(a.y,b.y)+4:continue
		var a2:=Vector2(a.x,a.z);var b2:=Vector2(b.x,b.z)
		var near:=Geometry2D.get_closest_point_to_segment(at,a2,b2)
		if near.distance_to(at)>float(row.width)*.5+.4:continue
		var t:=a2.distance_to(near)/maxf(.001,a2.distance_to(b2))
		if absf(p.y-lerpf(a.y,b.y,t))<4:return true
	return false
