extends RefCounted

func strike(game, target, done):
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	done.append(true)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var fixture = load("res://Test/i05_sally_jiegui_cases.gd").new()
	var controls = load("res://Test/i05_sally_smoking_action_cases.gd").new()
	for mode in ["normal", "short", "pay", "decline", "timeout", "invalid", "awaken"]:
		var game = fixture.fixture(t)
		var owner = game.players[0]
		var target = game.players[1]
		owner.sally_jiegui_enabled = false
		owner.sally_smoking_enabled = true
		owner.sally_boost_turn = game.turn_manager.turn_id if mode != "normal" else -1
		var corruption: Array = []
		if mode == "awaken":
			target.general_name = "史蒂芬·彼特先斯"
			target.max_hp = 3
			target.hp = 3
			game._awaken_pick_override = func(): return 1
			game.players[2].general_name = "桑尼·斯派"
			game._corruption_rules_enabled = true
			game._corruption_choice_override = func(_actor,batch,_stage,_valid):
				corruption.append([batch.owner,batch.count])
				return -1
		var initial_hp = target.hp
		var original = CardBase.create(CardData.CardSubType.STRIKE)
		var first = CardBase.create(CardData.CardSubType.DODGE)
		owner.determined_cards.append(original)
		target.hand.append(first)
		var second = CardBase.create(CardData.CardSubType.DODGE)
		if mode not in ["short", "awaken"]:
			target.determined_cards.append(second)
		game._dodge_override = Callable()
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		var facts: Array = []
		game.card_action_committed.connect(func(event): facts.append(event))
		var done: Array = []
		strike(game,target,done)
		await t.process_frame
		var first_token = controls.token(bridge,1,"出【闪】")
		t.check(first_token != "" and bridge.submit(1,first_token), "I05e5a real first Dodge via remote input: " + mode)
		for i in 4: await t.process_frame
		if mode not in ["normal", "short"]:
			var next_token = controls.token(bridge,1,"出【闪】")
			t.check(next_token != "" and next_token != first_token and not bridge.submit(1,first_token), "I05e5a second prompt has fresh token: " + mode)
			if next_token != "":
				match mode:
					"pay", "awaken": bridge.submit(1,next_token)
					"decline": bridge.submit(1,controls.token(bridge,1,"不响应"))
					"timeout": game._countdown_on_timeout.call()
					"invalid": game._choice_prompt_stack.back().overlay.queue_free()
			for i in 4: await t.process_frame
		var hit = mode in ["short", "decline", "timeout"]
		t.check(done == [true] and target.hp == initial_hp-int(hit)-int(mode == "awaken") and game._pending_card_actions.is_empty(), "I05e5a completes, hits or invalidates correctly: " + mode)
		if mode == "awaken":
			t.check(target.awoken and target.hand_size() == 1 and corruption == [[target,2]], "I05e5a first Dodge completes awakening and Corruption before the second payment")
		t.check(game.deck._discard.count(original) == 1 and game.deck._discard.count(first) == 1 and game.deck._discard.count(second) == int(mode == "pay"), "I05e5a physical payments occur once and do not roll back: " + mode)
		t.check(facts.size() == (3 if mode in ["pay","awaken"] else 2) and facts[0].settlement_completed == (mode != "invalid") and facts[1].settlement_completed, "I05e5a parent and committed response facts settle independently: " + mode)
		bridge.game = null
		bridge.queue_free()
		await fixture.dispose(t,game)
	for required in [CardData.CardSubType.STRIKE,CardData.CardSubType.DODGE]:
		var game = fixture.fixture(t)
		var owner = game.players[0]
		owner.sally_smoking_enabled = true
		owner.sally_boost_turn = game.turn_manager.turn_id
		owner.hand.append(null)
		game.players[1].hand.append_array([null,null])
		game.players[2].hand.append(null)
		game._aoe_override = func(): return true
		await game._play_aoe(required,"范围锦囊","基本牌")
		t.check(game.players[1].hp == 5 and game.players[1].hand_size() == 0, "I05e5a AOE target with two cards pays both and avoids damage")
		t.check(game.players[2].hp == 4 and game.players[2].hand_size() == 0 and game.players[3].hp == 4, "I05e5a AOE target with one payment takes damage and next target settles")
		await fixture.dispose(t,game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]
