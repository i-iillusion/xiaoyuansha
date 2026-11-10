extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func fixture(t):
	var game=Cards.new().fixture(t)
	game._dodge_override=func(): return false
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==game.players[4] else GameManager.RPS_SCISSORS
	return game

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for sub in [CardData.CardSubType.STRIKE,CardData.CardSubType.FIRE_STRIKE,CardData.CardSubType.THUNDER_STRIKE]:
		for concrete in [false,true]:
			for mode in ["win","decline","stale"]: await ordinary(t,sub,concrete,mode)
	for stale in [false,true]: await response(t,stale)
	await borrowed(t)
	for stale in [false,true]: await shensu(t,stale)
	await multi_without_qinglong(t)
	for seat in [0,1]: await bridge_case(t,seat)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func ordinary(t,sub,concrete,mode):
	var game=fixture(t); var p=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	p.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	var old=CardBase.create(CardData.CardSubType.DODGE); p.append_hand_card_silent(old)
	var original=CardBase.create(sub) if concrete else null
	if concrete: p.determined_cards.append(original)
	else: p.append_hand_card_silent(null)
	p.wine_stacks=1
	var actions: Array=[]; var completed: Array=[]; var seen: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==p and p.hand_size()==2 and p.wine_stacks==0 and target.hp==4 and game.turn_manager.strike_count_this_turn==1,"I05c Qinglong reaction follows one physical Strike payment and wine/quota commitment")
		await t.process_frame
		t.check(target.hp==4 and completed.is_empty() and actions.size()==1,"I05c ordinary/elemental Strike awaits reward reaction before damage or completion")
		if mode=="stale": sunny.restore_game_start_state()
		return -1 if mode=="decline" else 0
	await game.execute_card_on_target(target,sub)
	t.check(seen.size()==1 and target.hp==(4 if mode=="stale" else 2) and completed.size()==(0 if mode=="stale" else 1),"I05c Qinglong original wine Strike resumes once or abandons stale completion")
	t.check(p.hand.has(old) and p.hand_size()==(1 if mode=="win" else 2) and sunny.hand_size()==(1 if mode=="win" else 0),"I05c Qinglong only transfers its new blank reward, retaining old concrete hand resource")
	t.check(game.deck._discard.count(actions[0].card)==1 and (not concrete or actions[0].card==original) and game._pending_card_actions.is_empty(),"I05c Qinglong ordinary/elemental paid resource and completion cannot be replayed")
	await Farming.new().dispose(t,game)

func response(t,stale):
	var game=fixture(t); var p=game.players[1]; var sunny=game.players[4]
	game.lan_enabled=false
	p.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	p.append_hand_card_silent(null); game.players[0].append_hand_card_silent(null)
	game._ai_response_override=func(view,_kind,options): return CardData.CardSubType.STRIKE if view.actor==1 and options.has(CardData.CardSubType.STRIKE) else -1
	var actions: Array=[]; var completed: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		t.check(valid.call() and batch.owner==p and actions.size()==2 and actions[1].kind==CardActionEvent.Kind.RESPONSE and completed.is_empty(),"I05c actual AOE response is paid before Qinglong reward and both parent facts remain pending")
		await t.process_frame
		t.check(p.hp==4 and game.players[2].hp==4,"I05c response reward suspends original AOE before next target")
		if stale: sunny.restore_game_start_state()
		return 0
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	t.check(p.hp==4 and game.players[2].hp==(4 if stale else 3),"I05c paid Strike response remains effective after its reward is stolen; stale response stops parent")
	t.check(game.turn_manager.strike_count_this_turn==0 and completed.size()==(0 if stale else 2),"I05c response uses no ordinary active Strike quota and completes response/AOE once")
	t.check(sunny.hand_size()==(0 if stale else 1) and game._pending_card_actions.is_empty(),"I05c AOE response and draw reaction release both original receipts")
	await Farming.new().dispose(t,game)

