extends Node3D
## 云岫仙山（0170 第六轮）
##
## 定位：摩天轮正西的「另一块陆地」，隔约 100 m 海峡与主岛相望。
## 形制：中式山巅宫阙。四级石砌台地逐层收分，中轴一线贯通：
##       跨海长桥 → 一级台地 → 天梯 → 二级 → 天梯 → 三级 → 天梯 → 四级 → 天梯
##       → 山巅 → 太极广场 → 大阶梯 → 须弥座台基 → 重檐歇山主殿「云岫殿」→ 东西配殿
##
## 建筑语言（这一版遵守的五条）：
##   1. 三段式立面：石砌台基 / 柱廊墙身 / 出檐屋顶，高度比约 1 : 2.2 : 1.1
##   2. 开间韵律：主殿正面 7 开间，明间最宽，次间按 1.0 / 0.86 / 0.72 递减
##   3. 屋顶曲线：檐口平缓、近脊陡峻，6 段折线逼近凹曲面，四角起翘
##   4. 台地收分：每级收 14 m、升 7 m，阶梯坡度 26.6°，恰好可走
##   5. 中轴对位：长桥—天梯—广场—大阶梯—殿门—主殿全部压在 z=0 轴线上
##
## 全部程序化网格 + 静态碰撞，不依赖外部资源，不改原版地形。
## 本地坐标：+X = 东（朝主岛），+Z = 南；节点整体放在 ISLAND_CENTER。

const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")

const ISLAND_CENTER := Vector3(-770.0, 0.0, 300.0)
const SEA_Y := -2.4
const BED_Y := -15.0
const RING_N := 16

## 水下基座：[y, 半宽X, 半宽Z]
## 水面处收进 4 m，让一级台地略微悬挑，形成海蚀崖的凹脚；
## 否则底座和台地一样宽，整座岛从侧面看就是一只蛋糕托盘。
const BASE_RINGS := [
	[-15.0, 124.0, 98.0],
	[-8.0, 120.0, 95.0],
	[0.0, 118.0, 93.0],
]
## 五级台地 + 山巅：[y, 半宽X, 半宽Z]。每级收 10 m、升 8 m（38.7°）。
const TERRACES := [
	[4.0, 122.0, 96.0],
	[12.0, 112.0, 88.0],
	[20.0, 102.0, 80.0],
	[28.0, 92.0, 72.0],
	[36.0, 82.0, 64.0],
	[44.0, 72.0, 56.0],
]
const SUMMIT_Y := 44.0
const PLATFORM_Y := 52.0

## 跨海长桥（本地坐标）
const BRIDGE_A := Vector3(218.0, 1.6, 0.0)     # 主岛岸
## 桥必须插进一级台地的碰撞体内部，否则桥末端与台地碰撞盒之间会留空洞。
## 桥面在台缘（本地 x=122）处必须略高于台地顶面 4.0，否则玩家走上台地会撞
## 一级台地圆柱的竖直侧面。桥头 A 端实测落在 2.44 m，末端抬到 4.25 后
## 台缘处桥面 = 2.44 + 0.873*(4.25-2.44) ≈ 4.02，正好越过台地顶面。
const BRIDGE_B := Vector3(108.0, 4.25, 0.0)    # 深入一级台地
## 山巅大阶梯
const INNER_A := Vector3(52.0, SUMMIT_Y, 0.0)
const INNER_B := Vector3(34.0, PLATFORM_Y, 0.0)
## 台基
const PLAT_HALF := Vector2(34.0, 28.0)
const PLAT_CX := 0.0
## 山巅背后的岩峰（纯景观，撑起山形轮廓）
const PEAK_C := Vector2(-44.0, -54.0)
const PEAK_RINGS := [
	[38.0, 25.0, 21.0],
	[56.0, 19.0, 16.0],
	[74.0, 14.0, 11.6],
	[90.0, 9.0, 7.4],
	[102.0, 4.8, 3.9],
	[112.0, 2.0, 1.6],
]

const C_ROCK := "rock"
const C_ROCK_D := "rock_d"
const C_MOSS := "moss"
const C_TILE := "tile"
const C_TILE_D := "tile_d"
const C_RED := "red"
const C_WALL := "wall"
const C_STONE := "stone"
const C_STONE_D := "stone_d"
const C_GOLD := "gold"
const C_WOOD := "wood"
const C_SAKURA := "sakura"
const C_TRUNK := "trunk"
const C_PINE := "pine"
const C_GRASS := "grass"
const C_WATER := "water"
const C_PATH := "path"
const C_GLASS := "glass"
const C_STEEL := "steel"
const C_FALL := "fall"
const C_FOAM := "fall_foam"
const C_FLOWER := "terrace_flower"
const C_LANTERN := "lantern_glow"

var layer: Node
var _mats := {}
var _root: Node3D
var _bodies: Array = []
var _jit: Array[float] = []
var _car: Node3D
var _cabins: Array = []
var _car_t := 0.0
var _car_a := Vector3.ZERO
var _car_b := Vector3.ZERO

func setup(p_layer: Node) -> void:
	layer = p_layer
	position = ISLAND_CENTER
	_make_mats()
	_make_jitter()
	_root = Node3D.new()
	_root.name = "SkyPalaceIsland"
	add_child(_root)
	_build_mountain()
	_build_peak()
	_build_terraces()
	_build_terrace_stairs()
	_build_bridge()
	_build_plateau()
	_build_inner_stair()
	_build_platform()
	_build_main_hall()
	_build_side_halls()
	_build_plaza()
	_build_pond()
	_build_pavilions()
	_build_gardens()
	_build_waterfalls()
	_build_cablecar()
	_build_terrace_details()
	# 调试：--skypaint 给山体套一层不受光的纯色，用来判断黑块是"法线错"还是"别的物体"
	if OS.get_cmdline_user_args().has("--skypaint"):
		var mm: Node = _root.get_node_or_null("MountainMesh")
		if mm != null and mm is MeshInstance3D:
			var pm := StandardMaterial3D.new()
			pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.albedo_color = Color(1.0, 0.2, 0.9)
			(mm as MeshInstance3D).material_override = pm
	# 调试：--skyx=waterfall,bridge 可跳过指定构件，用于定位异常几何
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skyhide="):
			for nm in a.substr(10).split(","):
				var n: Node = _root.get_node_or_null(nm)
				if n != null:
					(n as Node3D).visible = false
	set_process(true)
	print("SKY_ISLAND_BUILT bodies=%d" % _bodies.size())

# ---------------------------------------------------------------- 材质

