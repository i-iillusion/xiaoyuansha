extends RefCounted
const DAVID = "大卫·法米尔"

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	# This is a mid-PLAY resource fixture. Public startup now records initial
	# deals/normal DRAW too; start the isolated receipt ledger at this prefix.
	# Ordinary opening capture is tested separately through actual start_game.
	game._draw_batches.clear()
	game._draw_batch_serial=0
	game.lan_enabled = true
	game._david_rules_enabled = true
	game._nullify_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game._duel_respond_override = func(): return false
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var p = game.players[0]
	p.general_name = DAVID
	p.max_hp = 4
	p.hp = 4
	p.hand.clear()
	p.determined_cards.clear()
	p.capture_game_start_state()
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await immediate(t)
	await paid_responses(t)
	await filters_and_turns(t)
	await resets_and_gate(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func immediate(t):
	for concrete in [false, true]:
		var game = fixture(t)
		var p = game.players[0]
		var target = game.players[1]
		target.hand.clear()
		target.determined_cards.clear()
		var wine = CardBase.create(CardData.CardSubType.WINE) if concrete else null
		var duel = CardBase.create(CardData.CardSubType.DUEL) if concrete else null
		if concrete: p.determined_cards.assign([wine, duel])
		else: p.hand.assign([null, null])
		var facts: Array = []
		var seen: Array = []
		game.card_action_committed.connect(func(a):
			facts.append(a)
			seen.append([p.farm_empty_fields, a.settlement_completed]))
		await game.play_card(CardData.CardSubType.WINE)
		t.check(p.farm_hand_actions == 1 and p.farm_empty_fields == 0, "I05b first paid hand card gives no field")
		var counter_seen: Array = []
		game._nullify_override = func():
			counter_seen.append([p.farm_empty_fields, facts.back().settlement_completed])
			return false
		await game.execute_card_on_target(target, CardData.CardSubType.DUEL)
		t.check(facts.size() == 2 and seen == [[0, false], [1, false]], "I05b Q1 field exists before committed observers and original settlement")
		t.check(not counter_seen.is_empty() and counter_seen[0] == [1, false], "I05b Q1 original Duel counter window already sees new field")
		t.check(p.farm_hand_actions == 2 and p.farm_empty_fields == 1 and p.hand_size() == 0, "I05b two actual hand payments give exactly one field")
		t.check(facts.all(func(a): return a.from_hand and not a.is_virtual and a.settlement_completed), "I05b original paid USE facts retain completion and hand origin")
		if concrete:
			t.check(facts[0].card == wine and facts[1].card == duel and game.deck._discard.count(wine) == 1 and game.deck._discard.count(duel) == 1, "I05b concrete dual-storage resources keep original identity and discard once")
		else:
			t.check(facts[0].sub_type == CardData.CardSubType.WINE and facts[1].sub_type == CardData.CardSubType.DUEL, "I05b ordinary blanks concretize only as declared actual cards")
		game._complete_card_actions(facts)
		game._complete_card_actions(facts)
		t.check(p.farm_empty_fields == 1 and p.farm_hand_actions == 2, "I05b repeated completion never repeats immediate farming")
		await dispose(t, game)

func paid_responses(t):
	var game = fixture(t)
	var p = game.players[0]
	var original = CardBase.create(CardData.CardSubType.THUNDER_STRIKE)
	p.hand.append(null)
	p.determined_cards.append(original)
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	var declined = await game._ask_basic_card_response_result(p, CardData.CardSubType.STRIKE, Callable(), func(): return false)
	t.check(declined == GameManager.BasicResponseOutcome.DECLINED and p.hand_size() == 2 and facts.is_empty(), "I05b declined actual response never pays or records farming")
	var paid = await game._ask_basic_card_response_result(p, CardData.CardSubType.STRIKE, Callable(), func(): return true)
	t.check(paid == GameManager.BasicResponseOutcome.PAID and facts.size() == 1 and facts[0].card == original and p.farm_hand_actions == 1, "I05b actual response accepts original elemental Strike from determined hand")
	paid = await game._ask_basic_card_response_result(p, CardData.CardSubType.DODGE, Callable(), func(): return true)
	t.check(paid == GameManager.BasicResponseOutcome.PAID and facts.size() == 2 and facts[1].kind == CardActionEvent.Kind.RESPONSE and p.farm_empty_fields == 1, "I05b second actual paid response gives field with ordinary blank")
	var missing = await game._ask_basic_card_response_result(p, CardData.CardSubType.DODGE, Callable(), func(): return true)
	t.check(missing == GameManager.BasicResponseOutcome.DECLINED and facts.size() == 2 and p.farm_hand_actions == 2, "I05b unavailable physical payment creates neither action nor field")
	p.hand.append(null)
	var stale = await game._ask_basic_card_response_result(p, CardData.CardSubType.DODGE, Callable(), func():
		p.hand.append(null)
		return true)
	t.check(stale == GameManager.BasicResponseOutcome.DECLINED and p.hand_size() == 2 and facts.size() == 2, "I05b stale hand selection cannot pay a replacement resource or count")
	var invalid = await game._ask_basic_card_response_result(p, CardData.CardSubType.DODGE, Callable(), func(): return GameManager.CHOICE_INVALID)
	t.check(invalid == GameManager.BasicResponseOutcome.INVALIDATED and facts.size() == 2 and p.farm_empty_fields == 1, "I05b invalidated actual response leaves previous field and hand intact")
	# Explicit general substitution isolates the two hooks; it does not authorize copying skills.
	p.general_name = "里奥·普利威尔"
	var leo = game._record_card_action(p, CardBase.create(CardData.CardSubType.NULLIFICATION))
	t.check(p.prep_tokens == 0 and p.farm_hand_actions == 2, "I05b Leo still gets no mark at commitment and never farms")
	game._complete_card_actions([leo])
	t.check(p.prep_tokens == 1 and p.farm_empty_fields == 1, "I05b Leo completion mark stays independent of David immediate fields")
	await dispose(t, game)

func filters_and_turns(t):
	var game = fixture(t)
	var p = game.players[0]
	var actions: Array = []
	# Explicit event-boundary fixtures below are not natural-game/LAN lifecycle proof.
	for kind in [CardActionEvent.Kind.USE, CardActionEvent.Kind.RESPONSE, CardActionEvent.Kind.RESPONSE, CardActionEvent.Kind.USE]:
		actions.append(game._record_card_action(p, CardBase.create(CardData.CardSubType.STRIKE), kind, true, false))
	t.check(p.farm_hand_actions == 4 and p.farm_empty_fields == 2, "I05b every two successful USE/RESPONSE facts count together")
	game._complete_card_actions(actions)
	t.check(p.farm_empty_fields == 2, "I05b finishing a response batch never gives a second set of fields")
	var count = p.farm_hand_actions
	for flags in [[false, true], [true, true], [false, false]]:
		var event = game._record_card_action(p, CardBase.create(CardData.CardSubType.NULLIFICATION), CardActionEvent.Kind.USE, flags[0], flags[1])
		game._complete_card_actions([event])
	t.check(p.farm_hand_actions == count and p.farm_empty_fields == 2, "I05b virtual or non-hand facts never count even with inconsistent hand flag")
	p.hand.assign([null, null])
	t.check(game._discard_hand_cards(p, 2), "I05b real discard-cost helper pays both ordinary blanks")
	t.check(p.farm_hand_actions == count and p.farm_empty_fields == 2, "I05b actual skill discard is not a hand USE/RESPONSE")
	var old_turn = game.turn_manager.turn_id
	game.turn_manager.current_phase = TurnManager.Phase.WAITING
	var response = game._record_card_action(p, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
	t.check(p.farm_hand_actions == 5 and p.farm_action_turn == old_turn, "I05b WAITING phase keeps owner's turn identity and odd remainder")
	game._complete_card_actions([response])
	game.turn_manager.current_player_idx = 1
	game.turn_manager.play_actor_idx = 0
	var gifted = game._record_card_action(p, CardBase.create(CardData.CardSubType.DUEL))
	game._complete_card_actions([gifted])
	t.check(p.farm_hand_actions == 5 and p.farm_empty_fields == 2, "I05b granted PLAY actor never impersonates the actual turn owner")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.turn_id += 1
	var next = game._record_card_action(p, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
	t.check(p.farm_hand_actions == 1 and p.farm_empty_fields == 2 and p.farm_action_turn != old_turn, "I05b fresh owner's turn resets pairing only, retaining existing fields")
	game._complete_card_actions([next])
	var second = game._record_card_action(p, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
	t.check(p.farm_hand_actions == 2 and p.farm_empty_fields == 3, "I05b new turn needs its own two cards to gain another field")
	game._complete_card_actions([second])
	await dispose(t, game)

func resets_and_gate(t):
	var unopened = GameManager.new()
	t.check(unopened._david_rules_enabled and unopened._wrestling_rules_enabled, "I05b accepted public constructor enables both David server capabilities")
	unopened.free()
	var game = fixture(t)
	var p = game.players[0]
	game._david_rules_enabled = false
	for i in 2:
		var event = game._record_card_action(p, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
		game._complete_card_actions([event])
	t.check(p.farm_hand_actions == 0 and p.farm_empty_fields == 0, "I05b explicit disabled server capability leaves farming inactive")
	game._david_rules_enabled = true
	p.farm_empty_fields = 3
	p.farm_good_fields = 2
	p.farm_action_turn = game.turn_manager.turn_id
	p.farm_hand_actions = 5
	var round_before = game.turn_manager.rounds.round_id
	p.identity_max_hp_bonus = 1
	p.identity = "忠臣"
	p.restore_game_start_state()
	t.check(p.farm_empty_fields == 0 and p.farm_good_fields == 0 and p.farm_action_turn == -1 and p.farm_hand_actions == 0, "I05b Sage general snapshot resets all farming state")
	t.check(p.max_hp == 5 and p.hp == 5 and p.identity == "忠臣" and game.turn_manager.rounds.round_id == round_before, "I05b farming reset never rewinds identity bonus, identity or round ledger")
	for i in 2:
		var event = game._record_card_action(p, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
		game._complete_card_actions([event])
	t.check(p.farm_empty_fields == 1 and p.farm_hand_actions == 2, "I05b restored general can start a fresh legal farming pair")
	t.check(GeneralData.GENERALS.has(DAVID) and GeneralData.get_available_random_generals().size() == 14 and GeneralData.get_implementation_status(DAVID) == "prototype" and LanSession.PROTOCOL == "campus-lan-17", "I05b fully accepted public David appears once with new LAN protocol/pool")
	await dispose(t, game)
