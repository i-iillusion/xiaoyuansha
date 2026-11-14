extends RefCounted
const Base=preload("res://Test/h02_integration_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func fixture(t,mode=GameModes.FREE_FOR_ALL):
	var game=Base.new().fixture(t,5,mode)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.lan_enabled=false; game._paipian_rules_enabled=true; game._spy_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var actor=game.players[1]; actor.general_name="桑尼·斯派"; actor.max_hp=4; actor.hp=4; actor.capture_game_start_state()
	game.turn_manager.current_player_idx=1; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	game.ai_pacer.speed=AiActionPacer.Speed.FAST
	game._nullify_override=func(): return false
	game._duel_respond_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	return game

func offer(game,p,skill):
	var options=game._ai_play_candidates(game._ai_observation(p))
	for action in options:
		if action.get("skill","")==skill: return action
	return {}

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for gifted in [false,true]:
		for concrete in [false,true]: await filming(t,gifted,concrete)
	for mode in [GameModes.CLASSIC,GameModes.AMBITIOUS]: await spy(t,mode)
	await identity_privacy(t)
	for skill in ["paipian","spy"]:
		for fault in ["restore_actor","restore_target","phase","hand","target_dead","registry","gate","used","terrain"]: await stale(t,skill,fault)
	for mode in ["win","lose","tie","decline","stale","technical","dead","phase","ended","reset","wrestle"]: await corruption(t,mode)
	await target_rules(t)
	await yudaxi(t)
	await paced(t)
	await sage_turn(t)
	await human_response(t)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func filming(t,gifted,concrete):
	var game=fixture(t); var actor=game.players[1]; var a=game.players[0]; var b=game.players[2]
	a.hp=1; b.hp=2
	var card=CardBase.create(CardData.CardSubType.DODGE) if concrete else null
	if concrete: actor.determined_cards.append(card)
	else: actor.append_hand_card_silent(null)
	var action=offer(game,actor,"paipian")
	t.check(action.get("targets",[])==[0,2] and game._ai_sunny_action_current(actor,action),"Sunny AI offers two most injured legal other recipients without exposing bodies")
	var facts: Array=[]; game.card_action_committed.connect(func(e): facts.append(e))
	if gifted:
		a.general_name="麦克斯·欧尼斯特"; game.turn_manager.current_player_idx=0; game.turn_manager.current_phase=TurnManager.Phase.START
		game._meiyong_override=func(): return true
		game._meiyong_option_override=func(): return 2
		game._meiyong_target_override=func(): return actor
		var act=func():
			t.check(game._play_actor()==actor and game.turn_manager.current_player_idx==0,"Actual Max gift keeps AI Sunny as PLAY actor, Max as turn owner")
			await game._run_ai_play(actor)
		act.call_deferred()
		t.check(await game._maybe_meiyong(a)==1 and game.turn_manager.current_phase==TurnManager.Phase.START,"AI completes genuine gifted PLAY and resumes donor START")
	else:
		await game._run_ai_play(actor)
		t.check(game.turn_manager.current_phase==TurnManager.Phase.DISCARD,"Default AI finishes ordinary PLAY after useful filming")
	t.check(actor.hand_size()==0 and a.hp==2 and b.hp==3 and actor.hp==4,"Actual AI shared filming pays one original card, heals two others exactly once")
	t.check(facts.is_empty() and (not concrete or game.deck._discard.count(card)==1),"AI skill fee is not a card USE and concrete cost discards once")
	t.check(game._paipian_pending.is_empty() and game._pending_card_actions.is_empty(),"AI filming releases shared skill lease and event state")
	await Farming.new().dispose(t,game)

func spy(t,mode):
	# Ambitious identity mode needs six real players; use the existing legal
	# opening fixture rather than fabricating a five-player ambitious roster.
	var game=fixture(t,mode) if mode==GameModes.CLASSIC else Base.new().fixture(t,6,mode)
	if mode!=GameModes.CLASSIC:
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed); game.lan_enabled=false; game._spy_rules_enabled=true
		for p in game.players: p.clear_hand_silent(); p.determined_cards.clear()
		game.players[1].general_name="桑尼·斯派"; game.players[1].max_hp=4; game.players[1].hp=4; game.players[1].capture_game_start_state()
		game.turn_manager.current_player_idx=1; game.turn_manager.current_phase=TurnManager.Phase.PLAY; game.ai_pacer.speed=AiActionPacer.Speed.FAST
	var actor=game.players[1]; var action=offer(game,actor,"spy")
	t.check(not action.is_empty() and action.targets.size()==2 and action.targets[0]!=action.targets[1] and not action.targets.has(0),"AI spy offers two distinct non-lords in actual identity opening")
	var a=game.players[action.targets[0]]; var b=game.players[action.targets[1]]
	var roles=[a.identity,b.identity]; var health=game.players.map(func(p): return [p.hp,p.max_hp])
	await game._execute_ai_action(action)
	t.check(actor.spy_used and [a.identity,b.identity]==[roles[1],roles[0]] and game.players.map(func(p): return [p.hp,p.max_hp])==health,"AI uses common atomic identity exchange once without modifying health")
	await game._execute_ai_action(action)
	t.check([a.identity,b.identity]==[roles[1],roles[0]] and offer(game,actor,"spy").is_empty(),"AI cannot replay limited spy from stale or refreshed candidates")
	actor.restore_game_start_state()
	t.check(not actor.spy_used and not offer(game,actor,"spy").is_empty(),"General-card restoration restores limited spy qualification for fresh AI observation")
	await game._run_ai_play(actor)
	t.check(actor.spy_used and actor.hand_size()==0 and game.turn_manager.current_phase==TurnManager.Phase.DISCARD,"Default identity AI actually uses restored spy once and completes PLAY without hand cost")
	await Farming.new().dispose(t,game)

