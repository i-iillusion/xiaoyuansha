extends RefCounted

func fixture(t):
	return load("res://Test/i05_simba_emergency_cases.gd").new().fixture(t)

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await single_target(t)
	await prevented_aoe(t)
	await deductions(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func single_target(t):
	for name in [load("res://Test/i05_peter_peach_cases.gd").PETER, "大卫·法米尔"]:
		var game = fixture(t)
		var target = game.players[1]
		target.general_name = name
		target.max_hp = GeneralData.get_max_hp(name)
		target.hp = target.max_hp - 1
		var card = CardBase.create(CardData.CardSubType.DODGE)
		target.determined_cards.append(card)
		var asked: Array = []
		game._peter_ignore_override = func(_p, _a, _e, _v): asked.append("ignore"); return 1
		game._wrestling_choice_override = func(_p, _v): asked.append("wrestle"); return 1
		game._simba_deed_choice_override = func(_p, candidates, _r, _v): return candidates.find(target)
		t.check(await game._perform_good_deed(game.players[0]) == 1 and target.hp == target.max_hp and target.good_deed_marks == 1, "I05d single-recipient Good Deed remains legal for public Peter/David: " + name)
		t.check(asked.is_empty() and target.determined_cards == [card], "I05d single-target HP/mark grant is neither Peter multi-target immunity nor David card-loss reaction")
		await dispose(t, game)

func prevented_aoe(t):
	var game = fixture(t)
	var owner = game.players[0]
	var peter = game.players[1]
	peter.general_name = load("res://Test/i05_peter_peach_cases.gd").PETER
	game._peter_ignore_override = func(p, _a, _e, _v): return 1 if p == peter else 0
	var victims: Array = []
	game._simba_emergency_choice_override = func(_p, victim, _v): victims.append(victim); return -1
	game.turn_manager.current_player_idx = 3; game.turn_manager.play_actor_idx = 3
	game._set_input_player(game.players[3])
	game.players[3].hand.append(null)
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	t.check(peter.hp == 5 and peter.good_deed_marks == 0 and not victims.has(peter), "I05d actual Peter AOE immunity prevents damage and therefore opens no Emergency")
	t.check(victims.size() == 3 and owner.hp == 4 and game._pending_card_actions.is_empty(), "I05d paid AOE completes other damage targets and declined Emergency normally")
	await dispose(t, game)

func deductions(t):
	var game = fixture(t)
	var owner = game.players[0]
	var david = game.players[1]
	david.general_name = "大卫·法米尔"; david.max_hp = 4; david.hp = 4
	david.good_deed_marks = 2
	var card = CardBase.create(CardData.CardSubType.DODGE)
	david.determined_cards.append(card)
	owner.hp = 0
	var asked: Array = []
	game._wrestling_choice_override = func(_p, _v): asked.append("wrestle"); return 1
	game._simba_emergency_choice_override = func(_p, _t, _v): asked.append("emergency"); return 0
	game._simba_deed_choice_override = func(_p, candidates, _r, _v): return candidates.find(david)
	t.check(await game._resolve_dying(owner, null, "test") == 0 and owner.hp == 2 and david.hp == 2 and david.good_deed_marks == 0, "I05d real recovery strongly deducts all David marks and heals original owner")
	t.check(asked.is_empty() and david.determined_cards == [card], "I05d mark deduction is neither damage for Emergency nor card loss for Wrestling")
	await dispose(t, game)
	game = fixture(t)
	var leo = game.players[1]
	leo.general_name = "里奥·普利威尔"; leo.max_hp = 3; leo.hp = 0
	for p in [game.players[0], game.players[2], game.players[3], game.players[4]]: p.hp = 4
	var emergency: Array = []
	game._simba_emergency_choice_override = func(_p, victim, _v): emergency.append(victim); return 0
	await game._resolve_dying(leo, null, "test")
	t.check(leo.is_dead() and emergency.is_empty() and game.players[0].hp == 2, "I05d actual highest-priority Yudaxi deducts HP without creating Emergency damage reactions")
	t.check(game._dying_contexts.is_empty(), "I05d Yudaxi and Simba coexist without suspended rescue frames")
	await dispose(t, game)
