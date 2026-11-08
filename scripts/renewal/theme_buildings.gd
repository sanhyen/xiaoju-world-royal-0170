extends Node
## 20 栋主题建筑重建（0170）
##
## 用原世界自带的构建器 world.b（box / oriented_box / beam / glass / text3d / picture / planter / lamp
## / table / shelf）绘制，因此材质、网格批次、碰撞与原世界同源，风格一致而不另造一套低模。
## 每栋至少改变：主轮廓、入口构图、立面开窗、材质体系，并重建室内主题；原 ID、用途、互动、楼层保留。
##
## 参数：--themes=B05,B09  仅生成指定栋（样板验证）；默认全部 20 栋。

const CONFIG := "res://data/renewal/buildings_0170.json"
const MeshLib = preload("res://scripts/renewal/mesh_lib.gd")

var layer: Node
var enabled_ids: Array = []
var built: Array[String] = []
var container: Node3D
var mb: RefCounted
var bodies: Array = []
var palette_glass := ""
var _door_x := 0.0
var _front_openings: Array[Rect2] = []
const WALL_THICKNESS := 0.50

func setup(p_layer: Node) -> void:
	layer = p_layer
	container = Node3D.new()
	container.name = "RenewalThemeBuildings"
	layer.world.add_child(container)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--themes="):
			enabled_ids = Array(a.substr(9).split(","))

func build() -> void:
	if container == null or layer.world == null:
		return
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		push_error("theme config missing")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for cfg in data["buildings"]:
		var id := str(cfg["id"])
		if enabled_ids.size() > 0 and not enabled_ids.has(id):
			continue
		_draw(cfg)
		built.append(id)
	print("THEMES_BUILT %d: %s" % [built.size(), ", ".join(built)])

# ---------------------------------------------------------------- 基础绘制
# 使用自有 MeshLib（与摩天轮同源）：颜色 hex 即材质分组键，最后合并为一个 ArrayMesh，
# 每种材质一个 surface；碰撞单独按 solid 标记生成 StaticBody3D。

func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _key(col: String, transparent: bool = false) -> String:
	return ("G_" if transparent else "C_") + col

func _box(pos: Vector3, size: Vector3, col: String, solid: bool = false, kind: String = "wall") -> void:
	mb.begin(_key(col, kind == "glass"))
	mb.box(Transform3D(Basis.IDENTITY, pos), size)
func _beam(a: Vector3, c: Vector3, width: float, col: String, solid: bool = false) -> void:
	mb.begin(_key(col))
	mb.beam(a, c, width)

func _glass(pos: Vector3, size: Vector3) -> void:
	mb.begin(_key(palette_glass, true))
	mb.box(Transform3D(Basis.IDENTITY, pos), size)

func _slab(pos: Vector3, size: Vector3, col: String, angle: float, solid: bool = false) -> void:
	var rot := Transform3D(Basis(Vector3(1, 0, 0), angle), pos)
	mb.begin(_key(col))
	mb.box(rot, size)
	# 瓦垄：沿坡向排布的细条，给屋面加出瓦片的节奏。
	# 原来屋面是一整块纯色平板，远看像塑料片；加了垄之后屋面才有「瓦」的读感。
	var span: float = size.x
	var n: int = int(maxf(3.0, floor(span / 0.55)))
	var w: float = span / float(n)
	mb.begin(_key(col))
	for i in range(n):
		var lx := -span * 0.5 + w * (float(i) + 0.5)
		var bar := Transform3D(rot.basis, rot.origin + rot.basis * Vector3(lx, size.y * 0.5 + 0.035, 0.0))
		mb.box(bar, Vector3(w * 0.32, 0.07, size.z * 0.97))
	# 檐口压边：坡面两端各加一条横向凸起，收住瓦垄末端
	mb.begin(_key(col))
	for sz in [-1.0, 1.0]:
		var lip := Transform3D(rot.basis, rot.origin + rot.basis * Vector3(0.0, size.y * 0.5 + 0.05, float(sz) * size.z * 0.49))
		mb.box(lip, Vector3(size.x, 0.09, size.z * 0.045))
func _text(words: String, pos: Vector3, size: float, col: String) -> void:
	var l := Label3D.new()
	l.text = words
	l.font_size = 48
	l.pixel_size = 0.006
	l.modulate = Color.from_string("#" + col, Color.WHITE)
	l.outline_size = 6
	l.outline_modulate = Color(0.1, 0.1, 0.1)
	l.position = pos
	l.rotation = Vector3(0, PI, 0)
	l.visibility_range_end = 180.0
	container.add_child(l)

