extends Node
## 探测 world / 生成器对象 / 布局对象 暴露的自定义方法，判断能否按新参数重建单栋建筑。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout
	var w: Node = layer.world
	_dump("world", w)
	for key in ["b", "layout", "terrain_art", "path_art", "home_extras", "streamer"]:
		var o = w.get(key)
		if o is Object:
			_dump("world." + key, o)
	# 主脚本与存档对象
	_dump("main", layer.main)
	for key in ["store", "ui", "hud"]:
		var o = layer.main.get(key)
		if o is Object:
			_dump("main." + key, o)
	var f := FileAccess.open("user://api_world.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("API_WORLD_DONE ", out.size())
	get_tree().quit()

func _dump(label: String, o: Object) -> void:
	out.append("=== " + label + " (" + str(o.get_class()) + ") ===")
	var base := {}
	for m in Node.new().get_method_list():
		base[str(m.name)] = true
	Node.new().free()
	var names: Array[String] = []
	for m in o.get_method_list():
		var mn := str(m.name)
		if base.has(mn) or mn.begins_with("_"):
			continue
		var args: Array[String] = []
		for a in m.args:
			args.append(str(a.name) + ":" + type_string(a.type))
		names.append(mn + "(" + ", ".join(args) + ")")
	out.append("METHODS: " + ", ".join(names))
	var props: Array[String] = []
	for p in o.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props.append(str(p.name))
	out.append("VARS: " + ", ".join(props))
