extends Node

func _ready() -> void:
	await get_tree().create_timer(12.0).timeout
	var root := get_tree().root
	var main := root.get_node_or_null("XiaojuWorld")
	var world: Node = null
	var stream: Node = null
	var player: Node = null
	for c in main.get_children():
		var sp := ""
		if c.get_script() != null:
			sp = (c.get_script() as Script).resource_path
		if sp.ends_with("world.gd"):
			world = c
		if c is CharacterBody3D:
			player = c
	for c in world.get_children():
		if c.get_script() != null and (c.get_script() as Script).resource_path.ends_with("world_stream.gd"):
			stream = c
	var dump := {}
	for key in ["metadata/architecture110", "metadata/entrances110", "metadata/upper_routes110", "building_bounds", "interactions", "path_corridors"]:
		dump[key] = world.get(key)
	_write_json("user://meta.json", dump)

	var base := {}
	for m in Node.new().get_method_list():
		base[str(m.name)] = true
	Node.new().free()
	var out: Array[String] = []
	for n in [main, world, stream, player]:
		var p: String = (n.get_script() as Script).resource_path
		var names: Array[String] = []
		for m in n.get_method_list():
			var mn := str(m.name)
			if not base.has(mn) and not mn.begins_with("_"):
				names.append(mn)
		out.append("%s :: %s" % [p, ", ".join(names)])
	_write_text("user://methods.txt", out)
	print("PROBE_DONE")
	get_tree().quit()

func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _write_text(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