## 半圆拱（XY 平面，底边在 y=0）
func _arch(c: Vector3, r: float, width: float, col: String, segs: int = 9) -> void:
	for i in range(segs):
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, 0)
		_beam(p0, p1, width, col, false)

## 尖拱（哥特）：两段直线交于尖顶
func _pointed(c: Vector3, r: float, h: float, width: float, col: String) -> void:
	_beam(c + Vector3(-r, 0, 0), c + Vector3(0, h, 0), width, col, false)
	_beam(c + Vector3(0, h, 0), c + Vector3(r, 0, 0), width, col, false)

## 穹顶 / 圆塔：逐层收分的环带
func _dome_band(c: Vector3, r: float, y: float, col: String, segs: int = 12, thick: float = 0.45) -> void:
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := c + Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, y, sin(a1) * r)
		_beam(p0, p1, thick, col, false)

# ---------------------------------------------------------------- 通用构件

func _walls(base: Vector3, w: float, d: float, h: float, P: Dictionary, door_x: float) -> void:
	var wall := str(P["wall"])
	var t := WALL_THICKNESS
	_box(base + Vector3(-w * 0.5, h * 0.5, 0), Vector3(t, h, d), wall, true)
	_box(base + Vector3(w * 0.5, h * 0.5, 0), Vector3(t, h, d), wall, true)
	_box(base + Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, t), wall, true)
	# 依门窗开口的边界拆分实体墙段。窗框放在墙洞内侧，留下可见侧壁。
	var dx := clampf(door_x - base.x, -w * 0.5 + 3.0, w * 0.5 - 3.0)
	var facade := Rect2(-w * .5, 0, w, h)
	_front_openings.append(Rect2(dx - 2.5, 0, 5.0, 3.4))
	var xs: Array[float] = [facade.position.x, facade.end.x]
	var ys: Array[float] = [0.0, h]
	for i in range(_front_openings.size()):
		var opening := _front_openings[i].intersection(facade)
		_front_openings[i] = opening
		if opening.has_area():
			xs.append(opening.position.x)
			xs.append(opening.end.x)
			ys.append(opening.position.y)
			ys.append(opening.end.y)
	xs.sort()
	ys.sort()
	for i in range(xs.size()-1):
		for j in range(ys.size()-1):
			var size := Vector2(xs[i+1]-xs[i], ys[j+1]-ys[j])
			if size.x < .005 or size.y < .005:
				continue
			var mid := Vector2(xs[i],ys[j]) + size*.5
			var is_open := false
			for opening in _front_openings:
				if opening.has_point(mid):
					is_open = true
					break
			if not is_open:
				_box(base+Vector3(mid.x,mid.y,d*.5),Vector3(size.x,size.y,t),wall,true)
	# 墙裙沿侧墙与背墙连续，正面保留门洞。
	for side in [-1.0,1.0]:
		_box(base+Vector3(side*w*0.5,0.4,0),Vector3(0.46,0.8,d),str(P["frame"]))
	_box(base+Vector3(0,0.4,-d*0.5),Vector3(w,0.8,0.46),str(P["frame"]))

