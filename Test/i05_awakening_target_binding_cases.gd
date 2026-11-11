extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	for sub in [CardData.CardSubType.BARBARIAN_INVASION,CardData.CardSubType.VOLLEY_OF_ARROWS]:
		for concrete in [false,true]:
			for greed in [false,true]: await aoe(t,sub,concrete,greed)
		await prior_immunity(t,sub)
	for concrete in [false,true]:
		for greed in [false,true]: await duel(t,concrete,greed)

func prepare(t,concrete,sub):
	var game=Cards.new().fixture(t); var c=game.players[2]
	c.general_name="史蒂芬·彼特先斯"; c.max_hp=3; c.hp=3; c.capture_game_start_state()
	if concrete: c.determined_cards.append(CardBase.create(sub))
	else: c.append_hand_card_silent(null)
	game._paixiong_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	return game

func aoe(t,sub,concrete,greed):
	var game=prepare(t,concrete,CardData.CardSubType.NULLIFICATION)
	var a=game.players[0]; var b=game.players[1]; var c=game.players[2]; var sunny=game.players[4]
	a.append_hand_card_silent(null)
	var counters: Array=[]; var draws: Array=[]; var completed: Array=[]
	game.card_action_completed.connect(func(event): completed.append(event))
	game._nullify_override=func():
		if game._input_seat==c.seat_index and counters.is_empty(): counters.append(true); return true
		return false
	game._aoe_override=func(): return false
	game._corruption_choice_override=func(_p,batch,_s,valid):
		draws.append(batch)
		t.check(valid.call() and batch.owner==c and batch.count==2 and b.hp==4 and completed.is_empty(),"Q13 original AOE remains suspended at B while C awakens from last Nullification")
		return 0 if greed else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func(): return 3
	await game.play_card(sub)
	t.check(c.awake_choice==3 and c.max_hp==2 and c.hp==1,"Q13 newly gained immunity cannot cancel this already-designated Nanman/Arrows target")
	t.check(b.hp==4 and game.players[3].hp==3 and sunny.hp==3,"Q13 paid Nullification protects B only; later original targets still resolve")
	t.check(draws.size()==1 and c.hand_size()==(0 if greed else 2) and sunny.hand_size()==(2 if greed else 0),"Q13 exact awakening batch resolves once before the original AOE resumes")
	t.check(not game._prep_group_scope(a,sub).has(c) and completed.size()==2 and game._pending_card_actions.is_empty(),"Q13 next AOE cannot designate C; original AOE and Nullification complete once")
	await Farming.new().dispose(t,game)

func prior_immunity(t,sub):
	var game=prepare(t,false,CardData.CardSubType.STRIKE); var c=game.players[2]
	c.awoken=true; c.awaken_effects_applied=true; c.awake_choice=3; c.max_hp=2; c.hp=2
	game.players[0].append_hand_card_silent(null); game._nullify_override=func(): return false; game._aoe_override=func(): return false
	t.check(not game._prep_group_scope(game.players[0],sub).has(c),"Q13 existing immunity prevents initial designation, rather than cancelling a later target")
	await game.play_card(sub)
	t.check(c.hp==2 and c.hand_size()==1 and game._pending_card_actions.is_empty(),"Q13 pre-immune C pays no response and suffers no damage from a newly used AOE")
	await Farming.new().dispose(t,game)

func duel(t,concrete,greed):
	var game=prepare(t,concrete,CardData.CardSubType.STRIKE)
	var a=game.players[0]; var c=game.players[2]; var sunny=game.players[4]
	for i in 3: a.append_hand_card_silent(null)
	var draws: Array=[]; var completed: Array=[]; var replies: Array=[]
	game.card_action_completed.connect(func(event): completed.append(event))
	game._nullify_override=func(): return false
	game._duel_respond_override=func():
		replies.append(true)
		return replies.size()<=2 # C's last Kill, then A's Kill; C declines next.
	game._corruption_choice_override=func(_p,batch,_s,valid):
		draws.append(batch)
		t.check(valid.call() and batch.owner==c and c.awake_choice==0 and a.hand_size()==2 and completed.is_empty(),"Q14 original Duel waits for C's last Kill awakening before A's response")
		return 0 if greed else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func(): return 2
	await game.execute_card_on_target(c,CardData.CardSubType.DUEL)
	t.check(c.awake_choice==2 and c.hp==1 and c.max_hp==2 and a.hand_size()==1,"Q14 original Duel continues after immunity: A pays Kill and C suffers one damage")
	t.check(draws.size()==1 and c.hand_size()==(0 if greed else 2),"Q14 original Duel neither re-awakens C nor steals another batch")
	t.check(not game.get_trick_targets(a,CardData.CardSubType.DUEL).has(c),"Q14 new Duel declarations reject C after immunity is chosen")
	t.check(completed.size()==3 and game._pending_card_actions.is_empty(),"Q14 original Duel and both physical Kill responses complete exactly once")
	await Farming.new().dispose(t,game)
