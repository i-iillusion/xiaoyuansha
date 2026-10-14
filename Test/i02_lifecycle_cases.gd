extends RefCounted

func add_unit(game: GameManager, kind: int, summoner: Player) -> Player:
	var body = Player.new()
	body.identity = ""
	body.player_name = "火龙" if kind == UnitRegistry.Kind.FIRE_DRAGON else "山"
	body.max_hp = 3 if kind == UnitRegistry.Kind.FIRE_DRAGON else 5
	game._register_unit_body(kind, body, summoner)
	return body

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in [GameModes.FREE_FOR_ALL, GameModes.CLASSIC]:
		for scenario in ["rescue", "owner_death", "yudaxi_saved", "yudaxi_failed", "unit_normal", "reset"]:
			var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, mode)
			var owner = game.players[1]
			var dragon = add_unit(game, UnitRegistry.Kind.FIRE_DRAGON, owner)
			var mountain_owner = game.players[2] if scenario == "yudaxi_saved" else owner
			var mountain = add_unit(game, UnitRegistry.Kind.MOUNTAIN, mountain_owner)
			var dragon_id = game.unit_registry.id_for(dragon)
			var mountain_id = game.unit_registry.id_for(mountain)
			var removed: Array = []
			var deaths: Array = []
			game.unit_removed.connect(func(id, reason): removed.append([id, reason]))
			game.unit_death_committed.connect(func(id): deaths.append(id))
			dragon.hand.assign([null, null])
			# Prepared equipment-zone transfer fixture, not a fabricated concrete
			# dodge or a claim to have enabled unit snatch gameplay before I03.
			var weapon = CardBase.create(CardData.CardSubType.LIANNU)
			game.players[3].equip_card_to_slot("weapon", weapon)
			dragon.determined_cards.append(game.players[3].remove_equipment("weapon"))
			var lion = CardBase.create(CardData.CardSubType.SILVER_LION)
			dragon.equip_card_to_slot("armor", lion)
			var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
			dragon.judgment_cards.append(judgment)
			dragon.hp = 1
			t.check(game.players.size() == 5 and dragon.seat_index == -1 and not game.players.has(dragon), "I02c production registry does not alter player rows")
			t.check(not dragon_id.is_empty() and game.unit_registry.controller(dragon_id) == owner, "I02c registered intelligent control mapped to owner")
			if scenario == "rescue":
				game._rescue_choice_override = func(rescuer, dying, options): return CardData.CardSubType.PEACH if rescuer == owner and dying == owner and options.has(CardData.CardSubType.PEACH) else -1
				owner.hp = 1
				await game._deal_damage(game.players[0], owner, 1, EffectChain.DamageType.PHYSICAL)
				t.check(owner.is_alive() and game.unit_registry.active_units().size() == 2 and removed.is_empty(), "I02c real ordinary rescue retains attachments")
			elif scenario.begins_with("yudaxi"):
				owner.general_name = "里奥·普利威尔"
				for player in game.players: player.hp = 5
				if scenario == "yudaxi_saved": game.players[2].hp = 2
				owner.hp = 1
				await game._deal_damage(game.players[0], owner, 1, EffectChain.DamageType.PHYSICAL)
				if scenario == "yudaxi_saved":
					t.check(owner.hp == 1 and owner.is_alive() and game.yudaxi.results[0].deaths == 1, "I02c true yudaxi X counts dead player not attached mountain")
					t.check(game.unit_registry.contains_active(dragon) and not game.unit_registry.contains_active(mountain), "I02c rescued owner retains dragon, finally dead other owner loses mountain")
					t.check(removed == [[mountain_id, UnitRegistry.Removal.SUMMONER_LOST]] and deaths.is_empty(), "I02c nested owner cleanup emits disappearance only")
				else:
					t.check(owner.is_dead() and game.yudaxi.results[0].deaths == 0 and game.unit_registry.active_units().is_empty(), "I02c failed yudaxi finally removes attachments")
			elif scenario == "owner_death":
				owner.hp = 1
				await game._deal_damage(game.players[0], owner, 1, EffectChain.DamageType.PHYSICAL)
				t.check(owner.is_dead() and game.unit_registry.active_units().is_empty(), "I02c real strike final owner death removes units")
			elif scenario == "unit_normal":
				# Final-state dispatch API only; unit rescue/kill skills remain I03/I04.
				dragon.hp = 0
				t.check(not game._retire_final_unit(dragon), "I02c dying unit cannot bypass final death")
				dragon.mark_dead()
				var before = game.players[0].hand_size()
				t.check(game._retire_final_unit(dragon) and deaths == [dragon_id], "I02c committed normal unit death uses separate notification")
				t.check(game.players[0].hand_size() == before and game.unit_registry.contains_active(mountain), "I02c unit final dispatch does not award role rewards or erase siblings")
				t.check(not game._retire_final_unit(dragon), "I02c repeated unit death is inert")
			else:
				var old_epoch_id = dragon_id
				game.reset_game_over_state()
				t.check(game.unit_registry.all_bodies().is_empty() and removed.is_empty() and deaths.is_empty(), "I02c technical reset releases unit references without gameplay events")
				var replacement = add_unit(game, UnitRegistry.Kind.FIRE_DRAGON, owner)
				t.check(game.unit_registry.id_for(replacement) != old_epoch_id and game.unit_registry.entry(old_epoch_id).is_empty(), "I02c restart cannot reuse old unit handle")
			if scenario in ["owner_death", "yudaxi_failed"]:
				t.check(dragon.hp == 1 and not dragon.is_dead() and deaths.is_empty(), "I02-Q1 disappearance does not heal lion or fabricate unit death")
				t.check(dragon.hand_size() == 0 and dragon.equipment.is_empty() and dragon.judgment_cards.is_empty(), "I02-Q1 every card zone emptied on attached disappearance")
				for card in [weapon, lion, judgment]: t.check(game.deck._discard.count(card) == 1, "I02-Q1 concrete original discarded exactly once")
				var before = game.deck.discard_count()
				await game._handle_death(owner, game.players[0])
				t.check(game.deck.discard_count() == before and removed.size() == 2, "I02c repeated owner death cannot repeat cleanup")
			if scenario in ["rescue", "yudaxi_saved"]:
				t.check(dragon.hp == 1 and dragon.hand_size() == 3 and dragon.get_equipment_card("armor") == lion and dragon.judgment_cards == [judgment], "I02c successful rescue preserves all original unit zones")
			game._game_over = true
			game.queue_free()
			await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
