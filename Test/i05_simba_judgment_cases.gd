extends RefCounted
const SIMBA = "辛巴·古德曼"
const DELAYED = [CardData.CardSubType.LIGHTNING, CardData.CardSubType.INDULGENCE,
	CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	game.lan_enabled = true
	game._nullify_override = func(): return false
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
		p.judgment_cards.clear()
		p.max_hp = 5
		p.hp = 5
	game.players[0].general_name = SIMBA
	game.players[0].simba_wanci_enabled = true
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await judgments(t)
	await uses(t)
	await counters(t)
	await phases(t)
	await selectors(t)
	await invalidation(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func judgments(t):
	for granted in [false, true]:
		for sub in DELAYED:
			for enabled in [false, true]:
				var game = fixture(t)
				var p = game.players[0]
				p.simba_wanci_enabled = enabled
				var card = CardBase.create(sub)
				p.judgment_cards.append(card)
				var actions: Array = []
				game.card_action_committed.connect(func(a): actions.append(a))
				t.check(await game._run_judgment(p, granted), "I05d normal/granted judgment completes, private gate=" + str(enabled))
				var danger = sub in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.BURNING_CAMP]
				var hp = 5 if enabled or not danger else (2 if sub == CardData.CardSubType.LIGHTNING else 4)
				t.check(p.hp == hp, "I05d Wanci prevents judgment damage without changing ordinary baseline")
				t.check(game.turn_manager.skip_play_phase == (not enabled and not granted and sub == CardData.CardSubType.INDULGENCE), "I05d failed Indulgence does not skip PLAY")
				t.check(game.turn_manager.supply_shortage_active == (not enabled and not granted and sub == CardData.CardSubType.SUPPLY_SHORTAGE), "I05d failed Supply does not reduce DRAW")
				if enabled and sub == CardData.CardSubType.LIGHTNING:
					t.check(game.players[1].judgment_cards == [card] and not game.deck._discard.has(card), "I05d SI-Q1 Lightning transfers the original instance once")
				else:
					t.check(game.deck._discard.count(card) == 1, "I05d settled non-transferred original discarded exactly once")
				if sub == CardData.CardSubType.BURNING_CAMP:
					for seat in [1, 4]:
						t.check(game.players[seat].hp == (5 if enabled else 4) and game.players[seat].judgment_cards.size() == (0 if enabled else 1), "I05d SI-Q1 no neighbor damage or new fire on failed judgment")
				t.check(p.judgment_cards.is_empty() and actions.is_empty(), "I05d judgment/transfer does not fabricate USE or hand-payment facts")
				await dispose(t, game)
	var game = fixture(t)
	var p = game.players[0]
	for other in game.players.slice(1):
		other.general_name = "布鲁斯·萨维奇"
		other.kneeling = true
	var lightning = CardBase.create(CardData.CardSubType.LIGHTNING)
	p.judgment_cards.append(lightning)
	t.check(await game._run_judgment(p, false) and p.judgment_cards == [lightning] and p.hp == 5, "I05d wrapped failed Lightning waits for next judgment, no same-stage loop")
	await dispose(t, game)

func uses(t):
	for sub in DELAYED:
		for concrete in [false, true]:
			var game = fixture(t)
			var p = game.players[0]
			var card = CardBase.create(sub) if concrete else null
			if concrete:
				p.determined_cards.append(card)
				game._pending_determined_card = card
			else: p.hand.append(null)
			var actions: Array = []
			game.card_action_committed.connect(func(a): actions.append(a))
			t.check(not game.can_declare_trick(p, sub) and not game.can_declare_trick(p, sub, true) and game.get_trick_targets(p, sub).is_empty(), "I05d delayed declaration/AI/target queries all reject Wanci")
			await game.play_card(sub)
			if sub != CardData.CardSubType.LIGHTNING: await game.execute_card_on_target(game.players[1], sub)
			t.check(await game._take_trick_card(p, sub) == null, "I05d final delayed payment gate rejects bypass callers")
			t.check(p.hand_size() == 1 and actions.is_empty() and game.players.all(func(b): return b.judgment_cards.is_empty()), "I05d rejected blank/concrete delayed use pays nothing and emits no USE")
			if concrete: t.check(p.determined_cards == [card] and not game.deck._discard.has(card), "I05d rejected determined card keeps original physical identity")
			game._pending_determined_card = null
			p.determined_cards.clear()
			p.hand.assign([null])
			t.check(game.can_declare_trick(p, CardData.CardSubType.DUEL), "I05d ordinary immediate trick remains legal")
			p.simba_wanci_enabled = false
			t.check(game.can_declare_trick(p, sub), "I05d private gate off preserves delayed declaration baseline")
			p.simba_wanci_enabled = true
			p.general_name = "稻草人"
			t.check(game.can_declare_trick(p, sub), "I05d another general gains no Wanci merely from capability")
			await dispose(t, game)
	for sub in DELAYED.slice(1):
		var game = fixture(t)
		var p = game.players[0]
		var source = game.players[1]
		game.turn_manager.current_player_idx = 1
		game.turn_manager.play_actor_idx = 1
		source.hand.assign([null])
		await game.execute_card_on_target(p, sub)
		t.check(p.judgment_cards.size() == 1 and source.hand.is_empty(), "I05d Wanci does not prohibit other players legally placing delayed cards")
		await dispose(t, game)

func counters(t):
	for sub in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.BURNING_CAMP]:
		for mode in ["odd", "even", "self"]:
			var game = fixture(t)
			var p = game.players[0]
			var card = CardBase.create(sub)
			p.judgment_cards.append(card)
			p.hand.append(null)
			if mode != "self": game.players[1].hand.append(null)
			if mode == "even": game.players[2].hand.append(null)
			var actions: Array = []
			game.card_action_committed.connect(func(a): actions.append(a))
			game._nullify_override = func():
				return game._input_seat == 0 if mode == "self" else game._input_seat in ([1, 2] if mode == "even" else [1])
			t.check(await game._run_judgment(p, false) and p.hp == 5, "I05d odd/even/self real paid counter chain still ends in failed Wanci judgment")
			t.check(actions.size() == (2 if mode == "even" else 1) and actions.all(func(a): return a.sub_type == CardData.CardSubType.NULLIFICATION and a.settlement_completed), "I05d Wanci retains self counter responses and joins original counter completion")
			t.check(not game.deck._discard.has(card) if sub == CardData.CardSubType.LIGHTNING else game.deck._discard.count(card) == 1, "I05d counter chain preserves distinct original delayed-card destination")
			await dispose(t, game)

