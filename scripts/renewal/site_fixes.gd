extends Node3D
## 场地级修复（0170）：门槛短坡、河岸可见石阶、窄缝封边。
## 用自有 MeshLib 生成可见几何 + 贴合的连续坡面碰撞，几何按材质合并，避免逐块绘制开销。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")

var layer: Node
var built_steps := 0
var built_banks := 0
var built_edges := 0

var _mb: RefCounted
var _bodies: Array = []
var _root: Node3D

func setup(p_layer: Node) -> void:
	layer = p_layer

func build() -> void:
	_mb = MeshLib.new()
	_bodies = []
	_root = Node3D.new()
	_root.name = "RenewalSiteFixes"
	add_child(_root)
	_fix_thresholds()
	_fix_river_banks()
	_fix_narrow_gaps()
	_commit()

# ---------------------------------------------------------------- 绘制封装

func _mat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.from_string("#" + hex, Color(0.7, 0.7, 0.7))
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _box(pos: Vector3, size: Vector3, hex: String, solid: bool = false) -> void:
	_mb.begin(hex)
	_mb.box(Transform3D(Basis.IDENTITY, pos), size)
	if solid:
		_bodies.append({"pos": pos, "size": size, "basis": Basis.IDENTITY})

func _ramp_body(a: Vector3, b: Vector3, width: float) -> void:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := flat.length()
	if length < 0.25:
		return
	var dir3 := (b - a).normalized()
	var side := dir3.cross(Vector3.UP).normalized()
	var normal := side.cross(dir3).normalized()
	var basis := Basis(side, normal, dir3)
	if basis.determinant() < 0.0:
		basis = Basis(-side, normal, dir3)
	# 可见踏步
	var n := maxi(3, int(length / 0.42))
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t)
		_mb.begin("C9C1AE")
		_mb.box(Transform3D(basis, p), Vector3(width, 0.16, length / float(n) * 1.02))
		built_steps += 1
	# 连续坡面碰撞（楔形凸包，起始端刀口）
	var half := width * 0.5
	var pts := PackedVector3Array([
		Vector3(-half, 0, 0), Vector3(half, 0, 0),
		Vector3(half, 0, length), Vector3(-half, 0, length),
		Vector3(-half, -0.18, length), Vector3(half, -0.18, length),
	])
	_bodies.append({"convex": pts, "pos": a, "basis": basis})

func _commit() -> void:
	var mats := {}
	for k in _mb.groups.keys():
		mats[k] = _mat(str(k))
	var mesh: ArrayMesh = _mb.build(mats)
	var mi := MeshInstance3D.new()
	mi.name = "SiteFixMesh"
	mi.mesh = mesh
	_root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "SiteFixCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	_root.add_child(body)
	for rec in _bodies:
		var cs := CollisionShape3D.new()
		if rec.has("convex"):
			var sh := ConvexPolygonShape3D.new()
			sh.points = rec["convex"]
			cs.shape = sh
			cs.transform = Transform3D(rec["basis"], rec["pos"])
		else:
			var sh2 := BoxShape3D.new()
			sh2.size = rec["size"]
			cs.shape = sh2
			cs.transform = Transform3D(rec["basis"], rec["pos"])
		body.add_child(cs)
	print("SITE_FIXES steps=%d banks=%d edges=%d" % [built_steps, built_banks, built_edges])

# ---------------------------------------------------------------- 门槛

