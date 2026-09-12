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

func _init(target: Player, source: Player, reason: String, chain: EffectChain = null):
	victim = target
	killer = source
	cause = reason
	effect_chain = chain