func identity_privacy(t):
	var game=fixture(t,GameModes.CLASSIC); var actor=game.players[1]
	game.ai_driver.rng.seed=73; var first=offer(game,actor,"spy")
	var before=game._ai_observation(actor)
	t.check(not contains_object(before) and not contains_object(first),"AI chooser receives only whitelisted values; server body epochs remain private")
	t.check(before.players.filter(func(p): return p.seat!=1 and p.seat!=0).all(func(p): return p.identity==""),"AI observation keeps third-party non-lord identities hidden")
	t.check(game.players[2].identity!=game.players[4].identity,"Privacy comparison actually permutes different hidden identity categories")
	var old=game.players[2].identity; game.players[2].identity=game.players[4].identity; game.players[4].identity=old
	game.ai_driver.rng.seed=73; var second=offer(game,actor,"spy")
	t.check(first.targets==second.targets,"Same public state and seed choose same spy pair despite hidden identity permutation")
	game._spy_rules_enabled=false; game._paipian_rules_enabled=false
	actor.append_hand_card_silent(null); game.players[0].hp=1
	t.check(offer(game,actor,"spy").is_empty() and offer(game,actor,"paipian").is_empty(),"Private gates remain authoritative for AI candidates")
	game._spy_rules_enabled=true; game.game_mode=GameModes.FREE_FOR_ALL
	t.check(offer(game,actor,"spy").is_empty(),"No AI identity skill in free-for-all")
	await Farming.new().dispose(t,game)

