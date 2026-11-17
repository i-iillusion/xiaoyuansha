extends RefCounted

func hit(game, source, target, amount := 1, element := EffectChain.DamageType.PHYSICAL):
	var chain = game._new_damage_chain(source, target, null, amount, element)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	await game._finish_damage_chain(chain)
	return chain.damage

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for gender in ["male", "female", "none"]:
		for lieqi in [false, true]:
			for woman in [false, true]:
				var game = helper.fixture(t)
				var owner = game.players[0]; var target = game.players[1]
				owner.sally_lieqi_enabled = lieqi; owner.sally_woman_enabled = woman
				target.gender = gender; target.max_hp = 20; target.hp = 20
				var expected = 1 + int(lieqi) + int(woman and gender == "female")
				var first = await hit(game, owner, target)
				t.check(first.committed and first.applied_amount == expected and target.hp == 20-expected, "I05e3 independent source flags and same/opposite/none gender bonus")
				var second = await hit(game, owner, target)
				t.check(second.applied_amount == 1+int(woman and gender == "female"), "I05e3 first bonus consumes only once per actual body")
				var other = game.players[2]
				var different = await hit(game, owner, other)
				t.check(different.applied_amount == 1+int(lieqi), "I05e3 a different body has an independent first hit")
				t.check(owner.sally_first_dealt.size() == (2 if lieqi else 0), "I05e3 disabled Lieqi never collects history through Jiegui or Woman")
				owner.restore_game_start_state()
				t.check(owner.sally_first_dealt.is_empty() and not owner.sally_first_taken and owner.gender == "female" and owner.sally_lieqi_enabled == lieqi, "I05e3 Sage restores general history/gender but not server configuration")
				await helper.dispose(t,game)
	for mode in ["normal", "lion", "fire_prevent", "source_dead", "sourceless"]:
		var game = helper.fixture(t)
		var owner = game.players[0]; var source = game.players[1]
		owner.sally_lieqi_enabled = true
		if mode == "lion": owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SILVER_LION))
		if mode == "fire_prevent": owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.QIXING_PAO))
		if mode == "source_dead": source.hp = 0; source.mark_dead()
		var record = await hit(game, null if mode == "sourceless" else source, owner, 1, EffectChain.DamageType.FIRE)
		var expected = 0 if mode == "fire_prevent" else (1 if mode == "lion" else 2)
		t.check(record.applied_amount == expected and owner.hp == 3-expected, "I05e3 received-first bonus before armor, including sourceless damage: " + mode)
		t.check(owner.sally_first_taken == (expected > 0), "I05e3 prevented damage does not consume first received: " + mode)
		if mode == "fire_prevent":
			owner.remove_equipment("armor")
			var retry = await hit(game,source,owner)
			t.check(retry.applied_amount == 2, "I05e3 first received still available after prevention")
		await helper.dispose(t,game)
	await chain_and_transfer(t, helper)
	await actual_cards_and_units(t, helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func chain_and_transfer(t, helper):
	for mode in ["chain", "transfer", "prevention"]:
		var game = helper.fixture(t)
		var owner = game.players[0]; var b = game.players[1]; var c = game.players[2]
		owner.sally_lieqi_enabled = true
		if mode == "chain": b.chained = true; c.chained = true
		if mode == "transfer":
			c.hand.append(null)
			game._sacrifice_actor_override = func(p,_victim,_amount): return p == c
		if mode == "prevention": b.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.QIXING_PAO))
		var first = await hit(game, owner, b, 1, EffectChain.DamageType.FIRE)
		if mode == "chain":
			t.check(b.hp == 3 and c.hp == 3 and first.applied_amount == 2, "I05e3 Q10 chain transfers two without repeating source Lieqi")
			t.check(owner.sally_first_dealt.size() == 2 and not b.chained and not c.chained, "I05e3 Q10 both actual victims consume first qualification")
		elif mode == "transfer":
			t.check(b.hp == 5 and c.hp == 3 and not first.committed and first.transferred_damage.applied_amount == 2, "I05e3 Q11 only substitute receives original two damage")
			t.check(not owner.sally_first_dealt.has(b.get_instance_id()) and owner.sally_first_dealt.has(c.get_instance_id()) and c.hand_size() == 0, "I05e3 Q11 protected original keeps qualification, substitute consumes it after real payment")
		else:
			t.check(not first.committed and owner.sally_first_dealt.is_empty(), "I05e3 prevention does not consume source first qualification")
			b.remove_equipment("armor")
		game._sacrifice_actor_override = func(_p,_victim,_amount): return false
		var next_b = await hit(game,owner,b)
		var next_c = await hit(game,owner,c)
		t.check(next_b.applied_amount == (1 if mode == "chain" else 2), "I05e3 next original victim hit uses only actually committed history")
		t.check(next_c.applied_amount == (2 if mode == "prevention" else 1), "I05e3 next substitute/propagation victim hit does not regrant first bonus")
		owner.restore_game_start_state()
		b.hp = 5
		var restored = await hit(game,owner,b)
		t.check(restored.applied_amount == 2 and owner.sally_first_dealt.size() == 1, "I05e3 immutable opening history survives multiple Sage restorations")
		await helper.dispose(t,game)

