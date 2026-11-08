extends Node
## 打开原版地图并截图 + dump 面板结构，用于排查 M 键地图是否被破坏。

var layer: Node

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var main: Node = layer.main
	main.call("start_game", false)
	await get_tree().create_timer(2.0).timeout
	for key in ["menu", "hud"]:
		var n = main.get(key)
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	main.call("show_map")
	await get_tree().create_timer(2.0).timeout
	var modal = main.get("modal")
	var lines: Array[String] = []
	if modal is Control:
		var m := modal as Control
		lines.append("modal visible=%s size=%s children=%d" % [str(m.visible), str(m.size), m.get_child_count()])
		for c in m.get_children():
			var extra := ""
			if c is Control:
				extra = " pos=%s size=%s" % [str((c as Control).position), str((c as Control).size)]
			lines.append("  %s[%s]%s children=%d" % [str(c.name), str(c.get_class()), extra, c.get_child_count()])
			if c is PanelContainer:
				for g in c.get_children():
					var e2 := ""
					if g is Control:
						e2 = " pos=%s size=%s" % [str((g as Control).position), str((g as Control).size)]
					lines.append("    %s[%s]%s" % [str(g.name), str(g.get_class()), e2])
	var f := FileAccess.open("user://mapshot.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	var img := get_viewport().get_texture().get_image()
	img.save_png("D:/xiaojuWorld/renewal/evidence/shots/map_open.png")
	print("MAPSHOT_DONE")
	get_tree().quit()
