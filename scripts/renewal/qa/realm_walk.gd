extends Node

var layer: Node
var p: CharacterBody3D
var island: Node3D
var checks: Array = []

func _key(code: Key,pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func _walk(point: Vector3) -> bool:
	for i in range(170):
		var d := point-p.global_position
		if Vector2(d.x,d.z).length() < .6:
			_key(KEY_W,false)
			return absf(d.y) < 1.25
		p.set("yaw",atan2(-d.x,-d.z))
		_key(KEY_W,true)
		await get_tree().create_timer(.05).timeout
	_key(KEY_W,false)
	return false

func _stamp() -> void:
	_key(KEY_Y,true)
	await get_tree().process_frame
	_key(KEY_Y,false)

func _follow(route: Array) -> bool:
	for point in route:
		var goal: Vector3 = island.wp(point[0],point[1],point[2])
		var ok := await _walk(goal)
		checks.append({"target":str(point),"reached":ok,"at":str(p.global_position)})
		if not ok:
			return false
	return true

func _ready() -> void:
	p = layer.player
	island = layer.sky_island
	var realm: Node3D = island.celestial_realm
	var formation: Node3D = realm.court.get_node("StarFormation")
	var args := OS.get_cmdline_user_args()
	if args.has("--realm-reopen"):
		var restored: bool = realm.stamps.size()==3 and realm.shrine_awakened and formation.visible
		print("REALM_REOPEN ",restored)
		load("res://scripts/renewal/qa/completion.gd").finish(self,0 if restored else 1)
		return
	var initial: Dictionary = realm.stamps.duplicate()
	var compatible := initial.size()==2 and initial.has("gate") and initial.has("spring") if args.has("--realm-existing") else initial.is_empty()
	p.set("enabled",true)
	layer.teleport(island.wp(0,10,48.2))
	await get_tree().create_timer(.75).timeout
	await _stamp()
	var walk := await _follow([[13,14.5,48],[28,14.5,48],[33,25,48],[48,36,48]])
	if walk:
		await _stamp()
		walk = await _follow([[41,35,48],[34,38.5,48],[34,43.5,48.68],[34,67,48.68],[34,73.5,48.49],[35,79.6,48]])
	var rang_bell := false
	if walk:
		await _stamp()
		await get_tree().create_timer(.18).timeout
		var bell: Node3D = realm.court.get_node("CloudChime")
		rang_bell = absf(bell.rotation.z)>.03 and realm.court.get("_chime") is AudioStreamWAV
		walk = await _follow([[34,76.3,48],[34,72,48.68],[34,47,48.68],[34,39.2,48],
			[33,25,48],[28,14.5,48],[13,14.5,48],[0,21,48],[0,46,48],[0,77,64],[0,90,64],[0,92.6,64]])
	var gated := false
	if walk:
		await _stamp()
		gated = realm.stamps.size()==2 and not realm.shrine_awakened and not formation.visible
		walk = await _follow([[0,79.5,64],[16,78,64]])
	if walk:
		await _stamp()
		walk = await _follow([[0,79.5,64],[0,92.6,64]])
	if walk:
		await _stamp()
		await get_tree().create_timer(1.05).timeout
	var saved = JSON.parse_string(FileAccess.get_file_as_string(realm.SAVE))
	var written: bool = saved is Dictionary and saved.get("shrine_awakened",false) and saved.get("stamps",{}).size()==3
	var awake: bool = realm.shrine_awakened and formation.visible and formation.scale.is_equal_approx(Vector3.ONE)
	var passed: bool = compatible and walk and rang_bell and gated and awake and written
	var result := {"pass":passed,"waypoints":checks,"stamps":realm.stamps,"initial_stamps":initial,
		"bell":rang_bell,"requires_three_seals":gated,"formation":awake,"saved":written}
	FileAccess.open("user://realm_walk.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("REALM_WALK ",JSON.stringify(result))
	load("res://scripts/renewal/qa/completion.gd").finish(self,0 if passed else 1)
