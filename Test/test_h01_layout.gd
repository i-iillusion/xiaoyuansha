extends SceneTree
var checks := 0
var failures := 0
func _initialize(): _run.call_deferred()
func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1
	print(("PASS: " if value else "FAIL: ") + message)
func _run():
	load("res://Test/ai_test_clock.gd").install(self)
	await load("res://Test/h01_layout_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
