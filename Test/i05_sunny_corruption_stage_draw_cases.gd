extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["win","decline","tie","stale","reset","duplicate"]: await awakening(t,mode)
	for stale in [false,true]: await medicine(t,stale)
	await nested_awakening(t)
	for phase in [0,1,2]:
		for mode in ["win","decline","stale"]: await granted(t,phase,mode)
	for seat in [0,1]:
		await bridge_case(t,seat,false)
		await bridge_case(t,seat,true)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func awakening(t,mode):
	var game=Cards.new().fixture(t); var owner=game.players[1]; var sunny=game.players[4]
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state(); owner.awoken=true
	game.turn_manager.current_phase=TurnManager.Phase.DRAW # Another character's DRAW, not owner's normal draw.
	var seen: Array=[]; var chosen: Array=[]; var results: Array=[]
	game._corruption_choice_override=func(_p,batch,stage,valid):
		if stage=="tie": return 0
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and owner.max_hp==2 and owner.hand_size()==2 and owner.awake_choice==0 and chosen.is_empty(),"I05c entered awakening draws before Corruption and before mandatory immunity choice")
		await t.process_frame
		t.check(results.is_empty() and game.turn_manager.current_phase==TurnManager.Phase.DRAW,"I05c awakening and joined parent wait for this exact reward reaction")
		if mode=="stale": sunny.restore_game_start_state()
		if mode=="reset": game.reset_game_over_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny or mode=="tie" else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func():
		chosen.append(true)
		t.check(owner.hand_size()==(2 if mode=="decline" else (1 if mode=="tie" else 0)),"I05c immunity is chosen only after this awakening draw has moved or remained")
		return 1
	if mode=="duplicate":
		var run=func(): results.append(await game._do_awaken(owner))
		run.call_deferred(); run.call_deferred()
		for i in 8: await t.process_frame
	else: results.append(await game._do_awaken(owner))
	var invalid=mode in ["stale","reset"]
	t.check(results==([0,0] if mode=="duplicate" else [GameManager.CHOICE_INVALID if invalid else 0]),"I05c one or joined awakening parents receive explicit completed/invalid result")
	t.check(seen.size()==1 and chosen.size()==(0 if invalid else 1) and owner.max_hp==2 and owner.awaken_effects_applied,"I05c awakening applies upper-limit cost and reward only once, even across joined callers")
	t.check(owner.awake_choice==(0 if invalid else 1) and not game._awaken_in_progress.has(owner),"I05c completed/invalid awakening releases only its own lease and never guesses immunity")
	await Farming.new().dispose(t,game)

func medicine(t,stale):
	var game=Cards.new().fixture(t); var chris=game.players[0]; var owner=game.players[1]; var later=game.players[2]; var sunny=game.players[4]
	chris.general_name="克里斯·西弗"; owner.general_name="史蒂芬·彼特先斯"
	owner.max_hp=3; owner.hp=3; owner.capture_game_start_state(); owner.append_hand_card_silent(null); later.append_hand_card_silent(null)
	game.turn_manager.current_phase=TurnManager.Phase.DRAW
	game._medicine_choice_override=func(_p,_choices): return [owner,later]
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		t.check(valid.call() and batch.owner==owner and chris.hand_size()==1 and later.hand_size()==1,"I05c actual steal-medicine parent waits for forced awakening before taking second target")
		await t.process_frame
		if stale: sunny.restore_game_start_state()
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func(): return 1
	var result=await game._maybe_steal_medicine(chris)
	t.check(result==(GameManager.CHOICE_INVALID if stale else 1) and chris.hand_size()==(1 if stale else 2) and later.hand_size()==(1 if stale else 0),"I05c medicine resumes next recipient only after valid awakening+Corruption completion")
	t.check(owner.awake_choice==(0 if stale else 1) and sunny.hand_size()==(0 if stale else 2) and game._medicine_pending.is_empty(),"I05c forced awakening draw is EXTRA in another actor's DRAW without a phantom card action")
	t.check(game._card_action_serial==0,"I05c medicine and its awakening/Corruption transfer do not manufacture hand USE")
	await Farming.new().dispose(t,game)

