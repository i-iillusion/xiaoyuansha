extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for concrete in [false,true]:
		for mode in ["decline","win","tie","stale","reset"]: await bagua(t,concrete,mode)
	for enabled in [false,true]: await joined(t,enabled)
	for seat in [0,1]: await bridge_case(t,seat)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func stephen(p):
	p.general_name="史蒂芬·彼特先斯"; p.max_hp=3; p.hp=3; p.capture_game_start_state()
	p.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN))

func bagua(t,concrete,mode):
	var game=Cards.new().fixture(t); var defender=game.players[1]; var sunny=game.players[4]
	stephen(defender); game.players[0].append_hand_card_silent(null)
	var original=CardBase.create(CardData.CardSubType.DODGE) if concrete else null
	if concrete: defender.determined_cards.append(original)
	else: defender.append_hand_card_silent(null)
	game._dodge_override=func(): return true
	var actions: Array=[]; var done: Array=[]; var seen: Array=[]; var chosen: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._corruption_choice_override=func(_p,batch,stage,valid):
		if stage=="tie": return 0
		seen.append(batch)
		t.check(valid.call() and batch.owner==defender and defender.max_hp==2 and defender.hp==2 and actions.size()==2 and done.is_empty(),"Q12 actual response paid once; full awakening begins before Bagua and original completion")
		if seen.size()==1:
			t.check(batch.count==2 and defender.hand_size()==2 and defender.awake_choice==0 and chosen.is_empty(),"Q12 first reward is awakening two cards, not Bagua one card")
			await t.process_frame
			if mode=="stale": sunny.restore_game_start_state()
			if mode=="reset": game.reset_game_over_state()
			return -1 if mode=="decline" else 0
		t.check(batch.count==1 and defender.awake_choice==1 and chosen==[true],"Q12 Bagua only follows completed awakening reaction and mandatory immunity")
		return -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny or mode=="tie" else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func():
		chosen.append(true)
		t.check(seen.size()==1 and defender.hand_size()==(2 if mode=="decline" else (1 if mode=="tie" else 0)) and done.is_empty(),"Q12 immunity follows exact awakening batch; original paid response still pending")
		await t.process_frame
		return 1
	await game.execute_card_on_target(defender,CardData.CardSubType.STRIKE)
	var invalid=mode in ["stale","reset"]
	t.check(seen.size()==(1 if invalid else 2) and chosen.size()==(0 if invalid else 1),"Q12 invalid awakening does not advance to Bagua; ordinary flow includes both batches")
	if not invalid:
		t.check(defender.hp==2 and defender.max_hp==2 and defender.hand_size()==(3 if mode=="decline" else (2 if mode=="tie" else 1)),"Q12 final health/hand reflect awakening then Bagua; consumed response still avoids original damage")
	t.check(actions.size()==2 and done.size()==(0 if invalid else 2) and game._pending_card_actions.is_empty(),"Q12 original Strike and Dodge finish once or abandon together after lifecycle invalidation")
	t.check(game.deck._discard.count(actions[1].card)==1 and (not concrete or actions[1].card==original),"Q12 exact paid concrete/arbitrary Dodge is discarded once without repayment")
	t.check(not game._awaken_in_progress.has(defender),"Q12 mandatory awakening releases its own lease")
	await Farming.new().dispose(t,game)

func joined(t,enabled):
	var game=Cards.new().fixture(t); var owner=game.players[1]
	stephen(owner); game._corruption_rules_enabled=enabled
	game._corruption_choice_override=func(_p,_b,_s,_v): return -1
	var picked: Array=[]; var results: Array=[]
	game._awaken_pick_override=func():
		picked.append(true)
		await t.process_frame
		await t.process_frame
		t.check(results.is_empty(),"Q12 all explicit payment parents wait for the same mandatory choice even with legacy gates")
		return 1
	var run=func(): results.append(await game._await_hand_awakening(owner))
	run.call_deferred(); run.call_deferred()
	for i in 8: await t.process_frame
	t.check(results==[0,0] and picked==[true] and owner.max_hp==2 and owner.hand_size()==2,"Q12 joined payment barriers apply one awakening and return only after immunity")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"Q12 Bridge starts for host/remote mandatory awakening")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true; game._extra_draw_receipts_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var owner=game.players[seat]; stephen(owner); owner.append_hand_card_silent(null)
	var sunny=game.players[3]; sunny.general_name=Cards.SUNNY
	game._dodge_override=func(): return true
	var seen: Array=[]; var results: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,_v): seen.append(batch.count); return -1
	var run=func(): results.append(await game._ask_basic_card_response_result(owner,CardData.CardSubType.DODGE,Callable(),func(): return true))
	run.call_deferred()
	for i in 3: await t.process_frame
	var choice=Sage.new().token(bridge,seat,"不能成为【杀】的目标")
	t.check(not choice.is_empty() and seen==[2] and owner.hand_size()==2 and results.is_empty(),"Q12 host/remote must choose awakening immunity before Bagua can create its draw")
	t.check(not bridge.submit(1-seat,choice) and bridge.submit(seat,choice),"Q12 mandatory immunity belongs to actual remote/host responder")
	for i in 3: await t.process_frame
	t.check(results==[GameManager.BasicResponseOutcome.PAID] and seen==[2,1] and owner.hand_size()==3 and owner.max_hp==2,"Q12 network response resumes once after immunity and then Bagua")
	t.check(not bridge.submit(seat,choice) and game._pending_card_actions.is_empty(),"Q12 old immunity token cannot replay a reward or original response")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
