extends RefCounted
const Base=preload("res://Test/i05_extra_draw_batch_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const SUNNY="桑尼·斯派"

func fixture(t):
	var game=Base.new().fixture(t)
	game._corruption_rules_enabled=true
	game._extra_draw_receipts_enabled=false # Real private capability itself captures the batch.
	game._wrestling_choice_override=func(_p,_v): return 0
	game.players[2].general_name=SUNNY
	game.players[2].hp=4
	var donor=game.players[1]
	donor.general_name="大卫·法米尔"; donor.hp=4; donor.max_hp=4; donor.capture_game_start_state(); donor.hp=0
	donor.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); donor.sage_activated=true
	return game

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["decline","win","lose","tie_take","tie_timeout","tie_retry","wrestle","stale"]: await branches(t,mode)
	for win in [false,true]: await during_yudaxi(t,win)
	await gate(t)
	for seat in [0,1]:
		for cancel in [false,true]: await bridge_case(t,seat,cancel)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func branches(t,mode):
	var game=fixture(t)
	var donor=game.players[1]; var actor=game.players[2]
	actor.facedown=mode=="lose"
	var asks: Array=[]; var punches: Array=[]
	game._corruption_choice_override=func(p,batch,stage,valid):
		asks.append(stage)
		t.check(p==actor and batch.owner==donor and donor.hand_size()==4 and valid.call(),"I05c Sage draw enters original hand before each Corruption choice: "+mode)
		await t.process_frame
		if mode=="stale": actor.restore_game_start_state()
		if stage=="activate": return -1 if mode=="decline" else 0
		return 1 if mode=="tie_retry" else (-1 if mode=="tie_timeout" else 0)
	game._rps_override=func(p):
		punches.append(p)
		if mode=="lose": return GameManager.RPS_SCISSORS if p==actor else GameManager.RPS_ROCK
		if mode.begins_with("tie") and punches.size()<=2: return GameManager.RPS_ROCK
		return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	if mode=="wrestle": game._wrestling_choice_override=func(_p,_v): return 1
	var result=await game._do_sage_save(donor)
	var expected=4 if mode in ["decline","lose","wrestle","stale"] else (3 if mode in ["tie_take","tie_timeout"] else 0)
	t.check(donor.hp==4 and donor.hand_size()==expected and actor.hand_size()==4-expected,"I05c complete Sage reaction preserves exact original resources: "+mode)
	t.check(asks.count("activate")==1 and punches.size()==(0 if mode in ["decline","stale"] else (4 if mode=="tie_retry" else 2)),"I05c activation and each individual RPS happen once; tie is explicit: "+mode)
	t.check(result==(GameManager.CHOICE_INVALID if mode=="stale" else (0 if mode=="decline" else 1)),"I05c technical invalidation is distinct from decline and committed reaction: "+mode)
	if mode=="lose": t.check(not actor.facedown,"I05c losing Corruption toggles facedown Sunny back to face-up")
	if mode=="wrestle": t.check(actor.hp==3 and donor.wrestle_round==game.turn_manager.rounds.round_id,"I05c real David prevention retains Sage cards and completes extra Duel before returning")
	var before=[donor.hand_size(),actor.hand_size(),asks.size()]
	await game._resolve_corruption_batch(game._draw_batches[0])
	t.check(before==[donor.hand_size(),actor.hand_size(),asks.size()] and game._pending_card_actions.is_empty(),"I05c same batch cannot reopen after a decline, result or stale answer: "+mode)
	await Farming.new().dispose(t,game)