func _make_mats() -> void:
	# 太阳在西南，云岫仙山的东立面完全背光。纯漫反射会把五级台地压成一整块深灰，
	# 层次全丢。给岩石/苔藓补一点自发光当作环境反照，只提暗部、不改亮部。
	_mats[C_ROCK] = _mat_e(Color(0.70, 0.66, 0.59), 0.93, 0.0, Color(0.30, 0.28, 0.25))
	_mats[C_ROCK_D] = _mat_e(Color(0.55, 0.52, 0.47), 0.95, 0.0, Color(0.20, 0.18, 0.16))
	_mats[C_MOSS] = _mat_e(Color(0.44, 0.54, 0.36), 0.92, 0.0, Color(0.17, 0.21, 0.13))
	_mats[C_TILE] = _mat(Color(0.19, 0.44, 0.39), 0.50, 0.08)
	_mats[C_TILE_D] = _mat(Color(0.12, 0.32, 0.29), 0.58, 0.08)
	_mats[C_RED] = _mat(Color(0.56, 0.16, 0.13), 0.72, 0.0)
	_mats[C_WALL] = _mat(Color(0.91, 0.89, 0.83), 0.88, 0.0)
	_mats[C_STONE] = _mat_e(Color(0.79, 0.77, 0.71), 0.92, 0.0, Color(0.26, 0.24, 0.22))
	_mats[C_STONE_D] = _mat_e(Color(0.60, 0.58, 0.54), 0.95, 0.0, Color(0.20, 0.18, 0.16))
	_mats[C_GOLD] = _mat(Color(0.83, 0.66, 0.30), 0.26, 0.74)
	_mats[C_WOOD] = _mat(Color(0.46, 0.31, 0.21), 0.85, 0.0)
	_mats[C_SAKURA] = _mat(Color(0.96, 0.74, 0.81), 0.90, 0.0)
	_mats[C_TRUNK] = _mat(Color(0.34, 0.25, 0.20), 0.92, 0.0)
	_mats[C_PINE] = _mat(Color(0.19, 0.38, 0.24), 0.90, 0.0)
	_mats[C_GRASS] = _mat(Color(0.35, 0.47, 0.28), 0.94, 0.0)
	_mats[C_PATH] = _mat(Color(0.86, 0.84, 0.78), 0.91, 0.0)
	_mats[C_STEEL] = _mat(Color(0.34, 0.36, 0.38), 0.40, 0.86)
	var w := _mat(Color(0.32, 0.64, 0.68), 0.10, 0.20)
	w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	w.albedo_color.a = 0.76
	_mats[C_WATER] = w
	# 瀑布在山体背光面，靠漫反射会被压成近黑；直接给足自发光，让水幕自带亮度。
	# 瀑布在山体背光面，靠漫反射会被压成近黑；直接关掉光照用无光材质，
	# albedo 即最终颜色，稳定可控。
	var fw := ShaderMaterial.new()
	fw.shader = load("res://scripts/renewal/island_waterfall.gdshader")
	_mats[C_FALL] = fw
	var foam := ShaderMaterial.new()
	foam.shader = load("res://scripts/renewal/island_foam.gdshader")
	_mats[C_FOAM] = foam
	_mats[C_FLOWER] = _mat(Color(0.86,0.64,0.62),0.92,0.0)
	_mats[C_LANTERN] = _mat_e(Color(0.92,0.55,0.22),0.7,0.0,Color(0.95,0.45,0.12))
	var g := _mat(Color(0.64, 0.80, 0.82), 0.05, 0.30)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color.a = 0.40
	_mats[C_GLASS] = g

## 带自发光的材质：给背光面留一点环境反照，避免整片压黑。
func _mat_e(c: Color, rough: float, metal: float, glow: Color) -> StandardMaterial3D:
	var m := _mat(c, rough, metal)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 1.0
	# 程序化山体在个别角度会翻出朝内的面片，配合 CULL_DISABLED 会渲染成纯黑斑。
	# 打开背光让背面也有基础亮度，黑斑就被抹平了；对岩壁来说也像岩石透光。
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.52, 0.48)
	return m

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	# 程序化几何绕序不完全统一，关背面剔除避免局部缺失
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _make_jitter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261106
	_jit.clear()
	for i in range(RING_N):
		_jit.append(rng.randf_range(0.93, 1.07))

# ---------------------------------------------------------------- 基础构件

func _new() -> RefCounted:
	return MeshLib.new()

