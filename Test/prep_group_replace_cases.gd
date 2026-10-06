extends RefCounted

const GROUPS = [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS, CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST, CardData.CardSubType.DISARM]

func _play(game, sub, targets: Array[Player]):
	match sub:
		CardData.CardSubType.BARBARIAN_INVASION: await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
		CardData.CardSubType.VOLLEY_OF_ARROWS: await game._play_aoe(CardData.CardSubType.DODGE, "万箭齐发", "闪")
		CardData.CardSubType.PEACH_GARDEN: await game._play_peach_garden()
		CardData.CardSubType.HARVEST: await game._play_harvest()
		CardData.CardSubType.DISARM: await game._play_disarm()
		CardData.CardSubType.IRON_CHAIN: await game._execute_iron_chain(targets)
		_: await game.execute_card_on_target(targets[0], sub)

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var mode = game.game_mode
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	var originals = GROUPS + [CardData.CardSubType.DUEL, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE, CardData.CardSubType.IRON_CHAIN]
	for concrete in [false, true]:
		for original_sub in originals:
			for final_sub in GROUPS:
				if original_sub == final_sub: continue
				resetter._reset(suite)
				game.deck._discard.clear()
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = 1
				var user: Player = game.players[1]
				var target: Player = game.players[2]
				var leo: Player = game.players[0]
				leo.general_name = "里奥·普利威尔"
				leo.prep_tokens = 1
				user.hp = 9
				target.hp = 9
				target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
				var original: CardBase = CardBase.create(original_sub) if concrete else null
				if concrete: user.determined_cards.append(original)
				else: user.hand.append(null)
				game._aoe_override = func(): return false
				var events: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var commit = func(e): events.append(e)
				var finish = func(e): completed.append(e)
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				game._prep_replace_override = func(owner, actor, _fixed, current, options):
					suite.check(owner == leo and actor == user and current == original_sub and options.has(final_sub), "F02b-3b group offered with original user")
					suite.check(not options.has(CardData.CardSubType.SACRIFICE) and options.has(CardData.CardSubType.HARVEST) == (original_sub != CardData.CardSubType.HARVEST) and options.has(CardData.CardSubType.DISARM) == (original_sub != CardData.CardSubType.DISARM), "F02b-3b Q14 conditional/empty scopes allowed, sacrifice forbidden")
					if original_sub in game.GLOBAL_TRICKS:
						suite.check(not options.has(CardData.CardSubType.DUEL) and not options.has(CardData.CardSubType.IRON_CHAIN), "F02b-3b five-player group never shrinks to single")
					suite.check(events.size() == 1 and completed.is_empty() and leo.prep_tokens == 1, "F02b-3b original committed before prep, no early mark")
					return final_sub
				var targets: Array[Player] = [target]
				await _play(game, original_sub, targets)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				suite.check(events.size() == 1 and completed == events and events[0].card.sub_type == original_sub and game.deck._discard.count(events[0].card) == 1 and (not concrete or events[0].card == original), "F02b-3b original entity/name one payment/USE/completion")
				var attack = final_sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS]
				suite.check(user.hand_size() == (1 if final_sub == CardData.CardSubType.HARVEST else 0) and target.hand_size() == (2 if final_sub == CardData.CardSubType.HARVEST else 1) and not target.chained, "F02b-3b no intermediate steal/draw/chain or second payment")
				suite.check(user.hp == (10 if final_sub == CardData.CardSubType.PEACH_GARDEN else 9) and target.hp == (8 if attack else (10 if final_sub == CardData.CardSubType.PEACH_GARDEN else 9)), "F02b-3b peach includes original user, attack excludes user")
				suite.check(game.players[3].hp == (9 if attack else 10), "F02b-3b expanded scope reaches other player")
				suite.check(tm.aoe_count_this_turn == (1 if attack else 0) and tm.peach_garden_count_this_turn == (1 if final_sub == CardData.CardSubType.PEACH_GARDEN else 0), "F02b-3b final global category only")
				suite.check(tm.duel_count_this_turn == 0 and tm.steal_count_this_turn == 0 and tm.harvest_count_this_turn == (1 if final_sub == CardData.CardSubType.HARVEST else 0) and tm.disarm_count_this_turn == (1 if final_sub == CardData.CardSubType.DISARM else 0) and leo.prep_tokens == 0 and game._pending_card_actions.is_empty(), "F02b-3b no original/intermediate usage or pending receipt")
	# Only southern/arrow scope gains the two-survivor exception, not peach/harvest.
	for sub in GROUPS:
		resetter._reset(suite)
		game.game_mode = GameManager.MODE_FREE_FOR_ALL
		for idx in [0, 3, 4]: game.players[idx].mark_dead()
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		user.general_name = "里奥·普利威尔"
		user.prep_tokens = 1
		user.hand.append(null)
		target.hand.append(null)
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var southern = sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS]
		game._prep_replace_override = func(_owner, actor, fixed, _current, options):
			suite.check(actor == user and fixed == target and options.has(CardData.CardSubType.DUEL) == southern and options.has(CardData.CardSubType.IRON_CHAIN) == southern, "F02b-3b two-player exception restricted to southern/arrows")
			return CardData.CardSubType.DUEL if southern else -1
		var targets: Array[Player] = [target]
		await _play(game, sub, targets)
		suite.check(target.hp == (9 if southern else 10) and tm.duel_count_this_turn == (1 if southern else 0) and user.prep_tokens == (1 if southern else 2), "F02b-3b exception resolves fixed other, own mark only after completion")
	# Two-target chain may expand, never execute its intermediate toggle.
	for final_sub in GROUPS:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		game.players[1].hand.append(null)
		game.players[0].general_name = "里奥·普利威尔"
		game.players[0].prep_tokens = 1
		game._prep_replace_override = func(_owner, _actor, fixed, _current, options):
			suite.check(fixed == null and options == GROUPS, "F02b-3b two-chain only known groups")
			return final_sub
		var targets: Array[Player] = [game.players[2], game.players[3]]
		await _play(game, CardData.CardSubType.IRON_CHAIN, targets)
		suite.check(not targets[0].chained and not targets[1].chained and game.players[4].hp == (9 if final_sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS] else 10), "F02b-3b two-chain expands once without intermediate effect")
	# Continuous replacement: one original fact, no intermediate healing, own mark deferred.
	for mode_name in ["continuous", "decline", "fresh_limit", "invalid", "restart", "equipment", "limited", "empty"]:
		resetter._reset(suite)
		game.game_mode = mode
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		var leo: Player = user
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 2
		user.hp = 8
		target.hp = 8
		user.hand.append(null)
		var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		if mode_name == "equipment": target.equip_card_to_slot("mount_1", mount)
		if mode_name == "limited":
			tm.harvest_count_this_turn = 1
			tm.disarm_count_this_turn = 1
		var windows: Array[int] = [0]
		game._prep_replace_override = func(_owner, actor, _fixed, current, options):
			windows[0] += 1
			suite.check(actor == user and user.prep_tokens == (2 if windows[0] == 1 else 1), "F02b-3b continuous uses only old marks")
			if mode_name == "limited":
				suite.check(not options.has(CardData.CardSubType.HARVEST) and not options.has(CardData.CardSubType.DISARM), "F02b-3b conditional groups still obey limits")
				return -1
			if mode_name == "fresh_limit":
				tm.peach_garden_count_this_turn = 1
				return CardData.CardSubType.PEACH_GARDEN
			if mode_name in ["equipment", "empty"]: return CardData.CardSubType.DISARM if windows[0] == 1 else -1
			if windows[0] == 1: return CardData.CardSubType.PEACH_GARDEN
			if mode_name == "invalid":
				tm.current_phase = TurnManager.Phase.END
				tm.current_phase = TurnManager.Phase.PLAY
			elif mode_name == "restart": game.reset_game_over_state()
			if mode_name != "continuous": return -1
			suite.check(current == CardData.CardSubType.PEACH_GARDEN and options.has(CardData.CardSubType.BARBARIAN_INVASION), "F02b-3b current group governs next candidates")
			return CardData.CardSubType.BARBARIAN_INVASION
		await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
		var invalid = mode_name in ["invalid", "restart"]
		suite.check(target.hp == (7 if mode_name in ["continuous", "fresh_limit", "limited"] else (9 if mode_name == "decline" else 8)), "F02b-3b no intermediate group effects; fresh/invalid branches")
		suite.check(user.hp == (9 if mode_name == "decline" else 8), "F02b-3b continuous back to attack never heals user")
		suite.check(user.prep_tokens == (1 if mode_name in ["continuous", "invalid", "restart"] else (3 if mode_name in ["fresh_limit", "limited"] else 2)), "F02b-3b paid marks retained, own completion once or abandoned")
		suite.check(game._pending_card_actions.is_empty() and (not invalid or tm.aoe_count_this_turn == 0), "F02b-3b invalid continuation releases receipt without final count")
		if mode_name in ["equipment", "empty"]:
			suite.check(target.equipment.is_empty() and target.hand_size() == (1 if mode_name == "equipment" else 0) and tm.disarm_count_this_turn == 1 and tm.aoe_count_this_turn == 0, "F02b-3b empty/populated disarm final effect and usage")
			if mode_name == "equipment": suite.check(game.deck._discard.count(mount) == 1, "F02b-3b disarm moves original mount once")
	# Real prep popup for group card: optional decline/timeout, not mandatory target policy.
	var bank = game._bank_remaining
	for mode_name in ["confirm", "timeout", "close"]:
		resetter._reset(suite)
		game.game_mode = mode
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		game.players[1].hand.append(null)
		game.players[1].hp = 8
		game.players[0].general_name = "里奥·普利威尔"
		game.players[0].prep_tokens = 1
		game._prep_replace_override = Callable()
		var drive = func():
			suite.check(game._choice_prompt_stack.size() == 1 and game._countdown_active and game._step_remaining > 29.0, "F02b-3b real group prep basic countdown")
			var pending = game._choice_prompt_stack.back()
			if mode_name == "confirm": pending.answer.submit(1) # southern -> [arrows, peach, harvest, disarm]
			elif mode_name == "close": pending.overlay.queue_free()
			else:
				game._step_remaining = 0.001
				game._bank_remaining = 0.0
				game._process(0.01)
		drive.call_deferred()
		await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
		suite.check(game.players[1].hp == (9 if mode_name == "confirm" else 8) and game.players[2].hp == (9 if mode_name == "timeout" else 10), "F02b-3b real confirmation/timeout/invalid effect")
		suite.check(game.players[0].prep_tokens == (0 if mode_name == "confirm" else 1) and game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty(), "F02b-3b real popup mark/default/release")
	game._bank_remaining = bank
	resetter._reset(suite)
	game._aoe_override = Callable()
	game.game_mode = mode
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
