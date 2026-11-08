extends Node

var layer: Node

func _ready() -> void:
	layer.main.call("start_game", false)
	await get_tree().create_timer(1.2).timeout
	layer.teleport(Vector3(256, 2.1, 427))
	for i in range(20):
		await get_tree().create_timer(.5).timeout
		var cell: Node = layer.stream.get_node_or_null("Cell_2_4")
		if cell != null and cell.get_child_count() > 200:
			await get_tree().create_timer(1).timeout
			break
	var world: Node3D = layer.world
	var report: Dictionary = {"visuals": [], "bodies": [], "interactions": [], "floors": [], "open_views": []}
	for n in layer.main.find_children("*", "Node3D", true, false):
		if n is GeometryInstance3D:
			var aabb: AABB = n.global_transform * n.get_aabb()
			var p := aabb.get_center()
			if aabb.intersects(AABB(Vector3(274,0,437), Vector3(12,9,38))):
				var count: int = n.multimesh.instance_count if n is MultiMeshInstance3D else 0
				report.visuals.append({"name": str(n.name), "path": str(n.get_path()), "class": n.get_class(), "p": [p.x,p.y,p.z], "s": [aabb.size.x,aabb.size.y,aabb.size.z], "instances":count})
		if n is CollisionShape3D and Rect2(253,413,41,68).has_point(Vector2(n.global_position.x,n.global_position.z)):
			var p: Vector3 = n.global_position
			var size: Vector3 = n.shape.size if n.shape is BoxShape3D else Vector3.ZERO
			report.bodies.append({"path": str(n.get_path()), "p": [p.x,p.y,p.z], "shape": n.shape.get_class(), "s":[size.x,size.y,size.z]})
	var interactions = world.get("interactions")
	if interactions is Array:
		for interaction in interactions:
			if "VILLA_" in str(interaction) or "ISLAND_LOBBY" in str(interaction):
				report.interactions.append(str(interaction))
	var space: PhysicsDirectSpaceState3D = layer.player.get_world_3d().direct_space_state
	var ids: Array[RID] = [layer.player.get_rid()]
	var floors := [Vector3(279.6,-.68,428.8),Vector3(283.6,-.68,443.8),Vector3(283.6,-.68,458.8),Vector3(279.6,-.68,473.8)]
	for p in floors:
		var q := PhysicsRayQueryParameters3D.create(p+Vector3.UP*.25,p-Vector3.UP*.6,1,ids)
		var hit := space.intersect_ray(q)
		report.floors.append({"point":str(p),"support":not hit.is_empty(),"height":hit.get("position",Vector3.ZERO).y})
	for p in [Vector3(280,1.1,441),Vector3(280,1.1,456),Vector3(276,1.1,471)]:
		var q := PhysicsRayQueryParameters3D.create(p-Vector3(3.5,0,0),p+Vector3(4.45,0,0),1,ids)
		report.open_views.append({"point":str(p),"clear":space.intersect_ray(q).is_empty()})
	if layer.coral_landscape != null:
		report["filtered_visuals"] = layer.coral_landscape.hidden_instances
		report["disabled_room_shapes"] = layer.coral_landscape.cleared_shapes
	FileAccess.open("user://coral_audit.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print("CORAL_AUDIT ",report.visuals.size()," ",report.bodies.size()," ",report.interactions.size())
	get_tree().quit()
