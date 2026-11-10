extends SceneTree
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await load("res://Test/i05_peter_card_cases.gd").new().run(self)
	await load("res://Test/i05_peter_skill_cases.gd").new().run(self)
	await load("res://Test/i05_peter_counter_cases.gd").new().run(self)
	await load("res://Test/i05_public_opening_cases.gd").new().run(self)
	await load("res://Test/i05_david_farming_cases.gd").new().run(self)
	await load("res://Test/i05_david_upgrade_cases.gd").new().run(self)
	await load("res://Test/i05_david_nullification_cases.gd").new().run(self)
	await load("res://Test/i05_david_peach_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_filming_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_identity_state_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_spy_cases.gd").new().run(self)
	await load("res://Test/i05_extra_draw_batch_cases.gd").new().run(self)
	await load("res://Test/i05_deferred_draw_resource_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_sage_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_card_draw_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_strike_draw_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
