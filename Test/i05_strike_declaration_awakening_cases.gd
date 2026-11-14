extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for path in ["single","borrowed","multi"]:
		for concrete in [false,true]: await nested(t,path,concrete)
	await shensu_boundary(t,Cards.new().fixture(t))
	for path in ["single","borrowed","shensu","multi","raw"]: await prior(t,path)
	await restrictions(t)
	for seat in [0,1]: await bridge_case(t,seat)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func nested(t,path,concrete):
	var game=Cards.new().fixture(t); var source=game.players[0]; var david=source; var target=game.players[1]; var sunny=game.players[4]
	if path=="multi":
		david=game.players[1]; target=game.players[2]
		source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
		source.equip_card_to_slot("mount_1",CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		david.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); david.sage_activated=true; david.hp=1
	else:
		source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	david.general_name="大卫·法米尔"; david.max_hp=4; david.capture_game_start_state()
	target.general_name="史蒂芬·彼特先斯"; target.max_hp=3; target.hp=3; target.capture_game_start_state()
	var flash=CardBase.create(CardData.CardSubType.NULLIFICATION) if concrete else null
	if concrete: target.determined_cards.append(flash)
	else: target.append_hand_card_silent(null)
	var original=CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
	if concrete: source.determined_cards.append(original)
	else: source.append_hand_card_silent(null)
	game._wrestling_choice_override=func(_p,_v): return 1
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	game._sacrifice_actor_override=func(_p,_v,_a): return false
	game._sage_save_override=func(): return true
	var counters: Array=[]; var batches: Array=[]; var used: Array=[]; var completed: Array=[]
	game.card_action_committed.connect(func(e): used.append(e))
	game.card_action_completed.connect(func(e): completed.append(e))
	game._nullify_override=func():
		if game._input_seat==target.seat_index and counters.is_empty(): counters.append(true); return true
		return false
	game._corruption_choice_override=func(_p,batch,_s,valid):
		batches.append(batch.owner)
		t.check(valid.call() and not used[0].settlement_completed,"Original designated Kill remains pending through real draw/Greed/Wrestle nesting: "+path)
		return 0 if batch.owner==david else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func():
		t.check(not used[0].settlement_completed and target.hp==2,"Target gains Kill immunity before original Kill resumes: "+path)
		return 1
	if path=="multi":
		var targets: Array[Player]=[david,target]
		await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
	elif path=="borrowed":
		t.check(await game._resolve_borrowed_strike(source,[target],CardData.CardSubType.STRIKE,func(): return true)!=GameManager.CHOICE_INVALID,"Borrowed original Kill continuation remains current")
	else: await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
	t.check(batches==[david,target] and counters.size()==1 and target.awake_choice==1,"Unique generals produce actual nested awakening, not a fabricated late status: "+path)
	t.check(target.hp==1 and target.max_hp==2 and target.hand_size()==2,"Q13/Q14 declared Kill still deals exactly one after later immunity: "+path)
	t.check(not game._get_strike_targets(source).has(target),"A later new Kill must still reject newly immune target: "+path)
	t.check(used.size()==3 and completed.size()==3 and game._pending_card_actions.is_empty(),"Original Kill, counter Duel and last Nullification complete once: "+path)
	t.check(used.all(func(e): return e.is_virtual or game.deck._discard.count(e.card)==1),"Nested declaration preserves original physical costs exactly once: "+path)
	if concrete: t.check(used[0].card==original and game.deck._discard.count(flash)==1,"Concrete Kill/Nullification identities survive actual nested flow")
	t.check(game.turn_manager.strikes_used()==(0 if path=="borrowed" else 1),"Borrowed Kill remains quota-free; ordinary/multiple-target Kill consumes once")
	await Farming.new().dispose(t,game)

func restrictions(t):
	for kind in ["armor","bare","kneeling"]:
		var game=Cards.new().fixture(t); var source=game.players[0]; var target=game.players[1]
		target.general_name="凯文·罗本" if kind=="bare" else "史蒂芬·彼特先斯"
		if kind=="armor": target.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.TENGJIA))
		if kind=="kneeling": target.general_name="布鲁斯·萨维奇"; target.hp=1; target.kneeling=true
		var hp=target.hp; var declared: Array[Player]=[target]
		var hit=await game._execute_single_strike(source,target,CardBase.create(CardData.CardSubType.STRIKE),CardData.CardSubType.STRIKE,EffectChain.DamageType.PHYSICAL,1,false,declared,true)
		t.check(not hit and target.hp==hp,"Bound awakening qualification never bypasses other target restrictions: "+kind)
		if kind!="kneeling": t.check(not await game._prepare_strike_target(source,target,false,[],true),"Preparation still checks armor/bare restrictions independently of awakening binding")
		await Farming.new().dispose(t,game)