func stale(t,skill,fault):
	var game=fixture(t,GameModes.CLASSIC); var actor=game.players[1]
	actor.append_hand_card_silent(null); game.players[2].hp=1; game.players[3].hp=2
	var action=offer(game,actor,skill); var target=game.players[action.targets[0]]
	t.check(not action.is_empty(),"Stale AI fixture offers original skill: "+skill+"/"+fault)
	match fault:
		"restore_actor": actor.restore_game_start_state()
		"restore_target": target.restore_game_start_state()
		"phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW; game.turn_manager.current_phase=TurnManager.Phase.PLAY
		"hand": actor.append_hand_card_silent(null)
		"target_dead": target.mark_dead()
		"registry": game.unit_registry.reset()
		"gate": game._paipian_rules_enabled=false; game._spy_rules_enabled=false
		"used":
			if skill=="spy": actor.spy_used=true
			else:
				for key in action.targets: game.players[key].hp=game.players[key].max_hp
		"terrain": game._ai_terrain_snapshot=[-123]
	var hands=actor.hand_size(); var health=game.players.map(func(p): return [p.hp,p.max_hp]); var roles=game.players.map(func(p): return p.identity)
	await game._execute_ai_action(action)
	t.check(actor.hand_size()==hands and health==game.players.map(func(p): return [p.hp,p.max_hp]) and roles==game.players.map(func(p): return p.identity),"Expired original AI candidate cannot pay/heal/swap after "+fault)
	await Farming.new().dispose(t,game)

func corruption(t,mode):
	var game=fixture(t); var actor=game.players[1]; var donor=game.players[2]
	game._corruption_rules_enabled=true
	if mode=="wrestle": donor.general_name="大卫·法米尔"; donor.capture_game_start_state(); game._wrestling_choice_override=func(_p,_v): return 1
	var batch=game._draw_blank_cards(donor,2); var asked: Array=[]
	game._ai_response_override=func(view,kind,options):
		if kind not in ["corruption_activate","corruption_tie"]: return ResponsePolicy.choose(view,kind,options)
		asked.append(kind)
		t.check(view.actor==1 and options==[0] and view.response.target==2,"Corruption AI gets public legal response values, not live bodies or private cards")
		if mode=="stale": actor.restore_game_start_state()
		if mode=="dead": actor.mark_dead()
		if mode=="phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
		if mode=="ended": game._finish_game("平局","AI reaction terminal fixture")
		if mode=="reset": game.reset_game_over_state()
		if mode=="technical": return GameManager.CHOICE_INVALID
		return -1 if mode=="decline" else ResponsePolicy.choose(view,kind,options)
	game._rps_override=func(p):
		if mode=="tie": return GameManager.RPS_ROCK
		return GameManager.RPS_ROCK if (p==actor)==(mode!="lose") else GameManager.RPS_SCISSORS
	var result=await game._resolve_corruption_batch(batch)
	var invalid=mode in ["stale","technical","dead","phase","ended","reset"]; var taken=0 if invalid or mode in ["lose","decline","wrestle"] else (1 if mode=="tie" else 2)
	t.check(actor.hand_size()==taken and donor.hand_size()==2-taken,"AI corruption retains exact original drawn batch and existing outcomes: "+mode)
	t.check(result==(GameManager.CHOICE_INVALID if invalid else (0 if mode=="decline" else 1)) and actor.facedown==(mode=="lose"),"AI corruption preserves technical invalidation, decline and losing flip")
	t.check(asked==(["corruption_activate","corruption_tie"] if mode=="tie" else ["corruption_activate"]),"AI tie takes one via same response policy; no repeated RPS loop")
	if mode=="wrestle": t.check(actor.hp==3 and donor.wrestle_round==game.turn_manager.rounds.round_id,"Real David can prevent AI Greed and counter Duel before original batch continues")
	await Farming.new().dispose(t,game)

func contains_object(value):
	if typeof(value)==TYPE_OBJECT or typeof(value)==TYPE_CALLABLE: return true
	if value is Array: return value.any(func(item): return contains_object(item))
	if value is Dictionary:
		for key in value:
			if contains_object(key) or contains_object(value[key]): return true
	return false

