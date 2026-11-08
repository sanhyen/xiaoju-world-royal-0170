extends RefCounted
static func finish(owner:Node,code:int=0)->void:
	owner.set_meta("qa_finished",code)
	if not owner.get_meta("qa_suite_active",false):owner.get_tree().quit(code)