func _commit(b, nm: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh: ArrayMesh = b.build(_mats)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	(parent if parent != null else _root).add_child(mi)
	return mi

func _solid(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY, nm: String = "col") -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.transform = Transform3D(basis, center)
	_root.add_child(body)
	_bodies.append(body)

## 椭圆台地碰撞：半径按 XZ 分别缩放的单位圆柱。
## 台地是 16 边形，用矩形内接会内缩 3%（每级 3~4 m），天梯顶端与碰撞盒之间
## 就露出空洞，玩家爬上天梯却踏不到台地；用矩形外接又会在四角凸出 40 m。
## 缩放圆柱既能贴合多边形轮廓，又能让边缘与天梯顶端严丝合缝。
func _solid_ellipse(center: Vector3, rx: float, rz: float, h: float, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.0
	cyl.height = h
	cs.shape = cyl
	cs.scale = Vector3(rx, 1.0, rz)
	body.add_child(cs)
	body.transform = Transform3D(Basis.IDENTITY, center)
	_root.add_child(body)
	_bodies.append(body)

## 带朝向校验的四边形：保证法线朝 out_dir，避免程序化绕序把面打黑。
func _face(b, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, out_dir: Vector3) -> void:
	var n := (c - a).cross(bb - a)
	if n.dot(out_dir) < 0.0:
		b.add_quad(a, d, c, bb)
	else:
		b.add_quad(a, bb, c, d)

func _ring_points(y: float, hx: float, hz: float) -> Array:
	var pts: Array = []
	for i in range(RING_N):
		var a := TAU * float(i) / float(RING_N)
		pts.append(Vector3(cos(a) * hx * _jit[i], y, sin(a) * hz * _jit[i]))
	return pts

func _all_levels() -> Array:
	var out: Array = []
	for r in BASE_RINGS:
		out.append(r)
	for r in TERRACES:
		out.append(r)
	return out

func _cliff_half_at(y: float) -> Vector2:
	var lv := _all_levels()
	if y >= float(lv[lv.size() - 1][0]):
		var l: Array = lv[lv.size() - 1]
		return Vector2(float(l[1]), float(l[2]))
	for k in range(lv.size() - 1):
		var a: Array = lv[k]
		var c: Array = lv[k + 1]
		if y >= float(a[0]) and y <= float(c[0]):
			var t := (y - float(a[0])) / maxf(0.001, float(c[0]) - float(a[0]))
			return Vector2(lerpf(float(a[1]), float(c[1]), t), lerpf(float(a[2]), float(c[2]), t))
	var f: Array = lv[0]
	return Vector2(float(f[1]), float(f[2]))

# ---------------------------------------------------------------- 山体

func _build_mountain() -> void:
	var b := _new()
	var lv := _all_levels()
	var rings: Array = []
	for r in lv:
		rings.append(_ring_points(float(r[0]), float(r[1]), float(r[2])))
	# 侧壁：每两级台地之间再切 3 条岩层带，材质交替，做出沉积岩的层理。
	# 整片单一材质的斜面在东立面背光下会糊成一整块深灰，五级台地完全读不出来，
	# 整座山看着就像一块梯形蛋糕。分层之后横向条纹能把「台」和「崖」区分开。
	var bands := 3
	for k in range(rings.size() - 1):
		var lo: Array = rings[k]
		var hi: Array = rings[k + 1]
		var cy: float = (float(lv[k][0]) + float(lv[k + 1][0])) * 0.5
		# 水线以上交给 TerracesMesh 的垂直石砌台基，这里只铺水下崖脚
		if float(lv[k + 1][0]) > 0.0:
			continue
		for s in range(bands):
			var t0 := float(s) / float(bands)
			var t1 := float(s + 1) / float(bands)
			var ar: Array = []
			var br: Array = []
			for i in range(RING_N):
				ar.append((lo[i] as Vector3).lerp(hi[i], t0))
				br.append((lo[i] as Vector3).lerp(hi[i], t1))
			var mk: String = C_ROCK
			if cy < 2.0:
				mk = C_ROCK_D
			elif cy > 24.0:
				mk = C_MOSS if s >= 1 else C_ROCK
			else:
				mk = C_ROCK_D if s == 0 else C_ROCK
			b.begin(mk)
			for i in range(RING_N):
				var j := (i + 1) % RING_N
				var p0: Vector3 = ar[i]
				var p1: Vector3 = ar[j]
				var p2: Vector3 = br[j]
				var p3: Vector3 = br[i]
				# 上下各溢出 0.08 m，层间接缝被覆盖
				p0.y -= 0.08
				p1.y -= 0.08
				p2.y += 0.08
				p3.y += 0.08
				# 崖壁四边形的绕序按解析式固定：ar[i] → br[i] → br[j] → ar[j]。
				# 用 _face + 猜测的外向矢量在陡缓交界处会判反，翻出几块黑斑；
				# 这里直接按「斜向上 × 切向 = 径向朝外」推出来的顺序写死。
				b.add_quad(p0, p3, p2, p1)
				# 内胆：同形状向内缩 0.35 m、绕序反向。程序化侧壁在个别角度仍会
				# 翻出朝内的面，从外面看就是一个黑洞；补一层内胆后，任何视角都能
				# 看到一层受光的岩面，黑洞被彻底堵死。
				var i0 := Vector3(p0.x * 0.997, p0.y, p0.z * 0.997)
				var i1 := Vector3(p1.x * 0.997, p1.y, p1.z * 0.997)
				var i2 := Vector3(p2.x * 0.997, p2.y, p2.z * 0.997)
				var i3 := Vector3(p3.x * 0.997, p3.y, p3.z * 0.997)
				b.add_quad(i1, i2, i3, i0)
	# 崖脚裙边：把山体压进海床，避免从水下看到底面
	b.begin(C_ROCK_D)
	var foot: Array = _ring_points(BED_Y - 1.5, 150.0, 114.0)
	var low: Array = rings[0]
	for i in range(RING_N):
		var j2 := (i + 1) % RING_N
		var q0: Vector3 = low[i]
		var q1: Vector3 = low[j2]
		var q2: Vector3 = foot[j2]
		var q3: Vector3 = foot[i]
		# 裙边法线朝外需要这个顺序（与侧壁相反：裙边是向下外扩的倒斜面）
		b.add_quad(q0, q3, q2, q1)
	_commit(b, "MountainMesh")
	# 每级台地一块实心碰撞。用缩放圆柱贴合 16 边形轮廓：矩形内接会内缩 3%
	# （每级 3~4 m），天梯顶端与碰撞盒之间露空洞；矩形外接又会在四角凸出 40 m。
	for t in TERRACES:
		var ty: float = float(t[0])
		_solid_ellipse(Vector3(0, ty - 3.0, 0), float(t[1]), float(t[2]), 6.0,
			"TerraceBody%d" % int(ty))

## 山巅背后的岩峰：纯景观，撑起「山」的轮廓。底部埋进山体，不参与碰撞。
func _build_peak() -> void:
	var b := _new()
	var rings: Array = []
	for r in PEAK_RINGS:
		var pts: Array = []
		for i in range(RING_N):
			var a := TAU * float(i) / float(RING_N)
			pts.append(Vector3(PEAK_C.x + cos(a) * float(r[1]) * _jit[i], float(r[0]),
				PEAK_C.y + sin(a) * float(r[2]) * _jit[i]))
		rings.append(pts)
	for k in range(rings.size() - 1):
		var lo: Array = rings[k]
		var hi: Array = rings[k + 1]
		var cy: float = (float(PEAK_RINGS[k][0]) + float(PEAK_RINGS[k + 1][0])) * 0.5
		# 只有接近峰顶的一小段转苔色，其余保持岩石色，否则整座峰会像一根绿竹笋
		if cy > 96.0:
			b.begin(C_MOSS)
		else:
			b.begin(C_ROCK)
		for i in range(RING_N):
			var j := (i + 1) % RING_N
			var p0: Vector3 = lo[i]
			var p1: Vector3 = lo[j]
			var p2: Vector3 = hi[j]
			var p3: Vector3 = hi[i]
			var mid := Vector3((p0.x + p1.x) * 0.5 - PEAK_C.x, cy, (p0.z + p1.z) * 0.5 - PEAK_C.y)
			_face(b, p0, p1, p2, p3, Vector3(mid.x, 0.0, mid.z))
	# 峰顶
	var top: Array = rings[rings.size() - 1]
	b.begin(C_MOSS)
	var last: Array = PEAK_RINGS[PEAK_RINGS.size() - 1]
	_disc_poly(b, top, Vector3(PEAK_C.x, float(last[0]), PEAK_C.y), 0.4)
	_commit(b, "PeakMesh")

func _build_terraces() -> void:
	var b := _new()
	# 一级至四级台地顶面（山巅由 _build_plateau 单独铺装）
	for k in range(TERRACES.size() - 1):
		var t: Array = TERRACES[k]
		var y: float = float(t[0])
		var hx: float = float(t[1])
		var hz: float = float(t[2])
		b.begin(C_STONE)
		_disc_poly(b, _ring_points(y, hx, hz), Vector3(0, y, 0), 0.22)
		# 草地铺到台缘内侧：原来只铺 0.90，从俯视看每级台地几乎全是石面，
		# 五级台地读起来像五圈水泥环。
		b.begin(C_GRASS)
		_disc_poly(b, _ring_points(y + 0.06, hx * 0.965, hz * 0.965), Vector3(0, y + 0.06, 0), 0.22)
		# 台缘石栏
		_ring_rail(b, y + 0.1, hx * 0.965, hz * 0.965, k == 0)
	# 台地挡墙：在每级台缘砌一圈石墙（1.6 m），让"台"读得出来
	for k in range(TERRACES.size()):
		var t: Array = TERRACES[k]
		var wy: float = float(t[0])
		var wx: float = float(t[1]) * 0.995
		var wz: float = float(t[2]) * 0.995
		# 挡墙从「台缘 1.7 m 矮墙」改成「整级 8 m 石砌台基」：中式宫阙的台基
		# 本来就是垂直石壁，这样既贴合参考图，也彻底避开程序化斜面在背光下
		# 翻面发黑的问题。
		# 石砌台基分三段：勒脚（深）/ 墙身（中）/ 压顶（浅）。
		# 一整片同色的 8 m 高墙会显得像水泥挡土墙，加两道横向分界才有砌筑感。
		var bands := [
			[wy - 8.0, wy - 7.1, C_ROCK_D],
			[wy - 7.1, wy - 0.45, C_STONE_D],
			[wy - 0.45, wy + 0.1, C_STONE],
		]
		for bd in bands:
			var ya: float = float(bd[0])
			var yb: float = float(bd[1])
			var mk: String = str(bd[2])
			var lo_ring: Array = _ring_points(ya, wx, wz)
			var hi_ring: Array = _ring_points(yb, wx, wz)
			b.begin(mk)
			for i in range(RING_N):
				var j := (i + 1) % RING_N
				var p0: Vector3 = lo_ring[i]
				var p1: Vector3 = lo_ring[j]
				var p2: Vector3 = hi_ring[j]
				var p3: Vector3 = hi_ring[i]
				var mid := Vector3((p0.x + p1.x) * 0.5, (ya + yb) * 0.5, (p0.z + p1.z) * 0.5)
				_face(b, p0, p1, p2, p3, Vector3(mid.x, 0.0, mid.z))
	_commit(b, "TerracesMesh")

## 多边形顶面封盖（扇形三角化）
func _disc_poly(b, pts: Array, center: Vector3, uv_scale: float) -> void:
	for i in range(pts.size()):
		var j := (i + 1) % pts.size()
		b.add_tri(center, pts[i], pts[j], uv_scale)

## 沿多边形排布的望柱 + 压顶，scale 用于内缩到台缘
func _ring_rail(b, y: float, hx: float, hz: float, skip_east: bool) -> void:
	var pts := _ring_points(y, hx, hz)
	for i in range(RING_N):
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[(i + 1) % RING_N]
		# 东侧中轴留出阶梯口
		if skip_east and p.x > 0.0 and absf(p.z) < 13.0:
			continue
		var d := q - p
		var n := int(maxf(1.0, round(d.length() / 3.6)))
		b.begin(C_STONE)
		for k in range(n):
			var t := (float(k) + 0.5) / float(n)
			var pp := p + d * t
			b.box(Transform3D(Basis.IDENTITY, Vector3(pp.x, y + 0.55, pp.z)), Vector3(0.34, 1.1, 0.34), 0.3)
			b.box(Transform3D(Basis.IDENTITY, Vector3(pp.x, y + 1.16, pp.z)), Vector3(0.46, 0.16, 0.46), 0.3)
		b.begin(C_STONE_D)
		b.beam(Vector3(p.x, y + 1.0, p.z), Vector3(q.x, y + 1.0, q.z), 0.22)

# ---------------------------------------------------------------- 四级天梯

func _build_terrace_stairs() -> void:
	var b := _new()
	for k in range(TERRACES.size() - 1):
		var lo: Array = TERRACES[k]
		var hi: Array = TERRACES[k + 1]
		var y0: float = float(lo[0])
		var y1: float = float(hi[0])
		var x0: float = float(lo[1])
		# 天梯必须正好从「本级台缘」爬到「上一级台缘」：顶端 (hi[1], hi[0]) 与
		# 上一级台地圆柱的顶面边缘严丝合缝。若把顶端往内收，天梯就会从上一级
		# 台地的竖直侧面里穿过去，玩家爬到一半撞墙。
		var x1: float = float(hi[1])
		# 第一段天梯接跨海长桥：桥面在一级台地边缘处比台地顶面低约 0.2 m。
		# 若天梯仍从 4.0 起，玩家会撞上一个 0.19 m 的竖直台阶（超过跨步极限而卡死）。
		# 把第一段天梯起点压到桥面高度，台阶从桥面直接起坡。
		if k == 0:
			y0 -= 0.30
		var rise := y1 - y0
		var run := x0 - x1
		var steps := int(round(rise / 0.34))
		var step_run := run / float(steps)
		var step_rise := rise / float(steps)
		var width := 14.0
		for i in range(steps):
			var x := x0 - step_run * (float(i) + 0.5)
			var y := y0 + step_rise * (float(i) + 0.5)
			b.begin(C_STONE)
			b.box(Transform3D(Basis.IDENTITY, Vector3(x, y - 0.17, 0)), Vector3(step_run * 1.06, step_rise + 0.34, width), 0.4)
		# 御路（中轴石带）
		var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5 + 0.10, 0)
		var ang := atan2(rise, -run)
		var basis := Basis(Vector3(0, 0, 1), ang)
		var slope_len := sqrt(run * run + rise * rise)
		b.begin(C_STONE_D)
		b.box(Transform3D(basis, mid), Vector3(slope_len, 0.10, 4.4), 0.3)
		# 垂带
		for s in [-1.0, 1.0]:
			b.begin(C_STONE_D)
			b.box(Transform3D(basis, mid + Vector3(0, 0.55, s * (width * 0.5 + 0.7))),
				Vector3(slope_len, 1.15, 1.4), 0.4)
		# 碰撞：一整块斜面
		var a := Vector3(x0, y0, 0)
		var c := Vector3(x1, y1, 0)
		var d3 := c - a
		var dir := d3.normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var up := side.cross(dir).normalized()
		# 碰撞盒底面必须与斜面中心线齐平：原来中心下移 0.22 会让盒底侵入下一级
		# 台地顶面 0.4 m，玩家走上天梯起点就被卡住。改成「表面向上 0.2、厚 0.4」。
		_solid((a + c) * 0.5 + up * 0.20, Vector3(width, 0.40, d3.length()),
			Basis(side, up, dir), "TStair%d" % k)
	_commit(b, "TerraceStairsMesh")

# ---------------------------------------------------------------- 跨海长桥

func _build_bridge() -> void:
	var b := _new()
	# 桥头按真实地形落位，避免桥面埋进沙滩或悬空
	var ba := BRIDGE_A
	if layer != null and layer.world != null:
		ba.y = float(layer.world.call("height_at", ba.x + ISLAND_CENTER.x, ba.z + ISLAND_CENTER.z)) + 0.06
	ba.y = maxf(ba.y, SEA_Y + 1.2)
	var d3 := BRIDGE_B - ba
	var total := d3.length()
	var dir := d3.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var segs := 52
	var step := total / float(segs)
	for i in range(segs):
		var t := (float(i) + 0.5) / float(segs)
		var p: Vector3 = ba + d3 * t
		b.begin(C_STONE)
		b.box(Transform3D(Basis(side, up, dir), p + Vector3(0, -0.35, 0)), Vector3(7.0, 0.7, step * 1.06), 0.4)
		if i % 3 == 0:
			b.begin(C_STONE_D)
			b.box(Transform3D(Basis(side, up, dir), p + Vector3(0, 0.02, 0)), Vector3(7.2, 0.14, 0.5), 0.3)
	# 桥墩
	for i in range(4, segs, 7):
		var t2 := (float(i) + 0.5) / float(segs)
		var p2: Vector3 = ba + d3 * t2
		var h := p2.y - (BED_Y - 1.0)
		b.begin(C_STONE_D)
		b.box(Transform3D(Basis.IDENTITY, Vector3(p2.x, p2.y - 0.7 - h * 0.5, p2.z)), Vector3(2.8, h, 3.6), 0.4)
		b.begin(C_STONE)
		b.box(Transform3D(Basis.IDENTITY, Vector3(p2.x, p2.y - 1.2, p2.z)), Vector3(3.6, 0.9, 4.4), 0.4)
	# 栏杆
	for s in [-1.0, 1.0]:
		for i in range(0, segs, 2):
			var t3 := (float(i) + 0.5) / float(segs)
			var p3: Vector3 = ba + d3 * t3
			b.begin(C_STONE)
			b.box(Transform3D(Basis(side, up, dir), p3 + side * (s * 3.3) + up * 0.6), Vector3(0.30, 1.2, 0.30), 0.3)
		b.begin(C_STONE_D)
		var mid: Vector3 = (ba + BRIDGE_B) * 0.5 + side * (s * 3.3) + up * 1.15
		b.box(Transform3D(Basis(side, up, dir), mid), Vector3(0.22, 0.18, total), 0.3)
	_commit(b, "BridgeMesh")
	_solid((ba + BRIDGE_B) * 0.5 + Vector3(0, -0.35, 0), Vector3(7.0, 0.7, total),
		Basis(side, up, dir), "BridgeBody")

# ---------------------------------------------------------------- 山巅铺装

func _build_plateau() -> void:
	var b := _new()
	var top: Array = _ring_points(SUMMIT_Y, 72.0, 56.0)
	b.begin(C_STONE)
	_disc_poly(b, top, Vector3(0, SUMMIT_Y, 0), 0.22)
	b.begin(C_GRASS)
	for s in [-1.0, 1.0]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(-8.0, SUMMIT_Y + 0.06, s * 42.0)), Vector3(96.0, 0.10, 24.0), 0.3)
	# 中轴石板
	b.begin(C_PATH)
	b.box(Transform3D(Basis.IDENTITY, Vector3(60.0, SUMMIT_Y + 0.09, 0)), Vector3(28.0, 0.12, 12.0), 0.4)
	b.box(Transform3D(Basis.IDENTITY, Vector3(-6.0, SUMMIT_Y + 0.09, 0)), Vector3(100.0, 0.12, 10.0), 0.4)
	# 台缘石压顶
	b.begin(C_STONE_D)
	var rim: Array = _ring_points(SUMMIT_Y + 0.85, 73.0, 57.0)
	for i in range(RING_N):
		var j := (i + 1) % RING_N
		var p0: Vector3 = top[i]
		var p1: Vector3 = top[j]
		var p2: Vector3 = rim[j]
		var p3: Vector3 = rim[i]
		_face(b, p0, p1, p2, p3, Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.z + p1.z) * 0.5))
	_ring_rail(b, SUMMIT_Y + 0.1, 68.5, 53.0, true)
	_commit(b, "PlateauMesh")
	# 山巅也要有碰撞：TERRACES 循环只覆盖到第四级，第五级天梯顶端 (72, 44)
	# 正好落在山巅边缘，没有这块椭圆玩家会直接踏空掉进山体。
	_solid_ellipse(Vector3(0, SUMMIT_Y - 3.0, 0), 72.0, 56.0, 6.0, "SummitBody")