func borrowed(t):
	var game=fixture(t); var first=game.players[1]; var target=game.players[2]; var sunny=game.players[4]
	first.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	for i in 2: first.append_hand_card_silent(null); game.players[0].append_hand_card_silent(null)
	game.turn_manager.strike_count_this_turn=1
	game._borrowed_second_target_override=func(options): return options.find(target)
	game._borrowed_strike_override=func(_p,_t,_o): return CardData.CardSubType.STRIKE
	var seen: Array=[]; var actions: Array=[]; var completed: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==first and actions.size()==2 and completed.is_empty() and target.hp==4,"I05c actual Borrowed Sword waits for first actor's reward, not trick user's draw")
		await t.process_frame
		return 0
	for i in 2: await game.execute_card_on_target(first,CardData.CardSubType.BORROWED_SWORD)
	t.check(seen.size()==1 and sunny.hand_size()==1 and first.hand_size()==0 and target.hp==2,"I05c two actual borrowed Strikes give Qinglong only the first reward in the same turn")
	t.check(game.turn_manager.strike_count_this_turn==1 and game.turn_manager.borrowed_sword_count_this_turn==2,"I05c borrowed requirement ignores ordinary Strike quota and preserves two-trick limit")
	t.check(actions.size()==4 and completed.size()==4 and actions.filter(func(a): return a.actor_body==first).size()==2,"I05c original borrowed tricks and required Strikes keep real actor ownership and complete once")
	t.check(game._pending_card_actions.is_empty(),"I05c borrowed reward does not strand original trick or required Strike")
	await Farming.new().dispose(t,game)

func shensu(t,stale):
	var game=fixture(t); var p=game.players[0]; var target=game.players[2]; var sunny=game.players[4]
	p.general_name="比尔·盖伊"
	p.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	p.wine_stacks=1
	var old=CardBase.create(CardData.CardSubType.DODGE); p.append_hand_card_silent(old)
	var actions: Array=[]; var completed: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		t.check(valid.call() and batch.owner==p and p.wine_stacks==0 and target.hp==4 and actions[0].is_virtual and not actions[0].from_hand,"I05c authorized Shensu Strike freezes wine before yielding to Qinglong reaction")
		await t.process_frame
		if stale: sunny.restore_game_start_state()
		return 0
	# Authorized strike subflow; the existing Bill suite owns judgment/skip UI.
	await game._execute_shensu_strike(p,target)
	t.check(target.hp==(4 if stale else 2) and p.hand==[old] if not stale else target.hp==4 and p.hand_size()==2,"I05c Shensu virtual wine Strike resumes without consuming an original hand card")
	t.check(game.turn_manager.strike_count_this_turn==0 and completed.size()==(0 if stale else 1),"I05c Shensu reward cannot add ordinary active Strike quota or double completion")
	t.check(game._pending_card_actions.is_empty(),"I05c stale/finished Shensu reward releases virtual Strike receipt")
	await Farming.new().dispose(t,game)

func multi_without_qinglong(t):
	var game=fixture(t); var p=game.players[0]
	p.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD)); p.append_hand_card_silent(null)
	var targets: Array[Player]=[game.players[1],game.players[2]]
	await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
	t.check(targets[0].hp==3 and targets[1].hp==3 and game._draw_batches.is_empty(),"I05c Fangtian parent still resolves all targets without inventing simultaneous Qinglong equipment")
	t.check(game.turn_manager.strike_count_this_turn==1 and game.turn_manager._strike_actors_this_turn.size()==1 and game._pending_card_actions.is_empty(),"I05c multi-target parent records only one Strike and no reward or replay")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c Qinglong borrowed parent Bridge starts")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear()
	var sunny=game.players[seat]; sunny.general_name=Cards.SUNNY
	var first=game.players[2]; var target=game.players[3]
	first.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	first.append_hand_card_silent(null); game.players[0].append_hand_card_silent(null)
	game._nullify_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._borrowed_second_target_override=func(options): return options.find(target)
	game._borrowed_strike_override=func(_p,_t,_o): return CardData.CardSubType.STRIKE
	game._dodge_override=func(): return false
	var hp=target.hp; var done: Array=[]
	var run=func():
		await game.execute_card_on_target(first,CardData.CardSubType.BORROWED_SWORD)
		done.append(true)
	run.call_deferred()
	for i in 2: await t.process_frame
	var activate=Sage.new().token(bridge,seat,"发动")
	t.check(not activate.is_empty() and done.is_empty() and first.hand_size()==1 and target.hp==hp,"I05c host/remote Qinglong reward holds actual borrowed trick before required Strike hits")
	t.check(not bridge.submit(1-seat,activate) and bridge.submit(seat,activate) and not bridge.submit(seat,activate),"I05c borrowed reward retains Sunny input ownership and rejects stale token")
	for i in 2: await t.process_frame
	t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"石头")),"I05c host/remote Qinglong reaction accepts first gesture")
	for i in 2: await t.process_frame
	t.check(bridge.submit(2,Sage.new().token(bridge,2,"剪刀")),"I05c required Strike actor owns second gesture")
	for i in 3: await t.process_frame
	t.check(done==[true] and target.hp==hp-1 and first.hand_size()==0 and sunny.hand_size()==1,"I05c host/remote borrowed trick resumes once after physical reward moves")
	t.check(game._pending_card_actions.is_empty() and not bridge.submit(seat,activate),"I05c borrowed/Strike/draw chain leaves no old action token")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
