extends Node

var layer: Node

func _ready() -> void:
	var data: Dictionary = {}
	for p in [Vector2(-722,401),Vector2(-758,451),Vector2(-103,467),Vector2(-104,510),
			Vector2(-66,491),Vector2(-23,491),Vector2(185,451),Vector2(199,450),Vector2(438,-435),Vector2(450,-468),Vector2(470,-480)]:
		data[str(p)] = layer.world.call("height_at",p.x,p.y)
	layer.main.call("start_game",false)
	await get_tree().create_timer(1).timeout
	layer.teleport(Vector3(438,85,-435))
	await get_tree().create_timer(6).timeout
	var space: PhysicsDirectSpaceState3D = layer.player.get_world_3d().direct_space_state
	var raised: Array = []
	for x in range(418,570,4):
		for z in range(-563,-451,4):
			var q := PhysicsRayQueryParameters3D.create(Vector3(x,180,z),Vector3(x,74,z))
			q.exclude = [layer.player.get_rid()]
			var hit := space.intersect_ray(q)
			var ground: float = layer.world.call("height_at",x,z)
			if not hit.is_empty() and hit.position.y > ground+4 and hit.normal.y > .70:
				raised.append([x,hit.position.y,z,str(hit.collider.name)])
	data["raised"] = raised
	var geometry: Array = []
	for n in layer.world.find_children("*","GeometryInstance3D",true,false):
		var b: AABB = n.global_transform*n.get_aabb()
		var c := b.get_center()
		if c.x > 390 and c.x < 580 and c.y > 82 and c.z < -465 and c.z > -590:
			if b.size.x > 4 and b.size.z > 4:
				geometry.append({"name":str(n.name),"center":[c.x,c.y,c.z],"size":[b.size.x,b.size.y,b.size.z],"visible":n.is_visible_in_tree()})
	data["geometry"] = geometry
	FileAccess.open("user://travel_play_survey.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	print("TRAVEL_PLAY_SURVEY ",raised.size())
	get_tree().quit()
