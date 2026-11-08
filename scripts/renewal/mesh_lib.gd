extends RefCounted
## 程序化网格构建器：按材质分组累积三角形，最终每种材质只产生一个 Surface，
## 用于在不增加绘制批次的前提下生成摩天轮、台阶、栏杆等设施几何。

var groups: Dictionary = {}   # mat_key -> { "st": SurfaceTool }
var _current: String = ""

func begin(mat_key: String) -> void:
	_current = mat_key
	if not groups.has(mat_key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[mat_key] = st

func _st() -> SurfaceTool:
	if _current == "":
		begin("default")
	return groups[_current]

func add_tri(a: Vector3, b: Vector3, c: Vector3, uv_scale: float = 1.0) -> void:
	# 注意：调用方按“从外侧看逆时针”给出 a,b,c，此处以 (a,c,b) 写入，
	# 使 Godot 的正面朝向与计算法线一致（盒体/屋面均依赖此约定）。
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var st := _st()
	st.set_normal(n)
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)
	st.set_normal(n)
	st.set_uv(Vector2(b.x, b.z) * uv_scale)
	st.add_vertex(b)

func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale: float = 1.0) -> void:
	add_tri(a, b, c, uv_scale)
	add_tri(a, c, d, uv_scale)

## 轴对齐盒体（可带旋转基），center 为中心，size 为三边长度。
func box(xf: Transform3D, size: Vector3, uv_scale: float = 1.0) -> void:
	var h := size * 0.5
	var p := [
		xf * Vector3(-h.x, -h.y, -h.z), xf * Vector3(h.x, -h.y, -h.z),
		xf * Vector3(h.x, -h.y, h.z), xf * Vector3(-h.x, -h.y, h.z),
		xf * Vector3(-h.x, h.y, -h.z), xf * Vector3(h.x, h.y, -h.z),
		xf * Vector3(h.x, h.y, h.z), xf * Vector3(-h.x, h.y, h.z),
	]
	add_quad(p[0], p[3], p[2], p[1], uv_scale)   # 底
	add_quad(p[4], p[5], p[6], p[7], uv_scale)   # 顶
	add_quad(p[0], p[1], p[5], p[4], uv_scale)   # -Z
	add_quad(p[1], p[2], p[6], p[5], uv_scale)   # +X
	add_quad(p[2], p[3], p[7], p[6], uv_scale)   # +Z
	add_quad(p[3], p[0], p[4], p[7], uv_scale)   # -X

## 两点之间的方截面梁。
func beam(a: Vector3, b: Vector3, thickness: float, up_hint: Vector3 = Vector3.UP, uv_scale: float = 1.0) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var x := up_hint.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var xf := Transform3D(Basis(x, y, z), (a + b) * 0.5)
	box(xf, Vector3(thickness, length, thickness), uv_scale)

## 两点之间的圆柱。
func cylinder(a: Vector3, b: Vector3, radius: float, segments: int = 10, caps: bool = true) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var st := _st()
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var p0 := a + d0 * radius
		var p1 := a + d1 * radius
		var q0 := b + d0 * radius
		var q1 := b + d1 * radius
		var n0 := (p0 - a).normalized()
		var n1 := (p1 - a).normalized()
		st.set_normal(n0); st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_normal(n1); st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_normal(n1); st.set_uv(Vector2(1, 1)); st.add_vertex(q1)
		st.set_normal(n0); st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_normal(n1); st.set_uv(Vector2(1, 1)); st.add_vertex(q1)
		st.set_normal(n0); st.set_uv(Vector2(0, 1)); st.add_vertex(q0)
		if caps:
			var ny := -y
			st.set_normal(ny); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
			st.set_normal(ny); st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
			st.set_normal(ny); st.set_uv(Vector2(0.5, 1)); st.add_vertex(p0)
			st.set_normal(y); st.set_uv(Vector2(0, 0)); st.add_vertex(b)
			st.set_normal(y); st.set_uv(Vector2(0.5, 1)); st.add_vertex(q0)
			st.set_normal(y); st.set_uv(Vector2(1, 0)); st.add_vertex(q1)

