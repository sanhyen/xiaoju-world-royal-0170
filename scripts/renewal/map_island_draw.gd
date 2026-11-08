extends Control
var marker: Node

func _draw() -> void:
	if marker == null or marker.map_view == null:
		return
	if marker.layer.get("sky_expansion")!=null:
		for row in marker.layer.sky_expansion.islands:
			var ring:=PackedVector2Array()
			for i in range(25):
				var a:=TAU*i/24.0
				ring.append(marker.project(Vector2(row.p.x+cos(a)*row.r.x,row.p.z+sin(a)*row.r.y)))
			draw_colored_polygon(ring,Color("90b4a6"));draw_polyline(ring,Color("e6e4cb"),1.2,true)
			if str(row.id) in ["flowers","spring","moon"]:
				draw_string(ThemeDB.fallback_font,marker.project(Vector2(row.p.x,row.p.z))+Vector2(8,-8),row.name,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff4d4"))
		for row in marker.layer.surfaces.paths:
			if row.kind=="legacy":continue
			var route:=PackedVector2Array()
			for p in row.points:route.append(marker.project(Vector2(p.x,p.z)))
			draw_polyline(route,Color("bce7dd") if row.kind=="cloud" else Color("d9ba91"),1.8,true)
	if marker.layer.sky_island != null and marker.layer.sky_island.has_method("contains_land"):
		var outline:=PackedVector2Array()
		for p in marker.layer.sky_island.shore:
			outline.append(marker.project(Vector2(-770-p.y,300-p.x)))
		draw_colored_polygon(outline,Color("748c69"))
		outline.append(outline[0]);draw_polyline(outline,Color("e0d8ac"),1.6,true)
		draw_line(marker.project(Vector2(-655,300)),marker.project(Vector2(-445,300)),Color("e4d5ab"),4.0,true)
		if marker.layer.travel_play != null:
			for line in marker.layer.travel_play.links:
				if line[0].y > 95:continue
				var route := PackedVector2Array()
				for point in line:
					route.append(marker.project(Vector2(point.x,point.z)))
				draw_polyline(route,Color("e6d8b1"),2.6,true)
		draw_circle(marker.project(Vector2(-655,300)),5,Color("fff0c3"))
		return
	for level in range(5):
		var points := PackedVector2Array()
		var rx := 122.0-level*10.0
		var rz := 96.0-level*8.0
		for i in range(25):
			var angle := TAU*i/24.0
			points.append(marker.project(Vector2(-770+cos(angle)*rx,300+sin(angle)*rz)))
		if level == 0:
			draw_colored_polygon(points,Color("748c69"))
		draw_polyline(points,Color("e0d8ac"),1.6,true)
	draw_line(marker.project(Vector2(-662,300)),marker.project(Vector2(-552,300)),Color("e4d5ab"),3.0,true)
	var center: Vector2 = marker.project(Vector2(-770,300))
	draw_circle(center,5,Color("224c48"))
	draw_arc(center,8,0,TAU,24,Color("fff0c3"),2,true)
