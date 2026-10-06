extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var phase_callback = game._on_phase_changed
	tm.phase_changed.disconnect(phase_callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			actor.hp = 9
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(event):
				events.append(event)
				suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
					"F02b-1a：桃酒成立时无新标记且尚未完成")
				suite.check(actor.hp == 9 and actor.wine_stacks == 0,
					"F02b-1a：成立事实未被拖到桃酒效果之后")
			var finish = func(event):
				completed.append(event)
				suite.check(actor.prep_tokens == 1 and event.settlement_completed,
					"F02b-1a：完成通知前已消费标记一次")
				suite.check(actor.hp == (10 if sub == CardData.CardSubType.PEACH else 9)
					and actor.wine_stacks == (1 if sub == CardData.CardSubType.WINE else 0),
					"F02b-1a：桃酒效果完成后才通知")
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			await game.play_card(sub)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(events.size() == 1 and completed == events and actor.hand_size() == 0,
				"F02b-1a：一费用一成立一完成")
			suite.check(game.deck._discard.count(events[0].card) == 1
				and (not concrete or events[0].card == original), "F02b-1a：原实体仅弃一次")
			game._complete_card_actions(events)
			suite.check(actor.prep_tokens == 1 and not game._pending_card_actions.has(events[0].id),
				"F02b-1a：重复完成不重复标记且凭据已消费")
			await game.play_card(sub)
			suite.check(actor.prep_tokens == 1, "F02b-1a：失败支付不产生完成标记")

	for owner in [0, 1]:
		for concrete in [false, true]:
			for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.DODGE]:
				suite.reset_players()
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = owner
				var actor: Player = game.players[0]
				actor.general_name = "里奥·普利威尔"
				# 真实装备后效：杀首次打出青龙摸牌、闪八卦摸牌。
				if sub == CardData.CardSubType.STRIKE:
					actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
				else:
					actor.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete: actor.determined_cards.append(original)
				else: actor.hand.append(null)
				var events: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var commit = func(event):
					events.append(event)
					suite.check(actor.prep_tokens == 0 and actor.hand_size() == 0,
						"F02b-1a：响应已支付但装备摸牌前无新标记")
				var finish = func(event):
					completed.append(event)
					suite.check(actor.prep_tokens == (1 if owner == 0 else 0)
						and actor.hand_size() == 1 and event.settlement_completed,
						"F02b-1a：响应装备后效完成，按原回合资格累计")
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				var declined = await game._ask_basic_card_response_result(actor, sub, Callable(), func(): return false)
				suite.check(declined == GameManager.BasicResponseOutcome.DECLINED and events.is_empty()
					and actor.prep_tokens == 0 and actor.hand_size() == 1, "F02b-1a：主动拒绝不付费/完成")
				var outcome = await game._ask_basic_card_response_result(actor, sub, Callable(), func(): return true)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				suite.check(outcome == GameManager.BasicResponseOutcome.PAID and events.size() == 1
					and completed == events, "F02b-1a：真实响应只成立/完成一次")
				suite.check(game.deck._discard.count(events[0].card) == 1
					and (not concrete or events[0].card == original), "F02b-1a：响应原牌一次弃置")

	for concrete in [false, true]:
		for sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
			suite.reset_players()
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			actor.hp = 0
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(event):
				events.append(event)
				suite.check(actor.hp == 0 and actor.prep_tokens == 0, "F02b-1a：濒死自救支付时不提前得标记")
			var finish = func(event):
				completed.append(event)
				suite.check(actor.hp == 1 and actor.prep_tokens == 1, "F02b-1a：自救回复后得标记")
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			var used = game._use_rescue_card(actor, actor, sub)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(used and events.size() == 1 and completed == events and actor.hand_size() == 0,
				"F02b-1a：濒死合法使用保留成立与完成事实")
			suite.check(game.deck._discard.count(events[0].card) == 1
				and (not concrete or events[0].card == original), "F02b-1a：自救原牌仅弃一次")

	# 凭据层防御注入；不宣称取消结算是合法技能，也不冒充真实异步牌链。
	suite.reset_players()
	var actor: Player = game.players[0]
	actor.general_name = "里奥·普利威尔"
	var pending = game._record_card_action(actor, CardBase.create(CardData.CardSubType.WINE),
		CardActionEvent.Kind.USE, true, false, true)
	var forged = CardActionEvent.new(pending.id, tm, actor, pending.card, CardActionEvent.Kind.USE, true, false)
	game._complete_card_actions([forged])
	suite.check(actor.prep_tokens == 0 and not pending.settlement_completed
		and game._pending_card_actions.has(pending.id), "F02b-1a：同编号伪造凭据不能完成原事件")
	game.reset_game_over_state()
	game._complete_card_actions([pending])
	suite.check(actor.prep_tokens == 0 and not pending.settlement_completed
		and game._pending_card_actions.is_empty(), "F02b-1a：重开丢弃旧凭据，同一玩家不能给新局计数")
	suite.reset_players()
	tm.current_phase = phase
	tm.phase_changed.connect(phase_callback)
