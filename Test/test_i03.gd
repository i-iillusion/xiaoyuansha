extends SceneTree
var checks := 0
var failures := 0
func _initialize(): _run.call_deferred()
func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1
	print(("PASS: " if value else "FAIL: ") + message)
func _run():
	await load("res://Test/i03_state_cases.gd").new().run(self)
	await load("res://Test/i03_actor_identity_cases.gd").new().run(self)
	await load("res://Test/i03_source_disappearance_cases.gd").new().run(self)
	await load("res://Test/i03_opening_cases.gd").new().run(self)
	await load("res://Test/i03_medicine_cases.gd").new().run(self)
	await load("res://Test/i03_egg_cases.gd").new().run(self)
	await load("res://Test/i03_summon_cases.gd").new().run(self)
	await load("res://Test/i03_roar_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