# ---------------------------------------------------------------- 山巅大阶梯

func _build_inner_stair() -> void:
	var b := _new()
	var d3 := INNER_B - INNER_A
	var run := absf(d3.x)
	var rise := d3.y
	var steps := 26
	var step_run := run / float(steps)
	var step_rise := rise / float(steps)
	for i in range(steps):
		var x := INNER_A.x - step_run * (float(i) + 0.5)
		var y := INNER_A.y + step_rise * (float(i) + 0.5)
		b.begin(C_STONE)
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, y - 0.17, 0)), Vector3(step_run * 1.06, step_rise + 0.34, 20.0), 0.4)
	var midx: float = (INNER_A.x + INNER_B.x) * 0.5
	var midy: float = (INNER_A.y + INNER_B.y) * 0.5
	var ang := atan2(rise, -run)
	var basis := Basis(Vector3(0, 0, 1), ang)
	var slope_len := sqrt(run * run + rise * rise)
	b.begin(C_STONE_D)
	b.box(Transform3D(basis, Vector3(midx, midy + 0.14, 0)), Vector3(slope_len, 0.10, 4.6), 0.3)
	for s in [-1.0, 1.0]:
		b.begin(C_STONE_D)
		b.box(Transform3D(basis, Vector3(midx, midy + 0.60, s * 10.4)), Vector3(slope_len, 1.15, 1.5), 0.4)
	_commit(b, "InnerStairMesh")
	var dir2 := d3.normalized()
	var side2 := dir2.cross(Vector3.UP).normalized()
	var up2 := side2.cross(dir2).normalized()
	_solid((INNER_A + INNER_B) * 0.5 + up2 * 0.20, Vector3(20.0, 0.40, d3.length()),
		Basis(side2, up2, dir2), "InnerStairBody")

