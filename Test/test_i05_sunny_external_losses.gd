# Mandatory standalone gate; existing Sunny reaction suite remains intact.
extends SceneTree
const Losses=preload("res://Test/i05_sunny_external_loss_cases.gd")
const StrikeBinding=preload("res://Test/i05_strike_declaration_awakening_cases.gd")
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await Losses.new().run(self)
	await StrikeBinding.new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
