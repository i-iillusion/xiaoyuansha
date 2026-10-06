extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var mode = game.game_mode
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	var player = load("res://Test/prep_group_replace_cases.gd").new()
	for original_sub in [CardData.CardSubType.DUEL, CardData.CardSubType.BARBARIAN_INVASION]:
		for final_sub in game.GLOBAL_TRICKS:
			if original_sub == final_sub: continue
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var user: Player = game.players[1]
			var target: Player = game.players[2]
			user.general_name = "安普提·斯丢皮得"
			user.hand.append(null)
			target.hp = 8
			game.players[0].general_name = "里奥·普利威尔"
			game.players[0].prep_tokens = 1
			game._yes_ah_override = func(): return "skill"
			game._aoe_override = func(): return false
			game._prep_replace_override = func(_leo, actor, fixed, current, options):
				suite.check(actor == user and current == original_sub and options.has(final_sub) and (original_sub != CardData.CardSubType.DUEL or fixed == target), "F02b-3b-1b virtual original scope/user offered once")
				return final_sub
			var committed: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(e): committed.append(e)
			var finish = func(e): completed.append(e)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			suite.check(await game._choose_yes_ah_for_play(user, CardData.get_type_name(original_sub)), "F02b-3b-1b actual virtual confirmation")
			var targets: Array[Player] = [target]
			await player._play(game, original_sub, targets)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(committed.size() == 1 and completed == committed and committed[0].is_virtual and not committed[0].from_hand and committed[0].sub_type == original_sub, "F02b-3b-1b original virtual fact/completion not new physical card")
			suite.check(not game.deck._discard.has(committed[0].card) and user.hand_size() == (2 if final_sub == CardData.CardSubType.HARVEST else 1), "F02b-3b-1b virtual original no entity discard/hand payment; final draw only")
			suite.check(user.hp == (10 if final_sub == CardData.CardSubType.PEACH_GARDEN else 9) and game.players[0].prep_tokens == 0, "F02b-3b-1b one HP fee, final heal only")
			suite.check(target.hp == (7 if final_sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS] else (9 if final_sub == CardData.CardSubType.PEACH_GARDEN else 8)) and game._pending_card_actions.is_empty(), "F02b-3b-1b virtual final group reaches same roster and releases")
	# Injected late availability checks snapshot mechanics, not a new resurrection rule.
	for sub in game.GLOBAL_TRICKS:
		resetter._reset(suite)
		game.game_mode = GameManager.MODE_FREE_FOR_ALL
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var late: Player = game.players[4]
		late.mark_dead()
		user.hand.append(null)
		game.players[0].general_name = "里奥·普利威尔"
		game.players[0].prep_tokens = 1
		var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		game._prep_replace_override = func(_leo, _actor, _fixed, _current, options):
			suite.check(options.has(sub), "F02b-3b-1b group available before late injected actor")
			late.reset_death_state()
			late.hp = 7
			late.equip_card_to_slot("mount_1", mount)
			return sub
		await game.execute_card_on_target(game.players[2], CardData.CardSubType.DUEL)
		suite.check(late.hp == 7 and late.hand_size() == 0 and late.get_equipment_card("mount_1") == mount, "F02b-3b-1b declared snapshot never expands with later availability")
		suite.check(user.hand_size() == 0 and game._pending_card_actions.is_empty(), "F02b-3b-1b late availability cannot consume/pay again")
	# Injected shrink during a continuous choice cannot reclassify the already declared five-player card.
	resetter._reset(suite)
	game.game_mode = GameManager.MODE_FREE_FOR_ALL
	tm.current_phase = TurnManager.Phase.PLAY
	tm.current_player_idx = 1
	var actor: Player = game.players[1]
	actor.general_name = "里奥·普利威尔"
	actor.prep_tokens = 3
	actor.hand.append(null)
	var calls: Array[int] = [0]
	game._prep_replace_override = func(_leo, _actor, _fixed, current, options):
		calls[0] += 1
		if calls[0] == 1: return CardData.CardSubType.PEACH_GARDEN
		if calls[0] == 2:
			for idx in [0, 3, 4]: game.players[idx].mark_dead()
			return CardData.CardSubType.BARBARIAN_INVASION
		suite.check(current == CardData.CardSubType.BARBARIAN_INVASION and not options.has(CardData.CardSubType.DUEL) and not options.has(CardData.CardSubType.IRON_CHAIN), "F02b-3b-1b declared five-player group cannot shrink during choice")
		return CardData.CardSubType.DUEL
	await game.execute_card_on_target(game.players[2], CardData.CardSubType.DUEL)
	suite.check(calls[0] == 3 and tm.aoe_count_this_turn == 1 and tm.duel_count_this_turn == 0 and tm.peach_garden_count_this_turn == 0 and actor.prep_tokens == 2 and game.players[2].hp == 9, "F02b-3b-1b declared classification and final-only count survive injected shrink")
	# Every per-target window runs against one declared roster; old effects keep original lifecycle outcomes.
	for kind in ["nullified", "invalid", "restart", "conditions", "immune"]:
		resetter._reset(suite)
		game.game_mode = mode
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		user.general_name = "里奥·普利威尔"
		user.prep_tokens = 1
		user.hand.append(null)
		var null_card = CardBase.create(CardData.CardSubType.NULLIFICATION)
		if kind == "nullified":
			user.determined_cards.append(null_card)
			game._ai_response_override = func(_view, response_kind, options): return CardData.CardSubType.NULLIFICATION if response_kind == "nullification" and options.has(CardData.CardSubType.NULLIFICATION) else -1
		if kind == "immune":
			game.players[0].kneeling = true
			game.players[3].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.RENWANG_DUN))
			game.players[4].general_name = "史蒂芬·彼特先斯"
			game.players[4].awoken = true
			game.players[4].awake_choice = 3
		game._prep_replace_override = func(_leo, _actor, _fixed, _current, options):
			if kind == "conditions":
				game.players[3].hp = 7
				return CardData.CardSubType.HARVEST
			suite.check(options.has(CardData.CardSubType.BARBARIAN_INVASION), "F02b-3b-1b final attack offered")
			return CardData.CardSubType.BARBARIAN_INVASION
		var windows: Array[int] = [0]
		game._nullify_override = func():
			windows[0] += 1
			if windows[0] == 2 and kind in ["invalid", "restart"]:
				if kind == "restart": game.reset_game_over_state()
				else:
					tm.current_phase = TurnManager.Phase.END
					tm.current_phase = TurnManager.Phase.PLAY
			return false
		var events: Array[CardActionEvent] = []
		var collect = func(e): events.append(e)
		game.card_action_committed.connect(collect)
		await game.execute_card_on_target(game.players[2], CardData.CardSubType.DUEL)
		game.card_action_committed.disconnect(collect)
		var invalid = kind in ["invalid", "restart"]
		suite.check(events.size() == (2 if kind == "nullified" else 1) and events[0].settlement_completed == not invalid and game._pending_card_actions.is_empty(), "F02b-3b-1b one original completion or explicit abandonment")
		suite.check(user.prep_tokens == (0 if invalid else (2 if kind == "nullified" else 1)), "F02b-3b-1b real null chain plus original deferred marks, invalid no completion")
		if invalid: suite.check(game.players[2].hp == 9 and game.players[3].hp == 10, "F02b-3b-1b prior damage retained, no later stale damage")
		elif kind == "nullified": suite.check(game.players[2].hp == 10 and game.players[3].hp == 9 and game.deck._discard.count(null_card) == 1, "F02b-3b-1b actual null card paid once, cancels only one final target")
		elif kind == "conditions": suite.check(game.players[3].hand_size() == 3 and tm.harvest_count_this_turn == 1, "F02b-3b-1b condition checked after change, not cached draw amount")
		else: suite.check(game.players[2].hp == 9 and game.players[3].hp == 10 and game._prep_other_single(user) == null, "F02b-3b-1b one affected actor still five-player AOE")
	resetter._reset(suite)
	game._aoe_override = Callable()
	game.game_mode = mode
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
