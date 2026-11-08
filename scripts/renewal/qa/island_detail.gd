extends Node
var layer: Node

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	var island: Node3D = layer.sky_island
	var result := {}
	var meshes: Array[Node] = island.find_children("*","MeshInstance3D",true,false)
	var finite := true
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var bounds := mi.global_transform*mi.mesh.get_aabb()
		finite = finite and bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length()<1000
	result["finite_mesh_bounds"] = finite
	result["collision_bodies"] = island.get("_bodies").size()
	result["foam_present"] = island.find_child("WaterfallFoamMesh",true,false) != null
	result["terrace_details_present"] = island.find_child("TerraceDetailsMesh",true,false) != null
	var space := island.get_world_3d().direct_space_state
	var a: Vector3 = island.get("_car_a")
	var b: Vector3 = island.get("_car_b")
	var collisions: Array = []
	var clearance := INF
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8,3.4,2.8)
	for i in range(121):
		var u := float(i)/120.0
		var local := a.lerp(b,u)
		local.y -= sin(u*PI)*2.0
		var world := island.to_global(local)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = world+Vector3(0,-0.7,0)
		query.exclude = [layer.player.get_rid()]
		var hits := space.intersect_shape(query,8)
		for hit in hits:
			collisions.append({"u":u,"collider":str(hit.collider.name)})
		var ray := PhysicsRayQueryParameters3D.create(world,world-Vector3(0,180,0))
		ray.exclude = [layer.player.get_rid()]
		var floor_hit := space.intersect_ray(ray)
		if not floor_hit.is_empty():
			clearance = minf(clearance,world.y-2.4-Vector3(floor_hit.position).y)
	result["cable_samples"] = 121
	result["cable_collision_hits"] = collisions
	result["cable_min_floor_clearance"] = clearance
	result["pass"] = finite and collisions.is_empty() and clearance>0 and result.foam_present and result.terrace_details_present
	var f := FileAccess.open("user://island_detail.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("ISLAND_DETAIL ",result)
	get_tree().quit(0 if result["pass"] else 1)
