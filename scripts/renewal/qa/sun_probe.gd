extends Node
var layer: Node
func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var out: Array[String] = []
	var sun = layer.main.get("sun")
	if sun is DirectionalLight3D:
		var s := sun as DirectionalLight3D
		var d := -s.global_transform.basis.z
		out.append("sun rot=(%.3f,%.3f,%.3f) dir=(%.3f,%.3f,%.3f) energy=%.2f shadow=%s" % [
			s.rotation.x, s.rotation.y, s.rotation.z, d.x, d.y, d.z, s.light_energy, str(s.shadow_enabled)])
	else:
		out.append("sun not found")
	var f := FileAccess.open("user://sun.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("SUN_DONE")
	get_tree().quit()