# ---------------------------------------------------------------- 台基

func _build_platform() -> void:
	var b := _new()
	var w := PLAT_HALF.x * 2.0
	var d := PLAT_HALF.y * 2.0
	b.begin(C_STONE_D)
	b.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX, SUMMIT_Y + 0.7, 0)), Vector3(w + 7.0, 1.4, d + 7.0), 0.4)
	b.begin(C_STONE)
	b.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX, SUMMIT_Y + 4.6, 0)), Vector3(w + 2.5, 6.4, d + 2.5), 0.4)
	b.begin(C_STONE_D)
	b.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX, SUMMIT_Y + 8.9, 0)), Vector3(w + 4.5, 2.2, d + 4.5), 0.4)
	b.begin(C_STONE)
	b.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX, PLATFORM_Y - 0.3, 0)), Vector3(w + 2.0, 0.6, d + 2.0), 0.4)
	_commit(b, "PlatformMesh")
	_solid(Vector3(PLAT_CX, SUMMIT_Y + 4.0, 0), Vector3(w + 2.5, 8.0, d + 2.5), Basis.IDENTITY, "PlatformBody")
	# 台基石栏
	var rail := _new()
	var half := Vector2(PLAT_HALF.x + 1.0, PLAT_HALF.y + 1.0)
	rail.begin(C_STONE)
	var z := -half.y
	while z <= half.y + 0.01:
		rail.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX - half.x, PLATFORM_Y + 0.55, z)), Vector3(0.34, 1.1, 0.34), 0.3)
		rail.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX + half.x, PLATFORM_Y + 0.55, z)), Vector3(0.34, 1.1, 0.34), 0.3)
		z += 3.2
	var x := -half.x
	while x <= half.x + 0.01:
		if absf(x) < 10.0:
			x += 3.2
			continue
		rail.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX + x, PLATFORM_Y + 0.55, half.y)), Vector3(0.34, 1.1, 0.34), 0.3)
		rail.box(Transform3D(Basis.IDENTITY, Vector3(PLAT_CX + x, PLATFORM_Y + 0.55, -half.y)), Vector3(0.34, 1.1, 0.34), 0.3)
		x += 3.2
	_commit(rail, "PlatformRail")

# ---------------------------------------------------------------- 中式屋顶

## 6 段折线逼近「檐口平缓、近脊陡峻」的凹曲面，四角起翘。
## w = 檐口宽（X 向），d = 檐口深（Z 向），脊沿 Z。
func _roof(b, center: Vector3, w: float, d: float, h: float, ridge_scale: float = 0.36) -> void:
	var segs := 6
	var prev: Array = []
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var hw := w * 0.5 * (1.0 - t * (1.0 - ridge_scale))
		var hd := d * 0.5 * (1.0 - t * 0.88)
		var yy := center.y + h * pow(t, 0.70)
		prev.append([hw, hd, yy])
	b.begin(C_TILE)
	for i in range(segs):
		_quad_ring(b, center, prev[i], prev[i + 1])
	var top: Array = prev[segs]
	b.begin(C_TILE_D)
	b.box(Transform3D(Basis.IDENTITY, Vector3(center.x, float(top[2]) + 0.20, center.z)),
		Vector3(float(top[0]) * 2.0 + 0.7, 0.44, 0.9), 0.3)
	b.begin(C_GOLD)
	for s in [-1.0, 1.0]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(center.x, float(top[2]) + 0.66, center.z + s * (float(top[1]) + 0.25))),
			Vector3(0.5, 0.95, 0.5), 0.3)
	b.begin(C_TILE_D)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(center.x + sx * w * 0.5, center.y, center.z + sz * d * 0.5)
			var tip := base + Vector3(sx * 2.4, 1.7, sz * 2.4)
			b.beam(base, tip, 0.36)

