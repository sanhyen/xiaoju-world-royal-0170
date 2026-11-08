extends Node
var layer: Node
func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	var p: CharacterBody3D = layer.player
	p.global_position = Vector3(188.0, 22.0, -205.0)
	await get_tree().create_timer(2.5).timeout
	var c := Vector3(188.0, 26.0, -225.0)
	var lines: Array[String] = []
	_scan(layer.world, c, lines, 0)
	var f := FileAccess.open("user://owner_probe.txt", FileAccess.WRITE)
	for l in lines: f.store_line(l)
	f.close()
	print("OWNER_PROBE_DONE ", lines.size())
	get_tree().quit()

func _scan(n: Node, c: Vector3, lines: Array[String], d: int) -> void:
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var gp: Vector3 = gi.global_transform.origin
		if Vector2(gp.x - c.x, gp.z - c.z).length() < 22.0:
			var aabb: AABB = gi.get_aabb()
			lines.append("%s|%s|parent=%s|vis=%s|pos=(%.1f,%.1f,%.1f)|sz=(%.1f,%.1f,%.1f)" % [
				str(n.get_class()), str(n.name), str(n.get_parent().name), str(gi.visible),
				gp.x, gp.y, gp.z, aabb.size.x, aabb.size.y, aabb.size.z])
	for ch in n.get_children():
		_scan(ch, c, lines, d + 1)
