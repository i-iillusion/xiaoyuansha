# New mandatory suite. Existing effect modules and their limits stay unchanged.
extends SceneTree
const ResponseDraw=preload("res://Test/i05_sunny_corruption_response_draw_cases.gd")
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await ResponseDraw.new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
