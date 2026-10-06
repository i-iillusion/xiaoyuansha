extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for mode in ["hit", "dodge", "immune", "multi", "invalid", "restart", "transfer"]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			var target: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			var original: CardBase = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(event):
				if event.actor_seat == 0:
					events.append(event)
					suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
						"F02b-1b：主动杀成立尚无新标记")
			var finish = func(event):
				if event.actor_seat == 0: completed.append(event)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			if mode == "immune": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.BAIHUA_SKIRT)); target.hp = 1
			if mode in ["dodge", "invalid", "restart", "multi"]:
				target.hand.append(null)
				game.players[4].hand.append(null)
				var decisions: Array[int] = [0]
				game._dodge_override = func():
					decisions[0] += 1
					suite.check(actor.prep_tokens == 0, "F02b-1b：杀响应窗口不提前获得整张标记")
					if mode == "multi" and decisions[0] == 2:
						suite.check(target.hp == 9 and game.players[4].hp == 10,
							"F02b-1b：首目标已完成，次目标未受伤，标记仍0")
					if mode == "restart":
						game.reset_game_over_state()
						return GameManager.CHOICE_INVALID
					if mode == "invalid": return GameManager.CHOICE_INVALID
					return mode == "dodge"
			if mode == "multi":
				actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
				await game.execute_multi_strike([target, game.players[4]], CardData.CardSubType.STRIKE)
			else:
				if mode == "transfer":
					actor.wine_stacks = 1
					actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CALAMITY_SWORD))
					game._calamity_target_override = func():
						suite.check(actor.prep_tokens == 0 and target.hp == 9,
							"F02b-1b：灾厄减伤后转移选择仍无新标记")
						return game.players[2]
				await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			game._calamity_target_override = Callable()
			var invalid = mode in ["invalid", "restart"]
			suite.check(events.size() == 1 and actor.hand_size() == 0
				and game.deck._discard.count(events[0].card) == 1
				and (not concrete or events[0].card == original), "F02b-1b：成立/失效均保留一次原牌支付")
			suite.check(actor.prep_tokens == (0 if invalid else 1)
				and completed.size() == (0 if invalid else 1), "F02b-1b：正常结算仅完成一次，技术失效不计")
			suite.check(game._pending_card_actions.is_empty(), "F02b-1b：正常或失效均释放本张凭据")
			if mode == "multi":
				suite.check(target.hp == 9 and game.players[4].hp == 9, "F02b-1b：两目标伤害完成后整张仅一标记")
			elif mode in ["dodge", "invalid", "restart"]:
				suite.check(target.hp == 10, "F02b-1b：闪/失效不制造后续伤害")
			elif mode == "hit":
				suite.check(target.hp == 9, "F02b-1b：伤害完整提交")
			elif mode == "immune":
				suite.check(target.hp == 1, "F02b-1b：规则免伤不等于技术失效")
			elif mode == "transfer":
				suite.check(actor.get_weapon() == -1 and game.players[2].get_weapon() == CardData.CardSubType.CALAMITY_SWORD,
					"F02b-1b：武器转移后效完成再累计")
	# 真实人类闪窗口的关闭/重开，不仅注入CHOICE_INVALID。
	for concrete in [false, true]:
		for restart in [false, true]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var actor: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
			else: actor.hand.append(null)
			game.players[0].hand.append(null)
			game._dodge_override = Callable()
			var drive = func():
				suite.check(actor.prep_tokens == 0 and actor.hand_size() == 0,
					"F02b-1b：真实闪弹窗已支付杀但未获得标记")
				if restart: game.reset_game_over_state()
				else: game._choice_prompt_stack.back().overlay.queue_free()
			drive.call_deferred()
			await game.execute_card_on_target(game.players[0], CardData.CardSubType.STRIKE)
			suite.check(actor.prep_tokens == 0 and game.players[0].hp == 10
				and game._pending_card_actions.is_empty(), "F02b-1b：真实关闭/重开结束旧杀，原费用保留")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "F02b-1b：真实旧窗口清理完毕")
			actor.hand.append(null)
			game._dodge_override = func(): return false
			await game.execute_card_on_target(game.players[0], CardData.CardSubType.STRIKE)
			suite.check(actor.prep_tokens == 1 and game.players[0].hp == 9,
				"F02b-1b：旧窗口之后下一合法杀正常完成一次")
	suite.reset_players()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
