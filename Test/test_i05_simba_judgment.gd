extends SceneTree
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)
func run():
	await load("res://Test/i05_simba_good_deed_state_cases.gd").new().run(self)
	await load("res://Test/i05_simba_good_deed_flow_cases.gd").new().run(self)
	await load("res://Test/i05_simba_tuanfei_cases.gd").new().run(self)
	await load("res://Test/i05_simba_tuanfei_end_cases.gd").new().run(self)
	await load("res://Test/i05_simba_tuanfei_integration_cases.gd").new().run(self)
	await load("res://Test/i05_simba_emergency_cases.gd").new().run(self)
	await load("res://Test/i05_simba_ai_cases.gd").new().run(self)
	await load("res://Test/i05_simba_lifecycle_cases.gd").new().run(self)
	await load("res://Test/i05_simba_interaction_cases.gd").new().run(self)
	await load("res://Test/i05_simba_public_opening_cases.gd").new().run(self)
	await load("res://Test/i05_simba_judgment_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