func _quad_ring(b, center: Vector3, lo, hi) -> void:
	var lw: float = lo[0]
	var ld: float = lo[1]
	var ly: float = lo[2]
	var hw: float = hi[0]
	var hd: float = hi[1]
	var hy: float = hi[2]
	var cx := center.x
	var cz := center.z
	_face(b, Vector3(cx + lw, ly, cz + ld), Vector3(cx + lw, ly, cz - ld),
		Vector3(cx + hw, hy, cz - hd), Vector3(cx + hw, hy, cz + hd), Vector3(1, 0.4, 0))
	_face(b, Vector3(cx - lw, ly, cz - ld), Vector3(cx - lw, ly, cz + ld),
		Vector3(cx - hw, hy, cz + hd), Vector3(cx - hw, hy, cz - hd), Vector3(-1, 0.4, 0))
	_face(b, Vector3(cx - lw, ly, cz + ld), Vector3(cx + lw, ly, cz + ld),
		Vector3(cx + hw, hy, cz + hd), Vector3(cx - hw, hy, cz + hd), Vector3(0, 0.4, 1))
	_face(b, Vector3(cx + lw, ly, cz - ld), Vector3(cx - lw, ly, cz - ld),
		Vector3(cx - hw, hy, cz - hd), Vector3(cx + hw, hy, cz - hd), Vector3(0, 0.4, -1))

# ---------------------------------------------------------------- 柱廊墙身

func _hall_body(b, cx: float, cz: float, y: float, w: float, d: float, h: float, bays: int) -> void:
	b.begin(C_STONE)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx, y + 0.3, cz)), Vector3(w + 2.4, 0.6, d + 2.4), 0.4)
	b.begin(C_WALL)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx, y + 0.6 + h * 0.5, cz)), Vector3(w - 1.2, h, d - 1.2), 0.4)
	var widths: Array[float] = []
	var mid := (float(bays) - 1.0) * 0.5
	for i in range(bays):
		widths.append(1.0 - absf(float(i) - mid) / maxf(1.0, mid) * 0.30)
	var total := 0.0
	for ww in widths:
		total += ww
	var offs: Array[float] = []
	var cursor := -d * 0.5
	offs.append(cursor)
	for i in range(bays):
		cursor += d * (widths[i] / total)
		offs.append(cursor)
	b.begin(C_RED)
	for z in offs:
		b.cylinder(Vector3(cx + w * 0.5 - 0.55, y + 0.6, cz + z), Vector3(cx + w * 0.5 - 0.55, y + 0.6 + h, cz + z), 0.36, 10, true)
		b.cylinder(Vector3(cx - w * 0.5 + 0.55, y + 0.6, cz + z), Vector3(cx - w * 0.5 + 0.55, y + 0.6 + h, cz + z), 0.36, 10, true)
	b.begin(C_WOOD)
	for i in range(bays):
		var z0 := cz + (offs[i] + offs[i + 1]) * 0.5
		var bw := (offs[i + 1] - offs[i]) * 0.66
		if i == bays / 2:
			b.box(Transform3D(Basis.IDENTITY, Vector3(cx + w * 0.5 - 0.46, y + 1.9, z0)), Vector3(0.16, 2.6, bw), 0.3)
			b.box(Transform3D(Basis.IDENTITY, Vector3(cx - w * 0.5 + 0.46, y + 1.9, z0)), Vector3(0.16, 2.6, bw), 0.3)
		else:
			b.box(Transform3D(Basis.IDENTITY, Vector3(cx + w * 0.5 - 0.46, y + 1.7, z0)), Vector3(0.14, 1.5, bw), 0.3)
	b.begin(C_RED)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx + w * 0.5 - 0.55, y + 0.6 + h + 0.25, cz)), Vector3(0.55, 0.5, d), 0.4)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx - w * 0.5 + 0.55, y + 0.6 + h + 0.25, cz)), Vector3(0.55, 0.5, d), 0.4)
	b.begin(C_GOLD)
	for z in offs:
		b.box(Transform3D(Basis.IDENTITY, Vector3(cx + w * 0.5 - 0.55, y + 0.6 + h + 0.64, cz + z)), Vector3(0.9, 0.34, 0.9), 0.3)

# ---------------------------------------------------------------- 主殿

func _build_main_hall() -> void:
	var b := _new()
	var cx := -14.0
	var cz := 0.0
	var w := 16.0     # 进深（X）
	var d := 36.0     # 面阔（Z），7 开间
	var h := 10.0
	var y := PLATFORM_Y
	_hall_body(b, cx, cz, y, w, d, h, 7)
	var eave1 := y + 0.6 + h + 0.9
	_roof(b, Vector3(cx, eave1, cz), w + 10.0, d + 10.0, 6.4, 0.36)
	b.begin(C_WALL)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx, eave1 + 3.3, cz)), Vector3(w * 0.66, 4.2, d * 0.62), 0.4)
	b.begin(C_WOOD)
	b.box(Transform3D(Basis.IDENTITY, Vector3(cx + w * 0.34, eave1 + 3.5, cz)), Vector3(0.2, 2.2, d * 0.5), 0.3)
	_roof(b, Vector3(cx, eave1 + 5.4, cz), w * 0.74, d * 0.72, 5.6, 0.32)
	_commit(b, "MainHallMesh")
	_solid(Vector3(cx, y + 6.0, cz), Vector3(w - 0.6, 12.0, d - 0.6), Basis.IDENTITY, "MainHallBody")
	var lab := Label3D.new()
	lab.text = "云 岫 殿"
	lab.font_size = 128
	lab.pixel_size = 0.013
	lab.modulate = Color(0.98, 0.88, 0.54)
	lab.outline_size = 10
	lab.outline_modulate = Color(0.20, 0.08, 0.06)
	lab.position = Vector3(cx + w * 0.5 + 0.15, y + 8.6, cz)
	lab.rotation.y = PI * 0.5
	_root.add_child(lab)

# ---------------------------------------------------------------- 配殿

func _build_side_halls() -> void:
	var b := _new()
	for s in [-1.0, 1.0]:
		var cx := 14.0
		var cz: float = s * 20.0
		var w := 14.0
		var d := 10.0
		var h := 6.8
		var y := PLATFORM_Y
		_hall_body(b, cx, cz, y, w, d, h, 3)
		_roof(b, Vector3(cx, y + 0.6 + h + 0.8, cz), w + 7.0, d + 7.0, 4.2, 0.36)
		_solid(Vector3(cx, y + 4.0, cz), Vector3(w - 0.6, 8.0, d - 0.6), Basis.IDENTITY, "SideHallBody")
	_commit(b, "SideHallsMesh")

# ---------------------------------------------------------------- 太极广场

func _build_plaza() -> void:
	var b := _new()
	var c := Vector3(60.0, SUMMIT_Y, 0.0)
	b.begin(C_STONE_D)
	b.disc(c + Vector3(0, 0.05, 0), 9.4, 0.20, 48)
	b.begin(C_PATH)
	b.disc(c + Vector3(0, 0.16, 0), 8.6, 0.18, 48)
	# 太极双鱼
	b.begin(C_STONE_D)
	b.disc(c + Vector3(0, 0.26, 0), 6.4, 0.10, 40)
	b.begin(C_PATH)
	_disc_half(b, c + Vector3(0, 0.32, 0), 6.4, 0.08, 36, 1.0)
	b.begin(C_STONE_D)
	_disc_half(b, c + Vector3(0, 0.32, 0), 6.4, 0.08, 36, -1.0)
	b.begin(C_STONE_D)
	b.disc(c + Vector3(0, 0.38, 3.2), 1.25, 0.10, 20)
	b.begin(C_PATH)
	b.disc(c + Vector3(0, 0.38, -3.2), 1.25, 0.10, 20)
	_commit(b, "PlazaMesh")

