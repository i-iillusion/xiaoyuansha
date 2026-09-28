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
	game._awaken_pick_override = Callable()

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
	# 本例只验证装逼支付；使用已觉醒角色，避免空手时排入延迟觉醒，
	# 在后续案例让出帧后给已 reset 的同一 Player 补牌、污染跨例断言。
	actor.awoken = true
	actor.awake_choice = 1
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

	await check_paixiong_result_boundaries(actor, target)
	await check_paid_rps_context(actor, target, second)
	await check_zhuangbi_last_card_awaken(actor, target)

	await check_selection_recovery(actor, target)
	await check_context_invalidation(actor, target)
	reset_case()
	game = null
	suite = null

func check_zhuangbi_last_card_awaken(actor: Player, target: Player):
	for use_concrete in [false, true]:
		reset_case()
		actor.general_name = "史蒂芬·彼特先斯"
		var card: CardBase = null
		if use_concrete:
			card = CardBase.create(CardData.CardSubType.PEACH)
			actor.determined_cards.append(card)
		else:
			actor.hand.append(null)
		target.hand.append(null)
		var order: Array[String] = []
		game._awaken_pick_override = func():
			order.append("awaken")
			check(target.hand_size() == 1, "支付最后一张后先觉醒，目标尚未弃牌")
			return 2
		game._hand_discard_override = func(snapshot, count, mandatory):
			if snapshot.owner == target:
				order.append("target_pay")
				check(actor.awoken and actor.awake_choice == 2 and actor.hand_size() == 2,
					"目标支付前已完成觉醒并摸两张任意牌")
			return snapshot.defaults(count)
		game._rps_override = func(p):
			order.append("rps")
			return 0 if p == actor else 2
		game._zhuangbi_again_override = func(): return false
		await game._execute_zhuangbi([target])
		check(order == ["awaken", "target_pay", "rps", "rps"], "最后手牌费用、觉醒、目标费用及拼点按顺序结算")
		check(actor.max_hp == 9 and actor.hp == 9 and actor.awoken and actor.awake_choice == 2,
			"觉醒只结算一次，失去一点体力上限并记录选择")
		check(actor.hand_size() == 2 and target.hand_size() == 0 and target.hp == 9,
			"觉醒所摸手牌保留，已付目标费用及拼点伤害继续")
		check(game.deck._discard == ([card] if use_concrete else []),
			"具体原牌只弃一次；任意牌支付不虚构实体")

