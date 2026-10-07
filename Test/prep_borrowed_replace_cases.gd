extends RefCounted

const BORROW = CardData.CardSubType.BORROWED_SWORD
const DUEL = CardData.CardSubType.DUEL
const CHAIN = CardData.CardSubType.IRON_CHAIN

func _play(game, sub, target):
	var targets: Array[Player] = [target]
	if sub == CHAIN: await game._execute_iron_chain(targets)
	else: await game.execute_card_on_target(target, sub)

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	# Into Borrow from each fixed single; out to every supported single/group.
	var pairs: Array = []
	for sub in [DUEL, CHAIN, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
		pairs.append([sub, BORROW])
	for sub in [DUEL, CHAIN, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE] + game.GLOBAL_TRICKS:
		pairs.append([BORROW, sub])
	for concrete in [false, true]:
		for pair in pairs:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var user: Player = game.players[1]
			var first: Player = game.players[2]
			var second: Player = game.players[3]
			var leo: Player = game.players[0]
			leo.general_name = "里奥·普利威尔"
			leo.prep_tokens = 1
			user.hp = 9
			var weapon = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			first.equip_card_to_slot("weapon", weapon)
			first.hand.append(null)
			var original = CardBase.create(pair[0]) if concrete else null
			if concrete: user.determined_cards.append(original)
			else: user.hand.append(null)
			var events: Array[CardActionEvent] = []
			var finished: Array[CardActionEvent] = []
			var commit = func(e): events.append(e)
			var finish = func(e): finished.append(e)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			game._prep_replace_override = func(owner, actor, fixed, sub, options):
				suite.check(owner == leo and actor == user and fixed == first and sub == pair[0] and options.has(pair[1]), "F02 prep Borrow preserves user/first, offers legal new effect")
				suite.check(events.size() == 1 and finished.is_empty() and leo.prep_tokens == 1 and tm.borrowed_sword_count_this_turn == 0, "F02 prep Borrow no early mark/count/second window")
				return pair[1]
			var seconds: Array[int] = [0]
			game._borrowed_second_target_override = func(options):
				seconds[0] += 1
				suite.check(leo.prep_tokens == 0 and options.has(second), "F02 prep Borrow second selection follows final replacement payment")
				return options.find(second)
			game._borrowed_strike_override = func(actor, target, _options):
				suite.check(actor == first and target == second, "F02 prep Borrow first uses strike on caster-selected second")
				return CardData.CardSubType.STRIKE
			game._prep_steal_pick_override = func(_options): return 0
			game._aoe_override = func(): return false
			await _play(game, pair[0], first)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(events.size() == (2 if pair[1] == BORROW else 1) and finished.back() == events[0] and events[0].settlement_completed, "F02 prep Borrow one original parent completes after final effect")
			suite.check(events[0].card.sub_type == pair[0] and game.deck._discard.count(events[0].card) == 1 and (not concrete or events[0].card == original), "F02 prep Borrow original entity/name kept, one payment")
			suite.check(leo.prep_tokens == 0 and seconds[0] == (1 if pair[1] == BORROW else 0) and game._pending_card_actions.is_empty(), "F02 prep Borrow no intermediate second target or pending receipt")
			suite.check(tm.borrowed_sword_count_this_turn == (1 if pair[1] == BORROW else 0) and tm.duel_count_this_turn == (1 if pair[1] == DUEL else 0) and tm.steal_count_this_turn == (1 if pair[1] in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE] else 0) and tm.strike_count_this_turn == 0, "F02 prep Borrow final type alone counted")
			suite.check(first.chained == (pair[1] == CHAIN) and first.hp == (9 if pair[1] == DUEL or pair[1] in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS] else 10), "F02 prep Borrow no original/intermediate effect")
			suite.check(second.hp == (9 if pair[1] in [BORROW, CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS] else 10), "F02 prep Borrow final strike/AOE reaches correct second")
			suite.check(user.hp == (10 if pair[1] == CardData.CardSubType.PEACH_GARDEN else 9), "F02 prep Borrow expanded peach includes original caster")
	# Continuous: intermediate Borrow must never choose second/count; final Borrow does once.
	for mode in ["to_chain", "back_borrow", "virtual", "own", "limit", "fresh_limit", "no_weapon", "invalid", "restart"]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var first: Player = game.players[2]
		var second: Player = game.players[3]
		var leo: Player = user if mode == "own" else game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 2 if mode in ["to_chain", "back_borrow"] else 1
		user.hand.append(null)
		first.hand.append(null)
		if mode != "no_weapon": first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		if mode == "limit": tm.borrowed_sword_count_this_turn = 2
		if mode == "virtual":
			user.general_name = "安普提·斯丢皮得"
			game._yes_ah_active = true
		var calls: Array[int] = [0]
		game._prep_replace_override = func(_owner, actor, fixed, current_sub, options):
			calls[0] += 1
			suite.check(actor == user and fixed == first and options.has(BORROW) == (mode not in ["limit", "no_weapon"] and current_sub != BORROW), "F02 prep Borrow candidate respects weapon/quota/current type")
			if mode == "fresh_limit": tm.borrowed_sword_count_this_turn = 2
			if mode == "invalid":
				tm.current_phase = TurnManager.Phase.END
				tm.current_phase = TurnManager.Phase.PLAY
			if mode == "restart": game.reset_game_over_state()
			return CHAIN if mode == "to_chain" and calls[0] == 2 else DUEL if mode == "back_borrow" and calls[0] == 1 else BORROW
		var seconds: Array[int] = [0]
		game._borrowed_second_target_override = func(options):
			seconds[0] += 1
			return options.find(second)
		game._borrowed_strike_override = func(_actor, _target, _options): return -1
		var events: Array[CardActionEvent] = []
		var commit = func(e): events.append(e)
		game.card_action_committed.connect(commit)
		await _play(game, BORROW if mode == "back_borrow" else DUEL, first)
		game.card_action_committed.disconnect(commit)
		var invalid = mode in ["invalid", "restart"]
		var final_borrow = mode in ["back_borrow", "virtual", "own"]
		suite.check(events.size() == 1 and events[0].settlement_completed == not invalid and events[0].is_virtual == (mode == "virtual"), "F02 prep Borrow continuous/virtual invalidity preserves single original use")
		suite.check(seconds[0] == (1 if final_borrow else 0) and tm.borrowed_sword_count_this_turn == (2 if mode in ["limit", "fresh_limit"] else 1 if final_borrow else 0), "F02 prep Borrow only final valid Borrow opens second/count")
		suite.check(leo.prep_tokens == (1 if mode == "own" or mode in ["limit", "fresh_limit", "no_weapon", "invalid", "restart"] else 0), "F02 prep Borrow confirmed replacement spends old marks, own parent replenishes after completion")
		suite.check(game.deck._discard.count(events[0].card) == (0 if mode == "virtual" else 1) and user.hp == (9 if mode == "virtual" else 10), "F02 prep Borrow virtual pays HP once, never physical discard")
		if final_borrow: suite.check(user.determined_cards.size() == 1 and first.get_equipment_card("weapon") == null, "F02 prep Borrow refusal gives original weapon to original caster")
		if mode == "to_chain": suite.check(first.chained and tm.duel_count_this_turn == 0, "F02 prep Borrow intermediate effect not executed or counted")
	# Original Borrow changed into Snatch may legally remove the very weapon it targeted.
	# Hidden equipment must be declared by its original holder after the real move.
	for concrete in [false, true]:
		for replaced in [false, true]:
			resetter._reset(suite)
			game.deck._discard.clear()
			game.equipment_pool.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			var holder: Player = game.players[0]
			var user: Player = game.players[1]
			var leo: Player = game.players[2]
			holder.general_name = "安普提·斯丢皮得"
			holder.hidden_equip_slot = ""
			holder.hidden_equip_card = null
			var original_weapon = CardBase.create(CardData.CardSubType.QINGGANG_SWORD) if concrete else null
			if concrete: holder.determined_cards.append(original_weapon)
			else: holder.hand.append(null)
			game._sao_type_override = func(): return "weapon"
			await game._do_sao_hide(holder, false)
			var hidden = holder.get_hidden_equipment_card("weapon")
			suite.check(hidden != null and holder.hand_size() == 0 and (not concrete or hidden == original_weapon), "F02 prep Borrow hidden weapon is real paid original")
			tm.play_actor_idx = 1
			user.hand.append(null)
			leo.general_name = "里奥·普利威尔"
			leo.prep_tokens = 1 if replaced else 0
			game._prep_replace_override = func(_l, _u, _t, _s, _o): return CardData.CardSubType.SNATCH
			game._borrowed_second_target_override = func(options): return options.find(user)
			game._borrowed_strike_override = func(_a, _t, _o): return -1
			game._prep_steal_pick_override = func(options):
				suite.check(options.size() == 1 and options[0].zone == "equip", "F02 prep Borrow changed Snatch selects original weapon only")
				return 0
			game._sao_transfer_declare_override = func():
				suite.check(user.determined_cards == [hidden] and holder.get_hidden_equipment_card("weapon") == null, "F02 prep Borrow declares only after original hidden weapon moved")
				return CardData.CardSubType.QINGGANG_SWORD if concrete else CardData.CardSubType.CALAMITY_SWORD
			var events: Array[CardActionEvent] = []
			var commit = func(e): events.append(e)
			game.card_action_committed.connect(commit)
			await game.execute_card_on_target(holder, BORROW)
			game.card_action_committed.disconnect(commit)
			suite.check(events.size() == 1 and events[0].settlement_completed and user.determined_cards == [hidden], "F02 prep Borrow original/refactored hidden transfer completes parent once")
			suite.check(hidden.sub_type == (CardData.CardSubType.QINGGANG_SWORD if concrete else CardData.CardSubType.CALAMITY_SWORD) and not game.deck._discard.has(hidden) and holder.get_equipment_card("weapon") == null, "F02 prep Borrow transfer declares same physical weapon, never loses/copies it")
			suite.check(tm.borrowed_sword_count_this_turn == (0 if replaced else 1) and tm.steal_count_this_turn == (1 if replaced else 0), "F02 prep Borrow changed Snatch releases original Borrow weapon guard/count")
			holder.hidden_equip_slot = ""
			holder.hidden_equip_card = null
	game._sao_type_override = Callable()
	game._sao_transfer_declare_override = Callable()
	# Two living players: only southern/arrow can shrink into Borrow, not peach/harvest.
	var old_mode = game.game_mode
	for original_sub in game.GLOBAL_TRICKS:
		resetter._reset(suite)
		game.game_mode = GameManager.MODE_FREE_FOR_ALL
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		for idx in [0, 3, 4]: game.players[idx].mark_dead()
		var user: Player = game.players[1]
		var first: Player = game.players[2]
		user.general_name = "里奥·普利威尔"
		user.prep_tokens = 1
		user.hp = 9
		user.hand.append(null)
		first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		var attack = original_sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS]
		game._prep_replace_override = func(_leo, _actor, _fixed, _sub, options):
			suite.check(options.has(BORROW) == attack, "F02 prep Borrow two-player exception excludes peach/harvest/disarm")
			return BORROW if attack else -1
		game._borrowed_second_target_override = func(options):
			suite.check(options == [user], "F02 prep Borrow second may be original caster when legal")
			return 0
		var targets: Array[Player] = [first]
		await load("res://Test/prep_group_replace_cases.gd").new()._play(game, original_sub, targets)
		suite.check(tm.borrowed_sword_count_this_turn == (1 if attack else 0) and user.prep_tokens == (1 if attack else 2), "F02 prep Borrow two-player final category and completion mark")
	game.game_mode = old_mode
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	game._aoe_override = Callable()
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
