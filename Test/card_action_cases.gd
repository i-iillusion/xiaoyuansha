extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var events: Array[CardActionEvent] = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	var previous_id = game._card_action_serial
	for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE,
		CardData.CardSubType.THUNDER_STRIKE, CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
		for concrete in [false, true]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			events.clear()
			var p: Player = game.players[0]
			p.hp = 9
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete:
				p.determined_cards.append(original)
			else:
				p.hand.append(null)
			if sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
				await game.play_card(sub)
			else:
				await game.execute_card_on_target(game.players[1], sub)
			suite.check(events.size() == 1, "E02d1：基本牌真实使用只发一次事件，任意/具体支付")
			if events.size() == 1:
				var event = events[0]
				suite.check(event.id > previous_id and event.turn_id == tm.turn_id and event.phase_id == tm.phase_id
					and event.actor_seat == 0 and event.turn_owner_seat == 0 and event.sub_type == sub
					and event.kind == CardActionEvent.Kind.USE and event.from_hand and not event.is_virtual,
					"E02d1：事件ID、回合/阶段、角色、牌名及手牌来源完整")
				suite.check(not concrete or event.card == original, "E02d1：已确定手牌事件保留原资源")
				previous_id = event.id
			await game.play_card(sub) # 无手牌，失败声明不得再发事件。
			suite.check(events.size() == 1, "E02d1：失败声明不发事件")
	suite.reset_players()
	events.clear()
	game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
	var multi_card = CardBase.create(CardData.CardSubType.STRIKE)
	game.players[0].hand.append(multi_card)
	await game.execute_multi_strike([game.players[1], game.players[4]], CardData.CardSubType.STRIKE)
	suite.check(events.size() == 1 and events[0].card == multi_card and game.players[1].hp == 9
		and game.players[4].hp == 9, "E02d1：多目标杀按一张使用记录，不按目标重复发事件")
	suite.reset_players()
	events.clear()
	tm.play_actor_idx = 1
	game.players[1].hand.append(null)
	await game.play_card(CardData.CardSubType.WINE)
	suite.check(events.size() == 1 and events[0].actor_seat == 1 and events[0].turn_owner_seat == 0,
		"E02d1：获赠操作者与当前回合所有者分别记录")
	for sub in [CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.DODGE]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		events.clear()
		var responder: Player = game.players[1]
		var original = CardBase.create(sub)
		responder.determined_cards.append(original)
		var expected = CardData.CardSubType.STRIKE if sub == CardData.CardSubType.FIRE_STRIKE else sub
		var ok = await game._ask_basic_card_response(responder, expected, Callable(), func(): return true)
		suite.check(ok and events.size() == 1 and events[0].kind == CardActionEvent.Kind.RESPONSE
			and events[0].card == original and events[0].sub_type == sub
			and events[0].actor_seat == 1 and events[0].turn_owner_seat == 0,
			"E02d1：基础响应记录实际属性杀/闪与响应者，不混为回合主人使用")
	suite.reset_players()
	events.clear()
	var rescuer: Player = game.players[1]
	var dying: Player = game.players[2]
	dying.hp = 0
	rescuer.hand.append(null)
	suite.check(game._use_rescue_card(rescuer, dying, CardData.CardSubType.PEACH)
		and events.size() == 1 and events[0].kind == CardActionEvent.Kind.USE
		and events[0].actor_seat == 1 and events[0].from_hand,
		"E02d1：救援桃是救援者的使用事件")
	suite.reset_players()
	events.clear()
	var bill: Player = game.players[0]
	bill.general_name = "比尔·盖伊"
	await game._execute_shensu_strike(bill, game.players[1])
	suite.check(events.size() == 1 and events[0].kind == CardActionEvent.Kind.USE
		and events[0].is_virtual and not events[0].from_hand
		and not game.deck._discard.has(events[0].card), "E02d1：神速视为杀只发一次虚拟非手牌事件")
	suite.reset_players()
	events.clear()
	var actor: Player = game.players[0]
	actor.hand.append(null)
	await game._select_hand_discard(actor, 1, true)
	game.players[1].hand.append(CardBase.create(CardData.CardSubType.PEACH))
	await game._steal_hand(actor, game.players[1], true, "顺手牵羊")
	suite.check(events.is_empty(), "E02d1：技能弃牌和单独原牌转移不冒充用牌事件")
	game.card_action_committed.disconnect(collect)
	suite.reset_players()
	tm.current_phase = old_phase
