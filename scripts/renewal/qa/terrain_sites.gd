extends Node
var layer: Node

func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	var buckets := {}
	var sites: Array = []
	for node in layer.world.find_children("FarStrata_*","MeshInstance3D",true,false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i in range(0,v.size(),3):
				var normal := (mi.global_basis*n[i]).normalized()
				if absf(normal.y) >= 0.81915:
					continue
				var center := mi.to_global((v[i]+v[mini(i+1,v.size()-1)]+v[mini(i+2,v.size()-1)])/3.0)
				if center.y <= 4:
					continue
				var key := "alpha=%.2f ny=%.1f" % [c[i].a,absf(normal.y)]
				buckets[key] = int(buckets.get(key,0))+1
				if c[i].a > 0.85 and sites.size()<150:
					sites.append({"node":str(mi.name),"position":[center.x,center.y,center.z],"normal":[normal.x,normal.y,normal.z],"color":[c[i].r,c[i].g,c[i].b,c[i].a]})
	var result := {"buckets":buckets,"natural_sites":sites}
	var f := FileAccess.open("user://terrain_sites.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("TERRAIN_SITES ",buckets," candidates=",sites.size())
	get_tree().quit()
