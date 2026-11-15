extends RefCounted
const Ai=preload("res://Test/i05_sunny_ai_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["replace","pick_invalid","prep_invalid","empty","good","anti_good","field_invalid","source_dead"]:
		for concrete in [false,true]: await combination(t,mode,concrete)
	for close in [false,true]: await bridge_case(t,close)
	await terminal(t)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func setup(t,mode,concrete):
	var game=Ai.new().fixture(t); game._corruption_rules_enabled=true
	var fields=mode in ["empty","good","anti_good","field_invalid","bridge"]
	var david=game.players[0 if fields else 2]; var leo=game.players[2 if fields else 0]; var sunny=game.players[1]
	david.general_name="大卫·法米尔"; david.max_hp=4; david.hp=4; david.capture_game_start_state(); david.hp=2
	leo.general_name="里奥·普利威尔"; leo.max_hp=GeneralData.get_max_hp(leo.general_name,5); leo.hp=leo.max_hp; leo.capture_game_start_state(); leo.prep_tokens=1
	if fields:
		david.farm_empty_fields=1 if mode=="empty" else 0
		david.farm_good_fields=0 if mode=="empty" else 1
	if mode=="anti_good": leo.determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
	var old=CardBase.create(CardData.CardSubType.DODGE) if concrete else null
	if concrete: sunny.determined_cards.append(old)
	else: sunny.append_hand_card_silent(null)
	if mode=="source_dead": sunny.hp=1
	game.players[3].append_hand_card_silent(null)
	game.turn_manager.current_player_idx=3; game._set_input_player(game.players[3])
	game._wrestling_choice_override=func(_p,_v): return 1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._prep_replace_override=func(_leo,user,_target,sub,options):
		if user!=david or sub!=CardData.CardSubType.DUEL: return -1
		if mode=="prep_invalid": return GameManager.CHOICE_INVALID
		if mode=="source_dead": return -1
		t.check(options.has(CardData.CardSubType.DISMANTLE),"Actual virtual Wrestle Duel offers legal fixed-target Dismantle replacement")
		return CardData.CardSubType.DISMANTLE
	game._prep_steal_pick_override=func(_choices): return GameManager.CHOICE_INVALID if mode=="pick_invalid" else 0
	return {"game":game,"david":david,"leo":leo,"sunny":sunny,"old":old}

func combination(t,mode,concrete):
	var f=setup(t,mode,concrete); var game=f.game; var david=f.david; var leo=f.leo; var sunny=f.sunny
	var events: Array=[]; var done: Array=[]; var fields: Array=[]; var ai: Array=[]
	game.card_action_committed.connect(func(e): events.append(e))
	game.card_action_completed.connect(func(e): done.append(e))
	game._ai_response_override=func(view,kind,options):
		if kind=="corruption_activate":
			ai.append(view.response.target)
			t.check(events.size()==1 and done.is_empty() and view.response.target==david.seat_index and david.hand_size()==2,"Actual Harvest is pending with exact new David batch before AI Greed")
		if kind=="nullification" and mode=="anti_good" and view.actor==leo.seat_index and events.size()>=3 and leo.hand_size()>0: return CardData.CardSubType.NULLIFICATION
		if kind=="basic" and mode=="source_dead" and view.actor==sunny.seat_index: return -1 # Explicitly decline Duel response, rather than the default AI Kill.
		return ResponsePolicy.choose(view,kind,options)
	game._farming_nullification_override=func(_p,options,valid):
		if events.size()<2: return "skip" # Do not cancel the original Harvest.
		fields.append(true)
		t.check(valid.call() and david.hand_size()==2 and leo.prep_tokens==0,"Field counter sees committed prevention and paid PREP before original batch resumes")
		if mode=="field_invalid": return "invalidated"
		var choice="field_empty" if mode=="empty" else "field_good"
		t.check(options.has(choice),"Field Nullification uses actual existing legal field resource")
		return choice
	await game.play_card(CardData.CardSubType.HARVEST)
	var invalid=mode in ["pick_invalid","prep_invalid","field_invalid"]
	var canceled=mode in ["empty","good"]
	t.check(ai==[david.seat_index] and david.hand_size()==2 and david.wrestle_round==game.turn_manager.rounds.round_id,"Committed Wrestle retains original new cards and round use after nested counter: "+mode)
	t.check(sunny.hand_size()==(1 if invalid or canceled else 0),"Counter moves only Sunny's old card; no retroactive Greed theft: "+mode)
	t.check(events.size()==(4 if mode=="anti_good" else (3 if canceled else 2)) and done.size()==(0 if invalid else events.size()),"Original Harvest and virtual/effective response complete once or abandon technically: "+mode)
	t.check(events[0].sub_type==CardData.CardSubType.HARVEST and not events[0].is_virtual and game.deck._discard.count(events[0].card)==1,"Paid original Harvest keeps its original physical identity exactly once")
	t.check(events[1].sub_type==CardData.CardSubType.DUEL and events[1].is_virtual and not events[1].from_hand and not game.deck._discard.has(events[1].card),"Effective Dismantle preserves original virtual Duel event; no phantom physical fee")
	t.check(leo.prep_tokens==(1 if mode in ["prep_invalid","source_dead"] else 0),"PREP cost commits only at actual replacement and is never refunded")
	t.check(david.hp==(3 if mode in ["good","anti_good"] else 2),"Good-field healing is immediate and survives an actual later anti-Nullification")
	if mode in ["empty","good","anti_good"]:
		t.check(fields.size()==1 and david.farm_empty_fields==0 and david.farm_good_fields==0 and david.farm_hand_actions==0,"Field payment and virtual counter do not create hand-use farming recursion")
	if mode=="source_dead": t.check(sunny.is_dead() and events.all(func(e): return e.settlement_completed),"Normal death of Greed user during counter still permits original Harvest to finish")
	if concrete: t.check(game.deck._discard.count(f.old)==(0 if invalid or canceled else 1),"Concrete old Sunny card has exact one original destination")
	t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(),"Nested PREP/counter/field path releases every owned action and reaction lease")
	t.check(game._input_seat==0 and game._play_actor()==game.players[3] and game.turn_manager.current_phase==TurnManager.Phase.PLAY,"Native human retains its input while original AI turn actor and PLAY remain unchanged")
	await Farming.new().dispose(t,game)

