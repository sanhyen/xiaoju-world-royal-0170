extends Node
## P2 近岸水面带 + P5 礁盘水面
##
## 原版主海面是一张 1480 m 的粗网格（BackgroundOcean 32000×32000 但只有 5528 三角），
## 近岸什么细节都承载不了：没有透底、没有分色、泡沫是 `abs(offshore - tide) < 0.38`
## 的一条随 x 变化的直线，岸线不规则处直接错位。
##
## 这里沿岸线新建一条 30 m 宽的水面带，UV 的 u = 沿岸距离、v = 离岸距离，
## 「离岸多远」于是变成可直接用的参数：透底、分色、泡沫、涌浪全部按 v 走。
## 两个海岛的礁盘复用同一材质，靠 is_reef 分支切到椭圆归一化半径判定。
##
## 开关：--nearshore=0

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")
const SHADER_PATH := "res://shaders/nearshore_water.gdshader"
const POLISH_SHADER_PATH := "res://scripts/renewal/nearshore_water_polished.gdshader"

const SEA_Y := -2.4
const BAND_Y := -2.35
const STEP := 2.5
## 离岸距离（米）。0 是水线，30 是近岸带外缘。
const OFFSETS := [0.0, 1.0, 2.2, 4.0, 6.5, 10.0, 16.0, 30.0]
const MAX_V := 30.0
const U_SCALE := 12.0

## 两个海岛的礁盘椭圆（与方案 v3 一致）
const REEFS := [
	{"name": "主岛礁盘", "center": Vector2(232.5, 452.5), "radius": Vector2(77.5, 47.5)},
	{"name": "第二岛林盘", "center": Vector2(-60.0, 490.0), "radius": Vector2(60.0, 39.2)},
]

var layer: Node
var world: Node
var enabled := true
var built := false
var band: MeshInstance3D
var reefs: Array[MeshInstance3D] = []
var _mat_band: ShaderMaterial
var _reef_mats: Array[ShaderMaterial] = []
var _tris := 0
var polish_enabled := true

func setup(p_layer: Node) -> void:
	layer = p_layer
	world = layer.world
	for a in OS.get_cmdline_user_args():
		if a == "--nearshore=0":
			enabled = false
		elif a == "--environment-polish=0":
			polish_enabled = false

func build() -> void:
	if not enabled or world == null or built:
		return
	var sh: Shader = load(POLISH_SHADER_PATH if polish_enabled else SHADER_PATH)
	if sh == null:
		push_error("nearshore shader missing")
		return
	_mat_band = ShaderMaterial.new()
	_mat_band.shader = sh
	_mat_band.set_shader_parameter("is_reef", 0.0)
	_build_band()
	_build_reefs()
	built = true
	print("NEARSHORE_BUILT tris=%d reefs=%d" % [_tris, reefs.size()])

# ---------------------------------------------------------------- 近岸带

func _build_band() -> void:
	var spec = world.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var bay = (spec as Dictionary).get("bay_layout", {})
	if typeof(bay) != TYPE_DICTIONARY:
		return
	var shore = (bay as Dictionary).get("shore", [])
	if not (shore is Array) or (shore as Array).size() < 3:
		return

	var pts: Array[Vector3] = _resample(shore)
	var n := pts.size()
	if n < 4:
		return

	# 1) 把每个岸线控制点推到真正的水线（height_at 穿过 SEA_Y 的位置）
	var edges: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in range(n):
		var nn := _outward(i, pts)
		normals.append(nn)
		edges.append(_water_edge(pts[i], nn))

	# 2) 沿法向外推成三角带
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var dist := 0.0
	var base := 0
	var rows := OFFSETS.size()
	for i in range(n - 1):
		var seg_len := edges[i].distance_to(edges[i + 1])
		for k in range(rows):
			var off := float(OFFSETS[k])
			var a := edges[i] + normals[i] * off
			var b := edges[i + 1] + normals[i + 1] * off
			a.y = BAND_Y
			b.y = BAND_Y
			verts.append(a)
			uvs.append(Vector2(dist / U_SCALE, off / MAX_V))
			cols.append(Color(1, 1, 1, 1.0 if _under(a) else 0.0))
			verts.append(b)
			uvs.append(Vector2((dist + seg_len) / U_SCALE, off / MAX_V))
			cols.append(Color(1, 1, 1, 1.0 if _under(b) else 0.0))
		for k in range(rows - 1):
			var i0 := base + k * 2
			var i1 := i0 + 1
			var i2 := i0 + 2
			var i3 := i0 + 3
			idx.append_array([i0, i1, i3, i0, i3, i2])
		base += rows * 2
		dist += seg_len

	if idx.size() < 3:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat_band)

	band = MeshInstance3D.new()
	band.name = "NearshoreBand"
	band.mesh = mesh
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.extra_cull_margin = 4.0
	layer.world.add_child(band)
	_tris += idx.size() / 3
	print("NEARSHORE_BAND points=%d tris=%d length=%.0fm" % [n, idx.size() / 3, dist])

