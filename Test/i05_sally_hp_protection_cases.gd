extends RefCounted

func protect(game):
	var p = game.players[0]
	p.sally_smoking_enabled = true; p.sally_smoke_active = true; p.gender = "male"
	game.turn_manager.current_player_idx = 1; game.turn_manager.play_actor_idx = 1
	return p

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	var damage = load("res://Test/i05_sally_damage_cases.gd").new()
	for mode in ["protected", "own_turn", "disabled", "expired", "skipped", "mountain"]:
		var game = helper.fixture(t); var owner = protect(game); var source = game.players[1]
		owner.sally_lieqi_enabled = true
		if mode == "own_turn": game.turn_manager.current_player_idx = 0; game.turn_manager.play_actor_idx = 0
		if mode == "disabled": owner.sally_smoking_enabled = false
		if mode == "expired": owner.sally_smoke_active = false
		if mode in ["skipped", "mountain"]:
			game.turn_manager.current_player_idx = 0; game.turn_manager.play_actor_idx = 0
		if mode == "skipped": game.turn_manager.skip_full_turn = true
		if mode == "mountain": game._mountain_judgment_contexts.append({})
		var kept = mode in ["protected", "skipped", "mountain"]
		var record = await damage.hit(game,source,owner)
		t.check(record.committed and record.applied_amount == 2 and owner.sally_first_taken, "I05e4b2 damage remains committed and consumes received-first: "+mode)
		t.check(record.smoking_hp_protected == kept and owner.hp == (3 if kept else 1), "I05e4b2 actual turn/body governs HP protection: "+mode)
		if kept:
			owner.hp = 2; owner.heal(1)
			var again = await damage.hit(game,source,owner)
			t.check(again.applied_amount == 1 and owner.hp == 3 and again.hp_before == again.hp_after, "I05e4b2 protects each decrease after healing, not a stored floor")
		game._mountain_judgment_contexts.clear()
		await helper.dispose(t,game)
	for element in [EffectChain.DamageType.FIRE,EffectChain.DamageType.THUNDER]:
		var game = helper.fixture(t); var owner = protect(game); var other = game.players[2]
		owner.sally_lieqi_enabled = true; owner.chained = true; other.chained = true
		var record = await damage.hit(game,game.players[1],owner,1,element)
		t.check(record.applied_amount == 2 and owner.hp == 3 and other.hp == 3, "I05e4b2 chain propagates committed two damage despite zero HP delta")
		t.check(not owner.chained and not other.chained, "I05e4b2 protected damage still consumes chain state")
		await helper.dispose(t,game)
	var game = helper.fixture(t); var owner = protect(game); var source = game.players[1]; var victim = game.players[2]
	owner.hand.append(null)
	game._sacrifice_actor_override = func(p,_victim,_amount): return p == owner
	var transferred = await damage.hit(game,source,victim)
	t.check(victim.hp == 5 and owner.hp == 3 and owner.hand_size() == 0 and not transferred.committed, "I05e4b2 actual paid Sacrifice protects original victim and smoking protects substitute HP")
	t.check(transferred.transferred_damage.committed and transferred.transferred_damage.applied_amount == 1, "I05e4b2 transferred damage remains an actual damage fact")
	await helper.dispose(t,game)
	game = helper.fixture(t); owner = protect(game); source = game.players[1]
	source.general_name = "凯文·罗本"; owner.sally_lieqi_enabled = true
	var asks: Array = []
	game._kaiwen_override = func(): asks.append(true); return true
	game._rps_override = func(_p): return GameManager.RPS_ROCK
	await damage.hit(game,source,owner)
	t.check(asks.size() == 2 and source.hand_size() == 0 and owner.hp == 3, "I05e4b2 protected two damage offers Kevin two opportunities; ties do not replay")
	await helper.dispose(t,game)
	game = helper.fixture(t); owner = protect(game); owner.hp = 2
	owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.LIEHUO_SHIELD))
	game._liehuo_override = func(): return true
	game._zone_pick_override = func(): return "equip"
	var dismantle = CardBase.create(CardData.CardSubType.DISMANTLE); game.players[1].hand.append(dismantle)
	await game.execute_card_on_target(owner,CardData.CardSubType.DISMANTLE)
	t.check(owner.hp == 1 and owner.sally_smoke_active and owner.get_armor() == CardData.CardSubType.LIEHUO_SHIELD and game.deck._discard.count(dismantle) == 1, "I05e4b2 Q16 actual paid Dismantle is stopped by truly paid shield HP fee")
	await helper.dispose(t,game)
	game = helper.fixture(t); owner = protect(game); owner.hp = 2
	owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR)); owner.hand.append(null)
	game._zhangba_override = func(): return 1
	var strike = await game._resolve_borrowed_strike(owner,[game.players[1]],CardData.CardSubType.STRIKE,func(): return true)
	t.check(strike == 1 and owner.hp == 1 and game.players[1].hp == 3 and owner.hand_size() == 0, "I05e4b2 Q13 actual borrowed Strike pays Zhangba HP and gains damage")
	await helper.dispose(t,game)
	game = helper.fixture(t); owner = protect(game); source = game.players[1]
	source.general_name = "里奥·普利威尔"; source.hp = 0
	game._rescue_choice_override = func(_p,_d,_o): return -1
	await game._resolve_dying(source,null,"test")
	t.check(owner.hp == 1 and not owner.sally_first_taken, "I05e4b2 highest-priority Yudaxi directly deducts HP, without creating damage")
	await helper.dispose(t,game)
	await non_cost(t,helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func non_cost(t,helper):
	var game = load("res://Test/i04_gather_cases.gd").new().fixture(t,5,true)
	var owner = game.players[1]
	owner.general_name = helper.SALLY; owner.sally_smoking_enabled = true; owner.sally_smoke_active = true; owner.hp = 2
	game._jim_gather_choice_override = func(_p,options,_v): return options.find("lose")
	var before = game.players[2].hp
	var result = await game._activate_jushan(game.players[0])
	t.check(result == 1 and owner.hp == 2 and game.players[2].hp == before-1, "I05e4b2 actual Gather non-cost loss protects only active smoking body")
	await helper.dispose(t,game)
	game = helper.fixture(t); owner = protect(game); owner.hp = 2; owner.good_deed_marks = 2
	var simba = game.players[2]; simba.general_name = "辛巴·古德曼"; simba.simba_good_deeds_enabled = true; simba.hp = 0
	game._simba_deed_choice_override = func(_p,candidates,_reclaim,_v): return candidates.find(owner)
	game._rescue_choice_override = func(_p,_d,_o): return -1
	await game._resolve_dying(simba,null,"test")
	t.check(owner.hp == 2 and owner.good_deed_marks == 0 and simba.hp == 2, "I05e4b2 actual deed reclaim removes marks and heals Simba while target HP is protected")
	await helper.dispose(t,game)
