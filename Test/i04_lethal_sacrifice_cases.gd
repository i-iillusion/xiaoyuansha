extends RefCounted

func configure(game):
	var actor = game.players[4]
	actor.general_name = "安普提·斯丢皮得"
	actor.hp = 1
	actor.hand.clear()
	actor.determined_cards.clear()
	game.players[3].hp = 2
	game._yes_ah_override = func(): return "skill"
	game._rps_override = func(p): return game.RPS_ROCK if p == actor else game.RPS_PAPER

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["duel","fire","thunder_chain","phase_after_use","restart_cost"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
		load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game)
		configure(game)
		var actor = game.players[4]
		var offered: Array = []
		var actions: Array = []
		var at_commit: Array = []
		game.card_action_committed.connect(func(e):
			actions.append(e)
			if e.sub_type == CardData.CardSubType.SACRIFICE:
				at_commit.append(actor.is_dead())
				if mode == "phase_after_use": game.turn_manager.current_phase = TurnManager.Phase.END)
		game._sacrifice_actor_override = func(p,target,_amount):
			if target != game.players[3]: return false
			offered.append(p.seat_index)
			return p == actor and p.is_alive()
		if mode == "restart_cost":
			game._rescue_choice_override = func(_r,_d,_o): game.reset_game_over_state(); return -1
		var chain: EffectChain
		if mode in ["fire","thunder_chain"]:
			game.players[2].chained = true
			game.players[3].chained = true
			chain = game._new_damage_chain(game.players[1],game.players[3],null,2,EffectChain.DamageType.FIRE if mode == "fire" else EffectChain.DamageType.THUNDER)
			chain.skip_targeting = true
			chain.skip_response = true
			chain.damage.is_chain = mode == "thunder_chain"
			await chain.start()
			await game._finish_damage_chain(chain)
		else:
			game.players[1].hand.append(null)
			await game.execute_card_on_target(game.players[3],CardData.CardSubType.DUEL)
		var sacrifice = actions.filter(func(e): return e.sub_type == CardData.CardSubType.SACRIFICE)
		var stale = mode in ["phase_after_use","restart_cost"]
		t.check(game.players[3].hp == 2 and actor.hp == 0 and (actor.is_dead() or mode == "restart_cost"), "I04 Q49 original D takes no damage; paid E is never charged transferred damage: "+mode)
		if mode != "restart_cost":
			t.check(offered == [4] and at_commit == [true] and sacrifice.size() == 1 and sacrifice[0].actor_body == actor and sacrifice[0].is_virtual and not sacrifice[0].from_hand, "I04 Q49 fully paid virtual Sacrifice is recorded after final death, without fallback volunteer or fabricated hand card")
			t.check(not game.deck._discard.has(sacrifice[0].card) and sacrifice[0].settlement_completed == (not stale) and not game._mountain_live_seats().has(4), "I04 Q49 normal paid response completes once; dead source is only retained attribution, never live membership")
		else:
			t.check(sacrifice.is_empty(), "I04 cost restart cannot authorize a virtual response in a new lifecycle")
		t.check(game._pending_card_actions.is_empty() and game.players[0].hand_size() == 1 and game.players[2].hand_size() == 1 and game.players[5].hand_size() == 1, "I04 Q49 no extra response/physical payment leaks; unused same/opposite-side resources remain")
		if chain != null:
			t.check(chain.damage.transfer_target == actor and chain.damage.transferred_damage == null and not chain.damage.committed and not chain.continuation_invalid and game.players[2].hp == 5 and game.players[3].chained, "I04 Q49 dead substitute completes prevention without creating new damage, after-damage triggers or chain propagation")
		else:
			t.check(actions[0].sub_type == CardData.CardSubType.DUEL and actions[0].settlement_completed == (not stale) and game.deck._discard.count(actions[0].card) == 1, "I04 Q49 paid original Duel settles once normally; technical invalidation preserves payment without completing stale action")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game = bridge.game
	configure(game)
	# Rescue declines and losing RPS use explicit deterministic hooks; E's
	# response button, HP cost, dying/death, USE and parent continuation are real.
	var actions: Array = []
	game.card_action_committed.connect(func(e): actions.append(e))
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,1,"出牌")
	helper.click(t,bridge,1,"锦囊牌")
	helper.click(t,bridge,1,"普通锦囊")
	helper.click(t,bridge,1,"决斗")
	await t.create_timer(0.15).timeout
	game._target_confirm_override = func(): return 1
	var target: String = bridge.snapshot(1).targets.get("3","")
	t.check(target != "" and bridge.submit(1,target), "I04 Q49 actual B menu pays Duel and targets D")
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(4),"发动【是~啊~】打出")
	t.check(token != "" and bridge.input_owner() == 4 and not bridge.submit(2,token) and bridge.submit(4,token), "I04 Q49 only live E can confirm actual no-hand virtual Sacrifice")
	for i in 3: await t.process_frame
	var sacrifice = actions.filter(func(e): return e.sub_type == CardData.CardSubType.SACRIFICE)
	t.check(game.players[4].is_dead() and game.players[4].hp == 0 and game.players[3].hp == 2 and sacrifice.size() == 1 and sacrifice[0].is_virtual and actions.all(func(e): return e.settlement_completed), "I04 actual lethal virtual payment finishes death then prevents D's Duel damage, completing both USE facts")
	t.check(game.players[2].hand_size() == 1 and game.players[0].hand_size() == 1 and game.players[5].hand_size() == 1 and not game.deck._discard.has(sacrifice[0].card), "I04 actual lethal virtual protection never bills another volunteer or invents physical discard")
	t.check(bridge.input_owner() == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._pending_card_actions.is_empty() and not bridge.submit(4,token), "I04 Q49 returns input to B PLAY and rejects dead E's old token")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
