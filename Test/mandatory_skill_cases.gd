# A2b-4：多方强制弃牌与【拍胸脯】来源拒绝支付。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "强制/拒绝选牌：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._rps_override = Callable()
	game._zhuangbi_again_override = Callable()
	game._paixiong_override = Callable()

func run(host):
	suite = host
	game = host.game
	var actor = game.players[0]
	var target = game.players[1]

	reset_case()
	actor.general_name = "杰基·斯特朗"
	actor.hand.append(null)
	target.hand.append(null)
	var mandatory_flags: Array[bool] = []
	game._hand_discard_override = func(snapshot, count, mandatory):
		mandatory_flags.append(mandatory)
		return snapshot.defaults(count)
	game._rps_override = func(p): return 0 if p == actor else 2
	await game._execute_campus_dominator(actor, target)
	check(mandatory_flags == [true, true], "校园霸主双方确认后都不能拒绝弃牌")
	check(actor.hand_size() == 0 and target.hand_size() == 0, "校园霸主可支付双方通常持有的任意牌")
	check(game.deck._discard.is_empty() and target.hp == 9, "任意牌不虚构弃牌实体，拼点伤害正常结算")

	reset_case()
	var second = game.players[2]
	actor.general_name = "史蒂芬·彼特先斯"
	actor.hand.append(null)
	target.hand.append(null)
	second.hand.append(null)
	mandatory_flags.clear()
	game._hand_discard_override = func(snapshot, count, mandatory):
		mandatory_flags.append(mandatory)
		return snapshot.defaults(count)
	game._rps_override = func(p): return 0 if p == actor else 2
	game._zhuangbi_again_override = func(): return false
	await game._execute_zhuangbi([target, second])
	check(mandatory_flags == [true, true, true], "装逼发动者及所有目标都不能拒绝弃牌")
	check(actor.hand_size() == 0 and target.hand_size() == 0 and second.hand_size() == 0, "装逼多方均可支付任意牌")
	check(game.deck._discard.is_empty() and target.hp == 9 and second.hp == 9, "多方任意牌支付后依次结算拼点伤害")

	reset_case()
	actor.hand.append(null)
	target.general_name = "史蒂芬·彼特先斯"
	game._paixiong_override = func(): return true
	game._hand_discard_override = func(_snapshot, count, mandatory):
		check(count == 1 and not mandatory, "拍胸脯的伤害来源可拒绝一张牌费用")
		return []
	await game._deal_damage(actor, target, 3, EffectChain.DamageType.PHYSICAL)
	check(target.hp == 10 and actor.hand_size() == 1, "来源拒绝弃牌时防止整次三点伤害且不扣牌")

	reset_case()
	actor.hand.append(null)
	target.general_name = "史蒂芬·彼特先斯"
	game._paixiong_override = func(): return true
	game._hand_discard_override = func(snapshot, count, mandatory):
		check(count == 1 and not mandatory, "拍胸脯一次多点伤害只需选择一张牌")
		return snapshot.defaults(count)
	await game._deal_damage(actor, target, 3, EffectChain.DamageType.PHYSICAL)
	check(actor.hand_size() == 0 and game.deck._discard.is_empty(), "来源可用一张任意牌支付且不制造具体牌")
	check(target.hp == 7, "支付一张后整次三点伤害正常造成")

	reset_case()
	game = null
	suite = null
