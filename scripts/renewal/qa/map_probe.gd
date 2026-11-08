extends Node
## 地图接口探测：zone 字典结构、地图面板节点、地点数据来源。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var main: Node = layer.main
	var w: Node = layer.world
	var z = main.call("zone_for_position", Vector3(289.0, 4.0, 248.0))
	out.append("zone_for_position => " + str(z))
	var spec = w.get("spec")
	if typeof(spec) == TYPE_DICTIONARY:
		var cp = spec.get("bay_layout", {}).get("creative_places", [])
		out.append("creative_places count=" + str(cp.size()))
		if cp.size() > 0:
			var first = cp[0]
			out.append("creative_places[0] keys=" + str(first.keys()))
			var first_s := str(first)
			out.append("creative_places[0] => " + first_s.substr(0, 300))
	var ep = spec.get("bay_layout", {}).get("extra_places", [])
	out.append("extra_places count=" + str(ep.size()))
	if ep.size() > 0:
		var ep0 := str(ep[0])
		out.append("extra_places[0] => " + ep0.substr(0, 250))
	# 打开地图并 dump UI
	main.call("start_game", false)
	await get_tree().create_timer(1.5).timeout
	main.call("show_map")
	await get_tree().create_timer(1.2).timeout
	var modal = main.get("modal")
	out.append("modal=" + str(modal))
	if modal is Node:
		out.append("modal visible=" + str((modal as Control).visible))
		_dump(modal as Node, 0)
	var f := FileAccess.open("user://map_probe.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("MAP_PROBE_DONE")
	get_tree().quit()

func _dump(n: Node, d: int) -> void:
	if d > 6:
		return
	var extra := ""
	if n is Label:
		extra = " text=" + str((n as Label).text)
	elif n is Button:
		extra = " text=" + str((n as Button).text)
	if extra != "" or d < 2:
		out.append("  ".repeat(d) + str(n.name) + "[" + str(n.get_class()) + "]" + extra)
	for c in n.get_children():
		_dump(c, d + 1)
