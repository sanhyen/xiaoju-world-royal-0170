extends Node
## 诊断探针：仅由 --renewal-probe= 触发，不参与正常游玩。

var mode := ""
var layer: Node

func _ready() -> void:
	# 探针运行时把窗口移到屏幕外并取消抢焦点：截图/测量照常，用户看不到窗口闪烁。
	# 加 --offscreen 才生效，正常游玩不受影响。
	for a in OS.get_cmdline_user_args():
		if a == "--offscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
			DisplayServer.window_set_position(Vector2i(-6000, -6000))
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			break
	await get_tree().create_timer(10.0).timeout
	match mode:
		"realresume":
			var resume_test:Node=load("res://scripts/renewal/qa/real_resume.gd").new()
			resume_test.layer=layer;add_child(resume_test);return
		"rectificationbundle":
			var bundle:Node=load("res://scripts/renewal/qa/rectification_bundle.gd").new()
			bundle.layer=layer;add_child(bundle);return
		"rectificationvisual":
			var visual:Node=load("res://scripts/renewal/qa/rectification_visual.gd").new()
			visual.layer=layer;add_child(visual);return
		"rectification":
			var rectification: Node = load("res://scripts/renewal/qa/rectification_test.gd").new()
			rectification.layer=layer
			add_child(rectification)
			return
		"islandcollision":
			var collision_test: Node = load("res://scripts/renewal/qa/island_collision_test.gd").new()
			collision_test.layer = layer
			add_child(collision_test)
			return
		"realmwalk":
			var realm_walk: Node = load("res://scripts/renewal/qa/realm_walk.gd").new()
			realm_walk.layer = layer
			add_child(realm_walk)
			return
		"boattravel":
			var boat_travel: Node = load("res://scripts/renewal/qa/boat_travel_test.gd").new()
			boat_travel.layer = layer
			add_child(boat_travel)
			return
		"linkwalk":
			var link_walk: Node = load("res://scripts/renewal/qa/link_walk.gd").new()
			link_walk.layer = layer
			add_child(link_walk)
			return
		"travelplay":
			var travel_play_test: Node = load("res://scripts/renewal/qa/travel_play_test.gd").new()
			travel_play_test.layer = layer
			add_child(travel_play_test)
			return
		"travelsurvey":
			var survey: Node = load("res://scripts/renewal/qa/travel_play_survey.gd").new()
			survey.layer = layer
			add_child(survey)
			return
		"coralaudit":
			var audit: Node = load("res://scripts/renewal/qa/coral_audit.gd").new()
			audit.layer = layer
			add_child(audit)
			return
		"feedback":
			var feedback:Node=load("res://scripts/renewal/qa/feedback_test.gd").new()
			feedback.layer=layer
			add_child(feedback)
			return
		"travelinspect", "traveltest":
			var travel: Node = load("res://scripts/renewal/qa/travel_test.gd").new()
			travel.layer = layer
			travel.inspect_only = mode == "travelinspect"
			add_child(travel)
			return
		"rebuildreview":
			var review: Node = load("res://scripts/renewal/qa/rebuild_review.gd").new()
			review.layer = layer
			add_child(review)
			return
		"rebuildbaseline":
			var baseline: Node = load("res://scripts/renewal/qa/rebuild_baseline.gd").new()
			baseline.layer = layer
			add_child(baseline)
			return
		"environmentab":
			var ea: Node = load("res://scripts/renewal/qa/environment_ab.gd").new()
			ea.layer = layer
			add_child(ea)
			return
		"figuremotion":
			var motion: Node = load("res://scripts/renewal/qa/figure_motion.gd").new()
			motion.layer = layer
			add_child(motion)
			return
		"islanddetail":
			var detail: Node = load("res://scripts/renewal/qa/island_detail.gd").new()
			detail.layer = layer
			add_child(detail)
			return
		"maptest":
			var mt: Node = load("res://scripts/renewal/qa/map_test.gd").new()
			mt.layer = layer
			add_child(mt)
			return
		"mapinspect":
			var inspect: Node = load("res://scripts/renewal/qa/map_inspect.gd").new()
			inspect.layer = layer
			add_child(inspect)
			return
		"terrainsites":
			var sites: Node = load("res://scripts/renewal/qa/terrain_sites.gd").new()
			sites.layer = layer
			add_child(sites)
			return
		"terrainab":
			var ab: Node = load("res://scripts/renewal/qa/terrain_ab.gd").new()
			ab.layer = layer
			add_child(ab)
			return
		"terrainvisible":
			var tv: Node = load("res://scripts/renewal/qa/terrain_visible.gd").new()
			tv.layer = layer
			add_child(tv)
			return
		"meta":
			_dump_meta()
		"tree":
			_dump_tree()
		"counts":
			_dump_counts()
		"shot":
			var sh: Node = load("res://scripts/renewal/qa/shot.gd").new()
			sh.layer = layer
			add_child(sh)
			return
		"survey":
			var sv: Node = load("res://scripts/renewal/qa/survey.gd").new()
			sv.layer = layer
			add_child(sv)
			return
		"api":
			var ap: Node = load("res://scripts/renewal/qa/api_probe.gd").new()
			ap.layer = layer
			add_child(ap)
			return
		"walk":
			var wt: Node = load("res://scripts/renewal/qa/walktest.gd").new()
			wt.layer = layer
			add_child(wt)
			return
		"perf":
			var pf: Node = load("res://scripts/renewal/qa/perf.gd").new()
			pf.layer = layer
			add_child(pf)
			return
		"water":
			var wtt: Node = load("res://scripts/renewal/qa/water_test.gd").new()
			wtt.layer = layer
			add_child(wtt)
			return
		"interp":
			var ip: Node = load("res://scripts/renewal/qa/interp_probe.gd").new()
			ip.layer = layer
			add_child(ip)
			return
		"water2":
			var wp: Node = load("res://scripts/renewal/qa/water_probe.gd").new()
			wp.layer = layer
			add_child(wp)
			return
		"env":
			var ev: Node = load("res://scripts/renewal/qa/env_probe.gd").new()
			ev.layer = layer
			add_child(ev)
			return
		"terrain":
			var tp: Node = load("res://scripts/renewal/qa/terrain_probe.gd").new()
			tp.layer = layer
			add_child(tp)
			return
		"terrain2":
			var tp2: Node = load("res://scripts/renewal/qa/terrain_probe2.gd").new()
			tp2.layer = layer
			add_child(tp2)
			return
		"terrain3":
			var tp3: Node = load("res://scripts/renewal/qa/terrain_probe3.gd").new()
			tp3.layer = layer
			add_child(tp3)
			return
		"terrain4":
			var tp4: Node = load("res://scripts/renewal/qa/terrain_probe4.gd").new()
			tp4.layer = layer
			add_child(tp4)
			return
		"door":
			var dp: Node = load("res://scripts/renewal/qa/door_probe.gd").new()
			dp.layer = layer
			add_child(dp)
			return
		"audit":
			var ea: Node = load("res://scripts/renewal/qa/env_audit.gd").new()
			ea.layer = layer
			add_child(ea)
			return
		"island":
			var ip: Node = load("res://scripts/renewal/qa/island_probe.gd").new()
			ip.layer = layer
			add_child(ip)
			return
		"islandwalk":
			var iw: Node = load("res://scripts/renewal/qa/island_walk.gd").new()
			iw.layer = layer
			add_child(iw)
			return
		"props":
			var pp: Node = load("res://scripts/renewal/qa/player_props.gd").new()
			pp.layer = layer
			add_child(pp)
			return
		"shallow":
			var sh: Node = load("res://scripts/renewal/qa/shallow_probe.gd").new()
			sh.layer = layer
			add_child(sh)
			return
		"stuck":
			var sk2: Node = load("res://scripts/renewal/qa/stuck_probe.gd").new()
			sk2.layer = layer
			add_child(sk2)
			return
		"pdump":
			var pd: Node = load("res://scripts/renewal/qa/player_dump.gd").new()
			pd.layer = layer
			add_child(pd)
			return
		"stuck2":
			var sk3: Node = load("res://scripts/renewal/qa/stuck2.gd").new()
			sk3.layer = layer
			add_child(sk3)
			return
		"stuck3":
			var sk4: Node = load("res://scripts/renewal/qa/stuck3.gd").new()
			sk4.layer = layer
			add_child(sk4)
			return
		"bounds":
			var bt: Node = load("res://scripts/renewal/qa/bounds_test.gd").new()
			bt.layer = layer
			add_child(bt)
			return
		"stair":
			var st2: Node = load("res://scripts/renewal/qa/stair_test.gd").new()
			st2.layer = layer
			add_child(st2)
			return
		"figure":
			var fg: Node = load("res://scripts/renewal/qa/figure_dump.gd").new()
			fg.layer = layer
			add_child(fg)
			return
		"wheelshot":
			var ws: Node = load("res://scripts/renewal/qa/wheel_shot.gd").new()
			ws.layer = layer
			add_child(ws)
			return
		"mataudit":
			var ma: Node = load("res://scripts/renewal/qa/mat_audit.gd").new()
			ma.layer = layer
			add_child(ma)
			return
		"ovshot":
			var ovs: Node = load("res://scripts/renewal/qa/ov_shot.gd").new()
			ovs.layer = layer
			add_child(ovs)
			return
		"stairdbg":
			var sd: Node = load("res://scripts/renewal/qa/stair_dbg.gd").new()
			sd.layer = layer
			add_child(sd)
			return
		"sun":
			var sp: Node = load("res://scripts/renewal/qa/sun_probe.gd").new()
			sp.layer = layer
			add_child(sp)
			return
		"skyaabb":
			var sa: Node = load("res://scripts/renewal/qa/sky_aabb.gd").new()
			sa.layer = layer
			add_child(sa)
			return
		"skysite":
			var ss: Node = load("res://scripts/renewal/qa/sky_site.gd").new()
			ss.layer = layer
			add_child(ss)
			return
		"float":
			var fp: Node = load("res://scripts/renewal/qa/float_probe.gd").new()
			fp.layer = layer
			add_child(fp)
			return
		"skymesh":
			var sm: Node = load("res://scripts/renewal/qa/sky_mesh.gd").new()
			sm.layer = layer
			add_child(sm)
			return
		"sky":
			var sk: Node = load("res://scripts/renewal/qa/sky_probe.gd").new()
			sk.layer = layer
			add_child(sk)
			return
		"themeaabb":
			var ta: Node = load("res://scripts/renewal/qa/theme_aabb.gd").new()
			ta.layer = layer
			add_child(ta)
			return
		"mesh":
			var mm: Node = load("res://scripts/renewal/qa/mesh_measure.gd").new()
			mm.layer = layer
			add_child(mm)
			return
		"mapshot":
			var ms: Node = load("res://scripts/renewal/qa/mapshot.gd").new()
			ms.layer = layer
			add_child(ms)
			return
		"owner":
			var op: Node = load("res://scripts/renewal/qa/owner_probe.gd").new()
			op.layer = layer
			add_child(op)
			return
		"batch":
			var bt: Node = load("res://scripts/renewal/qa/shot_batch.gd").new()
			bt.layer = layer
			add_child(bt)
			return
		"map":
			var mp: Node = load("res://scripts/renewal/qa/map_probe.gd").new()
			mp.layer = layer
			add_child(mp)
			return
		"geom":
			var gp: Node = load("res://scripts/renewal/qa/geom_probe.gd").new()
			gp.layer = layer
			add_child(gp)
			return
		"builder":
			var bb2: Node = load("res://scripts/renewal/qa/builder_probe.gd").new()
			bb2.layer = layer
			add_child(bb2)
			return
		"apiworld":
			var aw: Node = load("res://scripts/renewal/qa/api_world_probe.gd").new()
			aw.layer = layer
			add_child(aw)
			return
		"buildings":
			var bp: Node = load("res://scripts/renewal/qa/building_probe.gd").new()
			bp.layer = layer
			add_child(bp)
			return
		"wstate":
			_dump_wheel_state()
			get_tree().quit()
			return
		"input":
			var ip: Node = load("res://scripts/renewal/qa/input_probe.gd").new()
			ip.layer = layer
			add_child(ip)
			return
		"wheel":
			var wt: Node = load("res://scripts/renewal/qa/wheel_test.gd").new()
			wt.layer = layer
			add_child(wt)
			return
		_:
			print("unknown probe mode ", mode)
	get_tree().quit()