## 圆环（轮缘）：平面法线 axis，中心 center，主半径 major，管半径 tube。
func ring(center: Vector3, axis: Vector3, major: float, tube: float, major_segments: int = 96, tube_segments: int = 6) -> void:
	var y := axis.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var st := _st()
	for i in range(major_segments):
		var a0 := TAU * float(i) / float(major_segments)
		var a1 := TAU * float(i + 1) / float(major_segments)
		var c0 := center + (x * cos(a0) + z * sin(a0)) * major
		var c1 := center + (x * cos(a1) + z * sin(a1)) * major
		var rad0 := (c0 - center).normalized()
		var rad1 := (c1 - center).normalized()
		for j in range(tube_segments):
			var b0 := TAU * float(j) / float(tube_segments)
			var b1 := TAU * float(j + 1) / float(tube_segments)
			var n00 := (rad0 * cos(b0) + y * sin(b0)).normalized()
			var n01 := (rad0 * cos(b1) + y * sin(b1)).normalized()
			var n10 := (rad1 * cos(b0) + y * sin(b0)).normalized()
			var n11 := (rad1 * cos(b1) + y * sin(b1)).normalized()
			var p00 := c0 + n00 * tube
			var p01 := c0 + n01 * tube
			var p10 := c1 + n10 * tube
			var p11 := c1 + n11 * tube
			st.set_normal(n00); st.set_uv(Vector2(0, 0)); st.add_vertex(p00)
			st.set_normal(n10); st.set_uv(Vector2(1, 0)); st.add_vertex(p10)
			st.set_normal(n11); st.set_uv(Vector2(1, 1)); st.add_vertex(p11)
			st.set_normal(n00); st.set_uv(Vector2(0, 0)); st.add_vertex(p00)
			st.set_normal(n11); st.set_uv(Vector2(1, 1)); st.add_vertex(p11)
			st.set_normal(n01); st.set_uv(Vector2(0, 1)); st.add_vertex(p01)

## 水平圆盘（平台/基础）。
func disc(center: Vector3, radius: float, thickness: float, segments: int = 24) -> void:
	cylinder(center - Vector3(0, thickness * 0.5, 0), center + Vector3(0, thickness * 0.5, 0), radius, segments, true)

## 四坡/双坡屋面：沿 X 方向的屋脊。
func gable_roof(center: Vector3, width: float, depth: float, height: float, overhang: float = 0.6) -> void:
	var w := width * 0.5 + overhang
	var d := depth * 0.5 + overhang
	var base_y := center.y
	var apex_y := center.y + height
	var p := [
		center + Vector3(-w, 0, -d), center + Vector3(w, 0, -d),
		center + Vector3(w, 0, d), center + Vector3(-w, 0, d),
		center + Vector3(-w, apex_y - base_y, 0), center + Vector3(w, apex_y - base_y, 0),
	]
	add_quad(p[0], p[1], p[5], p[4])   # 北坡
	add_quad(p[3], p[2], p[5], p[4])   # 南坡（反向）
	add_tri(p[0], p[4], p[3])
	add_tri(p[1], p[2], p[5])

## 台阶：沿 dir 方向逐级抬升，返回顶端高度。
func stair_run(start: Vector3, dir: Vector3, steps: int, rise: float, run: float, width: float) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var side := d.cross(Vector3.UP).normalized()
	var p := start
	for i in range(steps):
		var xf := Transform3D(Basis(side, Vector3.UP, d), p + Vector3(0, rise * 0.5, 0) + d * run * 0.5)
		box(xf, Vector3(width, rise, run))
		p += d * run + Vector3(0, rise, 0)

## 合并为 ArrayMesh。
func build(materials: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in groups.keys():
		var st: SurfaceTool = groups[key]
		st.index()
		var tmp: ArrayMesh = st.commit()
		if tmp == null or tmp.get_surface_count() == 0:
			continue
		var arrays := tmp.surface_get_arrays(0)
		var idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if materials.has(key):
			mesh.surface_set_material(idx, materials[key])
	return mesh
