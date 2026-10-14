extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/h02_integration_cases.gd").new()
	for mode in [GameModes.FREE_FOR_ALL, GameModes.CLASSIC]:
		helper.prepare(5, mode)
		GameManager.selected_general = "克里斯·西弗"
		var game = load("res://Scenes/Game.tscn").instantiate()
		game.auto_start = false
		t.root.add_child(game)
		game.start_game()
		game._halt_countdown()
		game._rescue_choice_override = func(_r, _d, _o): return -1
		game._sacrifice_override = func(): return false
		var p: Player = game.players[0]
		t.check(p.fire_dragon_eggs == 1, "I03b2a actual opening gives Chris one egg")
		t.check(game.players.slice(1).all(func(other): return other.fire_dragon_eggs == 0), "I03b2a actual opening does not give other generals eggs")
		t.check(not game.fire_dragon_state.grant_start_egg(p) and p.fire_dragon_eggs == 1, "I03b2a repeated opening grant rejected")
		t.check(GeneralData.get_implementation_status(p.general_name) == "metadata_only", "I03b2a incomplete Chris remains closed")
		var original_hand = p.hand.duplicate()
		p.fire_dragon_eggs = 4
		p.hp = 1
		p.restore_game_start_state()
		t.check(p.fire_dragon_eggs == 1 and p.hand == original_hand, "I03b2a production opening snapshot restores one egg, preserves hand")
		var armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
		p.equip_card_to_slot("armor", armor)
		p.sage_activated = true
		p.fire_dragon_eggs = 5
		p.hp = 0
		game._sage_save_override = func(): return true
		await game._resolve_dying(p, null, "I03 opening Sage regression")
		t.check(p.is_alive() and p.fire_dragon_eggs == 1 and p.hp == p.max_hp, "I03b2a real existing rescue/Sage pipeline restores opening egg")
		t.check(p.hand_size() == 4 and p.equipment.is_empty() and game.deck._discard.count(armor) == 1, "I03b2a Sage retains its normal clear/draw semantics")
		# Authorized registration fixture, NOT a playable summon or unit strike.
		var dragon = FireDragonState.create_body()
		game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON, dragon, p)
		var target: Player = game.players[2]
		var owner_cards = p.hand_size()
		target.hp = 0
		await game._handle_death(target, dragon)
		t.check(target.is_dead() and dragon.hand_size() == (3 if mode == GameModes.CLASSIC else 0) and p.hand_size() == owner_cards, "I03-Q2 final rebel death rewards real dragon, not controller; FFA no reward")
		if mode == GameModes.CLASSIC:
			var loyal: Player = game.players[1]
			loyal.hp = 0
			await game._handle_death(loyal, dragon)
			t.check(loyal.is_dead() and p.identity == "主公" and dragon.identity == "" and p.hand_size() == owner_cards and dragon.hand_size() == 3, "I03-Q2 dragon kills loyalist without lord penalty to either body")
		game.reset_game_over_state()
		t.check(not game.fire_dragon_state.begin_turn(game.unit_registry.id_for(dragon), 1), "I03b2a reset rejects old dragon membership")
		game.queue_free()
		await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
