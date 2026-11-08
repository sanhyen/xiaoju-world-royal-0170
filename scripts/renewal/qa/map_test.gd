extends Node
var layer: Node
var checks := {}
var original_signals := 0

func _ready() -> void:
	layer.main.call("start_game",false)
	await get_tree().create_timer(2.0).timeout
	await _key(KEY_M)
	await get_tree().create_timer(1.0).timeout
	var modal: Control = layer.main.get("modal")
	var marker: Node = layer.map_marker
	checks["m_opens"] = modal.visible and marker.overlay.visible
	var view: Control = marker.map_view
	if view == null:
		_finish()
		return
	var panel := view.get_parent().get_parent().get_parent() as Control
	var rect_before := panel.get_global_rect()
	var map_before := view.get_global_rect()
	checks["independent_canvas"] = not modal.is_ancestor_of(marker.overlay) and marker.canvas.layer == 35
	checks["marker_projected"] = view.call("point",-770.0,300.0).distance_to(marker.project(Vector2(-770,300))) < 0.01
	checks["marker_visible"] = marker.button.visible and marker.overlay.get_global_rect().encloses(marker.button.get_global_rect())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://T3_map_after.png")
	var prior: Rect2 = view.get("view_rect")
	var mouse := view.global_position+view.size*Vector2(0.65,0.35)
	await _mouse(mouse,MOUSE_BUTTON_WHEEL_UP,true)
	await _mouse(mouse,MOUSE_BUTTON_WHEEL_UP,false)
	await get_tree().create_timer(0.3).timeout
	var zoomed: Rect2 = view.get("view_rect")
	checks["original_zoom"] = zoomed.size != prior.size
	var from := mouse
	await _mouse(from,MOUSE_BUTTON_RIGHT,true)
	var motion := InputEventMouseMotion.new()
	motion.position = from+Vector2(65,30)
	motion.global_position = motion.position
	motion.relative = Vector2(65,30)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	await _mouse(motion.position,MOUSE_BUTTON_RIGHT,false)
	await get_tree().create_timer(0.2).timeout
	var panned: Rect2 = view.get("view_rect")
	checks["original_pan"] = panned.position != zoomed.position
	view.call("reset_view")
	view.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	for sig in view.get_script().get_script_signal_list():
		if sig.args.size() == 1:
			view.connect(sig.name,func(_value): original_signals += 1)
	var hits: Array = view.get("hits")
	if not hits.is_empty():
		await _click(view.global_position+Vector2(hits[0].point))
		await get_tree().create_timer(0.4).timeout
	checks["original_map_click"] = original_signals > 0 or str(view.get("region_id")) != ""
	checks["layout_unchanged"] = panel.get_global_rect() == rect_before and view.get_global_rect() == map_before
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	checks["escape_closes"] = not modal.visible and not marker.overlay.visible
	await _key(KEY_M)
	await get_tree().create_timer(0.6).timeout
	checks["m_reopens"] = modal.visible and marker.overlay.visible
	await _click(marker.button.global_position+marker.button.size*0.5)
	await get_tree().create_timer(2.0).timeout
	var player: CharacterBody3D = layer.player
	checks["island_click_teleport"] = marker.used == 1 and player.global_position.x < -640 and player.global_position.y > 3
	checks["map_closed_after_teleport"] = not modal.visible and not marker.overlay.visible
	checks["arrival_position"] = str(player.global_position)
	_finish()

func _finish() -> void:
	var pass_all := true
	for value in checks.values():
		if value is bool and not value:
			pass_all = false
	checks["pass"] = pass_all
	var f := FileAccess.open("user://map_test.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(checks))
	f.close()
	print("MAP_TEST ",checks)
	get_tree().quit(0 if pass_all else 1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event,true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _mouse(point: Vector2,index: MouseButton,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = index
	event.pressed = down
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _click(point: Vector2) -> void:
	await _mouse(point,MOUSE_BUTTON_LEFT,true)
	await _mouse(point,MOUSE_BUTTON_LEFT,false)