## 立面开窗：style 决定窗型，是 20 栋差异化的四项之一
func _windows(base: Vector3, w: float, d: float, h: float, P: Dictionary, style: String) -> void:
	var frame := str(P["frame"])
	var glass := str(P["glass"])
	var fy := base.y
	var n := maxi(2, int(w / 4.0))
	for i in range(n):
		var x := base.x - w * 0.5 + w * (float(i) + 0.5) / float(n)
		var z := base.z + d * 0.5 - 0.11
		var cy := fy + h * 0.55
		var dimensions := Vector2(1.6,1.8)
		match style:
			"grid": dimensions = Vector2(2.4,2.2)
			"lattice": dimensions = Vector2(1.8,1.8)
			"tall": dimensions = Vector2(0.7,3.2)
			"ribbon":
				dimensions = Vector2(3.0,0.8)
				cy = fy+h*0.7
			"round": dimensions = Vector2(2.0,2.0)
			"pointed": dimensions = Vector2(1.5,2.6)
		# 低窗不能横跨原入口。
		if absf(x-_door_x) < 2.5+dimensions.x*0.5 and cy-dimensions.y*0.5 < fy+3.4:
			continue
		_front_openings.append(Rect2(x-base.x-dimensions.x*.5,cy-fy-dimensions.y*.5,dimensions.x,dimensions.y))
		if style not in ["round","pointed"]:
			for side in [-1.0,1.0]:
				_box(Vector3(x+side*(dimensions.x*0.5+0.06),cy,z+0.06),Vector3(0.14,dimensions.y+0.28,0.20),frame)
				_box(Vector3(x,cy+side*(dimensions.y*0.5+0.06),z+0.06),Vector3(dimensions.x+0.28,0.14,0.20),frame)
		_box(Vector3(x,cy-dimensions.y*0.5-0.08,z+0.19),Vector3(dimensions.x+0.32,0.16,0.57),frame)
		match style:
			"round":
				_box(Vector3(x, cy, z), Vector3(2.0, 2.0, 0.12), glass, false, "glass")
				_arch(Vector3(x, cy - 0.2, z + 0.06), 1.05, 0.14, frame)
				_box(Vector3(x, cy - 1.05, z + 0.04), Vector3(2.2, 0.16, 0.16), frame)
			"pointed":
				_box(Vector3(x, cy, z), Vector3(1.5, 2.6, 0.12), glass, false, "glass")
				_pointed(Vector3(x, cy - 0.9, z + 0.06), 0.85, 2.1, 0.16, frame)
			"tall":
				_box(Vector3(x, cy, z), Vector3(0.7, 3.2, 0.12), glass, false, "glass")
				_box(Vector3(x, cy, z + 0.06), Vector3(0.12, 3.3, 0.16), frame)
			"grid":
				_box(Vector3(x, cy, z), Vector3(2.4, 2.2, 0.1), glass, false, "glass")
				for k in range(3):
					_box(Vector3(x - 0.8 + k * 0.8, cy, z + 0.06), Vector3(0.09, 2.2, 0.14), frame)
				_box(Vector3(x, cy, z + 0.06), Vector3(2.4, 0.09, 0.14), frame)
			"ribbon":
				_box(Vector3(x, fy + h * 0.7, z), Vector3(3.0, 0.8, 0.12), glass, false, "glass")
			"lattice":
				_box(Vector3(x, cy, z), Vector3(1.8, 1.8, 0.1), glass, false, "glass")
				for k in range(-1, 2):
					_box(Vector3(x + k * 0.55, cy, z + 0.06), Vector3(0.08, 1.8, 0.14), frame)
					_box(Vector3(x, cy + k * 0.55, z + 0.06), Vector3(1.8, 0.08, 0.14), frame)
			_:
				_box(Vector3(x, cy, z), Vector3(1.6, 1.8, 0.12), glass, false, "glass")

## 入口构图：style 决定门廊/挑檐/柱式
func _portico(base: Vector3, w: float, d: float, h: float, P: Dictionary, style: String, door_x: float) -> void:
	var frame := str(P["frame"])
	var accent := str(P["accent"])
	var roof := str(P["roof"])
	var dx := clampf(door_x - base.x, -w * 0.4, w * 0.4)
	var p := base + Vector3(dx, 0, d * 0.5)
	match style:
		"colonnade":
			for i in range(5):
				var x := base.x - w * 0.4 + w * 0.8 * float(i) / 4.0
				_box(Vector3(x, base.y + 1.7, p.z + 2.6), Vector3(0.4, 3.4, 0.4), frame, true)
			_box(Vector3(base.x, base.y + 3.5, p.z + 2.0), Vector3(w * 0.85, 0.35, 5.2), roof)
		"arched":
			_arch(p + Vector3(0, 1.6, 0.5), 1.9, 0.4, frame)
			_box(p + Vector3(-1.9, 0.8, 0.5), Vector3(0.45, 1.6, 0.45), frame, true)
			_box(p + Vector3(1.9, 0.8, 0.5), Vector3(0.45, 1.6, 0.45), frame, true)
			_box(p + Vector3(0, 3.5, 1.6), Vector3(4.6, 0.3, 3.4), accent)
		"canopy":
			_box(p + Vector3(0, 3.3, 1.3), Vector3(6.0, 0.28, 2.8), roof)
			for s in [-1.0, 1.0]:
				_box(p + Vector3(s * 2.7, 1.6, 2.4), Vector3(0.22, 3.2, 0.22), accent, true)
		"gable":
			_box(p + Vector3(0, 3.6, 1.6), Vector3(5.4, 0.3, 3.6), roof)
			_beam(p + Vector3(-2.7, 3.6, 1.6), p + Vector3(0, 4.8, 1.6), 0.22, frame)
			_beam(p + Vector3(0, 4.8, 1.6), p + Vector3(2.7, 3.6, 1.6), 0.22, frame)
		"steps":
			for i in range(4):
				_box(p + Vector3(0, 0.12 * float(i), 1.0 + float(i) * 0.6), Vector3(5.0, 0.24, 1.0), frame, true)
		_:
			_box(p + Vector3(0, 3.2, 0.9), Vector3(4.6, 0.28, 2.0), accent)

