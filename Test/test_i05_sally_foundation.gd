extends SceneTree
var checks := 0
var failures := 0

func _initialize(): run.call_deferred()

func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func run():
	await load("res://Test/i05_sally_foundation_cases.gd").new().run(self)
	await load("res://Test/i05_sally_jiegui_cases.gd").new().run(self)
	await load("res://Test/i05_sally_discard_cases.gd").new().run(self)
	await load("res://Test/i05_sally_jiegui_bridge_cases.gd").new().run(self)
	await load("res://Test/i05_sally_damage_cases.gd").new().run(self)
	await load("res://Test/i05_sally_woman_cases.gd").new().run(self)
	await load("res://Test/i05_sally_smoking_state_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
