extends Node
## 天梯通行测试：在各级天梯起点用不同速度上坡，判断是否为「每帧步长 > 跨步极限」。

var layer: Node
var out: Array[String] = []

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var p: CharacterBody3D = layer.player
	p.set("enabled", true)
	await get_tree().create_timer(0.4).timeout

	# 天梯起点（世界坐标 = 岛心 -770 + 本地 x）。每段从天梯东侧 6 m 的台地上起步。
	var starts := [
		["TStair0", Vector3(-654.0, 9.0, 300.0)],
		["TStair1", Vector3(-664.0, 17.0, 300.0)],
		["TStair2", Vector3(-674.0, 25.0, 300.0)],
		["TStair3", Vector3(-684.0, 33.0, 300.0)],
		["TStair4", Vector3(-694.0, 41.0, 300.0)],
	]
	var speeds := [9.36, 6.0, 4.0, 2.5]
	out.append("=== STAIR CLIMB TEST (3s each) ===")
	for st in starts:
		for sp in speeds:
			p.set("walk_speed", float(sp))
			p.global_position = st[1]
			p.velocity = Vector3.ZERO
			await get_tree().create_timer(0.9).timeout
			var y0 := p.global_position.y
			var x0 := p.global_position.x
			p.set("yaw", PI * 0.5)
			_key(true)
			await get_tree().create_timer(2.4).timeout
			_key(false)
			await get_tree().create_timer(0.2).timeout
			out.append("  %-8s speed=%.2f  dx=%.2f  dy=%.2f  end=(%.1f,%.2f)  gain_per_m=%.2f" % [
				str(st[0]), sp, p.global_position.x - x0, p.global_position.y - y0,
				p.global_position.x, p.global_position.y,
				(p.global_position.y - y0) / maxf(0.01, absf(p.global_position.x - x0))])
	p.set("walk_speed", 9.36)

	out.append("")
	out.append("=== SUMMIT STAIR (INNER 52->34, y 44->52) ===")
	for sp in [9.36, 4.0]:
		p.set("walk_speed", float(sp))
		p.global_position = Vector3(-714.0, 48.0, 300.0)
		p.velocity = Vector3.ZERO
		await get_tree().create_timer(0.9).timeout
		var y0b := p.global_position.y
		var x0b := p.global_position.x
		p.set("yaw", PI * 0.5)
		_key(true)
		await get_tree().create_timer(2.0).timeout
		_key(false)
		out.append("  speed=%.2f dx=%.2f dy=%.2f end=(%.1f,%.2f)" % [
			sp, p.global_position.x - x0b, p.global_position.y - y0b,
			p.global_position.x, p.global_position.y])
	p.set("walk_speed", 9.36)

	var f := FileAccess.open("user://stair_test.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("STAIR_TEST_DONE")
	get_tree().quit()

func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
