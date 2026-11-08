extends Node
## 原建筑可见网格隐藏（0170）
##
## 20 栋新主题外壳由 theme_buildings.gd 用原版构建器绘制。为避免「两套屋顶叠在一起」，
## 这里按登记占地 + 地坪高度，把落在建筑体内的原可见网格设为不可见。
##
## 重要取舍：只隐藏视觉，不动任何 StaticBody3D / CollisionShape3D。
## 原因是原建筑的楼板、楼梯、上层可达面与互动体都挂在这些碰撞上；保留它们才能满足
## 「保留原楼面与互动可达」。代价是局部可能残留不可见的小凸起，已在验收报告中说明。
##
## 地形、道路、桥、水体、屏幕/个人媒体一律排除，不参与隐藏。
## 流式区块卸载后会重新实例化节点，因此在 load_events 变化时重新应用（仅玩家附近）。

const CONFIG := "res://data/renewal/buildings_0170.json"
const SiteClear = preload("res://scripts/renewal/site_clear.gd")

var layer: Node
var enabled_ids: Array = []
var records: Array = []
var hidden_total := 0
var _last_events := -1
var _last_pos := Vector3(9999, 0, 0)
var _tick := 0
var do_clear := true
var do_hide := true

const EXCLUDE := ["terrain", "far", "strata", "road", "path", "water", "bridge", "ground",
	"screen", "media", "poster", "picture", "frame", "theme_", "sign", "plaque", "plaza",
	"shore", "ocean", "river", "deck", "pier", "lamp", "tree", "bench"]

func setup(p_layer: Node) -> void:
	layer = p_layer
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--themes="):
			enabled_ids = Array(a.substr(9).split(","))
		elif a == "--noclear":
			do_clear = false
		elif a == "--nohide":
			do_hide = false
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for cfg in data["buildings"]:
		var id := str(cfg["id"])
		if enabled_ids.size() > 0 and not enabled_ids.has(id):
			continue
		records.append({
			"id": id,
			"c": Vector3(float(cfg["center"][0]), float(cfg["floor_y"]), float(cfg["center"][2])),
			"w": float(cfg["w"]), "d": float(cfg["d"]), "h": float(cfg["h"]),
		})

func _excluded(name: String) -> bool:
	var low := name.to_lower()
	for k in EXCLUDE:
		if low.contains(k):
			return true
	return false

func _inside(gp: Vector3, size: Vector3, r: Dictionary) -> bool:
	var c: Vector3 = r["c"]
	var w: float = r["w"]
	var d: float = r["d"]
	var h: float = r["h"]
	if absf(gp.x - c.x) > w * 0.5 + 1.0 or absf(gp.z - c.z) > d * 0.5 + 1.0:
		return false
	if gp.y < c.y - 0.35 or gp.y > c.y + h + 14.0:
		return false
	# 地形/道路等超长构件
	if size.x > 80.0 or size.y > 45.0 or size.z > 80.0:
		return false
	# 门前地面铺装保留
	if size.y < 0.3 and gp.y < c.y + 0.45:
		return false
	return true

func apply() -> void:
	if layer == null or layer.world == null or records.size() == 0:
		return
	var pp: Vector3 = (layer.player as CharacterBody3D).global_position
	var active: Array = []
	for r in records:
		var c: Vector3 = r["c"]
		if Vector2(pp.x - c.x, pp.z - c.z).length() <= 340.0:
			active.append(r)
	if active.size() == 0:
		return
	if do_hide:
		_walk(layer.world, active)
	# 远景合并网格（屋顶/柱廊/装饰）按实例位置剔除
	var rects: Array = []
	for r in active:
		var c3: Vector3 = r["c"]
		rects.append({"center": Vector3(c3.x, c3.y + 4.0, c3.z),
			"size": Vector2(float(r["w"]) + 2.0, float(r["d"]) + 2.0),
			"y_min": c3.y - 1.0, "y_max": c3.y + float(r["h"]) + 14.0})
	var cleared := 0
	if do_clear:
		cleared = SiteClear.clear_rects(layer.world, rects, ["roof", "deck"])
	print("HIDE_ORIGINAL active=%d hidden_mesh=%d cleared_instances=%d" % [active.size(), hidden_total, cleared])

func _walk(n: Node, active: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.visible and not _excluded(str(mi.name)):
			var aabb := mi.get_aabb()
			var gp := mi.global_transform * aabb.get_center()
			for r in active:
				if _inside(gp, aabb.size, r):
					mi.visible = false
					hidden_total += 1
					break
	for ch in n.get_children():
		_walk(ch, active)

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % 30 != 0 or layer == null or layer.stream == null:
		return
	var ev := int(layer.stream.get("load_events"))
	var pp: Vector3 = (layer.player as CharacterBody3D).global_position
	var moved := pp.distance_to(_last_pos) > 15.0
	if ev == _last_events and not moved:
		return
	_last_events = ev
	_last_pos = pp
	apply()
