extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for kind in ["other","self_zero","self_negative"]:
		for concrete in [false,true]:
			for mode in ["decline","win","stale"]: await rescue(t,kind,concrete,mode)
	for concrete in [false,true]: await rescue(t,"self_negative",concrete,"tie")
	await receipt_permission(t)
	for seat in [0,1]:
		for win in [false,true]: await bridge_case(t,seat,win)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func setup(t,kind,concrete):
	var game=Cards.new().fixture(t); var victim=game.players[1]
	var owner=game.players[2] if kind=="other" else victim
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	victim.hp=2 if kind=="self_zero" else 1
	if concrete: owner.determined_cards.append(CardBase.create(CardData.CardSubType.PEACH))
	else: owner.append_hand_card_silent(null)
	game.players[0].append_hand_card_silent(null)
	game.players[0].wine_stacks=1 # Existing legal one-Wine prefix; this test pays the following Kill.
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	game._sacrifice_actor_override=func(_p,_v,_a): return false
	return game

func rescue(t,kind,concrete,mode):
	var game=setup(t,kind,concrete); var victim=game.players[1]
	var owner=game.players[2] if kind=="other" else victim
	var sunny=game.players[4]; var source=game.players[0]
	var done: Array=[]; var used: Array=[]; var asked: Array=[]; var draws: Array=[]; var picks: Array=[]
	game.card_action_committed.connect(func(e): used.append(e))
	game.card_action_completed.connect(func(e): done.append(e))
	game._rescue_choice_override=func(rescuer,_dying,options):
		asked.append(rescuer)
		if rescuer==owner or (kind=="other" and rescuer==sunny):
			return CardData.CardSubType.PEACH if options.has(CardData.CardSubType.PEACH) else -1
		return -1
	game._corruption_choice_override=func(_p,batch,stage,valid):
		if stage=="tie": return 0
		draws.append(batch)
		t.check(valid.call() and batch.owner==owner and batch.count==2 and batch.allow_dying_owner and owner.hand_size()==2,"Q16 actual awakening receipt permits this not-yet-dead owner, including zero HP")
		t.check(victim.hp==(1 if kind=="self_zero" else 0) and owner.max_hp==2 and game._dying_contexts.has(victim),"Q15 Peach has already healed before awakening/Corruption; original rescue context is retained")
		t.check(asked==[owner] and done.size()==1 and done[0].sub_type==CardData.CardSubType.PEACH,"Q15 original Peach completed once; next Peach/responder and original Kill have not advanced")
		await t.process_frame
		t.check(asked==[owner] and picks.is_empty(),"Q16 pending Corruption suspends further rescue and mandatory immunity")
		if mode=="stale": sunny.restore_game_start_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny or mode=="tie" else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func():
		picks.append(true)
		t.check(asked==[owner] and victim.hp==(1 if kind=="self_zero" else 0),"Q16 complete immunity choice before the next Peach, even while owner is DYING")
		return 1
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	var invalid=mode=="stale"
	var peaches=used.filter(func(e): return e.sub_type==CardData.CardSubType.PEACH)
	var kills=done.filter(func(e): return e.actor_body==source and e.sub_type==CardData.CardSubType.STRIKE)
	t.check(draws.size()==1 and owner.max_hp==2 and picks.size()==(0 if invalid else 1),"Q16 only one awakening/draw/choice, with invalidation distinct from refusal")
	if not invalid:
		var dies=kind=="self_negative" and mode=="win"
		t.check(victim.is_dead()==dies and victim.hp==(0 if dies else 1),"Q16 retained new cards can save negative-HP owner; stolen cards can leave it unsaved")
		var second=kind!="self_zero" and not dies
		t.check(peaches.size()==(2 if second else 1) and kills.size()==1,"Q15/16 next rescue happens after awakening; original wine Kill completes exactly once")
		if second: t.check(peaches[1].actor_body==(sunny if mode=="win" else owner),"Q16 rescue uses remaining original batch or the next legitimate responder's stolen cards")
		t.check(owner.hand_size()==(0 if mode in ["win","tie"] else (2 if kind=="self_zero" else 1)) and sunny.hand_size()==(1 if mode=="tie" or (mode=="win" and kind=="other") else (2 if mode=="win" else 0)),"Q16 exact physical batch movement and subsequent Peach payments retain correct hands")
		t.check(game._dying_contexts.is_empty() and not game._awaken_in_progress.has(owner),"Q16 normal dying/awakening frames release after original rescue continuation")
	else:
		t.check(victim.hp==(1 if kind=="self_zero" else 0) and peaches.size()==1 and kills.is_empty(),"Q16 invalid nested reaction never rolls back paid healing or resumes old Kill completion")
	t.check(used.all(func(e): return game.deck._discard.count(e.card)==1) and game._pending_card_actions.is_empty(),"Q16 exact original arbitrary/concrete Peach and Kill are discarded once, no phantom USE")
	await Farming.new().dispose(t,game)