## 花音商店街三处入口共用的 0.24m 门槛：加一段可见石阶 + 连续坡面。
## 已知限制（实测，未修复）：原版地面在 x=-111.9(4.429) → x=-111.4(4.620) 有一级
## 0.19 m 台阶，而玩家 capsule 的跨步能力 < 0.15 m。本坡能把台阶「垫」过去，但
## 是线性坡，在台阶处只有 4.47，仍低于台阶顶，所以通过与否取决于入射角度——
## 表现为 B03 / BAKERY_REAR 间歇性成功（多次实测 68～71/73 波动，非稳定 70/73）。
## 彻底修复需要按台阶轮廓做分段折线坡，本轮未完成，详见验收报告第 9 节。
func _fix_thresholds() -> void:
	# 实测玩家被卡在 (-113.59, 4.157, 217.25)，门口地面 4.6 / 5.6。
	# 起点压到 4.12 并留 3.6m 坡长，避免坡口本身形成新台阶。
	var spots := [
		[Vector3(-114.6, 4.12, 217.2), Vector3(-110.0, 4.62, 217.4), 3.4],
	]
	for s in spots:
		_ramp_body(s[0], s[1], float(s[2]))

# ---------------------------------------------------------------- 河岸石阶

## 沿登记河流每 ~28m 在两岸做可见石阶，水面到岸顶，坡度由实测地形高度决定。
func _fix_river_banks() -> void:
	var w: Node = layer.world
	var spec = w.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var rivers: Array = spec.get("bay_layout", {}).get("rivers", [])
	for r in rivers:
		var pts: Array = r.get("points", [])
		for i in range(pts.size() - 1):
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			var A := Vector3(float(a[0]), float(a[1]), float(a[2]))
			var B := Vector3(float(b[0]), float(b[1]), float(b[2]))
			var flat := Vector3(B.x - A.x, 0, B.z - A.z)
			var length := flat.length()
			if length < 1.0:
				continue
			var dir := flat / length
			var nrm := dir.cross(Vector3.UP).normalized()
			var samples := maxi(1, int(length / 28.0))
			for k in range(samples):
				var t := (float(k) + 0.5) / float(samples)
				var p := A.lerp(B, t)
				for side in [-1.0, 1.0]:
					var side_f := float(side)
					var offshore: Vector3 = p + nrm * side_f * 3.0
					var bank: Vector3 = p + nrm * side_f * 8.0
					var top := float(w.call("height_at", bank.x, bank.z))
					if top < p.y + 0.45 or top > p.y + 6.0:
						continue
					_ramp_body(Vector3(offshore.x, p.y + 0.05, offshore.z),
							   Vector3(bank.x, top, bank.z), 3.0)
					built_banks += 1
					_box(bank + nrm.cross(Vector3.UP) * 1.7 + Vector3(0, 0.45, 0),
						 Vector3(0.25, 0.9, 0.25), "8E887A")

# ---------------------------------------------------------------- 窄缝封边

## 对 20 栋改造建筑的侧向窄缝加贴合可见边界的矮墙（不封主通道）。
func _fix_narrow_gaps() -> void:
	var f := FileAccess.open("res://data/renewal/buildings_0170.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var list: Array = data["buildings"]
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			var ca: Vector3 = Vector3(float(a["center"][0]), float(a["floor_y"]), float(a["center"][2]))
			var cb: Vector3 = Vector3(float(b["center"][0]), float(b["floor_y"]), float(b["center"][2]))
			if absf(ca.y - cb.y) > 3.0:
				continue
			var gap_x := absf(ca.x - cb.x) - (float(a["w"]) + float(b["w"])) * 0.5
			var gap_z := absf(ca.z - cb.z) - (float(a["d"]) + float(b["d"])) * 0.5
			if gap_x > 0.2 and gap_x < 2.2 and absf(ca.z - cb.z) < (float(a["d"]) + float(b["d"])) * 0.5:
				var mid := (ca + cb) * 0.5
				_box(mid + Vector3(0, 0.55, 0), Vector3(gap_x + 0.1, 1.1, 0.4), "8E887A", true)
				built_edges += 1
			elif gap_z > 0.2 and gap_z < 2.2 and absf(ca.x - cb.x) < (float(a["w"]) + float(b["w"])) * 0.5:
				var mid2 := (ca + cb) * 0.5
				_box(mid2 + Vector3(0, 0.55, 0), Vector3(0.4, 1.1, gap_z + 0.1), "8E887A", true)
				built_edges += 1
