extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for path in ["nullify","sacrifice"]:
		for concrete in [false,true]:
			for mode in ["decline","win","stale"]: await payment(t,path,concrete,mode)
	for seat in [0,1]:
		for sacrifice in [false,true]: await bridge_case(t,seat,sacrifice)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func payment(t,path,concrete,mode):
	var game=Cards.new().fixture(t); var actor=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	var owner=game.players[3]
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	var sub=CardData.CardSubType.NULLIFICATION if path=="nullify" else CardData.CardSubType.SACRIFICE
	var original=CardBase.create(sub) if concrete else null
	if concrete: owner.determined_cards.append(original)
	else: owner.append_hand_card_silent(null)
	actor.append_hand_card_silent(null)
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	var used: Array=[]; var done: Array=[]; var seen: Array=[]; var picked: Array=[]; var counters: Array=[]
	game.card_action_committed.connect(func(a): used.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._nullify_override=func():
		if path=="nullify" and counters.is_empty() and game._input_seat==owner.seat_index:
			counters.append(true); return true
		return false
	game._sacrifice_actor_override=func(p,_target,_amount): return path=="sacrifice" and p==owner and picked.is_empty()
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and owner.max_hp==2 and used.size()==2 and done.is_empty(),"I05c other response payment root holds original card while awakening reaction runs: "+path)
		if seen.size()==1:
			t.check(batch.count==2 and owner.awake_choice==0 and target.hp==4 and picked.is_empty(),"I05c last physical card triggers awakening before parent effect/reward: "+path)
			await t.process_frame
			if mode=="stale": sunny.restore_game_start_state()
			return 0 if mode=="win" else -1
		return -1
	game._awaken_pick_override=func():
		picked.append(true)
		t.check(seen.size()==1 and target.hp==4 and done.is_empty(),"I05c other response parent cannot resolve damage/nullification/redirect before immunity: "+path)
		return 3
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	await game.execute_card_on_target(target,CardData.CardSubType.DUEL if path=="nullify" else CardData.CardSubType.STRIKE)
	var invalid=mode=="stale"
	t.check(seen.size()==1 and picked.size()==(0 if invalid else 1),"I05c root only advances after current awakening, with no repeated draw: "+path)
	if not invalid:
		t.check(owner.hand_size()==(0 if mode=="win" else 2) and owner.max_hp==2 and owner.hp==(1 if path=="sacrifice" else 2),"I05c other response root retains exact awakened resources and later damage: "+path)
		t.check(target.hp==4,"I05c paid original effect resumes exactly once after awakening: "+path)
	var paid=used.filter(func(a): return a.actor_body==owner and a.sub_type==sub)
	t.check(paid.size()==1 and game.deck._discard.count(paid[0].card)==1 and (not concrete or paid[0].card==original),"I05c other response root keeps exact arbitrary/concrete original payment once: "+path)
	t.check(game._pending_card_actions.is_empty() and done.size()==(0 if invalid else used.size()),"I05c other response root completes or abandons every original event without phantom card: "+path)
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,sacrifice):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05c other response Bridge starts for host/remote responder")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	game.turn_manager.current_player_idx=2; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	var source=game.players[2]; var target=game.players[3]; var owner=game.players[seat]
	var target_hp=target.hp
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	owner.append_hand_card_silent(null); source.append_hand_card_silent(null)
	game._set_input_player(source); game.players[4].general_name=Cards.SUNNY
	game._nullify_override=Callable(); game._sacrifice_actor_override=Callable(); game._sacrifice_override=Callable()
	game._dodge_override=func(): return false
	game._duel_respond_override=func(): return false
	game._paixiong_override=func(): return false
	var seen: Array=[]; var done: Array=[]; var actions: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game._corruption_choice_override=func(_p,batch,_s,_v):
		seen.append(batch.count)
		t.check(actions.size()==2 and done.is_empty(),"I05c other response records original paid response before awakening draw reaction")
		return -1
	var run=func():
		await game.execute_card_on_target(target,CardData.CardSubType.STRIKE if sacrifice else CardData.CardSubType.DUEL)
		done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var response=Sage.new().token(bridge,seat,"打出【舍己为人】" if sacrifice else "打出【无懈可击】")
	t.check(not response.is_empty() and seen.is_empty() and done.is_empty(),"I05c host/remote sees actual original response before any awakening reward")
	t.check(not bridge.submit(1-seat,response) and bridge.submit(seat,response),"I05c original other response rejects wrong seat and accepts actual responder")
	for i in 3: await t.process_frame
	var immunity=Sage.new().token(bridge,seat,"不能成为【南蛮入侵】和【万箭齐发】的目标")
	t.check(not immunity.is_empty() and seen==[2] and target.hp==target_hp and done.is_empty(),"I05c host/remote paid counter/redirect awaits mandatory immunity before original effect")
	t.check(not bridge.submit(seat,response) and bridge.submit(seat,immunity),"I05c actual immunity accepts current token and rejects old response token")
	for i in 3: await t.process_frame
	if not sacrifice:
		var decline=Sage.new().token(bridge,seat,"放弃")
		t.check(not decline.is_empty() and done.is_empty(),"I05c awakening cards remain legally available for a fresh counter-Nullification window")
		t.check(bridge.submit(seat,decline),"I05c actual responder may decline the next counter with new cards retained")
		for i in 3: await t.process_frame
	t.check(done==[true] and owner.hp==(1 if sacrifice else 2) and owner.max_hp==2 and owner.hand_size()==2 and target.hp==target_hp,"I05c other response returns original redirect/cancel result after full awakening")
	t.check(actions.size()==2 and game._pending_card_actions.is_empty() and bridge.input_owner()==2 and not bridge.submit(seat,immunity),"I05c other response completes original events once and restores original user input")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
