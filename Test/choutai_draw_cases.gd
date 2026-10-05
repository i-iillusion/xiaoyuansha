extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var phase_callback = game._on_phase_changed
	tm.phase_changed.disconnect(phase_callback)
	for general in ["里奥·普利威尔", "稻草人", "比尔·盖伊"]:
		for supply in [false, true]:
			suite.reset_players()
			var actor: Player = game.players[0]
			actor.general_name = general
			actor.shensu_penalty = 0
			actor.shensu_used_this_turn = false
			var original = CardBase.create(CardData.CardSubType.DODGE)
			actor.determined_cards.append(original)
			tm.current_phase = TurnManager.Phase.DRAW
			tm.supply_shortage_active = supply
			game._do_draw(0)
			var base = 1 if general == "里奥·普利威尔" else (3 if general == "比尔·盖伊" else 2)
			var expected = base - (1 if supply else 0)
			suite.check(actor.hand.size() == expected and actor.hand.all(func(card): return card == null)
				and actor.determined_cards == [original], "F01c：普通DRAW丑态/默认/英姿基数及兵粮，摸任意牌不改已有具体牌")
			suite.check(tm.current_phase == TurnManager.Phase.PLAY and not tm.supply_shortage_active
				and actor.prep_tokens == 0, "F01c：DRAW正常推进且只消费本阶段兵粮，摸牌不增加预习")
	# 比尔原有阶段修正保留：非发动回合一次扣清，最低零；发动当回合留欠账。
	for used in [false, true]:
		suite.reset_players()
		var actor: Player = game.players[0]
		actor.general_name = "比尔·盖伊"
		actor.shensu_penalty = 4
		actor.shensu_used_this_turn = used
		tm.current_phase = TurnManager.Phase.DRAW
		tm.supply_shortage_active = true
		game._do_draw(0)
		suite.check(actor.hand_size() == (2 if used else 0) and actor.shensu_penalty == (4 if used else 0),
			"F01c：丑态接入不回退英姿+兵粮+神速累计减益/当回合延后")
	# 实际烂忠厚赠DRAW：基数属于里奥，兵粮属于源回合，不混用。
	for supply in [false, true]:
		suite.reset_players()
		var actor: Player = game.players[0]
		actor.general_name = "里奥·普利威尔"
		actor.shensu_penalty = 0
		var source: Player = game.players[1]
		source.general_name = "麦克斯·欧尼斯特"
		tm.current_player_idx = 1
		tm.current_phase = TurnManager.Phase.START
		tm.supply_shortage_active = supply
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return 1
		game._meiyong_target_override = func(): return actor
		var result = await game._maybe_meiyong(source)
		suite.check(result == 1 and actor.hand == [null] and source.hand == [null]
			and tm.current_phase == TurnManager.Phase.START and tm.current_player_idx == 1
			and tm.granted_draw_completed and tm.supply_shortage_active == supply,
			"F01c：真实赠DRAW里奥摸一张，麦克斯额外摸一张且源兵粮不被消费")
		tm.current_phase = TurnManager.Phase.DRAW
		game._do_draw(1)
		suite.check(actor.hand == [null] and source.hand == [null] and tm.current_phase == TurnManager.Phase.PLAY
			and not tm.granted_draw_completed and tm.granted_draw_target_idx == -1
			and tm.supply_shortage_active == supply, "F01c：赠送者跳过本DRAW不重复摸牌/消费源兵粮")
		suite.check(actor.prep_tokens == 0 and source.prep_tokens == 0, "F01c：赠送及额外摸牌不形成使用/打出")
	game._meiyong_override = Callable()
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	var actor: Player = game.players[0]
	actor.general_name = "里奥·普利威尔"
	actor.hand.append(null)
	actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.STRIKE)
	suite.check(actor.hand == [null] and actor.prep_tokens == 1,
		"F01c：真实青龙首次杀额外摸牌不受丑态，原杀使用只计一个预习")
	game._draw_blank_cards(actor, 2)
	suite.check(actor.hand == [null, null, null] and actor.prep_tokens == 1,
		"F01c：额外摸牌公共入口不截断张数、不伪造用牌事件")
	actor.shensu_penalty = 0
	actor.shensu_used_this_turn = false
	game.players[1].shensu_penalty = 0
	tm.supply_shortage_active = false
	suite.reset_players()
	tm.current_phase = old_phase
	tm.phase_changed.connect(phase_callback)
