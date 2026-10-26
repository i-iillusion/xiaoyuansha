extends RefCounted

func finish_turn(tm: TurnManager):
	tm.current_phase = TurnManager.Phase.END
	tm.next_turn()

func run(t):
	await scheduler(t)
	await phases(t)
	await rescue(t)
	await ai_turn(t)
	await paid_disappearance(t)

func scheduler(t):
	var tm = TurnManager.new()
	tm.debug_log = false
	tm.player_count = 5
	var live: Array[int] = [0, 1, 2, 3, 4]
	var attached: Dictionary = {}
	tm.live_seats = func(): return live
	tm.attached_actor = func(seat): return attached.get(seat, "")
	tm.start_game()
	t.check(tm.get_turn_actor_key() == 0 and tm.rounds.round_id == 1, "I03 ordinary frame starts at permanent seat")
	attached[0] = "unit:fixture:A"
	tm.current_phase = TurnManager.Phase.PLAY
	tm.use_strike()
	tm.use_card("wine")
	var owner_turn = tm.turn_id
	finish_turn(tm)
	t.check(tm.get_turn_actor_key() == attached[0] and tm.get_play_actor_key() == attached[0] and tm.current_player_idx == 0,
		"I03 Q8 complete owner turn selects distinct attached actor, not an extra seat")
	t.check(tm.turn_id > owner_turn and tm.current_phase == TurnManager.Phase.START and tm._extra_frames.is_empty(), "I03 dragon has independent turn ID and START, no extra-turn frame")
	t.check(tm.rounds.round_id == 1 and tm.rounds.pending_seats().has(0) and tm.rounds.current().kind == RoundLedger.Kind.ORDINARY,
		"I03 round quota stays open while its attached normal turn is running")
	tm.current_phase = TurnManager.Phase.PLAY
	t.check(tm.strike_count_this_turn == 0 and tm.wine_count_this_turn == 0, "I03 dragon receives fresh own ordinary card counts")
	tm.use_strike()
	tm.use_card("wine")
	t.check(tm._get_turn_count("strike", attached[0]) == 1 and tm._get_turn_count("strike", 0) == 0,
		"I03 string unit counter cannot debit controller seat")
	tm.start_waiting("fixture", 1)
	tm.end_waiting()
	t.check(tm.get_play_actor_key() == attached[0] and tm.strike_count_this_turn == 1, "I03 WAITING resume retains actual unit and counts")
	finish_turn(tm)
	t.check(tm.get_turn_actor_key() == 1 and not tm.rounds.pending_seats().has(0), "I03 unit END completes owner quota once then enters next player")
	finish_turn(tm)
	t.check(tm.current_player_idx == 2, "I03 C ordinary turn follows B")
	var standalone = tm.begin_standalone_play(0)
	t.check(not standalone.is_empty(), "I03 Q8 C START can suspend for gifted A PLAY")
	var parent_turn = tm.turn_id
	t.check(tm.complete_standalone_phase(standalone) and tm.get_turn_actor_key() == 2 and tm.turn_id == parent_turn,
		"I03 Q8 gifted A phase completion resumes C, never starts A dragon")
	finish_turn(tm)
	t.check(tm.get_turn_actor_key() == 3, "I03 Q8 no delayed catch-up unit after C")
	finish_turn(tm)
	finish_turn(tm)
	t.check(tm.rounds.round_id == 2 and tm.get_turn_actor_key() == 0, "I03 Q8 next round begins with A, not its unit")
	finish_turn(tm)
	t.check(tm.get_turn_actor_key() == attached[0], "I03 Q8 unit waits until next whole A turn ends")
	# Unit skip follows the actual START->END path, still pays its round quota.
	tm.skip_full_turn = true
	tm.advance_phase()
	t.check(tm.current_phase == TurnManager.Phase.END and tm.rounds.round_id == 2, "I03 flipped attached opportunity skips all card phases")
	tm.next_turn()
	t.check(tm.get_turn_actor_key() == 1 and not tm.rounds.pending_seats().has(0), "I03 skipped dragon still completes current ordinary quota")
	tm.free()

