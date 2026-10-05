extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var phase_callback = game._on_phase_changed
	tm.phase_changed.disconnect(phase_callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.PEACH,
			CardData.CardSubType.WINE, CardData.CardSubType.LIANNU, CardData.CardSubType.LIGHTNING]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			game.equipment_pool.clear()
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			actor.judgment_cards.clear()
			actor.hp = 9
			var card: CardBase = CardBase.create(sub) if concrete else null
			if concrete: actor.determined_cards.append(card)
			else: actor.hand.append(null)
			if sub == CardData.CardSubType.STRIKE:
				await game.execute_card_on_target(game.players[1], sub)
			else:
				await game.play_card(sub)
			suite.check(actor.prep_tokens == 1 and actor.hand_size() == 0,
				"F01b：真实任意/具体基本牌、装备、延时使用各获一个标记")
			await game.play_card(sub)
			suite.check(actor.prep_tokens == 1, "F01b：无手牌失败声明不增加标记")
	for owner in [0, 1]:
		for concrete in [false, true]:
			suite.reset_players()
			tm.current_player_idx = owner
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.DODGE))
			else: actor.hand.append(null)
			await game._ask_basic_card_response(actor, CardData.CardSubType.DODGE, Callable(), func(): return false)
			suite.check(actor.prep_tokens == 0 and actor.hand_size() == 1, "F01b：拒绝响应不增加标记")
			await game._ask_basic_card_response(actor, CardData.CardSubType.DODGE, Callable(), func(): return true)
			suite.check(actor.prep_tokens == (1 if owner == 0 else 0) and actor.hand_size() == 0,
				"F01b：真实闪仅本人回合响应得标记")
	# 求救阶段的自己可以处于濒死；不能用is_alive过滤合法自救手牌。
	suite.reset_players()
	var actor: Player = game.players[0]
	actor.general_name = "里奥·普利威尔"
	actor.hp = 0
	actor.hand.append(null)
	suite.check(game._use_rescue_card(actor, actor, CardData.CardSubType.PEACH)
		and actor.prep_tokens == 1 and actor.hp == 1, "F01b：本人回合濒死自救桃也计一次")
	# 真实技能赠送PLAY：0号里奥实际操作，回合所有者仍是1号麦克斯。
	suite.reset_players()
	actor.general_name = "里奥·普利威尔"
	actor.hand.append(null)
	var source: Player = game.players[1]
	source.general_name = "麦克斯·欧尼斯特"
	tm.current_player_idx = 1
	tm.current_phase = TurnManager.Phase.START
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 2
	game._meiyong_target_override = func(): return actor
	var act_in_granted = func():
		suite.check(tm.current_phase == TurnManager.Phase.PLAY and tm.get_play_actor_idx() == 0
			and tm.current_player_idx == 1, "F01b：实际赠送帧区分操作人和回合主人")
		await game.play_card(CardData.CardSubType.WINE)
		suite.check(actor.prep_tokens == 0 and actor.hand_size() == 0, "F01b：获赠PLAY真实使用不获得预习标记")
		game._on_end_play_pressed()
	act_in_granted.call_deferred()
	var granted = await game._maybe_meiyong(source)
	suite.check(granted == 1 and tm.current_phase == TurnManager.Phase.START
		and source.hand_size() == 1, "F01b：真实赠送完成恢复源START且只摸一张")
	game._meiyong_override = Callable()
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	actor.general_name = "里奥·普利威尔"
	actor.hand.append(null)
	await game._select_hand_discard(actor, 1, true)
	game.players[1].hand.append(CardBase.create(CardData.CardSubType.PEACH))
	await game._steal_hand(actor, game.players[1], true, "顺手牵羊")
	suite.check(actor.prep_tokens == 0 and actor.hand_size() == 1, "F01b：真实费用/原牌转移不获得标记")
	# 事实接口防御注入，不宣称里奥现阶段能合法发动是啊/神速。
	for hand_origin in [false, true]:
		var event = CardActionEvent.new(0, tm, actor, CardBase.create(CardData.CardSubType.STRIKE),
			CardActionEvent.Kind.USE, hand_origin, true)
		game._apply_prep_card_action(actor, event)
		suite.check(actor.prep_tokens == 0, "F01b：虚拟事实排除，即便错误附带手牌来源也不累计")
	actor.hand.append(null)
	await game.play_card(CardData.CardSubType.WINE)
	tm.current_phase = TurnManager.Phase.END
	tm.current_player_idx = 1
	game._reset_turn_flags()
	suite.check(actor.prep_tokens == 1, "F01b：阶段结束/别人回合不清预习标记")
	game._update_player_panel(game._self_info_panel, actor)
	var label: Label = game._self_info_panel.get_meta("prep_indicator")
	suite.check(label.visible and label.text == "预习:1", "F01b：面板公开显示预习数量")
	actor.prep_tokens = 0
	actor.capture_game_start_state()
	actor.prep_tokens = 4
	game._do_sage_save(actor)
	suite.check(actor.prep_tokens == 0 and actor.hand == [null, null, null, null]
		and game._self_info_panel.get_meta("prep_indicator").text == "预习:0",
		"F01b：真实贤者复原恢复武将开局标记并同步显示，不计摸牌为用牌")
	suite.reset_players()
	game._update_player_panel(game._self_info_panel, actor)
	suite.check(not label.visible, "F01b：非里奥面板不显示预习标记")
	tm.current_phase = old_phase
	tm.phase_changed.connect(phase_callback)
