extends RefCounted

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	var factory = load("res://Test/terminal_boundary_cases.gd").new()
	for concrete in [false, true]:
		# The apparent attacker/survivor dies inside the target's death-before rule.
		var game = await factory.new_game(suite, 2, "里奥·普利威尔")
		var leo = game.players[0]
		var attacker = game.players[1]
		leo.hp = 1
		attacker.hp = 2
		game.turn_manager.current_player_idx = 1
		var original: CardBase = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
		if concrete: attacker.determined_cards.append(original)
		else: attacker.hand.append(null)
		var kept = CardBase.create(CardData.CardSubType.INDULGENCE)
		leo.judgment_cards.append(kept)
		var winners: Array = []
		game.game_over.connect(func(w): winners.append([w, leo.hp, leo.is_alive(), attacker.is_dead(), game.yudaxi.is_active(), game._dying_contexts.size()]))
		await game.execute_card_on_target(leo, CardData.CardSubType.STRIKE)
		suite.check(winners == [[leo.player_name, 1, true, true, false, 0]], "G01b death-before yudaxi changes apparent winner before one terminal notification")
		suite.check(leo.hand == [null] and leo.judgment_cards == [kept] and game.yudaxi.results[0].deaths == 1 and game._dead_processed == [attacker], "G01b success preserves original judgment, direct X only, null-source death no reward")
		suite.check(game.deck._discard.size() == 1 and (not concrete or game.deck._discard[0] == original) and game._pending_card_actions.is_empty(), "G01b killing parent card paid once, terminal does not create a second card or completion")
		game.queue_free()
		await suite.process_frame
		# Three-player real rescue: negative HP needs two actual peach payments;
		# no winner while asking or after successful rescue.
		game = await factory.new_game(suite, 3)
		var a = game.players[0]
		var b = game.players[1]
		var c = game.players[2]
		b.hp = 1
		var peaches: Array = []
		for i in 2:
			var peach: CardBase = CardBase.create(CardData.CardSubType.PEACH) if concrete else null
			peaches.append(peach)
			if concrete: c.determined_cards.append(peach)
			else: c.hand.append(null)
		var rescue_states: Array = []
		game._rescue_choice_override = func(r, d, options):
			if r == c and d == b and options.has(CardData.CardSubType.PEACH):
				rescue_states.append([b.hp, game._game_over, game._dying_contexts.size()])
				return CardData.CardSubType.PEACH
			return -1
		await game._deal_damage_result(a, b, 2, EffectChain.DamageType.PHYSICAL)
		suite.check(rescue_states == [[-1, false, 1], [0, false, 1]] and b.hp == 1 and b.is_alive() and not game._game_over, "G01b negative-HP real rescue pays both peaches without premature victory")
		suite.check(c.hand_size() == 0 and game.deck._discard.size() == 2 and (not concrete or peaches.all(func(card): return game.deck._discard.count(card) == 1)) and game._dying_contexts.is_empty(), "G01b rescue original instances exactly once and active context released")
		game.queue_free()
		await suite.process_frame
		# A real legal cost can kill the turn owner without ending a three-player
		# First, nested rescue inside the real death-before priority rule.
		game = await factory.new_game(suite, 3, "里奥·普利威尔")
		leo = game.players[0]
		b = game.players[1]
		c = game.players[2]
		leo.hp = 1
		b.hp = 2
		game.turn_manager.current_player_idx = 1
		original = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
		var rescue_card: CardBase = CardBase.create(CardData.CardSubType.PEACH) if concrete else null
		if concrete:
			b.determined_cards.append(original)
			c.determined_cards.append(rescue_card)
		else:
			b.hand.append(null)
			c.hand.append(null)
		var nested_states: Array = []
		game._rescue_choice_override = func(r, d, options):
			if r == c and d == b and options.has(CardData.CardSubType.PEACH):
				nested_states.append([game._dying_contexts.size(), game.yudaxi.is_active(), game._game_over])
				return CardData.CardSubType.PEACH
			return -1
		await game.execute_card_on_target(leo, CardData.CardSubType.STRIKE)
		suite.check(nested_states == [[2, true, false]] and leo.is_dead() and b.hp == 1 and c.hp == 3 and not game._game_over and game.yudaxi.results[0].deaths == 0,
			"G01b nested actual peach rescue inside yudaxi excludes saved child from X and prevents premature winner")
		suite.check(game._dying_contexts.is_empty() and game._pending_card_actions.is_empty() and game.deck._discard.size() == 2 and (not concrete or (game.deck._discard.count(original) == 1 and game.deck._discard.count(rescue_card) == 1)),
			"G01b nested real rescue releases both owners and pays original strike/peach exactly once")
		game.queue_free()
		await suite.process_frame
		# A real legal cost can kill the turn owner without ending a three-player
		# game. The already paid strike continues with no source, not a new turn.
		game = await factory.new_game(suite, 3)
		a = game.players[0]
		b = game.players[1]
		a.hp = 1
		var spear = CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR)
		a.equip_card_to_slot("weapon", spear)
		original = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
		if concrete: a.determined_cards.append(original)
		else: a.hand.append(null)
		game._zhangba_override = func(): return 1
		var revision = game.turn_manager.get_context_revision()
		var hp_before = b.hp
		await game.execute_card_on_target(b, CardData.CardSubType.STRIKE)
		suite.check(a.is_dead() and b.hp == hp_before - 2 and not game._game_over and game.turn_manager.current_player_idx == 0 and game.turn_manager.get_context_revision() == revision, "G01b lethal zhangba cost settles turn-owner death before original unsourced strike, no invented turn insertion")
		suite.check(game._dying_contexts.is_empty() and game._pending_card_actions.is_empty() and game._dead_processed == [a] and game.deck._discard.count(spear) == 1, "G01b turn-owner death has one cleanup, no card/dying owner leak")
		game.queue_free()
		await suite.process_frame
	# All-dead input is a defensive settlement fixture, not a newly invented
	# simultaneous-damage card. Both are already dying when this entry starts.
	var game = await factory.new_game(suite, 2)
	var winners: Array = []
	game.game_over.connect(func(w): winners.append(w))
	for p in game.players: p.hp = 0
	await game._resolve_dying(game.players[0], null, "G01 pre-existing dying state")
	suite.check(winners.is_empty() and game.players[0].is_dead() and game.players[1].is_dying(), "G01b pre-existing other dying player blocks interim survivor victory")
	await game._resolve_dying(game.players[1], null, "G01 pre-existing dying state")
	suite.check(winners == ["平局"] and game.players.all(func(p): return p.is_dead()) and game._dying_contexts.is_empty(), "G01b all-final-dead FFA goes through actual cleanup to one draw")
	game.queue_free()
	await suite.process_frame
	# Complete legal five-player identity layout, with explicit earlier deaths.
	for winner in ["主公", "反贼", "内奸"]:
		game = await factory.new_game(suite, 5)
		var target_index = 3 if winner == "主公" else 0
		var actor_index = 0 if winner == "主公" else (4 if winner == "内奸" else 1)
		var keep = [0, 1, 3] if winner == "主公" else ([0, 4] if winner == "内奸" else [0, 1, 2, 3, 4])
		for i in game.players.size():
			if not keep.has(i):
				game.players[i].hp = 0
				game.players[i].mark_dead()
		var actor = game.players[actor_index]
		var target = game.players[target_index]
		target.hp = 1
		actor.hand.append(null)
		game.turn_manager.current_player_idx = actor_index
		winners = []
		var captured = winners
		game.game_over.connect(func(w): captured.append(w))
		await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
		suite.check(winners == [winner] and target.is_dead() and target.identity_revealed and game._dying_contexts.is_empty(), "G01b real five-player final kill commits correct " + winner + " victory only after reveal/cleanup")
		suite.check(actor.hand_size() == (3 if winner == "主公" else 0) and game._dead_processed == [target], "G01b existing identity reward before terminal exactly once; FFA exception not generalized")
		game.queue_free()
		await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
