extends Node

var lines: Array[String] = []

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var inst := packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().create_timer(10.0).timeout
	_dump(inst, 0)
	var f := FileAccess.open("res://probe/tree.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("PROBE_DONE lines=", lines.size())
	get_tree().quit()

func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is Node3D:
		var p := (n as Node3D).global_position
		extra = " pos=(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]
	if n is CharacterBody3D:
		var b := n as CharacterBody3D
		extra += " vel=%s radius=%.2f height=%.2f" % [str(b.velocity), b.get("radius") if b.get("radius") != null else -1.0, b.get("height") if b.get("height") != null else -1.0]
	var scr := ""
	if n.get_script() != null:
		scr = " script=" + str((n.get_script() as Script).resource_path)
	lines.append("%s%s [%s]%s%s children=%d" % [pad, n.name, n.get_class(), extra, scr, n.get_child_count()])
	if depth < 40:
		for c in n.get_children():
			_dump(c, depth + 1)