func target_rules(t):
	var game=fixture(t,GameModes.CLASSIC); var actor=game.players[1]; var jim=game.players[4]
	jim.general_name="吉姆·芒顿"; jim.max_hp=6; jim.hp=6; jim.capture_game_start_state()
	t.check(game._spawn_mountain_at(jim,0,1)!=null and game._spawn_mountain_at(jim,3,4)!=null,"AI terrain fixture creates two actual boundary mountains")
	actor.append_hand_card_silent(null); game.players[0].hp=1; game.players[2].hp=2; game.players[3].hp=3
	var action=offer(game,actor,"paipian")
	t.check(action.get("targets",[])==[2,3],"AI filming uses same-region recipients despite more injured isolated lord")
	var spy_action=offer(game,actor,"spy")
	t.check(not spy_action.is_empty() and spy_action.targets.all(func(key): return key in [1,2,3]),"AI spy respects actual mountain regions, excludes mountains and isolated non-lord")
	action=offer(game,actor,"paipian"); await game._execute_ai_action(action)
	t.check(game.players[2].hp==3 and game.players[3].hp==4 and game.players[0].hp==1,"Actual AI shared filming heals only its legal region")
	game._corruption_rules_enabled=true; game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	var batch=game._draw_blank_cards(game.players[0],1)
	t.check(await game._resolve_corruption_batch(batch)==0 and actor.hand_size()==0 and game.players[0].hand_size()==1,"AI cannot Greed an extra draw across a real mountain partition")
	await Farming.new().dispose(t,game)
	game=fixture(t); actor=game.players[1]; var owner=game.players[3]
	owner.general_name="克里斯·西弗"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	var dragon=load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,owner); var id=game.unit_registry.id_for(dragon)
	dragon.hp=1; actor.append_hand_card_silent(null)
	t.check(offer(game,actor,"paipian").is_empty(),"AI cannot choose a still-hidden injured dragon, and avoids all-full visible pairs")
	var shown: Array[Player]=[actor]
	game.fire_dragon_state.record_use(id,1,shown) # Established historical direct-USE prefix; Q52 actual entry was tested in 5b.
	game._card_action_serial=1
	action=offer(game,actor,"paipian")
	t.check(str(action.targets[0])==id and typeof(action.targets[1])==TYPE_INT and action.targets[1]!=1,"AI can pair an injured visible unit with a legal full-health other target")
	await game._execute_ai_action(action)
	t.check(dragon.hp==2 and actor.hand_size()==0 and owner.hp==3,"Actual AI healing affects visible dragon itself, not controller")
	await Farming.new().dispose(t,game)

func yudaxi(t):
	var game=fixture(t); var actor=game.players[1]; var leo=game.players[0]; var donor=game.players[2]
	game._corruption_rules_enabled=true
	leo.general_name="里奥·普利威尔"; leo.max_hp=GeneralData.get_max_hp(leo.general_name,5); leo.hp=0
	donor.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); donor.sage_activated=true; donor.hp=1
	game.players[3].hp=1; game.players[4].hp=1
	game._sage_save_override=func(): return true
	var choices: Array=[]
	game._ai_response_override=func(view,kind,options):
		if kind=="corruption_activate":
			choices.append(kind)
			t.check(game.yudaxi.is_active() and view.response.count==4 and view.response.target==2 and game.players[3].hp==1,"Real AI Greed enters Sage's four cards inside Yudaxi before later deductions")
		return ResponsePolicy.choose(view,kind,options)
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	t.check(await game._resolve_dying(leo,null,"sunny_ai_yudaxi")==0,"Actual rule parent resumes after complete AI Greed")
	t.check(choices==["corruption_activate"] and actor.hand_size()==4 and donor.hand_size()==0,"AI takes exact Sage batch once; Leo's own success reward remains exempt")
	t.check(game.players[3].is_dead() and game.players[4].is_dead() and leo.hp==2 and leo.hand_size()==2,"Yudaxi death count and success draw reflect completed immediate AI reaction")
	t.check(not game.yudaxi.is_active() and game._dying_contexts.is_empty() and game._pending_card_actions.is_empty(),"Nested AI reaction leaves no rule, rescue or card lease dangling")
	await Farming.new().dispose(t,game)

