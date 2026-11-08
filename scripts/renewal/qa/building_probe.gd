extends Node
## 建筑节点勘察：定位 20 栋目标建筑在场景树中的实际网格节点与父节点，判断能否按节点隐藏/替换。

var layer: Node
var out: Array = []

const TARGETS := [
	["B02", -110.0, 4.6, 248.0], ["B03", -100.0, 3.6, 197.0],
	["B04", -215.0, 17.6, -215.0], ["B05", 188.0, 20.6, -225.0],
	["B06", 252.0, 15.6, -206.0], ["B08", -240.0, 11.6, -72.0],
	["B09", -230.0, 10.6, -8.0], ["B10", -287.0, 8.6, 8.0],
	["B11", -60.0, 5.6, 153.0], ["H01", -238.0, 4.4, 224.0],
	["H03", -312.0, 4.3, 220.0], ["H07", -183.0, 8.1, 35.0],
	["H08", 95.0, 5.6, 26.0], ["H11", -63.0, 4.0, 212.0],
	["H12", -139.0, 4.4, 208.0], ["Z09_B2", 326.0, 5.5, 59.0],
	["Z09_B3", 282.0, 14.5, -10.0], ["Z09_B6", 250.0, 19.5, 22.0],
	["SUMMIT_TEA", -20.0, 71.1, -396.0], ["AZURE_VIEW", 193.0, 29.2, -35.0],
]

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	var p: CharacterBody3D = layer.player
	for t in TARGETS:
		var id := str(t[0])
		var c := Vector3(float(t[1]), float(t[2]), float(t[3]))
		p.global_position = c + Vector3(0, 3.0, 0)
		await get_tree().create_timer(1.0).timeout
		var nodes: Array = []
		_collect(layer.world, c, 22.0, nodes)
		out.append({"id": id, "center": [c.x, c.y, c.z], "meshes": nodes})
		print("BLD ", id, " nodes=", nodes.size())
	var f := FileAccess.open("user://building_nodes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("BUILDINGS_PROBE_DONE")
	get_tree().quit()

func _collect(n: Node, c: Vector3, radius: float, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		var gp := mi.global_transform * aabb.get_center()
		if Vector2(gp.x - c.x, gp.z - c.z).length() < radius and gp.y > c.y - 8.0 and gp.y < c.y + 26.0:
			acc.append({
				"name": str(mi.name),
				"parent": str(mi.get_parent().name),
				"path": str(mi.get_path()),
				"center": [snappedf(gp.x, 0.1), snappedf(gp.y, 0.1), snappedf(gp.z, 0.1)],
				"size": [snappedf(aabb.size.x, 0.1), snappedf(aabb.size.y, 0.1), snappedf(aabb.size.z, 0.1)],
			})
	for ch in n.get_children():
		_collect(ch, c, radius, acc)
