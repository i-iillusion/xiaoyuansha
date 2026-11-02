extends RefCounted

func walls(game):
	var first = game._spawn_mountain_at(game.players[0],0,1)
	game._spawn_mountain_at(game.players[0],3,4)
	return first

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["fire","thunder","physical","lethal"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
		walls(game)
		for seat in [1,3,4]: game.players[seat].hp = 4; game.players[seat].chained = true
		if mode == "lethal": game.players[1].hp = 1
		var element = EffectChain.DamageType.PHYSICAL if mode == "physical" else (EffectChain.DamageType.THUNDER if mode == "thunder" else EffectChain.DamageType.FIRE)
		var source = null if mode in ["fire","thunder"] else game.players[2]
		var outcome = await game._deal_damage_result(source,game.players[1],1,element)
		t.check(not outcome.invalidated and game.players[3].hp == (4 if mode == "physical" else 3) and game.players[4].hp == 4, "I04 Q44 elemental chain reaches same-region D, never crosses to E: "+mode)
		t.check(game.players[1].chained == (mode == "physical") and game.players[3].chained == (mode == "physical") and game.players[4].chained, "I04 Q44 blocked E keeps its separate chained state; physical damage consumes no chains")
		t.check(game.players[1].is_dead() == (mode == "lethal") and game.mountain_space.ids().size() == 2, "I04 Q44 lethal propagation retains victim position without reviving a seat or removing walls")
		if mode != "physical":
			await game._deal_damage_result(null,game.players[4],1,EffectChain.DamageType.FIRE)
			t.check(game.players[4].hp == 3 and not game.players[4].chained and game.players[3].hp == 3, "I04 Q44 later independent E damage consumes only its remaining single chain")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await fire(t)
	await terrain_protection(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func fire(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	var center = walls(game)
	for seat in [1,4]: game.players[seat].hp = 4; game.players[seat].chained = true
	var original = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(center)
	t.check(await game._run_judgment(center,false), "I04 Q44 exact mountain fire judgment completes")
	t.check(center.hp == 3 and game.players[1].hp == 3 and not game.players[1].chained and game.players[4].hp == 4 and game.players[4].chained, "I04 Q44 sourceless mountain fire at B cannot propagate across region to nonneighbor E")
	t.check(game.players[0].hp == 4 and game.players[2].hp == 5 and game.players[3].hp == 5 and game.deck._discard.count(original) == 1, "I04 mountain direct neighbors still burn under Q33, without extra chain recipients or duplicate discard")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func lan(t):
	var bridge = load("res://Test/i04_aoe_region_cases.gd").new().bridge_fixture(t,4)
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	var center = game._spawn_mountain_at(game.players[4],0,1)
	game._spawn_mountain_at(game.players[4],3,4)
	for seat in [1,4]: game.players[seat].hp = 4; game.players[seat].chained = true
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(center)
	var token = load("res://Test/i04_aoe_region_cases.gd").new().click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	var view = bridge.snapshot(4)
	t.check(game.players[1].hp == 2 and not game.players[1].chained and game.players[4].hp == 4 and game.players[4].chained, "I04 Q44 real A END drives mountain fire then B's own spread fire, leaving cross-region E unhurt and chained")
	t.check(view.players[1].chained == false and view.players[4].chained == true and view.players[4].hp == 4, "I04 Q44 public remote snapshot preserves both separated chain states")
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and bridge.input_owner() == 1 and not bridge.submit(0,token), "I04 Q44 natural propagation finishes at B's legal PLAY and rejects old END replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func terrain_protection(t):
	for sub in [CardData.CardSubType.BURNING_CAMP,CardData.CardSubType.LIGHTNING]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
		var center = walls(game)
		game.players[2].hand.append(null)
		var offered: Array = []
		game._sacrifice_actor_override = func(p,target,_amount):
			if target == center: offered.append(p); return true
			return false
		var original = CardBase.create(sub)
		center.judgment_cards.append(original)
		t.check(await game._run_judgment(center,false), "I04 Q43 terrain delayed judgment completes without protection: "+str(sub))
		t.check(offered.is_empty() and center.hp == (3 if sub == CardData.CardSubType.BURNING_CAMP else 1) and game.players[2].hand_size() == 1 and game.players[2].hp == 5, "I04 Q43 neither Fire nor Lightning offers or charges terrain Sacrifice")
		t.check(game.deck._discard.count(original) == 1 and game._card_action_serial == 0, "I04 Q43 delayed source discards once without a forbidden card/virtual-card USE")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
