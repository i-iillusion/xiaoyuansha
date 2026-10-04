extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	for concrete in [false, true]:
		for timeout in [false, true]:
			suite.reset_players()
			game.deck._discard.clear()
			game._awaken_pick_override = Callable()
			game._zhuangbi_blocked_this_phase = false
			game._zhuangbi_again_override = func(): return false
			game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var source = game.players[0]
			var target = game.players[1]
			source.general_name = "史蒂芬·彼特先斯"
			source.max_hp = 3
			source.hp = 3
			source.capture_game_start_state()
			var card = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(card)
			else: source.hand.append(null)
			target.hand.append(null)
			var answer = func():
				var pending = game._choice_prompt_stack.back()
				suite.check(source.max_hp == 2 and source.hp == 2 and source.hand_size() == 2 and source.awake_choice == 0, "E03-R01b：费用后觉醒上限/摸牌已各一次，正在三选一")
				if timeout: game._countdown_on_timeout.call()
				else: pending.overlay.find_children("*", "Button", true, false)[-1].pressed.emit()
			answer.call_deferred()
			await game._execute_zhuangbi([target])
			await suite.process_frame
			suite.check(source.awake_choice == 1 and source.max_hp == 2 and source.hand_size() == 2, "E03-R01b：取消及超时均杀免疫，不选决斗或重做觉醒")
			suite.check(game._awake_blocks(source, 1) and not game._awake_blocks(source, 2), "E03-R01b：默认实际杀合法性生效，不误授决斗免疫")
			suite.check(target.hand_size() == 0 and target.hp == 9 and (not concrete or game.deck._discard.count(card) == 1), "E03-R01b：觉醒默认后原已付费用与真实技能拼点继续")
			suite.check(game._choice_prompt_stack.is_empty() and not game._awaken_in_progress.has(source), "E03-R01b：默认结算完成且不会重新打开必选窗口")
	game._zhuangbi_again_override = Callable()
	game._rps_override = Callable()
	suite.reset_players()
