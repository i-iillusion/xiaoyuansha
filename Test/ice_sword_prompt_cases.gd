extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._ice_sword_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY

func drive(action: String, actor: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active, "E03e-6a：寒冰不新增倒计时")
	match action:
		"yes":
			buttons[0].pressed.emit()
			pending.answer.submit(0)
		"no": buttons[1].pressed.emit()
		"close": pending.overlay.queue_free()
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			buttons[0].pressed.emit()
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
			buttons[0].pressed.emit()
		"weapon", "same_weapon":
			actor.determined_cards.append(actor.remove_equipment("weapon"))
			if action == "same_weapon":
				# 生命周期故障注入，不代表允许生成第二把同名唯一武器。
				actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
			buttons[0].pressed.emit()
		"armor":
			target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
			buttons[0].pressed.emit()
		"target_dead", "source_dead":
			var dead = target if action == "target_dead" else actor
			dead.hp = 0
			dead.mark_dead() # 防御性注入，不发明此窗口中额外行动时机。
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-6a回归")

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		windows.clear()
		for action in ["yes", "no", "close", "phase", "actor", "weapon", "same_weapon", "armor", "target_dead", "source_dead", "ended"]:
			reset()
			var actor = game.players[0]
			var target = game.players[1]
			actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
			var original = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			var peach = CardBase.create(CardData.CardSubType.PEACH)
			var wine = CardBase.create(CardData.CardSubType.WINE)
			if concrete: target.determined_cards.append_array([peach, wine])
			else: target.hand.append_array([null, null])
			drive.call_deferred(action, actor, target)
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			suite.check(target.hp == (0 if action == "target_dead" else (9 if action in ["no", "source_dead"] else 10)),
				"E03e-6a：防止、拒绝、失效、最终死亡来源的实际伤害：" + action)
			suite.check(target.hand_size() == (0 if action == "yes" else 2), "E03e-6a：只有有效发动弃目标两张手牌：" + action)
			suite.check(actor.hand_size() == (1 if action in ["weapon", "same_weapon"] else 0), "E03e-6a：原杀已支付不退款")
			suite.check(game.deck._discard.size() == (3 if concrete and action == "yes" else 1)
				and game.deck._discard[0].sub_type == CardData.CardSubType.STRIKE
				and (not concrete or game.deck._discard[0] == original), "E03e-6a：原杀实例入弃一次")
			if concrete and action == "yes":
				suite.check(game.deck._discard.count(peach) == 1 and game.deck._discard.count(wine) == 1,
					"E03e-6a：具体目标手牌原实例各入弃一次")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-6a：寒冰等待结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-6a：窗口实际释放")
	# 独立答复对象不能让上一窗口按钮或兼容旧信号污染下一窗口。
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._ask_ice_sword("B") == game.CHOICE_INVALID, "E03e-6a：关闭不是主动拒绝")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._ice_sword_result.emit(true)
		suite.check(not pending.answer.settled, "E03e-6a：旧按钮及共享信号不答新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._ask_ice_sword("B") == 0, "E03e-6a：下一窗口可以正常拒绝")
	await suite.process_frame
	for result in [true, false, -2]:
		game._ice_sword_override = func(): return result
		var expected = -2 if typeof(result) == TYPE_INT else (1 if result else 0)
		suite.check(await game._ask_ice_sword("B") == expected, "E03e-6a：旧bool钩子和整数失效值兼容")
	# 手册明确互弃，必须在寒冰询问前移出两件原装备。
	reset()
	var actor = game.players[0]
	var target = game.players[1]
	var weapon = CardBase.create(CardData.CardSubType.ICE_SWORD)
	var armor = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD)
	actor.equip_card_to_slot("weapon", weapon)
	target.equip_card_to_slot("armor", armor)
	actor.hand.append(null)
	target.hand.append_array([null, null])
	game._ice_sword_override = func():
		suite.check(false, "E03e-6a：互弃后不应再询问寒冰")
		return true
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	suite.check(target.hp == 9 and target.hand_size() == 2, "E03e-6a：互弃后原杀正常伤害，不弃目标手牌")
	suite.check(actor.get_equipment_card("weapon") == null and target.get_equipment_card("armor") == null
		and game.deck._discard.count(weapon) == 1 and game.deck._discard.count(armor) == 1,
		"E03e-6a：寒冰烈火互弃原装备一次")
	# 非人类沿用自动发动；任意/具体混合手牌只移出两张，不额外弃第三张。
	reset()
	actor = game.players[1]
	target = game.players[2]
	actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
	actor.hand.append(null)
	var concrete_card = CardBase.create(CardData.CardSubType.PEACH)
	target.hand.append_array([null, null])
	target.determined_cards.append(concrete_card)
	game.turn_manager.play_actor_idx = 1
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	suite.check(target.hp == 10 and target.hand_size() == 1, "E03e-6a：AI原策略发动，只弃两张混合手牌")
	suite.check(target.determined_cards.has(concrete_card) and game.deck._discard.size() == 1,
		"E03e-6a：沿用取牌顺序，第三张原具体牌不被额外弃置")
	reset()
	actor = game.players[0]
	target = game.players[1]
	actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
	target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
	actor.hand.append(null)
	target.hand.append_array([null, null])
	game._ice_sword_override = func():
		suite.check(false, "E03e-6a：青釭盾无视寒冰，不应询问")
		return true
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	suite.check(target.hp == 9 and target.hand_size() == 2, "E03e-6a：青釭盾阻止寒冰，原杀正常伤害")
	# 直接保留真实伤害链记录，检查TIME-04，而不仅检查扣血数值。
	reset()
	actor = game.players[0]
	target = game.players[1]
	actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
	target.hand.append_array([null, null])
	var chain = game._new_damage_chain(actor, target, CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
	chain.damage.from_strike = true
	drive.call_deferred("source_dead", actor, target)
	await chain.start()
	suite.check(chain.damage.source == null and chain.damage.committed and not chain.is_cancelled,
		"E03e-6a：最终死亡来源的余伤记录无源且真实施加")
	suite.check(target.hp == 9 and target.hand_size() == 2, "E03e-6a：来源死亡不弃目标手牌，继续一伤")
	await suite.process_frame
	reset()
	suite = null
	game = null
