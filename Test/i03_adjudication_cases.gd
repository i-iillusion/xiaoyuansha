extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for replace in [false, true]: await prep_scope(t, replace)
	await gender(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func prep_scope(t, replace: bool):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 2, GameModes.FREE_FOR_ALL)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._dodge_override = func(): return false
	game._aoe_override = func(): return false
	game._nullify_override = func(): return false
	var owner: Player = game.players[0]
	var leo: Player = game.players[1]
	owner.general_name = "克里斯·西弗"
	owner.max_hp = 3
	owner.hp = 3
	owner.hand.clear()
	leo.general_name = "里奥·普利威尔"
	leo.hand.assign([null])
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	await game.execute_card_on_target(owner, CardData.CardSubType.STRIKE)
	t.check(leo.prep_tokens == 1 and owner.hp == 2, "I03 Q11 Leo has one completed own-hand-card mark before dragon acts")
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_unit_id = id
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	dragon.hand.append(null)
	var offers: Array = []
	game._prep_replace_override = func(who, user, _target, current, options):
		offers.append(options)
		t.check(who == leo and user == dragon and current == CardData.CardSubType.BARBARIAN_INVASION,
			"I03 Q11 replacement window preserves dragon as original user")
		t.check(not options.has(CardData.CardSubType.DUEL) and not options.has(CardData.CardSubType.IRON_CHAIN) and options.has(CardData.CardSubType.VOLLEY_OF_ARROWS),
			"I03 Q11 two designated players allow AOE only, not duel or two-target chain")
		return CardData.CardSubType.VOLLEY_OF_ARROWS if replace else -1
	var events: Array = []
	game.card_action_committed.connect(func(event): events.append(event))
	var hp = leo.hp
	await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
	t.check(offers.size() == 1 and leo.prep_tokens == (0 if replace else 1), "I03 Q11 only confirmed legal AOE replacement spends mark")
	t.check(owner.hp == 1 and leo.hp == hp - 1 and dragon.hp == 3, "I03 Q11 both original players receive AOE, dragon user excluded")
	t.check(events.size() == 1 and events[0].actor_body == dragon and events[0].card.sub_type == CardData.CardSubType.BARBARIAN_INVASION,
		"I03 Q11 one original hand card/use fact remains barbarian even after replacement")
	t.check(dragon.hand_size() == 0 and game.deck._discard.count(events[0].card) == 1 and game._pending_card_actions.is_empty(),
		"I03 Q11 actual dragon payment/discard/completion occurs once")
	t.check(game.fire_dragon_state.is_revealed_to(id, owner) and game.fire_dragon_state.is_revealed_to(id, leo), "I03 Q11 actual use reveals to both designated players")
	game._game_over = true
	game.queue_free()
	await t.process_frame

func gender(t):
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.lan_enabled = true
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var bill: Player = game.players[1]
	bill.general_name = "比尔·盖伊"
	bill.max_hp = 4
	bill.gender = "male"
	bill.hp = 4
	bill.hand.assign([null])
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, game.players[0])
	t.check(dragon.gender == "none", "I03 Q12 actual registered dragon has no gender")
	dragon.gender = "male" # Defensive snapshot regression, not a gender-changing rule.
	dragon.restore_game_start_state()
	t.check(dragon.gender == "none", "I03 Q12 general reset preserves original genderless dragon")
	dragon.hp = 2
	var revealed: Array[Player] = [bill]
	game.fire_dragon_state.record_use(game.unit_registry.id_for(dragon), 1, revealed)
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._set_input_player(bill)
	var choices: Array = []
	game._gay_x_override = func():
		choices.append("gay")
		return 1
	await game._execute_gay(bill, dragon)
	t.check(choices.is_empty() and bill.hand_size() == 1 and bill.hp == 4 and dragon.hp == 2 and not game._gay_used,
		"I03 Q12 genderless dragon rejects actual Gay execution before choice/payment/healing")
	await game._on_gay_skill_clicked(bill)
	game._on_gay_target_click(dragon)
	t.check(game._is_gay_targeting and choices.is_empty(), "I03 Q12 actual Gay target click rejects dragon without consuming selection")
	game._cancel_target_btn.pressed.emit()
	var other: Player = game.players[2]
	other.gender = "female"
	t.check(bill.is_opposite_gender_to(other) and other.is_opposite_gender_to(bill), "I03 gender male/female remain opposite in both directions")
	t.check(not bill.is_opposite_gender_to(dragon) and not dragon.is_opposite_gender_to(bill) and not dragon.is_opposite_gender_to(other),
		"I03 Q12 no gender is not opposite to either male or female")
	game._chixiong_activate_override = func():
		choices.append("sword")
		return true
	game._dodge_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	bill.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
	await game.execute_card_on_target(dragon, CardData.CardSubType.STRIKE)
	t.check(choices.is_empty() and dragon.hp == 1 and bill.hand_size() == 0, "I03 Q12 actual male sword-user strike does not offer opposite-sex effect against dragon")
	dragon.equip_card_to_slot("weapon", bill.remove_equipment("weapon"))
	dragon.hand.append(null)
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_unit_id = game.unit_registry.id_for(dragon)
	await game.execute_card_on_target(bill, CardData.CardSubType.STRIKE)
	t.check(choices.is_empty() and bill.hp == 3 and dragon.hand_size() == 0, "I03 Q12 actual genderless sword-user strike also offers no opposite-sex effect")
	game._game_over = true
	game.queue_free()
	await t.process_frame
