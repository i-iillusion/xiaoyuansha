# New mandatory suite. Existing effect modules and their limits stay unchanged.
extends SceneTree
const ResponseDraw=preload("res://Test/i05_sunny_corruption_response_draw_cases.gd")
const StageDraw=preload("res://Test/i05_sunny_corruption_stage_draw_cases.gd")
const DeathDraw=preload("res://Test/i05_sunny_corruption_death_draw_cases.gd")
const YudaxiReward=preload("res://Test/i05_sunny_yudaxi_reward_exemption_cases.gd")
const PaymentAwakening=preload("res://Test/i05_sunny_payment_awakening_cases.gd")
const SharedPayment=preload("res://Test/i05_sunny_shared_payment_cases.gd")
const OtherUse=preload("res://Test/i05_sunny_other_use_payment_cases.gd")
const OtherResponse=preload("res://Test/i05_sunny_other_response_payment_cases.gd")
const TargetBinding=preload("res://Test/i05_awakening_target_binding_cases.gd")
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func run():
	await load("res://Test/i05_sunny_filming_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_identity_state_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_spy_cases.gd").new().run(self)
	await load("res://Test/i05_extra_draw_batch_cases.gd").new().run(self)
	await load("res://Test/i05_deferred_draw_resource_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_sage_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_card_draw_cases.gd").new().run(self)
	await load("res://Test/i05_sunny_corruption_strike_draw_cases.gd").new().run(self)
	await ResponseDraw.new().run(self)
	await StageDraw.new().run(self)
	await DeathDraw.new().run(self)
	await YudaxiReward.new().run(self)
	await PaymentAwakening.new().run(self)
	await SharedPayment.new().run(self)
	await OtherUse.new().run(self)
	await OtherResponse.new().run(self)
	await TargetBinding.new().run(self)
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
