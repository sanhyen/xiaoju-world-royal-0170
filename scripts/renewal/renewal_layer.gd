extends Node
## 0170 整改层入口。
## 设计约束：原始 162 个脚本为编译字节码，不可编辑。本层以主场景子节点方式挂载，
## 只通过公开节点/属性/方法与其协作，不替换原世界、不覆盖原存档格式。
##
## 模块：
##   ferris_wheel.gd  山海星轮（新增设施）
##   passability.gd   入口/门槛/楼梯通行修复
##   water_safety.gd  落水与跌落安全
##   perf_monitor.gd  帧耗时与流式加载监测
##   theme_buildings.gd 主题建筑改造

const VERSION := "0.17.0-renewal"
const WHEEL_SITE := Vector3(-420.0, 4.0, 275.0)

var main: Node
var world: Node
var player: Node
var stream: Node
var cam: Camera3D
var wheel: Node3D
var passability: Node
var safety: Node
var fixes_enabled := true
var wheel_enabled := true
var step_assist_enabled := false
var render_profile := ""
var stairs_enabled := true
var themes_enabled := true
var site_enabled := true
var themes: Node
var hide_original: Node
var site_fixes: Node
var map_marker: Node
var look: Node
var overhead: Node
var sky_island: Node3D
var nearshore: Node
var roads: Node
var island_enabled := true
var coral_landscape: Node3D
var travel_play: Node3D
var surfaces:Node3D
var sky_expansion:Node3D
var rivers:Node3D

var _probe_mode := ""
var _wheel_ready := false

func _ready() -> void:
	main = get_parent()
	_parse_args()
	await get_tree().process_frame
	_resolve_refs()
	surfaces=load("res://scripts/renewal/surface_routes.gd").new()
	surfaces.name="TraversalSurfaces";world.add_child(surfaces);surfaces.setup(self)
	print("RENEWAL_LAYER_READY %s world=%s player=%s stream=%s" % [VERSION, str(world != null), str(player != null), str(stream != null)])
	_widen_bounds()
	if wheel_enabled:
		_build_wheel()
	_setup_passability()
	_setup_safety()
	_setup_themes()
	_apply_render_profile()
	_setup_look()
	_setup_overhead()
	_setup_figure()
	_setup_sky_island()
	_setup_nearshore()
	_setup_roads()
	coral_landscape = load("res://scripts/renewal/coral_landscape.gd").new()
	coral_landscape.name = "CoralLandscape"
	world.add_child(coral_landscape)
	coral_landscape.setup(self)
	travel_play = load("res://scripts/renewal/travel_play.gd").new()
	travel_play.name = "TravelPlay"
	world.add_child(travel_play)
	travel_play.setup(self)
	sky_expansion=load("res://scripts/renewal/sky_expansion.gd").new()
	sky_expansion.name="SkyExpansion";world.add_child(sky_expansion);sky_expansion.setup(self)
	rivers=load("res://scripts/renewal/shallow_rivers.gd").new()
	rivers.name="ShallowRivers";world.add_child(rivers);rivers.setup(self)
	if _probe_mode != "":
		var probe: Node = load("res://scripts/renewal/qa/probe.gd").new()
		probe.mode = _probe_mode
		probe.layer = self
		add_child(probe)

func _build_wheel() -> void:
	if _wheel_ready:
		return
	var w: Node3D = load("res://scripts/renewal/ferris_wheel.gd").new()
	w.name = "ShanhaiStarWheel"
	w.layer = self
	w.position = WHEEL_SITE
	add_child(w)
	wheel = w
	_wheel_ready = true

## 渲染档位：默认保持原版画质，仅按命令行参数切换，避免“降画质换帧率”被当成优化。
func _apply_render_profile() -> void:
	if render_profile == "balanced":
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale = 1.0
		print("RENDER_PROFILE balanced msaa_off")
	elif render_profile == "interp":
		ProjectSettings.set_setting("physics/common/physics_interpolation", true)
		print("RENDER_PROFILE interp")

func _setup_passability() -> void:
	var p: Node = load("res://scripts/renewal/passability.gd").new()
	p.name = "Passability"
	add_child(p)
	p.setup(self)
	p.enabled = fixes_enabled
	p.step_assist = step_assist_enabled
	p.stairs = stairs_enabled
	passability = p
	if fixes_enabled:
		p.build()

func _setup_themes() -> void:
	if not themes_enabled:
		return
	var t: Node = load("res://scripts/renewal/theme_buildings.gd").new()
	t.name = "ThemeBuildings"
	add_child(t)
	t.setup(self)
	t.build()
	themes = t
	if site_enabled:
		var sf: Node = load("res://scripts/renewal/site_fixes.gd").new()
		sf.name = "SiteFixes"
		add_child(sf)
		sf.setup(self)
		sf.build()
		site_fixes = sf
	# 独立 CanvasLayer 只读取地图公开投影，不向原 PanelContainer 注入控件。
	if not OS.get_cmdline_user_args().has("--map-marker=0"):
		map_marker = load("res://scripts/renewal/map_marker.gd").new()
		map_marker.name = "IslandMapMarker"
		add_child(map_marker)
		map_marker.setup(self)

