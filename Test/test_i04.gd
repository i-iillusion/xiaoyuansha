extends SceneTree
var checks := 0
var failures := 0
func _initialize(): _run.call_deferred()
func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1
	print(("PASS: " if value else "FAIL: ") + message)
func _run():
	await load("res://Test/i04_topology_cases.gd").new().run(self)
	await load("res://Test/i04_space_cases.gd").new().run(self)
	await load("res://Test/i04_initial_cases.gd").new().run(self)
	await load("res://Test/i04_damage_cases.gd").new().run(self)
	await load("res://Test/i04_death_cases.gd").new().run(self)
	await load("res://Test/i04_rebuild_cases.gd").new().run(self)
	await load("res://Test/i04_hushan_cases.gd").new().run(self)
	await load("res://Test/i04_movement_cases.gd").new().run(self)
	await load("res://Test/i04_gather_cases.gd").new().run(self)
	await load("res://Test/i04_declaration_cases.gd").new().run(self)
	await load("res://Test/i04_aoe_region_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
