extends RefCounted
## 相交道路使用不同的毫米级视觉高度，保持三组网格和原碰撞。
## 只给相交道路分层，避免按 480 个 ID 累积出半米高差。

static func assign(roads: Array) -> Dictionary:
	var prepared: Array = []
	for road in roads:
		if not road is Dictionary:
			continue
		var points: Array[Vector2] = []
		for p in road.get("points",[]):
			if p is Array and p.size()>=3:
				points.append(Vector2(float(p[0]),float(p[2])))
		if points.size()<2:
			continue
		var width := float(road.get("width",0))
		if width<0.1:
			continue
		var bounds := Rect2(points[0],Vector2.ZERO)
		for p in points:
			bounds = bounds.expand(p)
		prepared.append({"id":str(road.get("id","")),"points":points,"radius":width*0.5+0.15,"bounds":bounds.grow(width*0.5+0.15)})
	prepared.sort_custom(func(a,b):return a.id<b.id)
	var ranks := {}
	var edges := 0
	var max_rank := 0
	for i in range(prepared.size()):
		var occupied := {}
		for j in range(i):
			if not prepared[i].bounds.intersects(prepared[j].bounds,true):
				continue
			if _overlap(prepared[i],prepared[j]):
				occupied[ranks[prepared[j].id]] = true
				edges += 1
		var rank := 0
		while occupied.has(rank):
			rank += 1
		ranks[prepared[i].id] = rank
		max_rank = maxi(max_rank,rank)
	var step := minf(0.0015,0.012/maxf(float(max_rank),1.0))
	return {"ranks":ranks,"roads":prepared.size(),"edges":edges,"max_rank":max_rank,"step_m":step,"max_lift_m":step*max_rank}

static func _overlap(a: Dictionary,b: Dictionary) -> bool:
	var pa: Array = a.points
	var pb: Array = b.points
	var radius := float(a.radius)+float(b.radius)
	for i in range(pa.size()-1):
		for j in range(pb.size()-1):
			if Geometry2D.segment_intersects_segment(pa[i],pa[i+1],pb[j],pb[j+1]) != null:
				return true
			for p in [pa[i],pa[i+1]]:
				if Vector2(p).distance_to(Geometry2D.get_closest_point_to_segment(p,pb[j],pb[j+1]))<radius:
					return true
			for p in [pb[j],pb[j+1]]:
				if Vector2(p).distance_to(Geometry2D.get_closest_point_to_segment(p,pa[i],pa[i+1]))<radius:
					return true
	return false