func during_yudaxi(t,win):
	var game=fixture(t)
	var root=game.players[0]; var donor=game.players[1]; var actor=game.players[2]
	root.general_name="里奥·普利威尔"; root.max_hp=5; root.hp=0
	donor.hp=1
	game.players[3].hp=1; game.players[4].hp=1
	game.turn_manager.current_player_idx=4
	game._sage_save_override=func(): return true
	var seen: Array=[]
	game._corruption_choice_override=func(_p,batch,stage,valid):
		seen.append(stage)
		t.check(batch.during_yudaxi and game.yudaxi.is_active() and donor.hand_size()==4 and root.hp==0 and game.players[3].hp==1 and game.players[4].hp==1 and valid.call(),"I05c Q10 Corruption is inside active rule, before any later victim can request Sage cards")
		await t.process_frame
		t.check(game.players[3].hp==1 and game.players[4].hp==1,"I05c suspended choice really holds the entire Yudaxi parent cursor")
		return 0 if win else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	game._rescue_choice_override=func(rescuer,dying,options):
		return CardData.CardSubType.PEACH if rescuer==donor and dying in [game.players[3],game.players[4]] and options.has(CardData.CardSubType.PEACH) else -1
	t.check(await game._resolve_dying(root,null,"sage_immediate_corruption")==0,"I05c Q10 actual death/rescue/rule parent returns normally")
	t.check(donor.hand_size()==0 and actor.hand_size()==(4 if win else 0),"I05c Q10 winner takes four before rescues; a declined batch can instead be paid as Peaches")
	t.check((game.players[3].is_dead() and game.players[4].is_dead()) if win else (game.players[3].hp==1 and game.players[4].hp==1),"I05c Q10 later victims reflect already completed immediate Corruption, never deferred stealing")
	t.check(root.hp==(2 if win else 0) and (root.is_alive() if win else root.is_dead()),"I05c original Leo X uses the actual subsequent deaths after the reaction")
	t.check(seen==["activate"] and not game.yudaxi.is_active() and game._dying_contexts.is_empty(),"I05c no second Corruption prompt at rule end; all death contexts finish")
	await Farming.new().dispose(t,game)

func gate(t):
	var game=fixture(t); var donor=game.players[1]
	game._corruption_rules_enabled=false
	game._corruption_choice_override=func(_p,_b,_s,_v):
		t.check(false,"I05c disabled private capability must never ask Corruption")
		return 0
	await game._do_sage_save(donor)
	t.check(donor.hand_size()==4 and game._draw_batches.is_empty(),"I05c legacy Sage remains synchronous-in-effect without private capability or receipt allocation")
	await Farming.new().dispose(t,game)

func token(bridge,seat,text):
	for control in bridge.snapshot(seat).controls:
		if control.text==text: return control.id
	return ""

func bridge_case(t,seat,cancel):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c Sage Corruption Bridge fixture starts normally")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	var actor=game.players[seat]; actor.general_name=SUNNY
	var donor=game.players[2]; donor.hp=donor.max_hp; donor.capture_game_start_state(); donor.hp=0
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear()
	var done: Array=[]
	var run=func(): done.append(await game._do_sage_save(donor))
	run.call_deferred()
	for i in 2: await t.process_frame
	var activate=token(bridge,seat,"取消" if cancel else "发动")
	t.check(not activate.is_empty() and done.is_empty() and donor.hand_size()==4,"I05c host/remote sees actual activation window after original draw, with parent suspended")
	t.check(not bridge.submit(1-seat,activate) and bridge.submit(seat,activate) and not bridge.submit(seat,activate),"I05c only active Sunny may answer; wrong-seat and replay tokens are rejected")
	if not cancel:
		for i in 2: await t.process_frame
		var rock=token(bridge,seat,"石头")
		t.check(not rock.is_empty() and bridge.submit(seat,rock),"I05c host/remote Sunny can answer actual RPS window")
		for i in 2: await t.process_frame
		var scissors=token(bridge,2,"剪刀")
		t.check(not scissors.is_empty() and not bridge.submit(seat,scissors) and bridge.submit(2,scissors),"I05c original recipient owns the second RPS, not Sunny's remote seat")
	for i in 3: await t.process_frame
	t.check(done==[0 if cancel else 1] and donor.hand_size()==(4 if cancel else 0) and actor.hand_size()==(0 if cancel else 4),"I05c host/remote completion resumes Sage exactly once with original batch moved or retained")
	t.check(not bridge.submit(seat,activate) and game._choice_prompt_stack.is_empty(),"I05c completed reaction leaves no actionable old token or choice frame")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