func paced(t):
	var game=fixture(t); var actor=game.players[1]
	actor.append_hand_card_silent(null); game.players[0].hp=1; game.players[2].hp=2
	game.ai_pacer.speed=AiActionPacer.Speed.STANDARD
	var calls: Array=[]
	game.ai_driver.chooser=func(_v,options):
		for i in options.size():
			if options[i].get("skill","")=="paipian": return i
		return -1
	game.ai_pacer.wait_override=func(seconds):
		calls.append(seconds)
		if calls.size()==1: actor.restore_game_start_state()
		await t.process_frame
	await game._run_ai_play(actor)
	t.check(calls==[0.6] and actor.hand_size()==1 and game.players[0].hp==1 and game.players[2].hp==2,"AI presentation wait revalidates restored Sunny before charging original skill")
	t.check(game.turn_manager.current_phase==TurnManager.Phase.PLAY and game._paipian_pending.is_empty(),"Invalid old Sunny turn cannot advance restored body's phase")
	for i in 7: await t.process_frame
	t.check(calls==[0.6,0.6] and actor.hand_size()==0 and game.players[0].hp==2 and game.players[2].hp==3,"Fresh AI frame reobserves after restore, waits normal pace and pays exactly one new skill")
	t.check(game.turn_manager.current_phase==TurnManager.Phase.DISCARD and game._ai_running_revisions.is_empty(),"Restored AI completes PLAY without a stalled lease")
	await Farming.new().dispose(t,game)

func sage_turn(t):
	var game=fixture(t); var actor=game.players[1]; var target=game.players[2]
	game._paipian_rules_enabled=false
	var duel=CardBase.create(CardData.CardSubType.DUEL); actor.determined_cards.append(duel)
	actor.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); actor.sage_activated=true; actor.hp=1
	target.append_hand_card_silent(null)
	var revision=actor.awakening_revision; var facts: Array=[]
	game.card_action_committed.connect(func(e): facts.append(e))
	game._duel_respond_override=func(): return true
	game._sage_save_override=func(): return true
	game.ai_driver.chooser=func(_v,options):
		if actor.awakening_revision!=revision: return -1
		for i in options.size():
			if options[i].sub==CardData.CardSubType.DUEL and options[i].target==2: return i
		return -1
	await game._run_ai_play(actor)
	for i in 5: await t.process_frame
	t.check(actor.awakening_revision==revision+1 and actor.hp==4 and actor.hand_size()==4 and actor.get_armor()==-1,"Actual AI Duel loss restores Sunny through Sage with exact four new cards")
	t.check(facts.size()==2 and facts.all(func(e): return e.settlement_completed) and game.deck._discard.count(duel)==1,"Actual Sage keeps paid original Duel/response and completion once")
	t.check(game.turn_manager.current_phase==TurnManager.Phase.DISCARD and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"Fresh AI frame finishes restored same turn after actual rescue/Sage parent")
	await Farming.new().dispose(t,game)

func human_response(t):
	var game=fixture(t); var actor=game.players[1]; var peter=game.players[0]
	peter.general_name=load("res://Test/i05_peter_peach_cases.gd").PETER; peter.hp=1; game.players[2].hp=2
	actor.append_hand_card_silent(null)
	var bridge=LanGameBridge.new(); t.root.add_child(bridge); bridge.game=game
	var done: Array=[]
	var run=func(): await game._execute_ai_action(offer(game,actor,"paipian")); done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var token=Sage.new().token(bridge,0,"免除此效果")
	t.check(not token.is_empty() and done.is_empty() and actor.hand_size()==0,"Human Peter sees real shared immunity after AI filming's committed fee")
	t.check(not bridge.submit(1,token) and bridge.submit(0,token),"AI effect does not bypass human controller's opaque response authority")
	for i in 4: await t.process_frame
	t.check(done==[true] and peter.hp==1 and game.players[2].hp==3 and not bridge.submit(0,token),"AI filming honors human immunity, still heals other target once and rejects old response")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