func phases(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.lan_enabled = true # Pause every real PLAY for explicit normal inputs.
	var owner: Player = game.players[0]
	owner.hp = 3
	owner.hand.clear()
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	t.check(game._attached_turn_actor(0).is_empty(), "I03 incomplete unit wire remains gated in public metadata-only games")
	game._unit_turns_enabled = true
	var phases_seen: Array = []
	game.turn_manager.phase_changed.connect(func(_old, phase, _seat):
		if game.turn_manager.current_unit_id == id: phases_seen.append(phase))
	var owner_size = owner.hand_size()
	game.end_play_phase()
	t.check(game._play_actor() == dragon and game._phase_actor(0) == dragon and game.turn_manager.current_phase == TurnManager.Phase.PLAY,
		"I03 real owner PLAY->DISCARD->END reaches actual independent dragon PLAY")
	t.check(game.fire_dragon_state.turn_count(id) == 1 and owner.fire_dragon_eggs == 1, "I03 real first dragon START does not award egg")
	t.check(dragon.hand_size() == 1 and owner.hand_size() == owner_size and dragon.seat_index == -1 and game.players.size() == 5,
		"I03 real DRAW gives only dragon one arbitrary hand card, never owner or permanent roster")
	t.check(phases_seen.has(TurnManager.Phase.JUDGE) and phases_seen.has(TurnManager.Phase.DRAW) and phases_seen.has(TurnManager.Phase.PLAY),
		"I03 real unit phase dispatch passes judgment, draw and play")
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	var event = game._record_card_action(dragon, peach)
	t.check(event.actor_seat == -1 and event.actor_key == id and event.actor_body == dragon and event.turn_owner_key == id,
		"I03 card fact records unit identity without borrowing controller seat")
	game._complete_card_actions([event])
	t.check(event.settlement_completed and game._pending_card_actions.is_empty() and owner.prep_tokens == 0, "I03 unit action completes without players[-1] or owner prep income")
	var leo: Player = game.players[2]
	var leo_general = leo.general_name
	leo.general_name = "里奥·普利威尔"
	var response = game._record_card_action(leo, CardBase.create(CardData.CardSubType.DODGE), CardActionEvent.Kind.RESPONSE)
	game._complete_card_actions([response])
	t.check(response.settlement_completed and leo.prep_tokens == 0, "I03 Leo response during unit turn compares typed identities and grants no own-turn token")
	leo.general_name = leo_general
	var stale_view = game._ai_observation(dragon)
	stale_view.actor = 0
	t.check(game._ai_play_candidates(stale_view).is_empty(), "I03 fixed-seat observation cannot authorize a string-key unit action")
	var response_options: Array = [CardData.CardSubType.PEACH]
	t.check(ResponsePolicy.choose({"actor": 0, "mode": GameModes.CLASSIC, "response": {"target": id}}, "rescue", response_options) == -1,
		"I03 fixed AI response safely rejects unrelated unit identity")
	t.check(ResponsePolicy.choose({"actor": id, "mode": GameModes.CLASSIC, "response": {"target": 0}}, "rescue", response_options) == -1,
		"I03 unit AI response safely handles fixed target identity")
	# Base positions inherit; equipment modifiers belong to actual body.
	t.check(owner.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS)), "I03 distance fixture has actual owner mount")
	t.check(dragon.seat_distance_to(game.players[2]) == 2 and dragon.attack_distance_to(game.players[2]) == 2,
		"I03 Q1a actual distance inherits owner seat but not owner minus mount")
	t.check(game.players[1].seat_distance_to(dragon) == 1 and game.players[0].seat_distance_to(game.players[2]) == 2,
		"I03 unit is targetable by base position without increasing player circle")
	dragon.hp = 1
	await game.play_card(CardData.CardSubType.PEACH)
	t.check(dragon.hp == 2 and dragon.hand_size() == 0 and owner.hand_size() == owner_size,
		"I03 Q6 real unit self Peach spends its own arbitrary card, not owner's")
	t.check(game.fire_dragon_state.is_revealed_to(id, dragon) and not game.fire_dragon_state.is_revealed_to(id, game.players[1]),
		"I03 own Peach USE does not reveal dragon to others")
	game.end_play_phase()
	t.check(game.turn_manager.current_unit_id.is_empty() and game.turn_manager.current_player_idx == 1,
		"I03 real dragon DISCARD->END returns to next permanent player")
	for _seat in range(1, 5): game.end_play_phase()
	dragon.facedown = true
	owner.hand.clear()
	game.end_play_phase()
	t.check(not dragon.facedown and game.turn_manager.current_player_idx == 1 and game.turn_manager.current_unit_id.is_empty(),
		"I03 Q7 real second opportunity flips unit back and skips its whole turn")
	t.check(game.fire_dragon_state.turn_count(id) == 1 and owner.fire_dragon_eggs == 1 and dragon.hand_size() == 0,
		"I03 Q7 skipped actual dispatch neither draws nor advances egg count")
	for _seat in range(1, 5):
		game._play_actor().hand.clear()
		game.end_play_phase()
	owner.hand.clear()
	game.end_play_phase()
	t.check(game._play_actor() == dragon and game.fire_dragon_state.turn_count(id) == 2 and owner.fire_dragon_eggs == 2 and dragon.hand_size() == 1,
		"I03 Q7 next actual START awards egg once and then draws one")
	t.check(not game._get_strike_targets(game.players[1]).has(dragon), "I03 concealed unit cannot be selected as strike target before USE")
	game._dodge_override = func(): return false
	game._sacrifice_override = func(): return false
	var target_hp = game.players[1].hp
	var cards_before = game._card_action_serial
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.STRIKE)
	t.check(game.players[1].hp == target_hp - 1 and dragon.hand_size() == 0 and game.turn_manager.strike_count_this_turn == 1,
		"I03 real dragon strike pays own card, uses own counter, and deals damage")
	t.check(game._card_action_serial == cards_before + 1 and game._pending_card_actions.is_empty(), "I03 actual paid unit strike completes its sole USE fact")
	t.check(game.fire_dragon_state.is_revealed_to(id, game.players[1]) and game._get_strike_targets(game.players[1]).has(dragon)
		and not game._get_strike_targets(game.players[4]).has(dragon), "I03 real designated USE reveals only to that character")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func rescue(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["self", "other", "death", "sage"]:
		var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
		var owner: Player = game.players[0]
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
		var id = game.unit_registry.id_for(dragon)
		for p in game.players: p.hand.clear()
		if mode == "self": dragon.hand.append(null)
		if mode == "other":
			var revealed: Array[Player] = [game.players[1]]
			game.fire_dragon_state.record_use(id, 1, revealed)
			game.players[1].hand.append(null)
		if mode == "sage":
			dragon.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			dragon.sage_activated = true
			game._sage_save_override = func(): return true
		var offered: Array = []
		game._rescue_choice_override = func(rescuer, victim, options):
			offered.append(rescuer)
			t.check(victim == dragon, "I03 normal rescue retains actual unit victim")
			return CardData.CardSubType.PEACH if options.has(CardData.CardSubType.PEACH) else -1
		var deaths: Array = []
		game.unit_death_committed.connect(func(unit): deaths.append(unit))
		dragon.hp = 0
		var result = await game._resolve_dying(dragon, game.players[2], "I03 normal unit damage")
		t.check(result != game.CHOICE_INVALID and game._dying_contexts.is_empty(), "I03 ordinary unit rescue settles without fixed-seat rejection: " + mode)
		if mode == "death":
			t.check(dragon.is_dead() and deaths == [id] and not game.unit_registry.contains_active(dragon) and owner.is_alive(),
				"I03 genuine unit final death retires exactly once without killing summoner")
		else:
			t.check(dragon.is_alive() and game.unit_registry.contains_active(dragon) and deaths.is_empty(), "I03 rescue/Sage preserves actual registered unit: " + mode)
			if mode == "self": t.check(offered == [dragon] and dragon.hand_size() == 0, "I03 unit can pay own Peach at its ordered rescue response")
			if mode == "other": t.check(offered == [game.players[1]] and game.players[1].hand_size() == 0, "I03 revealed source can rescue unit using its own original card")
			if mode == "sage": t.check(dragon.hp == 3 and dragon.hand_size() == 4 and dragon.equipment.is_empty(), "I03 normal damage allows unit Sage unlike roar mechanism cost")
		game._game_over = true
		game.queue_free()
		await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func ai_turn(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.turn_ended.disconnect(game._on_turn_ended)
	var owner: Player = game.players[1]
	owner.general_name = "克里斯·西弗"
	owner.max_hp = 3
	owner.hp = 3
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	dragon.hp = 2
	dragon.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_unit_id = id
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var observation = game._ai_observation(dragon)
	t.check(observation.actor == id and observation.own_cards.size() == 1 and observation.own_cards[0].sub == -1, "I03 AI sees actual unit key and own arbitrary card, not controller hand")
	var hand_before = owner.hand_size()
	game.ai_pacer.speed = AiActionPacer.Speed.FAST
	game.ai_driver.chooser = func(_view, actions):
		for index in actions.size():
			if actions[index].sub == CardData.CardSubType.PEACH: return index
		return -1
	await game._run_ai_play(dragon)
	t.check(dragon.hp == 3 and dragon.hand_size() == 0 and owner.hand_size() == hand_before, "I03 real AI driver pays unit self Peach without accessing owner cards")
	t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and game._pending_card_actions.is_empty(), "I03 real AI driver completes unit USE then ends only its PLAY")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func paid_disappearance(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.CLASSIC)
	game.lan_enabled = true
	var owner: Player = game.players[0]
	owner.identity = "忠臣"
	owner.identity_max_hp_bonus = 0
	owner.identity_revealed = false
	owner.general_name = "克里斯·西弗"
	owner.max_hp = 3
	owner.hp = 1
	owner.fire_dragon_eggs = 0
	var lord: Player = game.players[1]
	lord.identity = "主公"
	lord.identity_revealed = true
	lord.identity_max_hp_bonus = 1
	lord.hp = 1
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
		if p not in [owner, lord]: p.hp = 3
	owner.hand.append(null)
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	game.turn_manager.current_unit_id = id
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	dragon.hand.append(null)
	game._nullify_override = func(): return false
	game._sacrifice_actor_override = func(actor, target, _amount): return actor == owner and target == lord
	var completed: Array = []
	game.card_action_completed.connect(func(event): completed.append(event))
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	t.check(owner.is_dead() and dragon.unit_disappeared and not dragon.is_dead() and lord.hp == 1,
		"I03 Q9 actual dragon arbitrary-card AOE pays and survives through summoner sacrifice as no-source continuation")
	t.check(game.players.slice(2).all(func(p): return p.hp == 2) and dragon.hand_size() == 0,
		"I03 Q9 native paid unit AOE still settles every remaining live target")
	t.check(completed.filter(func(event): return typeof(event.actor_key) == TYPE_STRING and event.actor_key == id).size() == 1 and game._pending_card_actions.is_empty(),
		"I03 Q9 actual removed unit USE completes exactly once without aliasing owner")
	var rescue_order = game._rescue_order_for_turn()
	t.check(rescue_order.has(game.players[2]) and rescue_order.front() == lord, "I03 Q9 later victims retain ordinary rescue order after active source disappears")
	await t.process_frame
	t.check(game.turn_manager.current_unit_id.is_empty() and game.turn_manager.current_player_idx == 1,
		"I03 Q9 removed human-controlled unit exits PLAY only after established card completes")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
