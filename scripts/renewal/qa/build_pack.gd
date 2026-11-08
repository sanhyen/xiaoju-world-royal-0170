extends SceneTree
## 重构工程兼容打包：保留原始字节码、remap 和导入资源，不重新导入或反编译。
## --headless --path <project> --script res://scripts/renewal/qa/build_pack.gd -- <output.pck>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var output := args[0]
	var config_path := output + ".project.binary"
	if ProjectSettings.save_custom(config_path) != OK:
		push_error("PACK_CONFIG_FAILED")
		quit(3)
		return
	var pack := PCKPacker.new()
	if pack.pck_start(output, 32) != OK:
		quit(4)
		return
	var files := PackedStringArray()
	_collect("res://", files)
	files.sort()
	var count := 0
	for path in files:
		if pack.add_file(path, ProjectSettings.globalize_path(path)) != OK:
			push_error("PACK_ADD_FAILED " + path)
			quit(5)
			return
		count += 1
	if pack.add_file("res://project.binary", config_path) != OK:
		quit(6)
		return
	var result := pack.flush(false)
	print("RENEWAL_PACK files=%d result=%d output=%s" % [count + 1, result, output])
	quit(0 if result == OK else 7)

func _collect(path: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for name in dir.get_directories():
		var child := path.path_join(name)
		if child in ["res://probe", "res://.godot/editor", "res://.godot/shader_cache", "res://.git"]:
			continue
		_collect(child, files)
	for name in dir.get_files():
		if name in ["project.godot", "project.binary", "export_presets.cfg"] or name.ends_with(".bak") or name.ends_with(".orig") or name.ends_with(".tmp"):
			continue
		files.append(path.path_join(name))