## 室内主题：在原互动位置附近重建主题陈设，不覆盖原互动数据
func _interior(base: Vector3, w: float, d: float, h: float, P: Dictionary, kind: String) -> void:
	var accent := str(P["accent"])
	var frame := str(P["frame"])
	var wall := str(P["wall"])
	var y := base.y
	match kind:
		"cafe_bar", "bakery", "darkroom", "souvenir", "teahouse":
			_box(Vector3(base.x - w * 0.22, y + 0.6, base.z - d * 0.1), Vector3(w * 0.42, 1.2, 1.4), frame, true)
			for i in range(3):
				_box(Vector3(base.x + w * 0.12, y + 0.45, base.z - d * 0.25 + i * 1.8), Vector3(1.2, 0.9, 1.0), accent)
		"gallery", "herbarium", "record_wall", "workshop", "kiln", "atelier":
			for i in range(4):
				_box(Vector3(base.x - w * 0.32 + i * (w * 0.2), y + 1.5, base.z - d * 0.34), Vector3(1.6, 2.2, 0.22), wall)
				_box(Vector3(base.x - w * 0.32 + i * (w * 0.2), y + 1.5, base.z - d * 0.34 + 0.14), Vector3(1.2, 1.6, 0.1), accent)
		"cinema", "theatre", "musicbox", "studio":
			for i in range(4):
				for j in range(2):
					_box(Vector3(base.x - w * 0.28 + i * 2.0, y + 0.45, base.z - d * 0.28 + j * 1.6), Vector3(1.5, 0.9, 1.0), accent)
			_box(Vector3(base.x, y + 0.5, base.z + d * 0.3), Vector3(w * 0.6, 1.0, 1.2), frame, true)
		"fireplace":
			_box(Vector3(base.x - w * 0.3, y + 1.1, base.z - d * 0.3), Vector3(2.2, 2.2, 1.0), frame, true)
			_box(Vector3(base.x - w * 0.3, y + 1.0, base.z - d * 0.3 + 0.55), Vector3(1.2, 1.2, 0.1), accent)
		"belvedere", "telescope", "flower_beds":
			for i in range(5):
				_box(Vector3(base.x - w * 0.36 + i * (w * 0.18), y + 0.45, base.z + d * 0.22), Vector3(1.4, 0.9, 1.2), accent)
		_:
			_box(Vector3(base.x, y + 0.6, base.z - d * 0.18), Vector3(w * 0.3, 1.2, 1.4), frame, true)

# ---------------------------------------------------------------- 主轮廓

func _gable(base: Vector3, w: float, d: float, h: float, rise: float, P: Dictionary, upturned: bool = false) -> void:
	var roof := str(P["roof"])
	var frame := str(P["frame"])
	var slope := atan2(rise, d * 0.5)
	var span := (d * 0.5) / cos(slope) + 0.6
	_slab(base + Vector3(0, h + rise * 0.5, -d * 0.25), Vector3(w + 2.8, 0.34, span + 1.2), roof, slope)
	_slab(base + Vector3(0, h + rise * 0.5, d * 0.25), Vector3(w + 2.8, 0.34, span + 1.2), roof, -slope)
	_box(base + Vector3(0, h + rise, 0), Vector3(w + 1.4, 0.24, 0.4), frame)
	if upturned:
		for sx in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var corner := base+Vector3(sx*(w*0.5+1.2),h-0.5,sz*(d*0.5+0.6))
				for i in range(4):
					var t0 := float(i)/4.0
					var t1 := float(i+1)/4.0
					var a := corner+Vector3(sx*1.1*t0,0.75*t0*t0,sz*0.65*t0)
					var b := corner+Vector3(sx*1.1*t1,0.75*t1*t1,sz*0.65*t1)
					_beam(a,b,0.18,roof)

func _flat(base: Vector3, w: float, d: float, h: float, P: Dictionary) -> void:
	var roof := str(P["roof"])
	var frame := str(P["frame"])
	_box(base + Vector3(0, h + 0.15, 0), Vector3(w + 2.6, 0.34, d + 2.6), roof)
	for s in [-1.0, 1.0]:
		_box(base + Vector3(s * w * 0.5, h + 0.7, 0), Vector3(0.3, 1.1, d + 2.6), frame)
		_box(base + Vector3(0, h + 0.7, s * d * 0.5), Vector3(w + 2.6, 1.1, 0.3), frame)