func _dump_wheel_state() -> void:
	var wheel = layer.wheel
	var lines: Array[String] = []
	if wheel == null:
		lines.append("wheel=null")
	else:
		lines.append("angle=%.4f state=%s riding=%s door=%.2f" % [float(wheel.get("angle")), str(wheel.get("state")), str(wheel.get("riding")), float(wheel.get("door_open"))])
		lines.append("cabin0_seat=%s" % str(wheel.call("_cabin_world_seat", 0)))
		lines.append("player=%s" % str(layer.player.global_position))
	var f := FileAccess.open("user://wheel_state.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("WSTATE_DONE")

func _dump_meta() -> void:
	var w: Node = layer.world
	var keys := ["metadata/architecture110", "metadata/entrances110", "metadata/upper_routes110", "building_bounds", "interactions", "path_corridors", "spec"]
	var d := {}
	for k in keys:
		d[k] = w.get(k)
	_write_json("user://probe_meta.json", d)
	print("PROBE_META_DONE")

func _dump_tree() -> void:
	var lines: Array[String] = []
	_walk(get_tree().root, 0, lines)
	_write_text("user://probe_tree2.txt", lines)
	print("PROBE_TREE_DONE ", lines.size())

func _dump_counts() -> void:
	var out: Array[String] = []
	var w: Node = layer.world
	var s: Node = layer.stream
	out.append("loaded=%d far=%d peak=%d load_events=%d unload=%d" % [s.get("loaded").size(), s.get("far_cells").size(), s.get("peak_cells"), s.get("load_events"), s.get("unload_events")])
	out.append("instantiate_ms=" + str(s.get("instantiate_ms")))
	var counts := {}
	_count_types(get_tree().root, counts)
	var ks := counts.keys()
	ks.sort()
	for k in ks:
		out.append("%s=%d" % [k, counts[k]])
	_write_text("user://probe_counts.txt", out)
	print("PROBE_COUNTS_DONE")

func _count_types(n: Node, acc: Dictionary) -> void:
	var c := n.get_class()
	acc[c] = acc.get(c, 0) + 1
	for x in n.get_children():
		_count_types(x, acc)

func _walk(n: Node, d: int, lines: Array[String]) -> void:
	var pad := "  ".repeat(d)
	var scr := ""
	if n.get_script() != null:
		scr = " script=" + (n.get_script() as Script).resource_path
	var pos := ""
	if n is Node3D:
		var p := (n as Node3D).global_position
		pos = " pos=(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]
	lines.append("%s%s [%s]%s%s" % [pad, n.name, n.get_class(), pos, scr])
	if d < 30:
		for c in n.get_children():
			_walk(c, d + 1, lines)

func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _write_text(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