## 半圆盘：sign=+1 取 +Z 侧，-1 取 -Z 侧
func _disc_half(b, center: Vector3, radius: float, thickness: float, segs: int, sign: float) -> void:
	var y0 := center.y - thickness * 0.5
	var y1 := center.y + thickness * 0.5
	for i in range(segs):
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0) * sign, 0, sin(a0))
		var d1 := Vector3(cos(a1) * sign, 0, sin(a1))
		var p0 := center + d0 * radius
		var p1 := center + d1 * radius
		b.add_tri(Vector3(center.x, y1, center.z), Vector3(p0.x, y1, p0.z), Vector3(p1.x, y1, p1.z), 0.3)
		b.add_tri(Vector3(center.x, y0, center.z), Vector3(p1.x, y0, p1.z), Vector3(p0.x, y0, p0.z), 0.3)

# ---------------------------------------------------------------- 池塘

func _build_pond() -> void:
	var b := _new()
	var c := Vector3(-40.0, SUMMIT_Y, 38.0)
	b.begin(C_STONE)
	b.ring(c + Vector3(0, 0.30, 0), Vector3.UP, 10.0, 1.3, 44, 6)
	b.begin(C_WATER)
	b.disc(c + Vector3(0, 0.28, 0), 9.4, 0.10, 44)
	b.begin(C_STONE)
	b.cylinder(c + Vector3(3.4, 0.3, 2.6), c + Vector3(3.4, 2.2, 2.6), 0.36, 8, true)
	b.box(Transform3D(Basis.IDENTITY, c + Vector3(3.4, 2.7, 2.6)), Vector3(1.1, 0.85, 1.1), 0.3)
	b.begin(C_GOLD)
	b.box(Transform3D(Basis.IDENTITY, c + Vector3(3.4, 3.25, 2.6)), Vector3(0.46, 0.38, 0.46), 0.3)
	b.begin(C_STONE)
	for i in range(6):
		var t := float(i) / 5.0
		b.box(Transform3D(Basis.IDENTITY, c + Vector3(lerpf(-7.0, 7.0, t), 0.8, sin(t * PI) * 2.4 - 7.0)), Vector3(3.2, 0.22, 2.8), 0.3)
	_commit(b, "PondMesh")

# ---------------------------------------------------------------- 观景亭

func _build_pavilions() -> void:
	var b := _new()
	var spots := [Vector3(-44.0, SUMMIT_Y, -42.0), Vector3(44.0, SUMMIT_Y, -42.0), Vector3(-44.0, SUMMIT_Y, 42.0)]
	for p in spots:
		var y: float = p.y
		b.begin(C_STONE)
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.3, 0)), Vector3(9.0, 0.6, 9.0), 0.4)
		b.begin(C_RED)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.cylinder(p + Vector3(sx * 3.2, 0.6, sz * 3.2), p + Vector3(sx * 3.2, 6.4, sz * 3.2), 0.3, 8, true)
		b.begin(C_WOOD)
		for s in [-1.0, 1.0]:
			b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, s * 3.2)), Vector3(7.0, 0.16, 0.7), 0.3)
			b.box(Transform3D(Basis.IDENTITY, p + Vector3(s * 3.2, 1.0, 0)), Vector3(0.7, 0.16, 7.0), 0.3)
		b.begin(C_RED)
		b.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 6.5, 0)), Vector3(7.4, 0.4, 7.4), 0.3)
		_roof(b, p + Vector3(0, 6.7, 0), 8.6, 8.6, 3.6, 0.06)
		b.begin(C_GOLD)
		b.cylinder(p + Vector3(0, 10.0, 0), p + Vector3(0, 11.2, 0), 0.26, 8, true)
		_solid(p + Vector3(0, 0.4, 0), Vector3(9.0, 0.8, 9.0), Basis.IDENTITY, "PavilionBase")
	_commit(b, "PavilionMesh")

# ---------------------------------------------------------------- 樱花与松

func _build_gardens() -> void:
	var b := _new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var placed := 0
	var tries := 0
	while placed < 58 and tries < 1400:
		tries += 1
		var x := rng.randf_range(-67.0, 67.0)
		var z := rng.randf_range(-51.0, 51.0)
		# 避开中轴
		if absf(z) < 8.0 and x > -30.0:
			continue
		# 避开台基
		if absf(x - PLAT_CX) < PLAT_HALF.x + 9.0 and absf(z) < PLAT_HALF.y + 9.0:
			continue
		# 避开太极广场
		if Vector2(x - 60.0, z).length() < 12.0:
			continue
		# 避开池塘
		if Vector2(x + 40.0, z - 38.0).length() < 13.0:
			continue
		# 避开岩峰
		if Vector2(x + 52.0, z + 36.0).length() < 25.0:
			continue
		# 避开观景亭
		var skip := false
		for p in [Vector3(-44.0, 0, -42.0), Vector3(44.0, 0, -42.0), Vector3(-44.0, 0, 42.0)]:
			if Vector2(x - p.x, z - p.z).length() < 7.5:
				skip = true
		if skip:
			continue
		placed += 1
		var y := SUMMIT_Y
		var sakura := rng.randf() < 0.66
		var h := rng.randf_range(3.6, 5.8)
		var r0 := rng.randf_range(2.4, 3.4)
		b.begin(C_TRUNK)
		b.cylinder(Vector3(x, y, z), Vector3(x, y + h * 0.62, z), 0.30, 7, true)
		if sakura:
			b.begin(C_SAKURA)
			b.disc(Vector3(x, y + h * 0.72, z), r0, 1.5, 9)
			b.disc(Vector3(x, y + h * 0.90, z), r0 * 0.76, 1.3, 9)
			b.disc(Vector3(x, y + h * 1.05, z), r0 * 0.46, 1.0, 8)
		else:
			b.begin(C_PINE)
			b.disc(Vector3(x, y + h * 0.64, z), r0 * 0.92, 1.9, 8)
			b.disc(Vector3(x, y + h * 0.86, z), r0 * 0.64, 1.7, 8)
			b.disc(Vector3(x, y + h * 1.02, z), r0 * 0.38, 1.4, 7)
	_commit(b, "GardenMesh")

# ---------------------------------------------------------------- 崖壁瀑布

