extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")
const Death=preload("res://Test/i05_sunny_corruption_death_draw_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for path in ["snatch","dismantle","forced_snatch","forced_dismantle","ice","ice_two","penalty","selector","campus","soul"]:
		for concrete in [false,true]:
			for mode in ["decline","win","stale"]: await loss(t,path,concrete,mode)
	for seat in [0,1]:
		for snatch in [false,true]: await bridge_case(t,seat,snatch)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func loss(t,path,concrete,mode):
	var game=Cards.new().fixture(t); var source=game.players[0]; var owner=game.players[1]; var sunny=game.players[4]
	if path=="penalty":
		Death.new().roles(game,true)
		owner=source; game.players[1].hp=1
	if path=="soul": owner=source
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=4 if path=="penalty" else 3; owner.hp=owner.max_hp; owner.capture_game_start_state()
	var original=CardBase.create(CardData.CardSubType.PEACH) if concrete else null
	if concrete: owner.determined_cards.append(original)
	else: owner.append_hand_card_silent(null)
	if path=="ice_two": owner.append_hand_card_silent(null)
	if path!="selector": source.append_hand_card_silent(null)
	if path.begins_with("ice"): source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.ICE_SWORD))
	if path=="campus": source.general_name="杰基·斯特朗"; source.capture_game_start_state()
	if path=="soul":
		# Legal prefix: the weapon activated on an earlier complete damage.
		source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.SOUL_BLADE)); source.soul_blade_activated=true
		for i in 3: source.append_hand_card_silent(null)
	if path=="penalty": owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	game._dodge_override=func(): return false
	game._paixiong_override=func(): return false
	game._sacrifice_actor_override=func(_p,_v,_a): return false
	game._ice_sword_override=func(): return true
	game._soul_blade_activate_override=func(): return true
	game._soul_blade_discard_override=func(): return true
	game._zone_pick_override=func(): return "hand"
	game._prep_steal_pick_override=func(_choices): return 0
	game._hand_discard_override=func(_snapshot,count,_mandatory):
		var selected: Array[int]=[]
		for index in count: selected.append(index)
		return selected
	var seen: Array=[]; var choices: Array=[]; var used: Array=[]; var done: Array=[]
	game.card_action_committed.connect(func(e): used.append(e))
	game.card_action_completed.connect(func(e): done.append(e))
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and batch.count==2 and owner.hand_size()==2,"External loss commits before awakening's exact two-card receipt: "+path)
		t.check(done.is_empty() and choices.is_empty() and owner.max_hp==(3 if path=="penalty" else 2),"External loss parent waits for complete awakening rather than UI fallback: "+path)
		if path.ends_with("snatch"):
			t.check(source.hand_size()==1 and (not concrete or source.hand.has(original)),"Snatch retains exact old card before nested Greed, not the newly drawn batch")
		elif concrete: t.check(game.deck._discard.count(original)==1,"Committed old concrete card already discarded once before awakening: "+path)
		await t.process_frame
		t.check(done.is_empty() and choices.is_empty(),"External loss continuation stays suspended across an actual frame: "+path)
		if mode=="stale": sunny.restore_game_start_state()
		return 0 if mode=="win" else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny or (path=="campus" and p==source) or (path=="soul" and p==game.players[1]) else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func(): choices.append(true); return 3
	var outcome: Array=[]
	if path=="selector":
		outcome.append(await game._select_hand_discard_result(owner,1,true,func(): return true,source))
	elif path=="campus": await game._execute_campus_dominator(source,owner)
	elif path.begins_with("forced_"):
		# Exercise the paid transformed-card continuation, including its actual
		# event and forced picker, without pretending this fixture is natural PREP.
		var actions: Array[CardActionEvent]=[]
		var targets: Array[Player]=[owner]
		var sub=CardData.CardSubType.SNATCH if path.ends_with("snatch") else CardData.CardSubType.DISMANTLE
		t.check(await game._consume_trick(source,sub,actions,targets),"Forced steal fixture pays one real original event")
		await game._resolve_paid_steal(source,owner,path.ends_with("snatch"),"hand",actions,func(): return true,true)
	else:
		var sub=CardData.CardSubType.STRIKE if path in ["ice","ice_two","penalty","soul"] else (CardData.CardSubType.SNATCH if path=="snatch" else CardData.CardSubType.DISMANTLE)
		await game.execute_card_on_target(game.players[1],sub)
	var invalid=mode=="stale"
	t.check(seen.size()==1 and choices.size()==(0 if invalid else 1),"External loss joins one mandatory awakening without duplicate draw/choice: "+path)
	t.check(owner.hand_size()==(0 if mode=="win" else 2) and sunny.hand_size()==(2 if mode=="win" else 0),"Greed moves only newly drawn cards, not original lost card: "+path)
	if path=="selector": t.check(outcome==[GameManager.HandDiscardOutcome.REACTION_INVALIDATED if invalid else GameManager.HandDiscardOutcome.PAID],"Committed discard reports technical reaction failure separately from decline/payment")
	elif path=="campus":
		t.check(used.is_empty() and done.is_empty() and owner.hp==(2 if invalid else 1) and source.hand_size()==0,"Actual Campus pays both costs once, awaits target awakening, then original RPS/damage without phantom USE")
	else:
		t.check(used.size()==1 and done.size()==(0 if invalid else 1) and game._pending_card_actions.is_empty(),"Original paid loss event completes once or abandons stale continuation: "+path)
		t.check(game.deck._discard.count(used[0].card)==1,"Original effect never repays or discards a new awakening card: "+path)
	if concrete:
		t.check(game.deck._discard.count(original)==(0 if path.ends_with("snatch") else 1),"Old concrete loss preserves one exact destination, including stale reaction: "+path)
	if path.begins_with("ice"): t.check(owner.hp==2 and owner.is_alive(),"Ice Sword still prevents full damage and cannot discard newly drawn cards")
	if path=="penalty": t.check(game.players[1].is_dead() and owner.equipment.is_empty() and owner.hp==3,"Lord penalty commits cleanup, then awakening without rescue or penalty replay")
	if path=="soul": t.check(game.players[1].hp==3 and game.players[1].facedown==(not invalid),"Paid Soul Blade waits for source awakening before flipping; invalid reaction preserves committed damage only")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,snatch):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"External loss host/remote Bridge starts")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var source=game.players[seat+1]; var owner=game.players[seat]
	game.turn_manager.current_player_idx=source.seat_index; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	owner.append_hand_card_silent(null); source.append_hand_card_silent(null); game.players[4].general_name=Cards.SUNNY
	game._zone_pick_override=func(): return "hand"
	game._nullify_override=func(): return false
	game._set_input_player(source)
	var done: Array=[]; var seen: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,_v): seen.append(batch.count); return -1
	var run=func():
		await game.execute_card_on_target(owner,CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE)
		done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var choice=Sage.new().token(bridge,seat,"不能成为【南蛮入侵】和【万箭齐发】的目标")
	t.check(not choice.is_empty() and seen==[2] and done.is_empty(),"Host/remote stolen last card opens actual mandatory immunity before original effect completes")
	t.check(not bridge.submit(1-seat,choice) and bridge.submit(seat,choice),"External loss immunity accepts actual owner only")
	for i in 4: await t.process_frame
	t.check(done==[true] and owner.hand_size()==2 and source.hand_size()==(1 if snatch else 0),"Host/remote original steal resumes once after full awakening")
	t.check(game._pending_card_actions.is_empty() and bridge.input_owner()==source.seat_index and not bridge.submit(seat,choice),"External loss restores acting controller and rejects expired immunity token")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
