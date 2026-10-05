extends "res://Test/sage_save_lifecycle_cases.gd"

func prepare(phase):
	super.prepare(phase)
	for p in game.players:
		if p.seat_index != 0: p.judgment_cards.clear()

func run(host):
	suite = host
	game = host.game
	for sub in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.BURNING_CAMP]:
		for mode in ["accept", "close", "reset", "end"]:
			prepare(TurnManager.Phase.JUDGE)
			var victim = game.players[0]
			victim.hp = 3 if sub == CardData.CardSubType.LIGHTNING else 1
			var remaining = victim.judgment_cards[0]
			var card = CardBase.create(sub)
			victim.judgment_cards.append(card)
			var action = func():
				var pending = game._choice_prompt_stack.back()
				match mode:
					"close": pending.overlay.queue_free()
					"reset": game.reset_game_over_state()
					"end": game._game_over = true
					_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
			action.call_deferred()
			var result = await game._run_judgment(victim, false)
			suite.check(result == (mode == "accept") and game.deck._discard.count(card) == 1, "E03e-22a：判定伤害保命失效明确返回，已生效原判定牌只入堆一次")
			if mode == "accept":
				suite.check(victim.is_alive() and victim.hand == [null, null, null, null] and game.deck._discard.count(remaining) == 1, "E03e-22a：判定正常贤者复原并清其余判定牌，正常继续")
			else:
				suite.check(victim.is_dying() and victim.hp == 0 and victim.hand.size() == 2 and victim.judgment_cards == [remaining] and not victim.identity_revealed, "E03e-22a：判定已造成伤害不回滚，失效不继续下一判定/死亡清牌")
			if sub == CardData.CardSubType.BURNING_CAMP:
				suite.check(game.players[1].hp == (9 if mode == "accept" else 10) and game.players[4].hp == (9 if mode == "accept" else 10) and game.players[1].judgment_cards.size() == (1 if mode == "accept" else 0) and game.players[4].judgment_cards.size() == (1 if mode == "accept" else 0), "E03e-22a：火烧连营失效不伤左右/生成蔓延，正常保命后仍正常结算")
			await suite.process_frame
	prepare(TurnManager.Phase.JUDGE)
	game.players[0].hp = 3
	game.players[0].judgment_cards.assign([CardBase.create(CardData.CardSubType.LIGHTNING)])
	var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close.call_deferred()
	await game._do_judge(0)
	suite.check(game.turn_manager.current_phase == TurnManager.Phase.JUDGE and game.players[0].hp == 0, "E03e-22a：外层真实判定收到保命失效不推进DRAW")
	await suite.process_frame
	for mode in ["accept", "close", "reset"]:
		prepare(TurnManager.Phase.PLAY)
		game.turn_manager.current_player_idx = 4
		game.turn_manager.play_actor_idx = 4
		game.players[4].hand.assign([null])
		game.players[0].hp = 1
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"close": pending.overlay.queue_free()
				"reset": game.reset_game_over_state()
				_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		action.call_deferred()
		await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
		suite.check(game.players[4].hand.is_empty() and game.players[0].hp == (10 if mode == "accept" else 0) and game.players[1].hp == (9 if mode == "accept" else 10) and game.players[2].hp == (9 if mode == "accept" else 10) and game.players[3].hp == (9 if mode == "accept" else 10), "E03e-22a：真实AOE保命失效停止其余目标，原任意牌费用/已提交伤害保留，正常保命继续")
		await suite.process_frame
	prepare(TurnManager.Phase.PLAY)
	game.players[0].hp = 5
	game.players[0].general_name = "史蒂芬·彼特先斯"
	game.players[0].equipment.clear()
	game.players[0].equipment_cards.clear()
	game.players[1].hp = 1
	game.players[1].hand.assign([null])
	game.players[2].hand.assign([null])
	game._rescue_choice_override = Callable()
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	close.call_deferred()
	await game._execute_zhuangbi([game.players[1], game.players[2]] as Array[Player])
	suite.check(game.players[1].hp == 0 and game.players[1].is_dying() and game.players[2].hp == 10 and game.players[0].hand.size() == 1 and game.players[1].hand.is_empty() and game.players[2].hand.is_empty(), "E03e-22a：装逼第一输家求救失效停止后续伤害，双方已付费用保留")
	await suite.process_frame
	suite.reset_players()
	game._rps_override = Callable()
	game._sage_save_override = Callable()
	var old_bank = game._bank_remaining
	game._halt_countdown()
	game._bank_remaining = 10.0
	game._step_remaining = 19.0
	game._update_countdown_label()
	suite.check(game._countdown_label.text == "⏳ 29 秒" and game._countdown_label.get_theme_color("font_color") == Color(0.95, 0.9, 0.5), "E03e-22a：显示优化仍显示真实剩余秒数及原普通颜色")
	game._step_remaining = 25.0
	game._bank_remaining = 4.0
	game._update_countdown_label()
	suite.check(game._countdown_label.text == "⏳ 29 秒" and game._countdown_label.get_theme_color("font_color") == Color(1, 0.4, 0.4), "E03e-22a：总秒数不变时备用时间低仍更新警告颜色")
	game._halt_countdown()
	game._bank_remaining = 10.0
	game._step_remaining = 19.0
	game._update_countdown_label()
	suite.check(game._countdown_label.text == "⏳ 29 秒", "E03e-22a：清理计时后同一秒数的新显示不被旧缓存吞掉")
	game._set_label_font_color(game._log_label, Color(0.4, 1, 0.4))
	game._set_label_font_color(game._log_label, Color(0.4, 1, 0.4))
	suite.check(game._log_label.get_theme_color("font_color") == Color(0.4, 1, 0.4), "E03e-22a：重复颜色优化保留原日志胜局颜色")
	game._bank_remaining = old_bank
	game._halt_countdown()
	game = null
	suite = null
