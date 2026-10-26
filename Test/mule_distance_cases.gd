extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var owner: Player = game.players[0]
	for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		var original = CardBase.create(sub)
		owner.equip_card_to_slot("mount_1", original)
		for source in game.players:
			for target in game.players:
				if source == target: continue
				var adjustment = -1 if sub == CardData.CardSubType.MULE_MINUS and target == owner else 0
				if sub == CardData.CardSubType.MULE_PLUS and source == owner: adjustment += 1
				t.check(source.attack_distance_to(target) == maxi(1, source.seat_distance_to(target) + adjustment), "MULE pair-only fixed-player distance: %d %d->%d" % [sub, source.seat_index, target.seat_index])
		var dest: Player = game.players[2]
		game._minus_mule_target_override = func(): return dest
		game._plus_mule_target_override = func(): return dest
		await game._try_mule_transfer(owner, sub, sub == CardData.CardSubType.MULE_MINUS)
		t.check(dest.get_equipment_card("mount_1") == original and owner.get_mount_slots().is_empty(), "MULE transfer retains original body ownership")
		t.check(game.players[1].attack_distance_to(game.players[3]) == 2, "MULE transfer never changes third-party pair")
		t.check(game.players[2].attack_distance_to(owner) == (3 if sub == CardData.CardSubType.MULE_PLUS else 2), "MULE transfer removes old holder relation and installs new directed relation")
		dest.remove_equipment("mount_1")
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var c: Player = game.players[2]
	owner.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MULE_MINUS))
	t.check(c.attack_distance_to(owner) == 1 and c.attack_distance_to(dragon) == 2, "MULE controller equipment does not replace actual target unit equipment")
	owner.remove_equipment("mount_1")
	dragon.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MULE_MINUS))
	t.check(c.attack_distance_to(dragon) == 1 and c.attack_distance_to(owner) == 2 and game.players[1].attack_distance_to(game.players[3]) == 2, "MULE unit minus affects only its own incoming distance; Q14 first premise withdrawn")
	dragon.remove_equipment("mount_1")
	c.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MULE_MINUS))
	t.check(dragon.attack_distance_to(game.players[3]) == 2, "MULE Q14 second premise withdrawn: C mule cannot change F->D")
	c.remove_equipment("mount_1")
	dragon.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MULE_PLUS))
	t.check(dragon.attack_distance_to(c) == 3 and c.attack_distance_to(dragon) == 2 and owner.attack_distance_to(c) == 2, "MULE unit plus affects only its own outgoing distance")
	dragon.remove_equipment("mount_1")
	owner.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MULE_MINUS))
	c.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	game.players[1].equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
	t.check(c.attack_distance_to(owner) == 1 and owner.attack_distance_to(game.players[1]) == 2 and game.players[1].attack_distance_to(game.players[3]) == 2, "MULE normal mounts retain independent direction and lower bound")
	t.check("受到伤害后" in CardData.CARD_DESCRIPTIONS[CardData.CardSubType.MULE_PLUS], "MULE plus text follows both-mules after-damage ruling")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
