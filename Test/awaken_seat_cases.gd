extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var old_pick = game._awaken_pick_override
	var old_ai = game._ai_response_override
	game._awaken_pick_override = Callable()
	for seat in [1, 2, 3, 4]:
		for concrete in [false, true]:
			suite.reset_players()
			game._ai_response_override = Callable()
			var p: Player = game.players[seat]
			p.general_name = "史蒂芬·彼特先斯"
			p.max_hp = 3
			p.hp = 3
			p.capture_game_start_state()
			var card: CardBase = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			if concrete:
				p.determined_cards.append(card)
			else:
				p.hand.append(null)
			game._check_awaken_trigger()
			suite.check(not p.awoken, "E01c：非0号两种手牌区有牌不觉醒")
			var responded = await game._ask_basic_card_response(p, CardData.CardSubType.DODGE, Callable())
			suite.check(responded and p.awoken and p.awake_choice == 1 and p.max_hp == 2
				and p.hp == 2 and p.hand == [null, null], "E01c：非0号支付最后闪后立即觉醒、自动选择并摸两张")
			suite.check(not concrete or game.deck._discard.count(card) == 1,
				"E01c：觉醒不复制或重复弃置响应原牌")
			game._sync_all_ui()
			p.hand_updated.emit()
			suite.check(p.max_hp == 2 and p.hand_size() == 2, "E01c：重复同步和信号不重复觉醒")
			p.hp = 0
			game._do_sage_save(p)
			suite.check(not p.awoken and p.awake_choice == 0 and p.max_hp == 3
				and p.hand_size() == 4, "E01c：贤者恢复后不因中途空手误觉醒")
			game._ai_response_override = func(_view, kind, _options): return 3 if kind == "awaken" else -1
			for i in 4:
				p.remove_from_hand(null)
			suite.check(p.awoken and p.awake_choice == 3 and p.max_hp == 2 and p.hand_size() == 2,
				"E01c：贤者后再次真实失去最后手牌可重新觉醒并选择其他合法效果")
	for invalidation in ["phase", "death", "ended"]:
		suite.reset_players()
		var p: Player = game.players[1]
		p.general_name = "史蒂芬·彼特先斯"
		p.hand.append(null)
		game._ai_response_override = func(_view, _kind, _options):
			await suite.process_frame
			match invalidation:
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"death": p.mark_dead()
				"ended": game._game_over = true
			return 2
		var old_phase = game.turn_manager.current_phase
		p.remove_from_hand(null)
		await suite.process_frame
		await suite.process_frame
		suite.check(p.awake_choice == 0 and p.hand_size() == 2 and p.max_hp == 9,
			"E01c：过期自动选择不写回，已结算上限和摸牌不回滚：" + invalidation)
		game.turn_manager.current_phase = old_phase
	game._awaken_pick_override = old_pick
	suite.reset_players()
	game._ai_response_override = old_ai