func receipt_permission(t):
	var game=Cards.new().fixture(t); var p=game.players[1]
	var ordinary=game._draw_blank_cards(p,1); p.hp=0
	t.check(not ordinary.valid() and ordinary.take(1).is_empty(),"Q16 permission does not weaken existing ordinary dying-receipt guard")
	var permitted=game._draw_blank_cards(p,2,ExtraDrawBatch.Context.EXTRA,false,true)
	t.check(permitted.valid() and permitted.take(1).size()==1,"Q16 explicit awakening receipt supports physical loss while DYING")
	var dead_receipt=game._draw_blank_cards(p,2,ExtraDrawBatch.Context.EXTRA,false,true); p.mark_dead()
	t.check(not dead_receipt.valid() and dead_receipt.take(1).is_empty(),"Q16 permission never authorizes taking cards after final death")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,win):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"Q16 actual host/remote rescue Bridge starts")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var foe=game.players[2]; var owner=game.players[seat]; var sunny=game.players[4]
	game.turn_manager.current_player_idx=seat; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	# Own-turn Duel failure gives a legal two-damage source, and puts Sunny
	# after the dying owner in the ordinary rescue order for this same round.
	foe.general_name="布鲁斯·萨维奇"; foe.max_hp=6; foe.hp=5; foe.append_hand_card_silent(null)
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state(); owner.hp=1
	owner.append_hand_card_silent(null); owner.append_hand_card_silent(null)
	sunny.general_name=Cards.SUNNY
	game._set_input_player(owner); game._paixiong_override=func(): return false
	game._nullify_override=func(): return false
	var replies: Array=[]
	game._duel_respond_override=func(): replies.append(true); return replies.size()==1
	game._sacrifice_actor_override=func(_p,_v,_a): return false
	var done: Array=[]
	var run=func(): await game.execute_card_on_target(foe,CardData.CardSubType.DUEL); done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var peach=Sage.new().token(bridge,seat,"使用【桃】")
	t.check(not peach.is_empty() and owner.hp==-1 and done.is_empty(),"Q16 host/remote receives actual self-rescue Peach at negative HP")
	t.check(not bridge.submit(1-seat,peach) and bridge.submit(seat,peach),"Q16 only actual dying owner can pay original Peach")
	for i in 3: await t.process_frame
	var activate=Sage.new().token(bridge,4,"发动" if win else "取消")
	t.check(owner.hp==0 and owner.hand_size()==2 and owner.max_hp==2 and not activate.is_empty() and done.is_empty(),"Q16 Peach first heals to zero; real Corruption opens before any further rescue")
	t.check(bridge.submit(4,activate) and not bridge.submit(seat,peach),"Q16 nested Sunny input replaces old self-rescue token")
	if win:
		for i in 2: await t.process_frame
		t.check(bridge.submit(4,Sage.new().token(bridge,4,"石头")),"Q16 Sunny owns actual first gesture")
		for i in 2: await t.process_frame
		t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"剪刀")),"Q16 zero-HP owner can answer actual second gesture")
	for i in 3: await t.process_frame
	var immunity=Sage.new().token(bridge,seat,"不能成为【杀】的目标")
	t.check(not immunity.is_empty() and owner.hp==0 and done.is_empty() and bridge.submit(seat,immunity),"Q16 mandatory immunity remains actionable while owner is still DYING")
	for i in 3: await t.process_frame
	var rescue_seat=4 if win else seat
	var next_peach=Sage.new().token(bridge,rescue_seat,"使用【桃】")
	t.check(not next_peach.is_empty() and owner.hp==0 and done.is_empty() and bridge.submit(rescue_seat,next_peach),"Q16 after complete awakening, new cards support next self-Peach or later Sunny rescue")
	for i in 4: await t.process_frame
	t.check(done==[true] and owner.hp==1 and not owner.is_dead() and owner.max_hp==2,"Q16 actual host/remote rescue finishes original Duel once after successful continuation")
	t.check(game._pending_card_actions.is_empty() and game._choice_prompt_stack.is_empty() and not bridge.submit(seat,immunity),"Q16 actual nested rescue leaves no old event, window or replay token")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
