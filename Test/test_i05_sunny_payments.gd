# Mandatory companion gate: original Q12-Q16 parent modules, unchanged.
extends SceneTree
const PaymentAwakening=preload("res://Test/i05_sunny_payment_awakening_cases.gd")
const SharedPayment=preload("res://Test/i05_sunny_shared_payment_cases.gd")
const OtherUse=preload("res://Test/i05_sunny_other_use_payment_cases.gd")
const OtherResponse=preload("res://Test/i05_sunny_other_response_payment_cases.gd")
const TargetBinding=preload("res://Test/i05_awakening_target_binding_cases.gd")
const RescueAwakening=preload("res://Test/i05_sunny_rescue_awakening_cases.gd")
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await PaymentAwakening.new().run(self)
	await SharedPayment.new().run(self)
	await OtherUse.new().run(self)
	await OtherResponse.new().run(self)
	await TargetBinding.new().run(self)
	await RescueAwakening.new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
