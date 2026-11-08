extends RefCounted
## 场地清障：把落在指定矩形内的植被/装饰实例从 MultiMesh 中剔除。
## 用于台地、建筑基底等需要平整的施工场地；只删除装饰实例，不删除碰撞与地形。

static func clear_rect(world: Node, center: Vector3, size: Vector2, y_min: float, y_max: float) -> int:
	var removed := 0
	if world == null:
		return 0
	var nodes := world.find_children("*", "MultiMeshInstance3D", true, false)
	for n in nodes:
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		if mm.instance_count == 0:
			continue
		var xf := mmi.global_transform
		var keep: Array[int] = []
		var changed := false
		for i in range(mm.instance_count):
			var wp := xf * mm.get_instance_transform(i).origin
			if wp.x > center.x - size.x * 0.5 and wp.x < center.x + size.x * 0.5 \
				and wp.z > center.z - size.y * 0.5 and wp.z < center.z + size.y * 0.5 \
				and wp.y > y_min and wp.y < y_max:
				changed = true
			else:
				keep.append(i)
		if not changed:
			continue
		var nm := MultiMesh.new()
		nm.transform_format = mm.transform_format
		nm.use_colors = mm.use_colors
		nm.use_custom_data = mm.use_custom_data
		nm.mesh = mm.mesh
		nm.instance_count = keep.size()
		for j in range(keep.size()):
			var src := keep[j]
			nm.set_instance_transform(j, mm.get_instance_transform(src))
			if mm.use_colors:
				nm.set_instance_color(j, mm.get_instance_color(src))
			if mm.use_custom_data:
				nm.set_instance_custom_data(j, mm.get_instance_custom_data(src))
		mmi.multimesh = nm
		removed += mm.instance_count - keep.size()
	return removed

## 批量版：一次遍历处理多个场地矩形，避免每栋都全图扫描。
## rects 元素：{"center":Vector3, "size":Vector2, "y_min":float, "y_max":float}
static func clear_rects(world: Node, rects: Array, name_filter: Array = []) -> int:
	var removed := 0
	if world == null or rects.size() == 0:
		return 0
	var nodes := world.find_children("*", "MultiMeshInstance3D", true, false)
	for n in nodes:
		if name_filter.size() > 0:
			var low := str(n.name).to_lower()
			var hit_name := false
			for f in name_filter:
				if low.contains(str(f)):
					hit_name = true
					break
			if not hit_name:
				continue
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
			continue
		var mm := mmi.multimesh
		var xf := mmi.global_transform
		var keep: Array[int] = []
		var changed := false
		for i in range(mm.instance_count):
			var wp := xf * mm.get_instance_transform(i).origin
			var hit := false
			for r in rects:
				var c: Vector3 = r["center"]
				var sz: Vector2 = r["size"]
				if wp.x > c.x - sz.x * 0.5 and wp.x < c.x + sz.x * 0.5 \
					and wp.z > c.z - sz.y * 0.5 and wp.z < c.z + sz.y * 0.5 \
					and wp.y > float(r["y_min"]) and wp.y < float(r["y_max"]):
					hit = true
					break
			if hit:
				changed = true
			else:
				keep.append(i)
		if not changed:
			continue
		var nm := MultiMesh.new()
		nm.transform_format = mm.transform_format
		nm.use_colors = mm.use_colors
		nm.use_custom_data = mm.use_custom_data
		nm.mesh = mm.mesh
		nm.instance_count = keep.size()
		for j in range(keep.size()):
			var src := keep[j]
			nm.set_instance_transform(j, mm.get_instance_transform(src))
			if mm.use_colors:
				nm.set_instance_color(j, mm.get_instance_color(src))
			if mm.use_custom_data:
				nm.set_instance_custom_data(j, mm.get_instance_custom_data(src))
		mmi.multimesh = nm
		removed += mm.instance_count - keep.size()
	return removed