func _saw(base: Vector3, w: float, d: float, h: float, P: Dictionary, count: int) -> void:
	var roof := str(P["roof"])
	var glass := str(P["glass"])
	var step := d / float(count)
	for i in range(count):
		# 相对偏移（不能带 base.z，否则与 base 相加会翻倍）
		var dz := -d * 0.5 + step * (float(i) + 0.5)
		_slab(base + Vector3(0, h + 0.6, dz - step * 0.25), Vector3(w, 0.22, step * 1.05), roof, 0.42)
		_box(base + Vector3(0, h + 0.35, dz + step * 0.34), Vector3(w * 0.92, 0.9, 0.12), glass, false, "glass")

func _spire(base: Vector3, h: float, r: float, P: Dictionary, levels: int = 7) -> void:
	var roof := str(P["roof"])
	var accent := str(P["accent"])
	# 实体塔身，保证远景可辨
	_box(base + Vector3(0, h * 0.5, 0), Vector3(r * 1.7, h, r * 1.7), roof, false)
	for i in range(levels):
		var t := float(i) / float(levels)
		var rr := r * (1.0 - t * 0.86)
		_dome_band(base, rr, h + t * r * 2.6, roof, 8, 0.6)
	_box(base + Vector3(0, h + r * 2.6, 0), Vector3(0.5, 1.8, 0.5), accent)

func _dome(base: Vector3, h: float, r: float, P: Dictionary) -> void:
	var roof := str(P["roof"])
	var accent := str(P["accent"])
	for i in range(6):
		var t := float(i) / 6.0
		var rr := r * sqrt(maxf(0.05, 1.0 - t * t))
		_dome_band(base, rr, h + t * r * 0.85, roof, 14)
	_box(base + Vector3(0, h + r * 0.9, 0), Vector3(0.4, 1.2, 0.4), accent)

# ---------------------------------------------------------------- 逐栋绘制

