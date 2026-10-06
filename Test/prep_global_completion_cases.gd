extends RefCounted

func _reset(suite):
	suite.reset_players()
	# 本夹具创建普通坐骑；通用重置清空装备表但不清缓存计数。
	for p in suite.game.players:
		p.mount_plus = 0
		p.mount_minus = 0

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS,
			CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST, CardData.CardSubType.DISARM]:
			for mode in ["normal", "invalid", "restart"]:
				_reset(suite)
				tm.current_player_idx = 1
				tm.current_phase = TurnManager.Phase.PLAY
				var actor: Player = game.players[1]
				actor.general_name = "里奥·普利威尔"
				for p in game.players:
					p.hp = 9
					if sub == CardData.CardSubType.DISARM:
						p.equip_mount_card(CardBase.create(CardData.CardSubType.MOUNT_PLUS))
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete: actor.determined_cards.append(original)
				else: actor.hand.append(null)
				var events: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var windows: Array[int] = [0]
				var commit = func(event):
					events.append(event)
					suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
						"F02b-1d-a：群体锦囊成立不提前计数")
				var finish = func(event):
					completed.append(event)
					suite.check(actor.prep_tokens == 1 and event.settlement_completed,
						"F02b-1d-a：整张正常结束才计一次")
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				game._nullify_override = func():
					windows[0] += 1
					suite.check(actor.prep_tokens == 0, "F02b-1d-a：每个目标的无懈窗口仍无本张标记")
					if windows[0] == 2 and mode != "normal":
						if mode == "restart": game.reset_game_over_state()
						else:
							tm.current_phase = TurnManager.Phase.END
							tm.current_phase = TurnManager.Phase.PLAY
					return false
				await game.play_card(sub)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				var normal = mode == "normal"
				suite.check(events.size() == 1 and completed.size() == (1 if normal else 0)
					and actor.prep_tokens == (1 if normal else 0) and game._pending_card_actions.is_empty(),
					"F02b-1d-a：正常一次完成，技术失效/重开无完成无遗留")
				suite.check(events.size() == 1 and game.deck._discard.count(events[0].card) == 1
					and (not concrete or events[0].card == original), "F02b-1d-a：原费用/实例成立一次且不回滚")
				if normal:
					var aoe = sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS]
					suite.check(windows[0] == (4 if aoe else 5), "F02b-1d-a：末目标处理后才完成，非首目标结束")
					for p in game.players:
						var correct = p.hp == (9 if p == actor else 8) if aoe else (
							p.hp == 10 if sub == CardData.CardSubType.PEACH_GARDEN else p.hand_size() == 1)
						suite.check(correct, "F02b-1d-a：所有原目标伤害/回复/摸牌效果正常")
					game._complete_card_actions(events)
					suite.check(actor.prep_tokens == 1, "F02b-1d-a：重复通知不重复计数")
	# 真实末目标响应窗口：前面三名目标已受伤，整张仍未完成。
	for concrete in [false, true]:
		for restart in [false, true]:
			_reset(suite)
			tm.current_player_idx = 1
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.VOLLEY_OF_ARROWS))
			else: actor.hand.append(null)
			game.players[0].hand.append(null)
			game._aoe_override = Callable()
			var drive = func():
				suite.check(actor.prep_tokens == 0 and game.players[2].hp == 9
					and game.players[3].hp == 9 and game.players[4].hp == 9,
					"F02b-1d-a：真实末目标窗口前面三人已完成，标记仍0")
				if restart: game.reset_game_over_state()
				else: game._choice_prompt_stack.back().overlay.queue_free()
			drive.call_deferred()
			await game.play_card(CardData.CardSubType.VOLLEY_OF_ARROWS)
			suite.check(actor.prep_tokens == 0 and actor.hand_size() == 0
				and game.players[0].hp == 10 and game._pending_card_actions.is_empty(),
				"F02b-1d-a：真实关闭/重开不完成整张，不撤销前面真实伤害和费用")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "F02b-1d-a：真实旧响应窗口清理")
	_reset(suite)
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