func check_paixiong_result_boundaries(actor: Player, target: Player):
	# 非空过期答复重选；具体牌只以原实例入弃牌堆一次。
	reset_case()
	target.general_name = "史蒂芬·彼特先斯"
	actor.awoken = true
	var concrete = CardBase.create(CardData.CardSubType.PEACH)
	actor.determined_cards.append(concrete)
	game._paixiong_override = func(): return true
	var attempts: Array = []
	game._hand_discard_override = func(snapshot, count, _mandatory):
		attempts.append(true)
		return [99] if attempts.size() == 1 else snapshot.defaults(count)
	await game._deal_damage(actor, target, 3, EffectChain.DamageType.PHYSICAL)
	check(attempts.size() == 2 and actor.hand_size() == 0 and game.deck._discard == [concrete], "拍胸脯旧答复重问，具体原牌只弃一次")
	check(target.hp == 7, "重选支付后完整三点伤害继续")

	# 同值恢复也属于旧动作；不能在日志中称作主动拒绝或防止伤害。
	reset_case()
	target.general_name = "史蒂芬·彼特先斯"
	actor.hand.append(null)
	game._paixiong_override = func(): return true
	game._hand_discard_override = func(snapshot, count, _mandatory):
		game.turn_manager.current_phase = TurnManager.Phase.END
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		return snapshot.defaults(count)
	var chain = game._new_damage_chain(actor, target, null, 3, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	check(chain.is_cancelled and not chain.damage.committed and target.hp == 10, "动作过期中止当前链而非技能防伤")
	check(actor.hand_size() == 1 and game.deck._discard.is_empty(), "过期选择不误扣来源手牌")
	actor.hand.append(null)
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	check(await game._select_hand_discard(actor, 1, true) and actor.hand_size() == 1, "过期伤害后下一合法选择仍能支付")

	# 来源在选择期间最终死亡，原伤害继续结算且改为无来源。
	reset_case()
	target.general_name = "史蒂芬·彼特先斯"
	actor.hand.append(null)
	game._paixiong_override = func(): return true
	game._hand_discard_override = func(snapshot, count, _mandatory):
		actor.mark_dead()
		return snapshot.defaults(count)
	chain = game._new_damage_chain(actor, target, null, 3, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	check(chain.damage.committed and target.hp == 7 and chain.damage.source == null, "来源最终死亡后剩余三点伤害无来源结算")
	check(actor.hand_size() == 1 and game.deck._discard.is_empty(), "来源死亡时不冒称已付费或主动拒绝")

	# 失牌导致无法支付时，已发动技能按原文防止整次伤害。
	reset_case()
	target.general_name = "史蒂芬·彼特先斯"
	actor.hand.append(null)
	game._paixiong_override = func(): return true
	game._hand_discard_override = func(snapshot, count, _mandatory):
		actor.hand.clear()
		return snapshot.defaults(count)
	chain = game._new_damage_chain(actor, target, null, 3, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	check(chain.is_cancelled and not chain.damage.committed and target.hp == 10, "等待期间无法支付时防止整次伤害")

func check_paid_rps_context(actor: Player, target: Player, second: Player):
	# 双方已付费后，第一名出拳者的旧回合答复不应继续询问对手。
	reset_case()
	actor.general_name = "杰基·斯特朗"
	actor.hand.append(null)
	var retained = CardBase.create(CardData.CardSubType.PEACH)
	target.determined_cards.append(retained)
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	var choices: Array = []
	game._rps_override = func(p):
		choices.append(p)
		game.turn_manager.current_phase = TurnManager.Phase.END
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		return 0
	await game._execute_campus_dominator(actor, target)
	check(choices == [actor] and actor.hp == 10 and target.hp == 10, "校园霸主已付费后旧出拳不继续问对手或造成伤害")
	check(actor.hand_size() == 0 and target.hand_size() == 0 and game.deck._discard == [retained], "旧拼点中止不回滚已付双方费用或复制原牌")

	# 下一次合法发动不受旧拼点污染。
	actor.hand.append(null)
	target.hand.append(null)
	game._rps_override = func(p): return 0 if p == actor else 2
	await game._execute_campus_dominator(actor, target)
	check(target.hp == 9 and actor.hand_size() == 0 and target.hand_size() == 0, "旧校园霸主中止后下一次合法拼点仍可结算")

	# 默认平局须重猜；重猜期间行动者离开又恢复则旧拼点停止。
	reset_case()
	actor.general_name = "杰基·斯特朗"
	actor.hand.append(null)
	target.hand.append(null)
	choices.clear()
	game._rps_override = func(p):
		choices.append(p)
		if choices.size() == 3:
			game.turn_manager.current_player_idx = 1
			game.turn_manager.current_player_idx = 0
		return 0
	await game._execute_campus_dominator(actor, target)
	check(choices == [actor, target, actor] and actor.hp == 10 and target.hp == 10, "校园霸主平局重猜时旧行动者答复不继续结算")
	check(actor.hand_size() == 0 and target.hand_size() == 0, "平局重猜中止仍保留双方已付费用")

	# 装逼所有人已付费；第二人出拳期间目标死亡，不继续下一人或计算输赢。
	reset_case()
	actor.general_name = "史蒂芬·彼特先斯"
	actor.awoken = true # 此例隔离异步觉醒，另立组合回归。
	actor.hand.append(null)
	target.determined_cards.append(retained)
	second.hand.append(null)
	choices.clear()
	game._rps_override = func(p):
		choices.append(p)
		if p == target:
			target.mark_dead()
		return 0 if p == actor else 2
	await game._execute_zhuangbi([target, second])
	check(choices == [actor, target] and actor.hp == 10 and second.hp == 10, "装逼目标在拼点等待时死亡，不继续其他目标或伤害")
	check(actor.hand_size() == 0 and target.hand_size() == 0 and second.hand_size() == 0 and game.deck._discard == [retained], "已支付三方费用不回滚，具体原牌仅弃一次")

func check_context_invalidation(actor: Player, target: Player):
	for skill in ["campus", "zhuangbi"]:
		for transition in ["phase_return", "actor_return"]:
			reset_case()
			actor.general_name = "杰基·斯特朗" if skill == "campus" else "史蒂芬·彼特先斯"
			actor.awoken = true # 支付案例不引入跨例延迟觉醒。
			actor.hand.append(null)
			var retained = CardBase.create(CardData.CardSubType.PEACH)
			target.determined_cards.append(retained)
			var queries: Array = []
			var rps_calls: Array = []
			game._hand_discard_override = func(snapshot, count, _mandatory):
				queries.append(snapshot.owner)
				if snapshot.owner == target:
					if transition == "phase_return":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					else:
						game.turn_manager.current_player_idx = 1
						game.turn_manager.current_player_idx = 0
				return snapshot.defaults(count)
			game._rps_override = func(p):
				rps_calls.append(p)
				return 0 if p == actor else 2
			game._zhuangbi_again_override = func(): return false
			if skill == "campus":
				await game._execute_campus_dominator(actor, target)
			else:
				await game._execute_zhuangbi([target])
			check(queries == [actor, target], "上下文离开又恢复后停止，不重问或重扣：" + skill + transition)
			check(actor.hand_size() == 0 and target.determined_cards == [retained] and game.deck._discard.is_empty(), "保留已付费，拒绝目标旧答复，原牌不误弃：" + skill + transition)
			check(rps_calls.is_empty() and target.hp == 10 and actor.hp == 10, "旧外层不继续拼点及伤害：" + skill + transition)

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
