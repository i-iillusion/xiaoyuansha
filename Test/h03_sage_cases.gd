extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/h03_death_chain_cases.gd").new()
	for seat in [1, 5]:
		var game = helper.fixture(t)
		game._ambitious_declaration_override = func(_p): return 0
		game.players[0].hp = 0
		await game._resolve_dying(game.players[0], null, "h03")
		var p: Player = game.players[seat]
		var expected = "主公" if seat == 5 else "内奸"
		var cap = 6 if seat == 5 else 5
		t.check(p.identity == expected and game.players[5].has_lord_skill_authority() and not game.players[0].has_lord_skill_authority(), "H03d succession transfers live lord skill qualification")
		var armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
		t.check(p.equip_card_to_slot("armor", armor), "H03d real sage armor equipped")
		p.sage_activated = true
		var concrete = CardBase.create(CardData.CardSubType.PEACH)
		var judgment = CardBase.create(CardData.CardSubType.LIGHTNING)
		p.determined_cards.append(concrete)
		p.judgment_cards.append(judgment)
		p.awoken = true
		p.facedown = true
		game.lan_enabled = true
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		p.hp = 0
		var done = {"value": false}
		helper.start_death(game, p, done)
		await t.process_frame
		var state = bridge.snapshot(seat)
		t.check(state.owner == seat and not done.value, "H03d actual sage window belongs to transformed player")
		var button = state.controls.filter(func(x): return x.text == "发动【贤者的加护】")[0]
		t.check(not bridge.submit(2, button.id) and bridge.submit(seat, button.id), "H03d only sage owner may answer")
		for i in 3: await t.process_frame
		t.check(done.value and p.is_alive() and p.hp == cap and p.max_hp == cap, "H03d actual sage restores general plus current identity cap")
		t.check(p.identity == expected and p.identity_revealed == (seat == 5), "H03d actual sage retains new role and secrecy")
		t.check(not p.awoken and not p.facedown and p.hand_size() == 4 and p.determined_cards.is_empty(), "H03d reset awakened/face state, discard old hand then draw four arbitrary")
		t.check(p.equipment.is_empty() and p.judgment_cards.is_empty() and not p.sage_activated, "H03d sage clears old armor/judgment, does not retain its activation")
		for card in [armor, concrete, judgment]:
			t.check(game.deck._discard.count(card) == 1, "H03d each original concrete resource discarded exactly once")
		t.check(game._ambitious_state.valid() and not game._game_over, "H03d restored character does not corrupt succession state")
		var other = bridge.snapshot(2)
		t.check(other.players[seat].identity == ("主公" if seat == 5 else ""), "H03d third-party LAN snapshot does not reveal hidden converted role")
		t.check(not game.action_history.entries.any(func(e): return "【内奸】" in e.text or "【忠臣】" in e.text), "H03d public history does not expose transformed hidden roles")
		t.check(not bridge.submit(seat, button.id), "H03d old sage answer cannot restore/draw again")
		bridge.game = null
		bridge.queue_free()
		await helper.dispose(t, game)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
