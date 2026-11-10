extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for deaths in [1,2]: await reward(t,deaths)
	await sage_is_not_exempt(t)
	await callback_reset(t)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func reward(t,deaths):
	var game=Cards.new().fixture(t); var leo=game.players[0]; var sunny=game.players[4]
	leo.general_name="里奥·普利威尔"; leo.max_hp=5; leo.hp=0
	game.players[1].hp=1
	if deaths==2: game.players[2].hp=1
	var asks: Array=[]
	game._corruption_choice_override=func(_p,batch,_stage,_valid): asks.append(batch); return 0
	t.check(await game._resolve_dying(leo,null,"q11_actual_reward")==0,"I05c Q11 actual rescue/rule pipeline completes with reward excluded")
	t.check(leo.hp==deaths and leo.hand_size()==deaths and game.players[1].is_dead() and (deaths==1 or game.players[2].is_dead()),"I05c Q11 actual deaths still determine restored HP and exact X-card reward")
	var records=game._draw_batches.filter(func(batch): return batch.owner==leo)
	t.check(records.size()==1 and records[0].is_extra() and records[0].corruption_exempt and records[0].during_yudaxi,"I05c Q11 preserves EXTRA fact and originating rule context, with specific Corruption exemption")
	t.check(asks.is_empty() and sunny.hand_size()==0 and not game.yudaxi.is_active() and game._dying_contexts.is_empty(),"I05c Q11 asks neither inside rule nor as a deferred reward prompt")
	await game._resolve_corruption_batch(records[0])
	t.check(asks.is_empty() and leo.hand_size()==deaths and not records[0].reaction_started,"I05c Q11 dispatch after rule end cannot reopen this exempt reward")
	game._corruption_choice_override=func(_p,batch,_stage,_valid): asks.append(batch); return -1
	var later=game._draw_blank_cards(leo,1)
	await game._resolve_corruption_batch(later)
	t.check(not later.corruption_exempt and later.is_extra() and asks==[later] and leo.hand_size()==deaths+1,"I05c Q11 exemption is per batch and never leaks to a later normal extra draw")
	await Farming.new().dispose(t,game)

func sage_is_not_exempt(t):
	var game=Sage.new().fixture(t); var leo=game.players[0]; var david=game.players[1]; var sunny=game.players[2]
	leo.general_name="里奥·普利威尔"; leo.max_hp=5; leo.hp=0
	david.hp=1; game.players[3].hp=1; game.players[4].hp=1
	game._sage_save_override=func(): return true
	game._rescue_choice_override=func(_p,_t,_o): return -1
	var asks: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,valid):
		asks.append(batch)
		t.check(valid.call() and batch.owner==david and not batch.corruption_exempt and game.yudaxi.is_active(),"I05c Q10 Sage still triggers immediate Corruption during highest-priority rule")
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	t.check(await game._resolve_dying(leo,null,"q11_distinct_sage_reward")==0,"I05c Q10/Q11 coexist in one actual rule without duplicate or missing continuation")
	t.check(asks.size()==1 and sunny.hand_size()==4 and david.hand_size()==0 and leo.hp==2 and leo.hand_size()==2,"I05c Sage four cards may move immediately while Leo's later two reward cards stay exempt")
	var rewards=game._draw_batches.filter(func(batch): return batch.owner==leo)
	t.check(rewards.size()==1 and rewards[0].corruption_exempt and rewards[0].is_extra(),"I05c success reward and Sage draw remain different batches and skill policies")
	await game._resolve_corruption_batch(rewards[0])
	t.check(asks.size()==1 and game._dying_contexts.is_empty(),"I05c exempt success reward cannot create a second stale Sage window")
	await Farming.new().dispose(t,game)

func callback_reset(t):
	var resolver=YudaxiResolver.new(); var leo=Player.new(); var victim=Player.new()
	leo.hp=0; victim.hp=1
	var targets: Array[Player]=[victim]
	await resolver.resolve(leo,func(_p): return targets,func(p): p.mark_dead(),
		func(_p,_n): resolver.reset(),func(): return false,func(): t.check(false,"I05c unexpected rule safety limit"))
	t.check(leo.hp==1 and victim.is_dead() and not resolver.is_active() and resolver.results.is_empty(),"I05c reset inside synchronous reward observer cannot append old result or pop a new rule stack")
	leo.free(); victim.free()
