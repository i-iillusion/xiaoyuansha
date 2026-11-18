extends RefCounted

func give(p: Player, count: int) -> Array[CardBase]:
	var cards: Array[CardBase] = []
	for i in count:
		cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
	p.determined_cards.append_array(cards)
	return cards

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var fixture = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for count in [0,1,2,3,4,5,6]:
		var game = fixture.fixture(t)
		var sally = game.players[0]
		var target = game.players[1]
		sally.sally_smoking_enabled = true
		sally.sally_boost_turn = game.turn_manager.turn_id
		var duel = CardBase.create(CardData.CardSubType.DUEL)
		sally.determined_cards.append(duel)
		var expected: Array[Player] = []
		var paid: Array[CardBase] = []
		for i in count:
			var responder = game.players[2 + i % 3]
			expected.append(responder)
			paid.append_array(give(responder,1))
		game._nullify_override = func(): return true
		var facts: Array = []
		game.card_action_committed.connect(func(event): facts.append(event))
		await game.execute_card_on_target(target,CardData.CardSubType.DUEL)
		var groups = count >> 1
		t.check(target.hp == (5 if groups % 2 == 1 else 4), "I05e5c only complete pairs toggle Duel counter parity: %d payments" % count)
		var counters = facts.filter(func(e): return e.card.sub_type == CardData.CardSubType.NULLIFICATION)
		t.check(counters.map(func(e): return e.actor_body) == expected, "I05e5c contributions alternate downstream across players: %d payments" % count)
		t.check(paid.all(func(card): return game.deck._discard.count(card) == 1) and facts.size() == count+1 and facts.all(func(e): return e.settlement_completed) and game._pending_card_actions.is_empty(), "I05e5c partial or complete payments and paid Duel settle once: %d" % count)
		await fixture.dispose(t,game)
	await delayed(t,fixture)
	await bridge_response(t,fixture)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]; GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func delayed(t,fixture):
	for boosted in [false,true]:
		for count in [1,2]:
			var game = fixture.fixture(t)
			var sally = game.players[0]
			var holder = game.players[1]
			sally.sally_smoking_enabled = true
			if boosted: sally.sally_boost_turn = game.turn_manager.turn_id
			var original = CardBase.create(CardData.CardSubType.INDULGENCE)
			sally.determined_cards.append(original)
			await game.execute_card_on_target(holder,CardData.CardSubType.INDULGENCE)
			t.check(holder.judgment_cards == [original] and original.judgment_nullification_count == (2 if boosted else 1), "I05e5c actual delayed placement stores its response count")
			sally.sally_boost_turn = -1
			game.turn_manager.current_player_idx = 1
			var cards = give(game.players[2],count)
			game._nullify_override = func(): return true
			var finished = await game._run_judgment(holder,false)
			var skipped = count == (1 if boosted else 2)
			t.check(finished and game.turn_manager.skip_play_phase == skipped and holder.judgment_cards.is_empty() and game.deck._discard.count(original) == 1, "I05e5c later Indulgence judgment uses placement boost after expiration (boost=%s, paid=%d)" % [boosted,count])
			t.check(cards.all(func(card): return game.deck._discard.count(card) == 1), "I05e5c single responder payments are consumed once")
			await fixture.dispose(t,game)

func duel_on(game,target,done):
	await game.execute_card_on_target(target,CardData.CardSubType.DUEL)
	done.append(true)

func bridge_response(t,fixture):
	var game = fixture.fixture(t)
	var sally = game.players[0]
	var target = game.players[1]
	sally.sally_smoking_enabled = true
	sally.sally_boost_turn = game.turn_manager.turn_id
	sally.determined_cards.append(CardBase.create(CardData.CardSubType.DUEL))
	var first = give(game.players[2],1)[0]
	var second = give(game.players[3],1)[0]
	game._nullify_override = Callable()
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	bridge.game = game
	var controls = load("res://Test/i05_sally_smoking_action_cases.gd").new()
	var done: Array = []
	duel_on(game,target,done)
	await t.process_frame
	var label = "打出【无懈可击】"
	var first_token = controls.token(bridge,2,label)
	t.check(first_token != "" and not bridge.submit(3,first_token) and bridge.submit(2,first_token), "I05e5c real first remote contribution belongs to its owner")
	for i in 4: await t.process_frame
	var next_token = controls.token(bridge,3,label)
	t.check(next_token != "" and not bridge.submit(2,first_token) and bridge.submit(3,next_token), "I05e5c second owner completes group using a fresh token")
	for i in 4: await t.process_frame
	t.check(done == [true] and target.hp == 5 and game.deck._discard.count(first) == 1 and game.deck._discard.count(second) == 1, "I05e5c paid remote pair cancels the real Duel")
	bridge.game = null
	bridge.queue_free()
	await fixture.dispose(t,game)
