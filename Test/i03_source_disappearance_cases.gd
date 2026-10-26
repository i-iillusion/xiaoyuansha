extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.CLASSIC)
	# Controlled legal state for an ALREADY designated group effect. Independent
	# unit START/DRAW/PLAY and the public unit card menu remain I03c/d, not this test.
	var owner: Player = game.players[0]
	var lord: Player = game.players[1]
	owner.identity = "忠臣"
	owner.identity_revealed = false
	owner.identity_max_hp_bonus = 0
	owner.general_name = "克里斯·西弗"
	owner.max_hp = 3
	owner.hp = 1
	owner.fire_dragon_eggs = 0
	lord.identity = "主公"
	lord.identity_revealed = true
	lord.identity_max_hp_bonus = 1
	lord.hp = 1
	for player in game.players:
		player.hand.clear()
		player.determined_cards.clear()
		if player not in [owner, lord]: player.hp = 3
	owner.hand.append(null)
	var dragon = FireDragonState.create_body()
	var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON, dragon, owner)
	dragon.capture_game_start_state()
	var deaths: Array = []
	var removed: Array = []
	game.unit_death_committed.connect(func(unit): deaths.append(unit))
	game.unit_removed.connect(func(unit, reason): removed.append([unit, reason]))
	game._nullify_override = func(): return false
	game._sacrifice_actor_override = func(actor, target, _amount): return actor == owner and target == lord
	var pending = DamageRecord.new(dragon, game.players[2], null, 1)
	pending.refresh_source()
	t.check(pending.source == dragon and not dragon.unit_disappeared, "I03 Q9 active dragon retains damage source")
	var declared: Array[Player] = [lord, game.players[2], game.players[3], game.players[4], owner]
	var actions: Array[CardActionEvent] = []
	await game._resolve_paid_aoe(dragon, CardData.CardSubType.STRIKE, "南蛮入侵", "杀", actions, game.turn_manager.get_context_revision(), declared)
	t.check(owner.is_dead() and owner.hand_size() == 0 and owner.fire_dragon_eggs == 0, "I03 Q9 real last-card sacrifice and failed rescue finally kill summoner")
	t.check(lord.hp == 1 and lord.is_alive() and not game._game_over, "I03 Q9 lord is protected and match remains ongoing")
	t.check(dragon.unit_disappeared and not dragon.is_dead() and dragon.hp == 3, "I03 Q9 disappearance invalidates source without fake unit death or HP change")
	t.check(removed == [[id, UnitRegistry.Removal.SUMMONER_LOST]] and deaths.is_empty(), "I03 Q9 disappearance emits no normal unit death")
	t.check(game.players.slice(2).all(func(player): return player.hp == 2), "I03 Q9 all three remaining AOE targets still take one damage")
	var damage_events = game.action_history.entries.filter(func(event): return event.kind == "damage")
	t.check(damage_events.size() == 4, "I03 Q9 transferred first damage and three later damages each commit once")
	if damage_events.size() == 4:
		t.check(damage_events[0].text.begins_with("火龙 对"), "I03 Q9 transferred lethal damage retains pre-disappearance source")
		t.check(damage_events.slice(1).all(func(event): return event.text.begins_with("无来源 对")), "I03 Q9 remaining AOE damages publicly record no source")
	pending.refresh_source()
	t.check(pending.source == null and pending.original_source == dragon, "I03 Q9 preexisting damage record refreshes source but preserves original initiator")
	var later = DamageRecord.new(dragon, lord, null, 1)
	later.refresh_source()
	t.check(later.source == null, "I03 Q9 new record also rejects disappeared source")
	dragon.restore_game_start_state()
	t.check(dragon.unit_disappeared and not Player.GENERAL_STATE_FIELDS.has("unit_disappeared"), "I03 Q9 general-state reset cannot restore removed unit membership")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	var source = Player.new()
	source.hp = 0
	var victim = Player.new()
	victim.hp = 3
	var ordinary = DamageRecord.new(source, victim, null, 1)
	ordinary.refresh_source()
	t.check(ordinary.source == source, "I03 Q9 ordinary dying source is not cleared prematurely")
	source.mark_dead()
	ordinary.refresh_source()
	t.check(ordinary.source == null and ordinary.original_source == source, "I03 Q9 existing final-death source rule remains unchanged")
	source.free()
	victim.free()
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