func _draw(cfg: Dictionary) -> void:
	var id := str(cfg["id"])
	var c := _v(cfg["center"])
	var w := float(cfg["w"]); var d := float(cfg["d"]); var h := float(cfg["h"])
	var fy := float(cfg["floor_y"])
	var P: Dictionary = cfg["palette"]
	var arch := str(cfg["archetype"])
	mb = MeshLib.new()
	bodies = []
	palette_glass = str(P["glass"])
	var root := Node3D.new()
	root.name = "Theme_" + id
	container.add_child(root)
	# 外壳外扩 1.4m、抬高 0.6m，把原建筑整体罩住：主轮廓由新屋顶决定，
	# 正面做深门廊，玩家穿过门廊进入原入口，原楼面与互动完全保留。
	w += 2.8
	d += 2.8
	h += 2.0
	var base := Vector3(c.x, fy, c.z)
	var door_x := c.x
	if cfg.get("door") != null:
		door_x = float(cfg["door"][0])
	_door_x = door_x
	var wall := str(P["wall"]); var roof := str(P["roof"])
	var frame := str(P["frame"]); var accent := str(P["accent"]); var glass := str(P["glass"])

	# 楼板（提供可站立碰撞）
	_box(base + Vector3(0, 0.06, 0), Vector3(w - 0.5, 0.24, d - 0.5), frame, true, "floor")
	_front_openings.clear()

	match arch:
		"arcade":
			_flat(base + Vector3(0, -1.0, 0), w, d, h - 1.0, P)
			for i in range(6):
				var x := base.x - w * 0.42 + w * 0.84 * float(i) / 5.0
				_box(Vector3(x, fy + 1.6, base.z + d * 0.5 + 2.2), Vector3(0.42, 3.2, 0.42), wall, true)
				_arch(Vector3(x + w * 0.084, fy + 3.2, base.z + d * 0.5 + 2.2), w * 0.084, 0.22, accent, 6)
			_box(Vector3(base.x, fy + 3.6, base.z + d * 0.5 + 1.6), Vector3(w * 0.95, 0.32, 5.0), roof)
			_windows(base, w, d, h, P, "round")
			_portico(base, w, d, h, P, "canopy", door_x)
		"jazz":
			_saw(base, w, d, h, P, 3)
			for i in range(7):
				_box(Vector3(base.x - w * 0.44 + i * (w * 0.145), fy + h * 0.55, base.z + d * 0.5 + 0.16), Vector3(0.18, h * 0.8, 0.18), accent)
			_arch(Vector3(door_x, fy + 1.9, base.z + d * 0.5 + 0.4), 2.1, 0.35, frame)
			_windows(base, w, d, h, P, "ribbon")
			_portico(base, w, d, h, P, "canopy", door_x)
		"greenhouse":
			for i in range(4):
				var z := base.z - d * 0.4 + i * (d * 0.27)
				_box(Vector3(base.x, fy + h + 0.9, z), Vector3(w * 0.9, 0.12, d * 0.3), glass, false, "glass")
			_slab(base + Vector3(-w * 0.25, h + 1.3, 0), Vector3(w * 0.6, 0.2, d + 1.0), frame, 0.5)
			_slab(base + Vector3(w * 0.25, h + 1.3, 0), Vector3(w * 0.6, 0.2, d + 1.0), frame, -0.5)
			for i in range(5):
				_box(Vector3(base.x - w * 0.4 + i * (w * 0.2), fy + h * 0.6, base.z + d * 0.5 + 0.2), Vector3(0.16, h, 0.16), frame)
			_windows(base, w, d, h, P, "grid")
			_portico(base, w, d, h, P, "arched", door_x)
		"gothic":
			var th := h * 1.55
			_pointed(base + Vector3(0, h, d * 0.5 + 0.3), w * 0.42, th - h, 0.5, roof)
			_spire(base + Vector3(-w * 0.34, 0, 0), h, 2.4, P, 6)
			_spire(base + Vector3(w * 0.34, 0, 0), h, 2.4, P, 6)
			for i in range(4):
				_box(Vector3(base.x - w * 0.45 + i * (w * 0.3), fy + h * 0.6, base.z + d * 0.5 + 0.8), Vector3(0.8, h * 1.2, 1.6), wall, true)
			_windows(base, w, d, h, P, "pointed")
			_portico(base, w, d, h, P, "arched", door_x)
		"artdeco":
			for i in range(3):
				var s := 1.0 - float(i) * 0.22
				_box(base + Vector3(0, h + 0.5 + float(i) * 1.5, 0), Vector3(w * s, 1.5, d * s), wall)
				_box(base + Vector3(0, h + 1.3 + float(i) * 1.5, 0), Vector3(w * s + 0.5, 0.24, d * s + 0.5), accent)
			for i in range(9):
				_box(Vector3(base.x - w * 0.42 + i * (w * 0.105), fy + h * 0.6, base.z + d * 0.5 + 0.2), Vector3(0.16, h * 0.9, 0.18), accent)
			_windows(base, w, d, h, P, "tall")
			_portico(base, w, d, h, P, "canopy", door_x)
		"folded":
			_saw(base, w, d, h, P, 5)
			for i in range(6):
				_box(Vector3(base.x - w * 0.42 + i * (w * 0.17), fy + h * 0.55, base.z - d * 0.5 - 0.2), Vector3(0.2, h * 0.9, 0.2), frame)
			_windows(base, w, d, h, P, "ribbon")
			_portico(base, w, d, h, P, "canopy", door_x)
		"guitar":
			_box(base + Vector3(-w * 0.18, h * 0.72, 0), Vector3(w * 0.52, h * 0.55, d * 0.82), wall, true)
			_box(base + Vector3(w * 0.24, h * 0.58, 0), Vector3(w * 0.42, h * 0.42, d * 0.68), wall, true)
			_flat(base, w, d, h, P)
			for i in range(5):
				_beam(base + Vector3(-w * 0.42, 0.5 + i * 0.7, d * 0.5 + 0.3),
					  base + Vector3(w * 0.42, 0.5 + i * 0.7, d * 0.5 + 0.3), 0.06, accent)
			_windows(base, w, d, h, P, "round")
			_portico(base, w, d, h, P, "arched", door_x)
		"baroque":
			_dome(base + Vector3(0, h, 0), 0.0, w * 0.36, P)
			for i in range(6):
				var x := base.x - w * 0.42 + i * (w * 0.168)
				_box(Vector3(x, fy + h * 0.55, base.z + d * 0.5 + 0.7), Vector3(0.55, h * 1.05, 0.55), wall, true)
			_arch(Vector3(door_x, fy + 2.0, base.z + d * 0.5 + 1.2), 2.6, 0.5, accent)
			_windows(base, w, d, h, P, "round")
			_portico(base, w, d, h, P, "colonnade", door_x)
		"jiangnan":
			_gable(base, w, d, h, 1.7, P, true)
			_box(base + Vector3(0, h * 0.6, d * 0.5 + 0.8), Vector3(w * 0.9, 0.24, 2.0), frame)
			for i in range(4):
				_box(Vector3(base.x - w * 0.36 + i * (w * 0.24), fy + h * 0.3, base.z + d * 0.5 + 1.7), Vector3(0.2, h * 0.6, 0.2), frame, true)
			for s in [-1.0, 1.0]:
				_box(base + Vector3(s * w * 0.5, h + 0.9, 0), Vector3(0.5, 1.8, d + 0.8), wall)
			_windows(base, w, d, h, P, "lattice")
			_portico(base, w, d, h, P, "gable", door_x)
		"tudor":
			_gable(base, w, d, h, 3.2, P)
			for i in range(4):
				var x := base.x - w * 0.4 + i * (w * 0.26)
				_box(Vector3(x, fy + h * 0.5, base.z + d * 0.5 + 0.22), Vector3(0.28, h, 0.3), frame)
				# x 已是绝对坐标，不能再加 base.x
				_beam(Vector3(x - w * 0.13, fy + 0.3, base.z + d * 0.5 + 0.24),
					  Vector3(x + w * 0.13, fy + h * 0.75, base.z + d * 0.5 + 0.24), 0.22, frame)
			_box(base + Vector3(w * 0.3, h + 2.6, -d * 0.2), Vector3(1.2, 3.4, 1.2), accent, true)
			_windows(base, w, d, h, P, "lattice")
			_portico(base, w, d, h, P, "gable", door_x)
		"nordic":
			_slab(base + Vector3(0, h + 1.5, 0), Vector3(w + 1.0, 0.3, d + 1.0), roof, -0.42)
			_box(base + Vector3(-w * 0.3, h + 2.4, -d * 0.15), Vector3(w * 0.35, 1.8, d * 0.6), glass, false, "glass")
			for i in range(5):
				_box(Vector3(base.x - w * 0.4 + i * (w * 0.2), fy + h * 0.55, base.z + d * 0.5 + 0.2), Vector3(0.18, h, 0.2), frame)
			_windows(base, w, d, h, P, "tall")
			_portico(base, w, d, h, P, "gable", door_x)
		"alpine":
			_gable(base, w * 0.94, d, h, 2.0, P)
			_box(base + Vector3(0, h + 0.3, d * 0.5 + 1.4), Vector3(w + 2.6, 0.3, 3.6), roof)
			for i in range(7):
				_box(Vector3(base.x - w * 0.44 + i * (w * 0.146), fy + h * 0.42, base.z + d * 0.5 + 2.4), Vector3(0.22, 1.0, 0.22), frame)
			_box(base + Vector3(0, 0.35, 0), Vector3(w + 0.6, 0.7, d + 0.6), frame, true, "stone")
			_windows(base, w, d, h, P, "grid")
			_portico(base, w, d, h, P, "steps", door_x)
		"research":
			_slab(base + Vector3(-w * 0.22, h + 0.9, 0), Vector3(w * 0.62, 0.22, d + 1.0), glass, 0.55)
			_flat(base + Vector3(w * 0.28, 0, 0), w * 0.42, d, h, P)
			_box(base + Vector3(0, 1.0, d * 0.5 + 2.2), Vector3(w * 0.9, 0.24, 4.0), frame, true)
			for i in range(5):
				_box(Vector3(base.x - w * 0.4 + i * (w * 0.2), fy + 1.7, base.z + d * 0.5 + 4.0), Vector3(0.16, 1.4, 0.16), frame)
			_windows(base, w, d, h, P, "grid")
			_portico(base, w, d, h, P, "canopy", door_x)
		"toytheatre":
			_dome(base + Vector3(-w * 0.3, h, 0), 0.0, 2.6, P)
			_flat(base + Vector3(w * 0.2, 0, 0), w * 0.5, d, h, P)
			for i in range(3):
				_dome_band(base + Vector3(w * 0.26, 0, d * 0.5 + 0.3), 0.9 + float(i) * 0.35, 1.2 + float(i) * 0.9, accent, 10)
			_windows(base, w, d, h, P, "round")
			_portico(base, w, d, h, P, "arched", door_x)
		"brick":
			_saw(base, w, d, h, P, 4)
			_box(base + Vector3(0, 0.4, 0), Vector3(w + 0.4, 0.8, d + 0.4), frame, true, "stone")
			_box(base + Vector3(door_x - base.x, 1.7, d * 0.5 + 1.0), Vector3(3.6, 3.4, 2.0), glass, false, "glass")
			_windows(base, w, d, h, P, "grid")
			_portico(base, w, d, h, P, "canopy", door_x)
		"cliff":
			for i in range(3):
				var s := 1.0 - float(i) * 0.18
				_box(base + Vector3(0, 0.6 + float(i) * 1.5, 0), Vector3(w * s, 1.5, d * s), wall, true)
				_box(base + Vector3(0, 1.4 + float(i) * 1.5, 0), Vector3(w * s + 0.4, 0.22, d * s + 0.4), accent)
			_box(base + Vector3(w * 0.32, h + 2.0, -d * 0.25), Vector3(1.4, 3.2, 1.4), frame, true)
			_windows(base, w, d, h, P, "lattice")
			_portico(base, w, d, h, P, "steps", door_x)
		"courtyard":
			_gable(base, w, d, h, 1.5, P, true)
			_box(base + Vector3(0, 1.0, d * 0.5 + 3.0), Vector3(w * 0.8, 0.3, 6.0), frame, true)
			for s in [-1.0, 1.0]:
				_box(base + Vector3(s * w * 0.36, 1.8, d * 0.5 + 3.0), Vector3(0.3, 1.6, 6.0), wall)
			_windows(base, w, d, h, P, "lattice")
			_portico(base, w, d, h, P, "gable", door_x)
		"terrace":
			for i in range(2):
				_box(base + Vector3(0, 0.4 + float(i) * 2.0, d * 0.5 + float(i) * 3.0), Vector3(w + float(i) * 1.5, 0.3, 4.0), frame, true)
			for i in range(5):
				_arch(base + Vector3(-w * 0.4 + i * (w * 0.2), 4.2, d * 0.5 + 0.4), w * 0.1, 0.24, wall)
			_windows(base, w, d, h, P, "round")
			_portico(base, w, d, h, P, "colonnade", door_x)
		"tang":
			_gable(base, w, d, h, 1.4, P, true)
			_box(base + Vector3(0, h + 0.25, 0), Vector3(w + 4.0, 0.35, d + 4.0), roof)
			for s in [-1.0, 1.0]:
				for t in [-1.0, 1.0]:
					_box(base + Vector3(s * (w * 0.5 + 1.4), h * 0.5, t * (d * 0.5 + 1.4)), Vector3(0.5, h, 0.5), frame, true)
			_box(base + Vector3(0, 0.25, 0), Vector3(w + 5.0, 0.5, d + 5.0), frame, true, "stone")
			_windows(base, w, d, h, P, "lattice")
			_portico(base, w, d, h, P, "colonnade", door_x)
		"observatory":
			_box(base + Vector3(0, 1.0, 0), Vector3(w + 2.0, 2.0, d + 2.0), frame, true, "stone")
			var tower_h := h * 1.8
			_box(base + Vector3(0, tower_h * 0.5, 0), Vector3(w * 0.52, tower_h, d * 0.52), wall, true)
			for i in range(5):
				_dome_band(base, w * 0.42 + 0.6, tower_h - 1.0 + float(i) * 0.25, accent, 14)
			_dome(base + Vector3(0, tower_h, 0), 0.0, 3.4, P)
			for i in range(4):
				_box(Vector3(base.x - w * 0.18 + i * (w * 0.12), fy + tower_h * 0.6, base.z + d * 0.26 + 0.2), Vector3(0.5, tower_h * 0.5, 0.12), glass, false, "glass")
			_windows(base, w, d, h, P, "tall")
			_portico(base, w, d, h, P, "steps", door_x)
		_:
			_gable(base, w, d, h, 1.6, P)
			_windows(base, w, d, h, P, "grid")

	_interior(base, w, d, h, P, str(cfg["interior"]))
	_text(id, base + Vector3(0, 3.4, d * 0.5 + 0.45), 0.14, accent)
	_walls(base, w, d, h, P, door_x)
	_commit(root, id)

func _commit(root: Node3D, id: String) -> void:
	var mats := {}
	var keys: Array = mb.groups.keys()
	for k in keys:
		var hex := str(k).substr(2)
		var m := StandardMaterial3D.new()
		var col := Color.from_string("#" + hex, Color(0.8, 0.8, 0.8))
		if str(k).begins_with("G_"):
			col.a = 0.32
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.1
		else:
			m.roughness = 0.88
		m.albedo_color = col
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats[k] = m
	var mesh: ArrayMesh = mb.build(mats)
	var mi := MeshInstance3D.new()
	mi.name = "Facade_" + id
	mi.mesh = mesh
	mi.visibility_range_end = 340.0
	mi.visibility_range_end_margin = 25.0
	root.add_child(mi)
	# 合并碰撞：每栋一个 StaticBody，多个 BoxShape
	# 不生成新碰撞：原建筑的墙、楼板、楼梯碰撞完整保留，玩家仍按原路线行走。
	# 新外壳只承担视觉，避免出现「看得见的门 / 走不通的墙」或双层夹缝。