## P3：道路重建 mesh + UV + 路缘
func _setup_roads() -> void:
	var rd: Node = load("res://scripts/renewal/road_rebuild.gd").new()
	rd.name = "RoadRebuild"
	add_child(rd)
	rd.setup(self)
	rd.build()
	roads = rd

## P2/P5：近岸水面带 + 两个海岛礁盘水面
func _setup_nearshore() -> void:
	var ns: Node = load("res://scripts/renewal/nearshore_water.gd").new()
	ns.name = "NearshoreWater"
	add_child(ns)
	ns.setup(self)
	ns.build()
	nearshore = ns

## 正式版保留原方块人物；服装细节由仙山增量层添加。
func _setup_figure() -> void:
	pass

## 全局俯视（V 键）：独立相机，不注入原版地图 UI
func _setup_overhead() -> void:
	if OS.get_cmdline_user_args().has("--overhead=0"):
		return
	overhead = load("res://scripts/renewal/overhead_view.gd").new()
	overhead.name = "OverheadView"
	add_child(overhead)
	overhead.setup(self)

## 云岫仙山（新岛）：摩天轮正西的「另一块陆地」，隔海峡与主岛相望。
func _setup_sky_island() -> void:
	if not island_enabled:
		return
	# 最新重构直接作为正式版默认内容；阶段参数仅供开发探针使用。
	var island_args := OS.get_cmdline_user_args()
	if not island_args.has("--island-rebuild=s1") and not island_args.has("--island-rebuild=s2"):
		island_args.append("--island-rebuild=s2")
	for a in island_args:
		if a in ["--island-rebuild=s1","--island-rebuild=s2"]:
			var preview: Node3D = load("res://scripts/renewal/rebuild/island_preview.gd").new()
			preview.name = "IslandRebuildPreview"
			preview.stage = a.get_slice("=",1)
			add_child(preview)
			preview.setup(self)
			sky_island = preview
			return
	var isl: Node3D = load("res://scripts/renewal/sky_palace_island.gd").new()
	isl.name = "SkyPalaceIsland"
	add_child(isl)
	isl.setup(self)
	sky_island = isl

func _setup_look() -> void:
	var l: Node = load("res://scripts/renewal/look_enhance.gd").new()
	l.name = "LookEnhance"
	add_child(l)
	l.setup(self)
	l.apply()
	look = l

func _setup_safety() -> void:
	var s: Node = load("res://scripts/renewal/water_safety.gd").new()
	s.name = "WaterSafety"
	add_child(s)
	s.setup(self)
	s.enabled = fixes_enabled
	safety = s

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--renewal-probe="):
			_probe_mode = a.substr("--renewal-probe=".length())
		elif a.begins_with("--fix="):
			fixes_enabled = a.substr(6) != "0"
		elif a.begins_with("--stepassist="):
			step_assist_enabled = a.substr(13) != "0"
		elif a.begins_with("--themes="):
			pass
		elif a.begins_with("--nothemes"):
			themes_enabled = false
		elif a.begins_with("--nosite"):
			site_enabled = false
		elif a.begins_with("--stairs="):
			stairs_enabled = a.substr(9) != "0"
		elif a.begins_with("--render="):
			render_profile = a.substr(9)
		elif a.begins_with("--wheel="):
			wheel_enabled = a.substr(8) != "0"
		elif a.begins_with("--skyisland="):
			island_enabled = a.substr(12) != "0"

func _resolve_refs() -> void:
	if main == null:
		return
	for c in main.get_children():
		var sp := ""
		if c.get_script() != null:
			sp = (c.get_script() as Script).resource_path
		if sp.ends_with("/world.gd"):
			world = c
		elif c is CharacterBody3D and player == null:
			player = c
	if world != null:
		for c in world.get_children():
			if c.get_script() != null and (c.get_script() as Script).resource_path.ends_with("/world_stream.gd"):
				stream = c
	if player != null and cam == null:
		for n in player.find_children("*", "Camera3D", true, false):
			cam = n
			break

func _process(_delta: float) -> void:
	if player == null or world == null:
		_resolve_refs()
	_sync_wade_policy()

## 原版 bay_layout.bounds = [-640, 640, -720, 720] 是世界硬边界。
## 玩家越过 x=-640 就会被判出界、原地停住——这正是跨海长桥走到一半就
## 「速度归零、前方无任何碰撞体」的真正原因（与水深策略无关）。
## 云岫仙山在 -640 以西 130 m，必须先把西边界推开，长桥与整座岛才可抵达。
const WORLD_WEST_EXTEND := -960.0

func _widen_bounds() -> void:
	if world == null:
		return
	var spec: Variant = world.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var bay: Variant = (spec as Dictionary).get("bay_layout", {})
	if typeof(bay) != TYPE_DICTIONARY:
		return
	var b: Variant = (bay as Dictionary).get("bounds", null)
	if typeof(b) != TYPE_ARRAY:
		return
	var arr: Array = b
	if arr.size() < 4:
		return
	if float(arr[0]) <= WORLD_WEST_EXTEND + 0.5:
		return
	arr[0] = WORLD_WEST_EXTEND
	(bay as Dictionary)["bounds"] = arr
	(spec as Dictionary)["bay_layout"] = bay
	world.set("spec", spec)
	print("WORLD_BOUNDS_WIDENED west=%.1f" % WORLD_WEST_EXTEND)

