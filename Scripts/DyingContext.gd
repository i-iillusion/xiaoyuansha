# 一次濒死窗口的上下文；不是已确认死亡，也不是武将牌持久状态。
# before_death 的规则可通过 effect_chain 访问被暂停的原效果链。
class_name DyingContext
extends RefCounted

enum Stage { RESCUE, BEFORE_DEATH, FINAL_DEATH, FINISHED }

var victim: Player
var killer: Player
var cause: String
var effect_chain: EffectChain
var stage: Stage = Stage.RESCUE
var invalidated: bool = false
# SI-Q5b: once this victim is rescued, retire its rescue frame before
# processing the reclaimed target. The recovered owner is not immune to a
# nested Yudaxi merely because its old caller has not returned yet.
var pending_good_deed_rescue: Player
# Peter Q3: only this rescue frame restricts third-party Peaches. Not a
# permanent victim/source state; self-rescue and source rescue remain legal.
var peter_peach_restricted: bool = false

func _init(target: Player, source: Player, reason: String, chain: EffectChain = null):
	victim = target
	killer = source
	cause = reason
	effect_chain = chain
