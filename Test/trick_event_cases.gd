extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var events: Array[CardActionEvent] = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for delayed in [false, true]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		events.clear()
		var p: Player = game.players[0]
		p.general_name = "安普提·斯丢皮得"
		p.hp = 3
		game._yes_ah_active = true
		var sub = CardData.CardSubType.INDULGENCE if delayed else CardData.CardSubType.PEACH_GARDEN
		if delayed:
			await game.execute_card_on_target(game.players[1], sub)
		else:
			await game._play_peach_garden()
		suite.check(events.size() == 1 and events[0].sub_type == sub and events[0].is_virtual
			and not events[0].from_hand and p.hand_size() == 0,
			"E02d2：是啊即时/延时锦囊只发一次虚拟非手牌使用事件")
		if events.size() == 1:
			suite.check(not game.deck._discard.has(events[0].card)
				and (not delayed or game.players[1].judgment_cards.has(events[0].card)),
				"E02d2：虚拟即时牌不制造弃牌，延时事件指向判定区同资源")
	for virtual_use in [false, true]:
		for sub in [CardData.CardSubType.NULLIFICATION, CardData.CardSubType.SACRIFICE]:
			suite.reset_players()
			events.clear()
			var p: Player = game.players[1]
			p.general_name = "安普提·斯丢皮得" if virtual_use else "稻草人"
			var original = CardBase.create(sub)
			p.determined_cards.append(original)
			game._yes_ah_override = func(): return "skill" if virtual_use else "card"
			game._ai_response_override = func(view, kind, options):
				return sub if view.actor == 1 and kind == "nullification" and options.has(sub) else -1
			if sub == CardData.CardSubType.NULLIFICATION:
				var who = await game._ask_nullification_round("事件回归")
				suite.check(who == p.player_name, "E02d2：无懈确认真实使用者")
			else:
				game._sacrifice_actor_override = func(actor, _target, _amount): return actor == p
				await game._deal_damage(game.players[0], game.players[2], 1, EffectChain.DamageType.PHYSICAL)
				suite.check(game.players[2].hp == 10 and p.hp == (8 if virtual_use else 9),
					"E02d2：舍己实际转移伤害，虚拟流失单独支付")
			suite.check(events.size() == 1 and events[0].sub_type == sub and events[0].actor_seat == 1
				and events[0].kind == CardActionEvent.Kind.USE and events[0].is_virtual == virtual_use
				and events[0].from_hand != virtual_use, "E02d2：无懈/舍己记使用，转移链不重复发布")
			suite.check(p.determined_cards.has(original) == virtual_use
				and game.deck._discard.count(original) == (0 if virtual_use else 1),
				"E02d2：虚拟使用保留原手牌，物理支付只弃原牌一次")
	suite.reset_players()
	events.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	var p: Player = game.players[0]
	var lightning = CardBase.create(CardData.CardSubType.LIGHTNING)
	p.hand.append(lightning)
	await game.play_card(CardData.CardSubType.LIGHTNING)
	suite.check(events.size() == 1 and events[0].card == lightning and events[0].from_hand
		and p.judgment_cards.has(lightning) and not game.deck._discard.has(lightning),
		"E02d2：闪电真实入口发一次事件，原牌只在判定区")
	suite.reset_players()
	events.clear()
	p.general_name = "安普提·斯丢皮得"
	p.hp = 3
	game._yes_ah_active = true
	var invalidate = func(_hp): tm.current_phase = TurnManager.Phase.END
	p.hp_changed.connect(invalidate)
	var used = await game._consume_trick(p, CardData.CardSubType.PEACH_GARDEN)
	p.hp_changed.disconnect(invalidate)
	suite.check(not used and events.is_empty() and p.hp == 2,
		"E02d2：虚拟支付后上下文失效不发布使用，流失费用不回滚")
	game.card_action_committed.disconnect(collect)
	suite.reset_players()
	tm.current_phase = old_phase
