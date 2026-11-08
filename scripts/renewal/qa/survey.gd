extends Node
## 地形勘察：按区块传送玩家触发流式加载，再向下射线采样地面高度。
## 参数：--survey=x0,x1,z0,z1,step,hub

var layer: Node
var out: Array = []
var x0 := -420.0
var x1 := -260.0
var z0 := -450.0
var z1 := -250.0
var step := 10.0
var hub := 110.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--survey="):
			var parts := a.substr(9).split(",")
			if parts.size() >= 6:
				x0 = float(parts[0]); x1 = float(parts[1]); z0 = float(parts[2]); z1 = float(parts[3])
				step = float(parts[4]); hub = float(parts[5])
	await get_tree().create_timer(3.0).timeout
	var player: CharacterBody3D = layer.player
	var space := player.get_world_3d().direct_space_state
	var cx := x0
	while cx <= x1 + 0.01:
		var cz := z0
		while cz <= z1 + 0.01:
			player.global_position = Vector3(cx, 90.0, cz)
			await get_tree().create_timer(0.75).timeout
			var gx := cx - hub * 0.5
			while gx <= cx + hub * 0.5 + 0.01:
				var gz := cz - hub * 0.5
				while gz <= cz + hub * 0.5 + 0.01:
					if gx >= x0 - 0.01 and gx <= x1 + 0.01 and gz >= z0 - 0.01 and gz <= z1 + 0.01:
						var q := PhysicsRayQueryParameters3D.create(Vector3(gx, 320.0, gz), Vector3(gx, -40.0, gz))
						var hit := space.intersect_ray(q)
						if hit.is_empty():
							out.append({"x": snappedf(gx,0.1), "z": snappedf(gz,0.1), "y": null, "name": "", "ny": null})
						else:
							var nm := ""
							if hit.collider is Node:
								nm = str((hit.collider as Node).name)
							out.append({"x": snappedf(gx,0.1), "z": snappedf(gz,0.1), "y": snappedf(hit.position.y, 0.01), "name": nm, "ny": snappedf(hit.normal.y, 0.01)})
					gz += step
				gx += step
			cz += hub
		cx += hub
	var f := FileAccess.open("user://survey.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"bounds": [x0, x1, z0, z1], "step": step, "points": out}))
	f.close()
	print("SURVEY_DONE ", out.size())
	get_tree().quit()