## 原版控制器用「地形高度」判断涉水深度：`depth = 海面 - height_at(x,z)`。
## 云岫仙山整座岛与跨海长桥都悬在 -14 m 的海床上，于是每一步都被判成
## 深水禁步（edge_mode=stop_in_place），玩家走到桥中段就完全动不了。
## 这里只在「长桥走廊 + 岛体」范围内把 max_wade_depth_m 放开，离开即复原，
## 不影响原版任何浅滩/深水的行为。
const WADE_DEPTH_DEFAULT := 1.35
const WADE_DEPTH_OPEN := 99.0
const ISLAND_ZONE_X := -548.0
const ISLAND_ZONE_HALF_Z := 70.0

func _sync_wade_policy() -> void:
	if player == null or world == null or sky_island == null:
		return
	var p: Vector3 = (player as Node3D).global_position
	var in_zone := p.x < ISLAND_ZONE_X and absf(p.z - 300.0) < ISLAND_ZONE_HALF_Z
	if sky_island.has_method("contains_land"):
		in_zone = sky_island.call("contains_land",p) or sky_island.call("on_connection",p)
	if travel_play != null:
		in_zone = in_zone or travel_play.on_link(p)
	var spec: Variant = world.get("spec")
	if typeof(spec) != TYPE_DICTIONARY:
		return
	var bay: Variant = (spec as Dictionary).get("bay_layout", {})
	if typeof(bay) != TYPE_DICTIONARY:
		return
	var pol: Variant = (bay as Dictionary).get("shallow_policy", {})
	if typeof(pol) != TYPE_DICTIONARY or (pol as Dictionary).is_empty():
		return
	var want := WADE_DEPTH_OPEN if in_zone else WADE_DEPTH_DEFAULT
	if absf(float((pol as Dictionary).get("max_wade_depth_m", WADE_DEPTH_DEFAULT)) - want) < 0.01:
		return
	(pol as Dictionary)["max_wade_depth_m"] = want
	(bay as Dictionary)["shallow_policy"] = pol
	(spec as Dictionary)["bay_layout"] = bay
	world.set("spec", spec)

func _physics_process(_delta: float) -> void:
	_sync_wade_policy()
	if sky_island != null and (travel_play == null or not sky_island.has_method("wp")):
		_assist_island_stairs(_delta)

## 天梯助推
## 原版控制器在 38° 的程序化斜面碰撞上会「走着走着突然速度归零」：玩家踩在
## 斜面上、前方没有任何碰撞体、foot_destination_allowed 也返回 true，但
## move_and_slide 反复把水平速度消解掉，人就此钉死。引擎侧改不动，这里在
## 「岛上天梯 + 已站上坡面 + 按着 W + 速度确实归零」四个条件同时成立时才
## 沿坡面推一小步，正常行走完全不受影响。
const STAIR_X_EAST := -640.0
const STAIR_X_WEST := -840.0
const STAIR_HALF_Z := 13.0

func _assist_island_stairs(delta: float) -> void:
	if player == null or sky_island == null:
		return
	var p := player as CharacterBody3D
	if not p.is_on_floor():
		return
	var pos: Vector3 = p.global_position
	if pos.x > STAIR_X_EAST or pos.x < STAIR_X_WEST or absf(pos.z - 300.0) > STAIR_HALF_Z:
		return
	var n: Vector3 = p.get_floor_normal()
	# 竖直墙面 (n.y<0.5) 不介入；平地也允许介入——山巅平台边缘同样会把玩家钉死
	if n.y < 0.5:
		return
	if not (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)):
		return
	var yaw := float(p.get("yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if fwd.x > -0.35:
		return
	# 只有真的被钉住才推
	if p.velocity.length() > 0.6:
		return
	# 前向 0.45 m 处必须确实有坡面，且抬升量合理——否则会把玩家一路推到空中
	var space := p.get_world_3d().direct_space_state
	var ahead: Vector3 = pos + fwd * 0.45
	var q := PhysicsRayQueryParameters3D.create(ahead + Vector3(0, 1.5, 0), ahead - Vector3(0, 2.5, 0))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var hpt: Vector3 = hit.position
	var rise: float = hpt.y - pos.y
	if rise < -0.70 or rise > 1.1:
		return
	var step := 4.5 * delta * (float(p.get("run_multiplier")) if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var motion := Vector3(fwd.x * step, maxf(0.0, rise) * 0.9, fwd.z * step)
	if p.test_move(p.global_transform, motion):
		return
	p.global_position = pos + motion

## 供 QA 使用：把玩家放到指定位置并立即触发一次流式加载。
func teleport(pos: Vector3) -> void:
	if player == null:
		return
	(player as CharacterBody3D).global_position = pos
	(player as CharacterBody3D).velocity = Vector3.ZERO
