extends Node

var layer: Node
var p: CharacterBody3D

func key(code: Key,down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _ready() -> void:
	p = layer.player
	p.set("enabled",true)
	await get_tree().create_timer(.4).timeout
	var results: Array = []
	var paths: Array[PackedVector3Array] = []
	var tags: Array[String] = []
	if OS.get_cmdline_user_args().has("--ridge-walk"):
		var records: Array = layer.world.get("spec").bay_layout.roads
		var by_id := {}
		for r in records:
			by_id[r.id] = r
		for limits in [Vector2i(34,39),Vector2i(45,49)]:
			var path := PackedVector3Array()
			for index in range(limits.x,limits.y+1):
				for point in by_id["landscape150_cherry_loop_%03d"%index].points:
					var pos := Vector3(point[0],point[1],point[2])
					if path.is_empty() or path[-1].distance_to(pos)>.005:
						path.append(pos)
			paths.append(path)
			tags.append("cherry_%d"%limits.x)
	else:
		for i in range(3):
			if OS.get_cmdline_user_args().has("--third-link-only") and i!=2:
				continue
			paths.append(layer.travel_play.links[i])
			tags.append("bridge_%d"%(i+1))
	for i in range(paths.size()):
		var path := paths[i]
		layer.travel_play.release_motion_for_travel()
		p.set_physics_process(false)
		layer.teleport(path[0]+Vector3.UP*.20)
		await get_tree().create_timer(2.5 if tags[i].begins_with("cherry") else .4).timeout
		p.set_physics_process(true)
		await get_tree().create_timer(.24).timeout
		var start := Time.get_ticks_msec()
		var reached := 0
		for j in range(1,path.size()):
			var end := path[j]
			var deadline := Time.get_ticks_msec()+27000
			var last := p.global_position
			var idle := 0
			while Time.get_ticks_msec()<deadline:
				var d := end-p.global_position
				if Vector2(d.x,d.z).length()<.85:
					reached += 1
					break
				p.set("yaw",atan2(-d.x,-d.z))
				key(KEY_SHIFT,true)
				key(KEY_W,true)
				await get_tree().create_timer(.08).timeout
				idle = idle+1 if last.distance_to(p.global_position)<.04 else 0
				last = p.global_position
				if idle>14 or p.global_position.y<-1.6:
					break
			if reached<j:
				break
		key(KEY_W,false)
		key(KEY_SHIFT,false)
		var passed: bool = reached==path.size()-1 and p.global_position.distance_to(path[-1])<1.3
		var collisions: Array = []
		if not passed:
			for k in range(p.get_slide_collision_count()):
				var hit := p.get_slide_collision(k)
				collisions.append([str(hit.get_collider().get_path()),str(hit.get_normal()),str(hit.get_position())])
		results.append({"route":tags[i],"pass":passed,"reached":reached,"required":path.size()-1,"seconds":(Time.get_ticks_msec()-start)*.001,"pos":str(p.global_position),"collisions":collisions})
		print("LINK_WALK ",results[-1])
	FileAccess.open("user://link_walk.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	get_tree().quit(0 if results.all(func(r):return r.pass) else 1)
