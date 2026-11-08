extends Node
var layer: Node
var lines: Array[String] = []

func _ready() -> void:
	layer.main.call("start_game",false)
	await get_tree().create_timer(1.5).timeout
	layer.main.call("show_map")
	await get_tree().create_timer(1.5).timeout
	_dump(layer.main.get("modal"),0)
	var f := FileAccess.open("user://map_inspect.txt",FileAccess.WRITE)
	for line in lines:
		f.store_line(line)
	f.close()
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://T3_map_before.png")
	print("MAP_INSPECT_DONE")
	get_tree().quit()

func _dump(n: Node, depth: int) -> void:
	var script: Script = n.get_script()
	var path := script.resource_path if script != null else ""
	var desc := str(n.get_path())+" "+n.get_class()+" "+path
	if n is Control:
		desc += " rect="+str((n as Control).get_global_rect())
	lines.append(desc)
	if path.contains("bay_map") or path.contains("scenic_map130") or path.contains("floor_plan120"):
		for method in script.get_script_method_list():
			lines.append("  METHOD "+str(method.name)+" args="+str(method.args))
		for prop in script.get_script_property_list():
			var key := str(prop.name)
			var value = n.get(key)
			lines.append("  PROP "+key+"="+str(value).substr(0,300))
	for child in n.get_children(true):
		_dump(child,depth+1)