func bridge_case(t,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"Declared Kill host/remote Bridge starts")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var source=game.players[(seat+4)%5]; var david=game.players[(seat+3)%5]; var sunny=game.players[(seat+2)%5]; var target=game.players[seat]
	game.turn_manager.current_player_idx=source.seat_index; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD)); source.append_hand_card_silent(null)
	david.general_name="大卫·法米尔"; david.max_hp=4; david.hp=1; david.capture_game_start_state()
	david.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); david.sage_activated=true
	target.general_name="史蒂芬·彼特先斯"; target.max_hp=3; target.hp=3; target.capture_game_start_state(); target.append_hand_card_silent(null)
	sunny.general_name=Cards.SUNNY; sunny.capture_game_start_state()
	game._set_input_player(source)
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	game._sacrifice_actor_override=func(_p,_v,_a): return false
	game._sage_save_override=func(): return true
	game._wrestling_choice_override=func(_p,_v): return 1
	game._rescue_choice_override=func(_p,_v,_o): return -1
	var counters: Array=[]; var done: Array=[]; var events: Array=[]
	game.card_action_committed.connect(func(e): events.append(e))
	game._nullify_override=func():
		if game._input_seat==seat and counters.is_empty(): counters.append(true); return true
		return false
	game._corruption_choice_override=func(_p,batch,_s,_valid): return 0 if batch.owner==david else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	var run=func():
		var targets: Array[Player]=[david,target]
		await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
		done.append(true)
	run.call_deferred()
	for i in 5: await t.process_frame
	var choice=Sage.new().token(bridge,seat,"不能成为【杀】的目标")
	t.check(not choice.is_empty() and done.is_empty() and target.hp==2 and events.size()==3,"Actual host/remote mandatory immunity holds the already-paid multi Kill and nested counter")
	t.check(not bridge.submit(1-seat,choice) and bridge.submit(seat,choice),"Bound declaration immunity accepts current owner only")
	for i in 5: await t.process_frame
	t.check(done==[true] and target.hp==1 and target.awake_choice==1 and target.hand_size()==2,"Actual host/remote original multi Kill hits once after later immunity choice")
	t.check(events.all(func(e): return e.settlement_completed) and game._pending_card_actions.is_empty(),"Bridge nested card events finish exactly once")
	t.check(bridge.input_owner()==source.seat_index and not bridge.submit(seat,choice),"Declared Kill restores original acting controller and rejects stale choice")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame

func shensu_boundary(t,game):
	var source=game.players[0]; var target=game.players[1]
	source.general_name="比尔·盖伊"
	source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
	target.general_name="史蒂芬·彼特先斯"; target.max_hp=3; target.hp=3; target.capture_game_start_state()
	var events: Array=[]; game.card_action_committed.connect(func(e): events.append(e))
	# Explicit await-boundary injection: do not claim this is a natural
	# Bill/David combination. Natural nesting is exercised by the other paths.
	game._corruption_choice_override=func(_p,batch,_s,_valid):
		t.check(batch.owner==source and not events[0].settlement_completed,"Shensu holds its declared target while Qinglong reaction waits")
		target.awoken=true; target.awaken_effects_applied=true; target.awake_choice=1; target.max_hp=2; target.hp=2
		await t.process_frame
		return -1
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	await game._execute_shensu_strike(source,target)
	t.check(target.hp==1 and game.turn_manager.strikes_used()==0 and source.hand_size()==1,"Shensu retains original target qualification and one Qinglong reward without ordinary quota")
	t.check(events.size()==1 and events[0].is_virtual and events[0].settlement_completed and game._pending_card_actions.is_empty(),"Shensu virtual event completes once after bounded reaction")
	await Farming.new().dispose(t,game)

func prior(t,path):
	var game=Cards.new().fixture(t); var source=game.players[0]; var target=game.players[1]
	target.general_name="史蒂芬·彼特先斯"; target.max_hp=2; target.hp=2
	target.awoken=true; target.awaken_effects_applied=true; target.awake_choice=1
	source.append_hand_card_silent(null); source.wine_stacks=1
	if path=="multi": source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
	if path=="shensu": source.general_name="比尔·盖伊"
	var events: Array=[]; game.card_action_committed.connect(func(e): events.append(e))
	match path:
		"single": await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
		"multi":
			var targets: Array[Player]=[target,game.players[4]]
			await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
		"borrowed": await game._resolve_borrowed_strike(source,[target],CardData.CardSubType.STRIKE,func(): return true)
		"shensu": await game._execute_shensu_strike(source,target)
		"raw": await game._execute_single_strike(source,target,CardBase.create(CardData.CardSubType.STRIKE),CardData.CardSubType.STRIKE,EffectChain.DamageType.PHYSICAL,1)
	t.check(target.hp==2 and events.is_empty(),"Existing immunity rejects new or low-level forged designation: "+path)
	t.check(source.hand_size()==1 and source.wine_stacks==1 and game.turn_manager.strikes_used()==0,"Rejected declaration cannot pay hand/wine/quota: "+path)
	await Farming.new().dispose(t,game)