func nested_awakening(t):
	var game=Cards.new().fixture(t); var owner=game.players[1]; var sunny=game.players[4]
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state(); owner.hp=0
	owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); owner.sage_activated=true
	game._sage_save_override=func(): return true
	var seen: Array=[]
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and batch.count==(4 if seen.size()==1 else 2),"I05c actual Sage restoration and its later forced awakening create distinct draw batches")
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func(): return 1
	t.check(await game._resolve_dying(owner,null,"sage_then_awaken_corruption")==0,"I05c actual Sage parent waits for both nested draw reactions and mandatory awakening")
	t.check(seen.size()==2 and sunny.hand_size()==6 and owner.hand_size()==0 and owner.max_hp==2 and owner.awake_choice==1,"I05c taking last Sage cards forces one awakening, whose reward can be stolen without infinite reawakening")
	t.check(game._pending_card_actions.is_empty() and game._awaken_in_progress.is_empty() and game._dying_contexts.is_empty(),"I05c nested Sage/draw/awakening/Corruption releases all original contexts exactly once")
	await Farming.new().dispose(t,game)

func granted(t,phase,mode):
	var game=Cards.new().fixture(t); var source=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	source.general_name="麦克斯·欧尼斯特"
	game.turn_manager.current_phase=TurnManager.Phase.START
	game._meiyong_override=func(): return true
	game._meiyong_option_override=func(): return phase
	game._meiyong_target_override=func(): return target
	if phase==0: target.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	var seen: Array=[]; var stop: Array[bool]=[false]
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==source and batch.count==1 and source.hand_size()==1 and target.hand_size()==0 and game.turn_manager.current_phase==TurnManager.Phase.START,"I05c Max reward must resolve before any confirmed granted phase starts")
		await t.process_frame
		if mode=="stale": sunny.restore_game_start_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	if phase==2:
		var play=func():
			while not stop[0] and not game._game_over:
				if game._play_actor()==target and game.turn_manager.current_phase==TurnManager.Phase.PLAY:
					game.end_play_phase()
					return
				await t.process_frame
		play.call_deferred()
	var result=await game._maybe_meiyong(source); stop[0]=true
	var invalid=mode=="stale"
	t.check(result==(GameManager.CHOICE_INVALID if invalid else 1) and seen.size()==1 and game.turn_manager.current_phase==TurnManager.Phase.START,"I05c Max reward confirms one Corruption then restores source START after each granted phase")
	t.check(source.hand_size()==(0 if mode=="win" else 1) and sunny.hand_size()==(1 if mode=="win" else 0) and target.hand_size()==(2 if phase==1 and not invalid else 0),"I05c granted DRAW remains normal, distinct from Max EXTRA reward and never greed-triggered")
	t.check(game._meiyong_execution_owner==-1 and game._card_action_serial==0,"I05c Max choice/draw/granted phase lease completes without hand USE or replay")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,is_awaken):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c stage reward Bridge starts with private capability fixture")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear()
	var sunny=game.players[seat]; sunny.general_name=Cards.SUNNY
	var owner=game.players[2]; var target=game.players[3]; var done: Array=[]
	if is_awaken:
		owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state(); owner.awoken=true
	else:
		owner.general_name="麦克斯·欧尼斯特"
		game.turn_manager.current_player_idx=2; game.turn_manager.current_phase=TurnManager.Phase.START
		game._meiyong_override=func(): return true
		game._meiyong_option_override=func(): return 1
		game._meiyong_target_override=func(): return target
	var run=func(): done.append(await game._do_awaken(owner) if is_awaken else await game._maybe_meiyong(owner))
	run.call_deferred()
	for i in 2: await t.process_frame
	var activate=Sage.new().token(bridge,seat,"发动")
	t.check(not activate.is_empty() and done.is_empty() and owner.hand_size()==(2 if is_awaken else 1),"I05c host/remote entered stage reward suspends original parent")
	t.check(not bridge.submit(1-seat,activate) and bridge.submit(seat,activate),"I05c stage reward activation belongs only to active Sunny")
	for i in 2: await t.process_frame
	t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"石头")),"I05c stage reward accepts Sunny first gesture")
	for i in 2: await t.process_frame
	t.check(bridge.submit(2,Sage.new().token(bridge,2,"剪刀")),"I05c actual awakening/Max reward owner controls second gesture")
	for i in 2: await t.process_frame
	if is_awaken:
		var immune=Sage.new().token(bridge,2,"不能成为【杀】的目标")
		t.check(not immune.is_empty() and done.is_empty() and not bridge.submit(seat,immune) and bridge.submit(2,immune),"I05c mandatory immunity window follows complete Corruption, owned by awakened character")
	for i in 3: await t.process_frame
	t.check(done==[0 if is_awaken else 1] and owner.hand_size()==0 and sunny.hand_size()==(2 if is_awaken else 1) and (owner.awake_choice==1 if is_awaken else target.hand_size()==2),"I05c host/remote stage resumes once after reaction and mandatory next step")
	t.check(game._choice_prompt_stack.is_empty() and not bridge.submit(seat,activate),"I05c stage reward leaves no stale RPS/choice token after source continuation")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
