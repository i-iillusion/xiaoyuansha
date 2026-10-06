extends RefCounted

# 已支付入口不能再次消费原牌；正常原拆/顺仍由外层选择区域。
func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for snatch in [false, true]:
			for stale in [false, true]:
				resetter._reset(suite)
				game.deck._discard.clear()
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = 1
				var user: Player = game.players[1]
				var target: Player = game.players[2]
				var original: CardBase = CardBase.create(CardData.CardSubType.DUEL) if concrete else null
				if concrete: user.determined_cards.append(original)
				else: user.hand.append(null)
				var taken = CardBase.create(CardData.CardSubType.DODGE)
				target.hand.append(taken)
				var commits: Array[CardActionEvent] = []
				var completions: Array[CardActionEvent] = []
				var on_commit = func(event): commits.append(event)
				var on_complete = func(event): completions.append(event)
				game.card_action_committed.connect(on_commit)
				game.card_action_completed.connect(on_complete)
				var actions: Array[CardActionEvent] = []
				suite.check(await game._consume_trick(user, CardData.CardSubType.DUEL, actions), "paid steal original payment")
				await game._resolve_paid_steal(user, target, snatch, "hand", actions, func(): return not stale)
				suite.check(commits.size() == 1, "paid steal no second use fact")
				suite.check(completions.size() == (0 if stale else 1), "paid steal completion or invalidation")
				suite.check(user.hand_size() == (1 if snatch and not stale else 0), "paid steal no additional hand payment")
				suite.check(target.hand.has(taken) == stale, "paid steal fixed target movement")
				suite.check(tm.steal_count_this_turn == (0 if stale else 1) and tm.duel_count_this_turn == 0, "paid steal final category only")
				if concrete:
					suite.check(original.sub_type == CardData.CardSubType.DUEL and game.deck._discard.count(original) == 1, "paid steal original entity and name")
				if not stale:
					suite.check(user.hand.has(taken) if snatch else game.deck._discard.count(taken) == 1, "paid steal same target card")
				game.card_action_committed.disconnect(on_commit)
				game.card_action_completed.disconnect(on_complete)
	resetter._reset(suite)
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