## 开放折线的 Catmull-Rom 重采样（shore 是从西到东的一条曲线，首尾不闭合）
func _resample(shore: Array) -> Array[Vector3]:
	var raw: Array[Vector3] = []
	for s in shore:
		if s is Array and (s as Array).size() >= 2:
			raw.append(Vector3(float(s[0]), 0.0, float(s[1])))
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
		var steps: int = maxi(1, int(round(seg / STEP)))
		for s in range(steps):
			out.append(_cr(p0, p1, p2, p3, float(s) / float(steps)))
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

## 水平法向，并保证指向海侧（两侧各探 8 m，取地形更低的一侧）
func _outward(i: int, pts: Array[Vector3]) -> Vector3:
	var prev := pts[maxi(0, i - 1)]
	var nxt := pts[mini(pts.size() - 1, i + 1)]
	var t := nxt - prev
	t.y = 0.0
	if t.length() < 0.001:
		return Vector3(0, 0, 1)
	t = t.normalized()
	var n := Vector3(t.z, 0.0, -t.x)
	var pa := pts[i] + n * 8.0
	var pb := pts[i] - n * 8.0
	var ha := _h(pa)
	var hb := _h(pb)
	if ha > hb:
		n = -n
	return n

## 从岸线点沿海向搜索，找到 height_at 首次穿过 SEA_Y 的位置（二分细化）
func _water_edge(p: Vector3, n: Vector3) -> Vector3:
	var t := 0.0
	while t <= 72.0:
		var q := p + n * t
		if _h(q) <= SEA_Y:
			var lo := maxf(0.0, t - 2.0)
			var hi := t
			for _i in range(7):
				var mid := (lo + hi) * 0.5
				if _h(p + n * mid) <= SEA_Y:
					hi = mid
				else:
					lo = mid
			return p + n * hi
		t += 2.0
	return p + n * 72.0

func _h(p: Vector3) -> float:
	return float(world.call("height_at", p.x, p.z))

func _under(p: Vector3) -> bool:
	return _h(p) < BAND_Y - 0.02

# ---------------------------------------------------------------- 礁盘

func _build_reefs() -> void:
	var sh: Shader = load(SHADER_PATH)
	for r in REEFS:
		var c: Vector2 = r["center"]
		var rad: Vector2 = r["radius"]
		var m := ShaderMaterial.new()
		m.shader = sh
		if polish_enabled and c == Vector2(232.5,452.5):
			m.shader = load(POLISH_SHADER_PATH)
			m.set_shader_parameter("natural_coral",true)
		m.set_shader_parameter("is_reef", 1.0)
		m.set_shader_parameter("reef_ellipse", Vector4(c.x, c.y, rad.x, rad.y))
		m.set_shader_parameter("foam_width", 0.02)
		_reef_mats.append(m)

		var rings := 12
		var segs := 44
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		# 顶点网格：(rings+1) × segs，中心单独一个点用 ring=0 半径 0 代替
		for ring in range(rings + 1):
			var rr := float(ring) / float(rings) * 1.12
			for s in range(segs):
				var a := TAU * float(s) / float(segs)
				var px := c.x + cos(a) * rad.x * rr
				var pz := c.y + sin(a) * rad.y * rr
				var p := Vector3(px, BAND_Y, pz)
				verts.append(p)
				# u 近似沿岸距离、v 用归一化半径
				uvs.append(Vector2(a * maxf(rad.x, rad.y) * rr / U_SCALE, rr))
				cols.append(Color(1, 1, 1, 1.0 if _under(p) else 0.0))
		for ring in range(rings):
			for s in range(segs):
				var s2 := (s + 1) % segs
				var i0 := ring * segs + s
				var i1 := ring * segs + s2
				var i2 := (ring + 1) * segs + s
				var i3 := (ring + 1) * segs + s2
				idx.append_array([i0, i2, i1, i1, i2, i3])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.name = "Reef_" + str(r["name"])
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.world.add_child(mi)
		reefs.append(mi)
		_tris += idx.size() / 3
		print("REEF_BUILT %s tris=%d" % [str(r["name"]), idx.size() / 3])