func _build_waterfalls() -> void:
	var b := _new()
	var foam := _new()
	# 角度：0 = +X（东）。避开东侧天梯，取北、西、南三面
	var spots := [PI * 0.58, PI * 1.0, PI * 1.40, PI * 1.80]
	for a in spots:
		# 水帘改成一段段有厚度的薄板（box），不再用单层四边形。
		# 单层面片在倾斜崖面上绕序极易翻面，配合 CULL_DISABLED 会渲染成一条纯黑带；
		# 盒子有六个面，从任何角度看都至少有一个面是正面朝外的。
		var segs := 40
		var radial := Vector3(cos(a), 0.0, sin(a))
		for k in range(segs):
			var t0 := float(k) / float(segs)
			var t1 := float(k + 1) / float(segs)
			var y0 := lerpf(SUMMIT_Y + 0.4, SEA_Y - 0.8, t0)
			var y1 := lerpf(SUMMIT_Y + 0.4, SEA_Y - 0.8, t1)
			var h0 := _cliff_half_at(maxf(y0, 0.0))
			var h1 := _cliff_half_at(maxf(y1, 0.0))
			var p0 := Vector3(cos(a) * (h0.x + 1.0), y0, sin(a) * (h0.y + 1.0))
			var p1 := Vector3(cos(a) * (h1.x + 1.0), y1, sin(a) * (h1.y + 1.0))
			var seg_dir := (p1 - p0)
			var seg_len: float = seg_dir.length()
			if seg_len < 0.001:
				continue
			seg_dir = seg_dir / seg_len
			var side := seg_dir.cross(radial).normalized()
			var w0: float = lerpf(7.0, 15.0, t0)
			b.begin(C_FALL)
			b.box(Transform3D(Basis(side, seg_dir, radial), (p0 + p1) * 0.5),
				Vector3(w0, seg_len * 1.06, 0.5), 0.3)
		# 崖顶溢水口
		b.begin(C_STONE_D)
		var lip := Vector3(cos(a) * (72.0 + 1.2), SUMMIT_Y + 0.2, sin(a) * (56.0 + 1.2))
		b.box(Transform3D(Basis.IDENTITY, lip), Vector3(6.0, 0.6, 6.0), 0.4)
		# 落水处的断续泡沫环，无碰撞，避免扩宽水帘遮住崖壁。
		var foot := Vector3(cos(a)*122.0,SEA_Y+0.12,sin(a)*97.0)
		foam.begin(C_FOAM)
		foam.ring(foot,Vector3.UP,3.2,0.17,28,4)
		foam.ring(foot+radial*1.4,Vector3.UP,5.4,0.11,32,4)
	# 崖顶溪流
	b.begin(C_WATER)
	b.box(Transform3D(Basis.IDENTITY, Vector3(-40.0, SUMMIT_Y + 0.10, 46.0)), Vector3(4.4, 0.06, 12.0), 0.3)
	b.box(Transform3D(Basis.IDENTITY, Vector3(-52.0, SUMMIT_Y + 0.08, -24.0)), Vector3(4.0, 0.06, 34.0), 0.3)
	# 水帘不投影：它贴着崖壁，投影只会在崖面上刷出一条比水帘还宽的黑带
	var wf_mi := _commit(b, "WaterfallMesh")
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var foam_mi := _commit(foam,"WaterfallFoamMesh")
	foam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 台缘灌木与花簇、天梯外侧灯笼。全部为装饰网格，不新增碰撞。
func _build_terrace_details() -> void:
	var b := _new()
	for level in TERRACES:
		var y := float(level[0])
		var rx := float(level[1])
		var rz := float(level[2])
		for i in range(18):
			var a := TAU*(float(i)+0.5)/18.0
			var p := Vector3(cos(a)*(rx-4.0),y+0.30,sin(a)*(rz-3.0))
			if p.x > 0 and absf(p.z) < 14:
				continue
			b.begin(C_STONE_D)
			b.disc(p-Vector3(0,0.16,0),1.25,0.28,8)
			b.begin(C_PINE)
			b.disc(p+Vector3(0,0.30,0),1.12,0.75,8)
			b.begin(C_FLOWER)
			for side in [-1.0,1.0]:
				b.disc(p+Vector3(side*0.53,0.76,0.12),0.34,0.25,6)
		for side in [-1.0,1.0]:
			var p := Vector3(rx-3.0,y,side*11.0)
			b.begin(C_WOOD)
			b.cylinder(p,p+Vector3(0,2.5,0),0.09,6,true)
			b.begin(C_LANTERN)
			b.box(Transform3D(Basis.IDENTITY,p+Vector3(0,2.0,0)),Vector3(0.60,0.72,0.60))
			b.begin(C_TILE_D)
			b.box(Transform3D(Basis.IDENTITY,p+Vector3(0,2.4,0)),Vector3(0.78,0.16,0.78))
	_commit(b,"TerraceDetailsMesh")

# ---------------------------------------------------------------- 索道（游乐设施）

func _build_cablecar() -> void:
	_car = Node3D.new()
	_car.name = "CableCar"
	_root.add_child(_car)
	# 下站放在主岛岸边的空地上，上站放在山巅西北角（避开中轴与广场）
	var a := Vector3(236.0, 0.0, 46.0)
	var b := Vector3(40.0, SUMMIT_Y, -44.0)
	if layer != null and layer.world != null:
		a.y = float(layer.world.call("height_at", a.x + ISLAND_CENTER.x, a.z + ISLAND_CENTER.z))
	a.y = maxf(a.y, SEA_Y + 0.6)
	_car_a = a + Vector3(0, 28.0, 0)
	_car_b = b + Vector3(0, 24.0, 0)
	var tb := _new()
	for pair in [[a, _car_a], [b, _car_b]]:
		var base: Vector3 = pair[0]
		var top: Vector3 = pair[1]
		tb.begin(C_STEEL)
		tb.cylinder(base + Vector3(0, -1.2, 0), top, 1.0, 8, true)
		tb.begin(C_STONE_D)
		tb.box(Transform3D(Basis.IDENTITY, base + Vector3(0, 0.4, 0)), Vector3(6.0, 1.6, 6.0), 0.4)
		tb.begin(C_STEEL)
		tb.box(Transform3D(Basis.IDENTITY, top + Vector3(0, 0.6, 0)), Vector3(3.0, 0.8, 3.0), 0.3)
		for s in [-1.0, 1.0]:
			tb.beam(base + Vector3(0, 6.0, s * 1.2), top + Vector3(0, -1.5, 0), 0.16)
	_commit(tb, "CableTowerMesh")
	var cb := _new()
	cb.begin(C_STEEL)
	for s in [-1.0, 1.0]:
		cb.beam(_car_a + Vector3(0, 0, s * 1.5), _car_b + Vector3(0, 0, s * 1.5), 0.10)
	_commit(cb, "CableMesh")
	for i in range(7):
		var cab := Node3D.new()
		cab.name = "Car%02d" % i
		_car.add_child(cab)
		var mb := _new()
		mb.begin(C_STEEL)
		mb.beam(Vector3(0, 0.9, 0), Vector3(0, 0.1, 0), 0.14)
		mb.begin(C_RED)
		mb.box(Transform3D(Basis.IDENTITY, Vector3(0, -1.1, 0)), Vector3(2.2, 2.4, 2.2), 0.3)
		mb.begin(C_GLASS)
		mb.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0)), Vector3(2.34, 1.1, 2.34), 0.3)
		mb.begin(C_TILE_D)
		mb.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.16, 0)), Vector3(2.6, 0.22, 2.6), 0.3)
		_commit(mb, "CarMesh", cab)
		_cabins.append(cab)

func _process(delta: float) -> void:
	if _car == null or _cabins.is_empty():
		return
	_car_t = fmod(_car_t + delta * 0.055, 1.0)
	for i in range(_cabins.size()):
		var t := fmod(_car_t + float(i) / float(_cabins.size()), 1.0)
		var u := t * 2.0
		if u > 1.0:
			u = 2.0 - u
		var p := _car_a.lerp(_car_b, u)
		p.y -= sin(u * PI) * 2.0
		var cab: Node3D = _cabins[i]
		cab.position = p
		cab.rotation.y = deg_to_rad(sin(t * TAU * 2.0) * 4.0)