func actual_cards_and_units(t,helper):
	for kind in ["strike", "duel", "aoe"]:
		var game = helper.fixture(t)
		var owner = game.players[0]; var target = game.players[1]
		owner.sally_jiegui_enabled = false
		owner.sally_lieqi_enabled = true; owner.sally_woman_enabled = true
		target.gender = "female"
		for p in game.players: p.max_hp = 8; p.hp = 8
		var sub = CardData.CardSubType.STRIKE if kind == "strike" else (CardData.CardSubType.DUEL if kind == "duel" else CardData.CardSubType.BARBARIAN_INVASION)
		var original = CardBase.create(sub); owner.hand.append(original)
		var events: Array = []; game.card_action_committed.connect(func(e): events.append(e))
		if kind == "aoe": await game._play_aoe(CardData.CardSubType.STRIKE,"南蛮入侵","杀")
		else: await game.execute_card_on_target(target,sub)
		t.check(target.hp == 5 and owner.sally_first_dealt.has(target.get_instance_id()), "I05e3 actual paid card uses both locked modifiers: "+kind)
		t.check(events.size() == 1 and events[0].card == original and events[0].settlement_completed and game.deck._discard.count(original) == 1, "I05e3 actual original fee/USE/completion remains once: "+kind)
		if kind == "aoe":
			t.check(owner.sally_first_dealt.size() == 4 and game.players[2].hp == 6 and owner.hp == 8, "I05e3 actual AOE counts each damaged body and excludes its user")
		target.restore_game_start_state()
		var repeat = await hit(game,owner,target)
		t.check(repeat.applied_amount == 1, "I05e3 victim Sage does not reset source's already-consumed qualification")
		await helper.dispose(t,game)
	for kind in ["mountain", "dragon"]:
		var game = helper.fixture(t)
		var owner = game.players[0]
		owner.sally_lieqi_enabled = true; owner.sally_woman_enabled = true
		var unit: Player
		if kind == "mountain":
			game._mountain_rules_enabled = true; game.players[4].general_name = "吉姆·芒顿"
			unit = game._spawn_mountain_at(game.players[4],0,1)
		else:
			game.players[3].general_name = "克里斯·安德森"
			unit = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,game.players[3])
		var before = unit.hp
		var record = await hit(game,owner,unit)
		t.check(unit.gender == "none" and record.applied_amount == 2 and unit.hp == before-2, "I05e3 unit first hit applies Lieqi but never treats genderless as same sex: "+kind)
		t.check(not owner.sally_first_dealt.has(game.players[3 if kind == "dragon" else 4].get_instance_id()), "I05e3 unit first history never consumes controller's qualification")
		await helper.dispose(t,game)
