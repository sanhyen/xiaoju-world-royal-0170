extends Node
## Flight owns Space/Esc before the legacy character can consume the event.
var travel:Node
func _input(event:InputEvent)->void:
	if not is_instance_valid(travel) or not travel.in_flight:return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE]:
		travel._input(event)