func phases(t):
	var game = fixture(t)
	var p = game.players[0]
	var cards: Array[CardBase] = []
	for sub in DELAYED: cards.append(CardBase.create(sub))
	p.judgment_cards.assign(cards)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(0)
	t.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW and p.hp == 5 and p.judgment_cards.is_empty(), "I05d actual normal JUDGE resolves whole zone then advances once")
	t.check(game.players[1].judgment_cards == [cards[0]] and cards.slice(1).all(func(c): return game.deck._discard.count(c) == 1), "I05d mixed LIFO zone transfers Lightning, discards other originals once")
	await dispose(t, game)
	game = fixture(t)
	var source = game.players[0]
	source.general_name = "麦克斯·欧尼斯特"
	source.hand.assign([null, null])
	p = game.players[1]
	p.general_name = SIMBA
	p.simba_wanci_enabled = true
	p.judgment_cards.assign([CardBase.create(CardData.CardSubType.LIGHTNING), CardBase.create(CardData.CardSubType.BURNING_CAMP)])
	game.turn_manager.current_phase = TurnManager.Phase.START
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 0
	game._meiyong_target_override = func(): return p
	t.check(await game._maybe_meiyong(source) == 1, "I05d actual Max gift executes Wanci recipient judgment")
	t.check(p.hp == 5 and p.judgment_cards.is_empty() and source.hand_size() == 3 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.current_player_idx == 0, "I05d gifted judgment returns to original START and Max draws exactly one")
	await dispose(t, game)

func selectors(t):
	for seat in [0, 1]:
		var game = fixture(t)
		var p = game.players[seat]
		p.general_name = SIMBA
		p.simba_wanci_enabled = true
		p.hand.append(null)
		for sub in DELAYED: p.determined_cards.append(CardBase.create(sub))
		game.turn_manager.current_player_idx = seat
		game.turn_manager.play_actor_idx = seat
		game._set_input_player(p)
		game._on_play_btn_pressed()
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		var view = bridge.snapshot(seat)
		for sub in DELAYED:
			var determined = view.controls.filter(func(c): return c.text == CardData.get_type_name(sub))
			t.check(determined.size() == 1 and determined[0].disabled and not bridge.submit(seat, determined[0].id), "I05d host/remote determined delayed buttons disabled and rejected")
		for label in ["锦囊牌", "延时锦囊"]:
			var buttons = bridge.snapshot(seat).controls.filter(func(c): return c.text == label)
			t.check(buttons.size() == 1 and bridge.submit(seat, buttons[0].id), "I05d public selector category navigation: " + label)
		for sub in DELAYED:
			var buttons = bridge.snapshot(seat).controls.filter(func(c): return c.text == CardData.get_type_name(sub))
			t.check(buttons.size() == 1 and buttons[0].disabled and not bridge.submit(seat, buttons[0].id), "I05d host/remote arbitrary delayed declaration disabled before payment")
		t.check(p.hand_size() == 5 and game.players.all(func(b): return b.judgment_cards.is_empty()), "I05d selector rejection retains all arbitrary/concrete resources")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)

func invalidation(t):
	for mode in ["close", "reset"]:
		var game = fixture(t)
		var p = game.players[0]
		var card = CardBase.create(CardData.CardSubType.BURNING_CAMP)
		p.judgment_cards.append(card)
		game.players[1].hand.append(null)
		game._nullify_override = Callable()
		var result: Array = []
		var drive = func(): result.append(await game._run_judgment(p, false))
		drive.call()
		await t.process_frame
		t.check(not game._choice_prompt_stack.is_empty() and result.is_empty(), "I05d existing judgment counter window remains awaited")
		if mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
		else: game.reset_game_over_state()
		for i in 4: await t.process_frame
		t.check(result == [false] and p.judgment_cards == [card] and not game.deck._discard.has(card) and p.hp == 5, "I05d technical invalidation does not masquerade as failed judgment or consume original")
		await dispose(t, game)
