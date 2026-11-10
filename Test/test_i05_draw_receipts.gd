# Optional focused diagnostic. Both modules also run once in mandatory effects.
extends SceneTree
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await load("res://Test/i05_extra_draw_batch_cases.gd").new().run(self)
	await load("res://Test/i05_deferred_draw_resource_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_sage_cases.gd").new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