func bridge_case(t,close):
	var f=setup(t,"bridge",true); var game=f.game; var david=f.david; var sunny=f.sunny
	var bridge=LanGameBridge.new(); t.root.add_child(bridge); bridge.game=game
	var events: Array=[]; var done: Array=[]
	game.card_action_committed.connect(func(e): events.append(e))
	game._farming_nullification_override=Callable(); game._nullify_override=Callable()
	var run=func(): await game.play_card(CardData.CardSubType.HARVEST); done.append(true)
	run.call_deferred()
	# Harvest asks per recipient, including full-health recipients. Decline
	# those actual root windows until the virtual counter has been declared.
	for step in 8:
		for i in 3: await t.process_frame
		if events.size()>=2: break
		var skip=Sage.new().token(bridge,0,"取消")
		if skip.is_empty(): skip=Sage.new().token(bridge,0,"放弃")
		if not skip.is_empty(): t.check(bridge.submit(0,skip),"Human explicitly declines actual root Harvest Nullification")
	var command=""
	for control in bridge.snapshot(0).controls:
		if control.text.contains("好田当无懈"): command=control.id; break
	t.check(not command.is_empty() and done.is_empty() and david.hand_size()==2 and sunny.hand_size()==1 and david.hp==2,"Human field window holds real AI Greed/Harvest after PREP, before good-field payment")
	t.check(not bridge.submit(1,command),"AI Greed actor cannot answer human David's field window")
	if close:
		game._choice_prompt_stack.back().overlay.queue_free()
	else: t.check(bridge.submit(0,command),"Human David pays actual good field through current opaque command")
	for step in 8:
		for i in 3: await t.process_frame
		if not done.is_empty(): break
		var skip=Sage.new().token(bridge,0,"放弃")
		if skip.is_empty(): skip=Sage.new().token(bridge,0,"取消")
		if not skip.is_empty(): t.check(bridge.submit(0,skip),"Human declines remaining counter/root windows without paying another card")
	t.check(done==[true] and sunny.hand_size()==1 and david.hand_size()==2 and david.hp==(2 if close else 3),"Human field closure/counter preserves committed prevention and exact healing")
	t.check(events.size()==(2 if close else 3) and events.all(func(e): return e.settlement_completed==not close),"Technical closed field cannot complete old parent; real counter completes all events")
	t.check(game._input_seat==0 and game._play_actor()==game.players[3] and not bridge.submit(0,command) and game._pending_card_actions.is_empty(),"Native human input and original actor are distinct; old field command cannot replay")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame

func terminal(t):
	var game=Ai.new().fixture(t); var david=game.players[0]; var sunny=game.players[1]
	david.general_name="大卫·法米尔"; david.max_hp=4; david.hp=4; david.capture_game_start_state(); david.hp=2
	sunny.hp=1
	for seat in [2,3,4]: game.players[seat].mark_dead()
	david.append_hand_card_silent(null)
	game.turn_manager.current_player_idx=0; game._set_input_player(david)
	game._corruption_rules_enabled=true; game._wrestling_choice_override=func(_p,_v): return 1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._ai_response_override=func(view,kind,options): return -1 if kind=="basic" else ResponsePolicy.choose(view,kind,options)
	var events: Array=[]; game.card_action_committed.connect(func(e): events.append(e))
	await game.play_card(CardData.CardSubType.HARVEST)
	t.check(game._game_over and david.is_alive() and sunny.is_dead(),"Counter victory is a normal FFA terminal outcome, not a technical selection failure")
	t.check(david.hand_size()==2 and sunny.hand_size()==0 and david.wrestle_round==game.turn_manager.rounds.round_id,"Terminal prevention keeps the original two cards and never draws for later dead Sunny")
	t.check(events.size()==2 and events[0].sub_type==CardData.CardSubType.HARVEST and events[1].is_virtual,"Terminal counter retains original parent/virtual event identity without extra hand uses")
	t.check(game.deck._discard.count(events[0].card)==1 and not game.deck._discard.has(events[1].card),"Normal victory never refunds or duplicates committed original physical cost")
	t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(),"Terminal rule result releases parent and counter receipts without reviving old actions")
	await Farming.new().dispose(t,game)
