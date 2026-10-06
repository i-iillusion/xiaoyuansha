extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS, CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST, CardData.CardSubType.DISARM]:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var user: Player = game.players[1]
			var target: Player = game.players[2]
			var original: CardBase = CardBase.create(CardData.CardSubType.DUEL) if concrete else null
			if concrete: user.determined_cards.append(original)
			else: user.hand.append(null)
			if sub in [CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST]: user.hp = 8
			target.hp = 8
			var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
			if sub == CardData.CardSubType.DISARM: target.equip_card_to_slot("mount_1", mount)
			game._aoe_override = func(): return false
			var committed: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var on_commit = func(e): committed.append(e)
			var on_complete = func(e): completed.append(e)
			game.card_action_committed.connect(on_commit)
			game.card_action_completed.connect(on_complete)
			var actions: Array[CardActionEvent] = []
			suite.check(await game._consume_trick(user, CardData.CardSubType.DUEL, actions), "F02b-3a original paid once")
			var revision = tm.get_context_revision()
			match sub:
				CardData.CardSubType.BARBARIAN_INVASION: await game._resolve_paid_aoe(user, CardData.CardSubType.STRIKE, "南蛮入侵", "杀", actions, revision)
				CardData.CardSubType.VOLLEY_OF_ARROWS: await game._resolve_paid_aoe(user, CardData.CardSubType.DODGE, "万箭齐发", "闪", actions, revision)
				CardData.CardSubType.PEACH_GARDEN: await game._resolve_paid_peach_garden(user, actions, revision)
				CardData.CardSubType.HARVEST: await game._resolve_paid_harvest(user, actions, revision)
				CardData.CardSubType.DISARM: await game._resolve_paid_disarm(user, actions, revision)
			game.card_action_committed.disconnect(on_commit)
			game.card_action_completed.disconnect(on_complete)
			suite.check(committed.size() == 1 and completed == committed, "F02b-3a one original fact/completion")
			suite.check(user.hand_size() == (2 if sub == CardData.CardSubType.HARVEST else 0), "F02b-3a no second payment/self draw")
			suite.check(committed[0].card.sub_type == CardData.CardSubType.DUEL and game.deck._discard.count(committed[0].card) == 1 \
				and (not concrete or committed[0].card == original), "F02b-3a persistent original name/entity")
			suite.check(tm.duel_count_this_turn == 0, "F02b-3a original category not counted")
			if sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS]:
				suite.check(user.hp == 10 and target.hp == 7 and tm.aoe_count_this_turn == 1, "F02b-3a aoe excludes source and responds/damages")
			elif sub == CardData.CardSubType.PEACH_GARDEN:
				suite.check(user.hp == 9 and target.hp == 9 and tm.peach_garden_count_this_turn == 1, "F02b-3a peach includes source/heals once")
			elif sub == CardData.CardSubType.HARVEST:
				suite.check(target.hand_size() == 2 and tm.harvest_count_this_turn == 1, "F02b-3a harvest lost-hp draw")
			else:
				suite.check(target.equipment.is_empty() and target.hand_size() == 1 and game.deck._discard.count(mount) == 1 and tm.disarm_count_this_turn == 1, "F02b-3a disarm same original equipment/drop/draw")
			suite.check(game._pending_card_actions.is_empty(), "F02b-3a release original receipt")
	resetter._reset(suite)
	game._aoe_override = Callable()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
