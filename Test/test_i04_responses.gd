extends SceneTree
var checks := 0
var failures := 0
func _initialize(): _run.call_deferred()
func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1
	print(("PASS: " if value else "FAIL: ") + message)
func _run():
	await load("res://Test/i04_counter_stealth_cases.gd").new().run(self)
	await load("res://Test/i04_paid_skill_region_cases.gd").new().run(self)
	await load("res://Test/i04_zhuangsha_region_cases.gd").new().run(self)
	await load("res://Test/i04_paid_skill_lan_cases.gd").new().run(self)
	await load("res://Test/i04_max_region_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
