extends "res://scripts/bay_boats.gd"
## Preserve the compiled controller's driving, docking and camera lifecycle.
var renewal_river_owner:Node

func water_at(p:Vector3)->Dictionary:
	if is_instance_valid(renewal_river_owner):
		var channel:Dictionary=renewal_river_owner.profile(Vector2(p.x,p.z),false)
		if not channel.is_empty():return {"y":float(channel.water),"depth":float(channel.depth),"width":float(channel.half)*2.0}
	return super.water_at(p)

func shore_point()->Vector3:
	if is_instance_valid(renewal_river_owner):
		var p:CharacterBody3D=renewal_river_owner.layer.player
		if not renewal_river_owner.profile(Vector2(p.global_position.x,p.global_position.z),false).is_empty():
			return renewal_river_owner.river_shore(p)
	return super.shore_point()

func shore_hint()->String:
	if is_instance_valid(renewal_river_owner):
		var p:Vector3=renewal_river_owner.layer.player.global_position
		if not renewal_river_owner.profile(Vector2(p.x,p.z),false).is_empty():return "浅溪航行 · 空格减速，F 靠岸下船"
	return super.shore_hint()

func dock()->bool:
	if not is_instance_valid(renewal_river_owner):return await super.dock()
	var p:CharacterBody3D=renewal_river_owner.layer.player
	if renewal_river_owner.profile(Vector2(p.global_position.x,p.global_position.z),false).is_empty():return await super.dock()
	if absf(speed)>.8:
		m.call("notify","请先按空格减速，再按 F 停泊。")
		return false
	var shore:Vector3=renewal_river_owner.river_shore(p)
	if shore==Vector3.INF:
		m.call("notify","附近没有净空足够的浅岸，请稍向岸边靠近。")
		return false
	# Native mooring records the vessel; native release restores camera/pose.
	await moor_current(shore)
	await leave_for_travel()
	p.global_position=shore;p.velocity=Vector3.ZERO;p.call("reset_jump_state")
	renewal_river_owner.layer.travel_play.release_motion_for_travel()
	p.set("enabled",true);p.set_physics_process(true)
	m.call("notify","已停泊浅岸，可步行涉水；靠近停泊船可再次登船。")
	return true
