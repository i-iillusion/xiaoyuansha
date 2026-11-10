extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for path in ["strike","borrowed","multi","duel"]:
		for concrete in [false,true]:
			for mode in ["decline","win","stale"]: await payment(t,path,concrete,mode)
	for seat in [0,1]:
		for duel in [false,true]: await bridge_case(t,seat,duel)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func payment(t,path,concrete,mode):
	var game=Cards.new().fixture(t); var actor=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	var owner=actor
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	if path in ["strike","borrowed"]: owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	if path=="multi":
		owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
		owner.equip_card_to_slot("mount_1",CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	var sub=CardData.CardSubType.DUEL if path=="duel" else CardData.CardSubType.STRIKE
	var original=CardBase.create(sub) if concrete else null
	if concrete: owner.determined_cards.append(original)
	else: owner.append_hand_card_silent(null)
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	var used: Array=[]; var done: Array=[]; var seen: Array=[]; var picked: Array=[]
	game.card_action_committed.connect(func(a): used.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._nullify_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and owner.max_hp==2 and done.is_empty(),"I05c shared payment root holds original card while awakening reaction runs: "+path)
		if seen.size()==1:
			t.check(batch.count==2 and owner.awake_choice==0 and target.hp==4 and picked.is_empty(),"I05c last physical card triggers awakening before parent effect/reward: "+path)
			await t.process_frame
			if mode=="stale": sunny.restore_game_start_state()
			return 0 if mode=="win" else -1
		t.check(path in ["strike","borrowed"] and batch.count==1 and owner.awake_choice==3,"I05c first Strike equipment draw follows complete mandatory awakening")
		return -1
	game._awaken_pick_override=func():
		picked.append(true)
		t.check(seen.size()==1 and target.hp==4 and done.is_empty(),"I05c shared parent cannot resolve damage before immunity: "+path)
		return 3
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	var outcome: Array=[]
	match path:
		"strike": await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
		"borrowed": outcome.append(await game._resolve_borrowed_strike(owner,[target],CardData.CardSubType.STRIKE,func(): return true))
		"multi":
			var targets: Array[Player]=[target,game.players[3]]
			await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
		"duel": await game.execute_card_on_target(target,CardData.CardSubType.DUEL)
	var invalid=mode=="stale"
	var reward=1 if path in ["strike","borrowed"] else 0
	t.check(seen.size()==(1 if invalid else 1+reward) and picked.size()==(0 if invalid else 1),"I05c root only advances after current awakening, with no repeated draw: "+path)
	if not invalid:
		t.check(owner.hand_size()==(0 if mode=="win" else 2)+reward and owner.max_hp==2 and owner.hp==2,"I05c shared root retains exact awakened resources and later damage: "+path)
		t.check(target.hp==3 and (path!="multi" or game.players[3].hp==3),"I05c paid original effect resumes exactly once after awakening: "+path)
	var paid=used.filter(func(a): return a.actor_body==owner and a.sub_type==sub)
	t.check(paid.size()==1 and game.deck._discard.count(paid[0].card)==1 and (not concrete or paid[0].card==original),"I05c shared root keeps exact arbitrary/concrete original payment once: "+path)
	t.check(game._pending_card_actions.is_empty() and done.size()==(0 if invalid else used.size()),"I05c shared root completes or abandons every original event without phantom card: "+path)
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,duel):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05c shared payment Bridge starts for host/remote original user")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	game.turn_manager.current_player_idx=seat; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	var owner=game.players[seat]; var target=game.players[seat+1]
	var target_hp=target.hp
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	if not duel: owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	owner.append_hand_card_silent(null); game._set_input_player(owner)
	game.players[4].general_name=Cards.SUNNY
	game._nullify_override=func(): return false
	game._dodge_override=func(): return false
	game._duel_respond_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	var seen: Array=[]; var done: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,_v): seen.append(batch.count); return -1
	var run=func():
		await game.execute_card_on_target(target,CardData.CardSubType.DUEL if duel else CardData.CardSubType.STRIKE)
		done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var choice=Sage.new().token(bridge,seat,"不能成为【南蛮入侵】和【万箭齐发】的目标")
	t.check(not choice.is_empty() and seen==[2] and target.hp==target_hp and done.is_empty(),"I05c original paid Strike/Duel waits for host/remote mandatory immunity before damage")
	t.check(not bridge.submit(1-seat,choice) and bridge.submit(seat,choice),"I05c shared payment immunity rejects wrong seat and accepts actual original user")
	for i in 4: await t.process_frame
	t.check(done==[true] and seen==([2] if duel else [2,1]) and owner.hand_size()==(2 if duel else 3) and target.hp==target_hp-1,"I05c host/remote original payment resumes equipment reward and damage once")
	t.check(bridge.input_owner()==seat and game._pending_card_actions.is_empty() and not bridge.submit(seat,choice),"I05c shared payment restores acting controller and rejects stale immunity tokens")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
