extends RefCounted
const Core = preload("res://Test/i05_david_wrestling_core_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")
const Summon = preload("res://Test/i03_summon_cases.gd")

func fixture(t):
	var game = Core.new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	for p in game.players:
		p.max_hp = 4; p.hp = 4
	game.players[1].hp = 3
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for concrete in [false, true]: await dragon_disappearance(t, concrete)
	await terminal_counter(t)
	await interrupted_counter(t)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func dragon_disappearance(t, concrete):
	var game = fixture(t)
	var david = game.players[1]; var chris = game.players[2]; var leo = game.players[3]
	chris.general_name = "克里斯·西弗"; chris.hp = 1; chris.fire_dragon_eggs = 0
	leo.general_name = "里奥·普利威尔"; leo.prep_tokens = 1
	var dragon = Summon.new().seed_dragon(game, chris)
	var id = game.unit_registry.id_for(dragon)
	game.turn_manager.current_player_idx = 2
	game.turn_manager.current_unit_id = id
	game._set_input_player(dragon)
	var original = CardBase.create(CardData.CardSubType.SNATCH) if concrete else null
	if concrete: dragon.determined_cards.append(original); game._pending_determined_card = original
	else: dragon.hand.append(null)
	var armor = Core.new().equip(game)
	game._prep_replace_override = func(_leo, actor, _target, _sub, _options): return CardData.CardSubType.BARBARIAN_INVASION if actor == david else -1
	game._aoe_override = func(): return false
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(david, CardData.CardSubType.SNATCH)
	t.check(chris.is_dead() and dragon.unit_disappeared and not dragon.is_dead() and not game._game_over, "I05b5 actual paid dragon Snatch triggers counter AOE, final controller death removes unit without fake death")
	t.check(david.get_equipment_card("armor") == armor and david.hp == 3 and game.deck._discard.count(armor) == 0, "I05b5 unit-source disappearance cannot undo committed prevention or heal retained Lion")
	t.check(game.players[0].hp == 3 and leo.hp == 3 and game.players[4].hp == 3 and leo.prep_tokens == 0, "I05b5 counter replacement continues remaining original audience after source unit disappears")
	t.check(facts[0].actor_key == id and facts[0].settlement_completed and game._pending_card_actions.is_empty(), "I05b5 retained unit USE completes once after nested disappearance")
	t.check(david.wrestle_round == game.turn_manager.rounds.round_id and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05b5 nested source disappearance releases all leases without refunding quota")
	if concrete: t.check(game.deck._discard.count(original) == 1, "I05b5 exact paid concrete dragon card discarded exactly once")
	await Farming.new().dispose(t, game)

func terminal_counter(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 2, GameModes.FREE_FOR_ALL)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.lan_enabled = true; game._david_rules_enabled = true; game._wrestling_rules_enabled = true
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._nullify_override = func(): return false
	game._duel_respond_override = func(): return false
	game._wrestling_choice_override = func(_p, _v): return 1
	game._zone_pick_override = func(): return "equip"
	game._equip_pick_override = func(): return "armor"
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var source = game.players[0]; var david = game.players[1]
	source.hp = 1; source.hand.append(null)
	david.general_name = "大卫·法米尔"
	var armor = CardBase.create(CardData.CardSubType.SHENGGUANG_BAIYI)
	david.equip_card_to_slot("armor", armor)
	await game.execute_card_on_target(david, CardData.CardSubType.SNATCH)
	t.check(source.is_dead() and game._game_over and david.is_alive() and david.get_equipment_card("armor") == armor, "I05b5 counter terminal FFA keeps protected original, no deferred transfer after victory")
	t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty() and game._choice_prompt_stack.is_empty(), "I05b5 game-over counter leaves no pending card, lease or window")
	await Farming.new().dispose(t, game)

func interrupted_counter(t):
	var game = fixture(t)
	var source = game.players[0]; var david = game.players[1]
	var armor = Core.new().equip(game)
	source.hand.append(null)
	var calls: Array = []
	game._nullify_override = func():
		if not game._wrestling_resolving.is_empty():
			calls.append(true)
			game.turn_manager.current_player_idx = 2
		return false
	await game.execute_card_on_target(david, CardData.CardSubType.SNATCH)
	t.check(calls.size() == 1 and david.wrestle_round == game.turn_manager.rounds.round_id and source.hand_size() == 0, "I05b5 phase invalidation occurs after committed prevention and paid parent cost")
	t.check(david.get_equipment_card("armor") == armor and game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05b5 counter invalidation cannot apply old transfer and clears both action trees")
	await Farming.new().dispose(t, game)
