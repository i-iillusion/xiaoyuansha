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

	await check_selection_recovery(actor, target)
	reset_case()
	game = null
	suite = null

func check_selection_recovery(actor: Player, target: Player):
	# 已支付的发动者不能因为目标快照过期而被静默中断或重复收费。
	reset_case()
	actor.general_name = "杰基·斯特朗"
	actor.hand.append(null)
	var retained = CardBase.create(CardData.CardSubType.PEACH)
	target.hand.append(null)
	target.determined_cards.append(retained)
	var owners: Array = []
	game._hand_discard_override = func(snapshot, count, mandatory):
		owners.append(snapshot.owner)
		check(mandatory and count == 1, "重选仍是同一次强制弃一张")
		if owners.size() == 2:
			target.hand.clear() # 另一项已完成的移动使旧索引过期；不由本次费用回滚。
			return [1]
		return snapshot.defaults(count)
	game._rps_override = func(p): return 0 if p == actor else 2
	await game._execute_campus_dominator(actor, target)
	check(owners == [actor, target, target], "校园霸主只重问过期目标，不重收发动者费用")
	check(actor.hand_size() == 0 and target.hand_size() == 0 and game.deck._discard == [retained], "跨区旧索引不误扣，当前原牌只入弃牌一次")
	check(target.hp == 9, "目标重选成功后外层拼点和伤害继续一次")

	for invalid in [[], [2], [0, 0]]:
		reset_case()
		actor.hand.append(null)
		var attempts: Array = []
		game._hand_discard_override = func(snapshot, count, _mandatory):
			attempts.append(true)
			return invalid if attempts.size() == 1 else snapshot.defaults(count)
		var paid = await game._select_hand_discard(actor, 1, true)
		check(paid and attempts.size() == 2 and actor.hand_size() == 0, "强制空答复/越界/数量错误不能当作自愿拒绝：" + str(invalid))
		check(game.deck._discard.is_empty(), "重选任意牌不生成具体弃牌")

	for mode in ["phase", "actor", "dead", "empty", "ended", "disallowed"]:
		reset_case()
		actor.hand.append(retained)
		var attempts: Array = []
		var permitted: Array[bool] = [true]
		game._hand_discard_override = func(_snapshot, _count, _mandatory):
			attempts.append(true)
			match mode:
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"actor": game.turn_manager.current_player_idx = 1
				"dead": actor.hp = 0
				"empty": actor.hand.clear()
				"ended": game._finish_game("平局", "强制选择中终局")
				"disallowed": permitted[0] = false
			return [0]
		var paid = await game._select_hand_discard(actor, 1, true, func(): return permitted[0])
		check(not paid and attempts.size() == 1, "失效动作停止，不无限重问：" + mode)
		check(game.deck._discard.is_empty(), "失效动作不补扣费用：" + mode)
		check(actor.hand_size() == (0 if mode == "empty" else 1), "保留独立状态变化而不伪造回滚：" + mode)

	reset_case()
	actor.hand.append(null)
	var queries: Array = []
	game._hand_discard_override = func(snapshot, count, _mandatory):
		queries.append(true)
		return snapshot.defaults(count)
	check(not await game._select_hand_discard(actor, 1, true, func(): return false), "动作已失效时不打开窗口")
	check(queries.is_empty() and actor.hand_size() == 1, "前置合法性检查不询问、不收费")
