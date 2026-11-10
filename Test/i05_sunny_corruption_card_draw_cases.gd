extends RefCounted
const Base=preload("res://Test/i05_extra_draw_batch_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")
const SUNNY="桑尼·斯派"

func fixture(t):
	var game=Base.new().fixture(t)
	game._corruption_rules_enabled=true
	game._wrestling_choice_override=func(_p,_v): return 0
	game._rescue_choice_override=func(_p,_t,_o): return -1
	for p in game.players:
		p.general_name="稻草人"; p.max_hp=4; p.hp=4; p.capture_game_start_state()
	game.players[4].general_name=SUNNY; game.players[4].capture_game_start_state()
	return game

func prepare_global(game,sub,first:=1,second:=2):
	if sub==CardData.CardSubType.HARVEST:
		game.players[first].hp=2; game.players[second].hp=3
	else:
		game.players[first].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
		game.players[first].equip_card_to_slot("mount_1",CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		game.players[second].equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.RENWANG_DUN))

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for sub in [CardData.CardSubType.HARVEST,CardData.CardSubType.DISARM]:
		for mode in ["win","decline","tie","stale","terminal"]: await global_card(t,sub,mode)
		for seat in [0,1]: await bridge_case(t,sub,seat)
	for empty in [false,true]:
		for concrete in [false,true]:
			for mode in ["win","decline","stale"]: await chixiong(t,empty,concrete,mode)
	await source_death(t)
	for empty in [false,true]: await committed_weapon_loss(t,empty)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func global_card(t,sub,mode):
	var game=fixture(t); var actor=game.players[4]; var next=game.players[2]
	prepare_global(game,sub)
	game.players[0].append_hand_card_silent(null)
	var actions: Array=[]; var completed: Array=[]; var seen: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_p,batch,stage,valid):
		if stage=="tie": return 0
		seen.append(batch.owner)
		t.check(valid.call() and actions.size()==1 and not actions[0].settlement_completed and completed.is_empty(),"I05c group card remains incomplete while each draw reaction waits: "+mode)
		if batch.owner==game.players[1]:
			t.check(batch.owner.hand_size()==2 and next.hand_size()==0 and (sub==CardData.CardSubType.HARVEST or next.equipment.size()==1),"I05c first target enters hand before Corruption; next target has not drawn or lost equipment")
		await t.process_frame
		t.check(completed.is_empty() and (batch.owner!=game.players[1] or next.hand_size()==0),"I05c actual awaited choice holds the group effect cursor")
		if mode=="stale": actor.restore_game_start_state()
		if mode=="terminal": game._finish_game("平局","Corruption parent terminal fixture")
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor or mode=="tie" else GameManager.RPS_SCISSORS
	await game.play_card(sub)
	var interrupted=mode in ["stale","terminal"]
	t.check(actions.size()==1 and completed.size()==(0 if interrupted else 1) and game._pending_card_actions.is_empty(),"I05c paid group card finishes once or releases only its stale completion receipt: "+mode)
	t.check(seen==([game.players[1]] if interrupted else [game.players[1],next]),"I05c group draw reactions retain original target order without replay or skipped later target")
	if not interrupted:
		var first_count=2 if mode=="decline" else (1 if mode=="tie" else 0)
		t.check(game.players[1].hand_size()==first_count and next.hand_size()==(1 if mode=="decline" else 0) and actor.hand_size()==(0 if mode=="decline" else (2 if mode=="tie" else 3)),"I05c each precise batch moves or stays before group completion: "+mode)
		if sub==CardData.CardSubType.DISARM: t.check(game.players[1].equipment.is_empty() and next.equipment.is_empty(),"I05c all original Disarm equipment still leaves before its compensation draw")
	else:
		t.check(next.hand_size()==0 and (sub==CardData.CardSubType.HARVEST or next.equipment.size()==1),"I05c stale/terminal reaction never advances to a fresh target or discards their equipment")
	t.check(game.deck._discard.count(actions[0].card)==1,"I05c original global hand card is paid and discarded exactly once")
	await Farming.new().dispose(t,game)

func chixiong(t,empty,concrete,mode):
	var game=fixture(t); var source=game.players[0]; var target=game.players[1]; var actor=game.players[4]
	source.gender="male"; target.gender="female"
	source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
	var older=CardBase.create(CardData.CardSubType.DODGE)
	source.append_hand_card_silent(older)
	var original=CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
	if concrete: source.determined_cards.append(original)
	else: source.append_hand_card_silent(null)
	if not empty: target.append_hand_card_silent(null)
	game._chixiong_activate_override=func(): return true
	game._chixiong_target_override=func(): return false
	game._dodge_override=func(): return false
	var actions: Array=[]; var completed: Array=[]; var seen: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): completed.append(a))
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(batch.owner==source and batch.count==1 and source.hand_size()==2 and target.hp==4 and valid.call(),"I05c both Chixiong draw branches wait before Dodge/damage with older concrete card intact")
		await t.process_frame
		t.check(target.hp==4 and completed.is_empty(),"I05c original paid Strike cannot hit or complete during weapon draw reaction")
		if mode=="stale": actor.restore_game_start_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
	t.check(seen.size()==1 and target.hp==(4 if mode=="stale" else 3),"I05c Chixiong original Strike resumes damage once only after a valid reaction result")
	t.check(source.hand.has(older) and source.hand_size()==(1 if mode=="win" else 2) and actor.hand_size()==(1 if mode=="win" else 0),"I05c weapon reward transfers only its new arbitrary card, never an older concrete Flash")
	t.check(actions.size()==1 and completed.size()==(0 if mode=="stale" else 1) and game._pending_card_actions.is_empty(),"I05c Chixiong reaction neither creates extra hand USE nor leaks original Strike completion")
	t.check(game.deck._discard.count(actions[0].card)==1 and (not concrete or actions[0].card==original) and not game.deck._discard.has(older),"I05c arbitrary/concrete original Strike payment is preserved without a second discard")
	await Farming.new().dispose(t,game)

func source_death(t):
	var game=fixture(t); var source=game.players[0]; var donor=game.players[1]
	game.players[4].general_name="稻草人"
	source.general_name=SUNNY; source.hp=1; donor.general_name="大卫·法米尔"
	prepare_global(game,CardData.CardSubType.HARVEST)
	source.append_hand_card_silent(null)
	game._wrestling_choice_override=func(_p,_v): return 1
	game._corruption_choice_override=func(_p,_b,_s,_v): return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==source else GameManager.RPS_SCISSORS
	var completed: Array=[]
	game.card_action_completed.connect(func(a): completed.append(a))
	await game.play_card(CardData.CardSubType.HARVEST)
	t.check(source.is_dead() and donor.hand_size()==2 and donor.wrestle_round==game.turn_manager.rounds.round_id,"I05c actual David counter can kill the original Harvest source after committing prevention")
	t.check(game.players[2].hand_size()==1 and completed.filter(func(a): return a.sub_type==CardData.CardSubType.HARVEST).size()==1,"I05c paid Harvest continues next recipient and completes after its source dies during Corruption")
	t.check(game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"I05c nested prevention/death/parent card all release their own frames")
	await Farming.new().dispose(t,game)

func committed_weapon_loss(t,empty):
	var game=fixture(t); var source=game.players[0]; var target=game.players[1]; var actor=game.players[4]
	source.general_name="大卫·法米尔"; source.gender="male"; target.gender="female"
	source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
	source.append_hand_card_silent(null)
	if not empty: target.append_hand_card_silent(null)
	var leo=game.players[2]; leo.general_name="里奥·普利威尔"; leo.prep_tokens=1
	game._chixiong_activate_override=func(): return true
	game._chixiong_target_override=func(): return false
	game._dodge_override=func(): return false
	game._wrestling_choice_override=func(_p,_v): return 1
	game._prep_replace_override=func(_leo,user,_target,_sub,_options): return CardData.CardSubType.DISARM if user==source else -1
	var seen: Array=[]; var completed: Array=[]
	game._corruption_choice_override=func(_p,batch,_stage,_valid):
		seen.append(batch)
		return 0 if seen.size()==1 else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==actor else GameManager.RPS_SCISSORS
	game.card_action_completed.connect(func(a): completed.append(a))
	await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
	t.check(source.get_weapon()==-1 and leo.prep_tokens==0 and seen.size()==2,"I05c actual David counter becomes Disarm and removes already-triggered Chixiong before parent resumes")
	t.check(source.hand_size()==2 and actor.hand_size()==0 and source.wrestle_round==game.turn_manager.rounds.round_id,"I05c prevention protects original reward, while nested compensation is a separate declined draw")
	t.check(target.hp==3 and completed.filter(func(a): return a.sub_type==CardData.CardSubType.STRIKE).size()==1,"I05c losing already-triggered sword during nested reaction cannot cancel the original paid Strike")
	t.check(completed.size()==2 and game._pending_card_actions.is_empty(),"I05c original Strike and replaced virtual counter each complete once after committed weapon loss")
	await Farming.new().dispose(t,game)

func bridge_case(t,sub,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c card draw Bridge starts with ordinary public roster")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	game._nullify_override=func(): return false
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var actor=game.players[seat]; actor.general_name=SUNNY
	var donor=game.players[2]
	if sub==CardData.CardSubType.HARVEST: donor.hp=donor.max_hp-2
	else:
		donor.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
		donor.equip_card_to_slot("mount_1",CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	game.players[0].append_hand_card_silent(null)
	var done: Array=[]
	var run=func():
		await game.play_card(sub)
		done.append(true)
	run.call_deferred()
	for i in 2: await t.process_frame
	var activate=Sage.new().token(bridge,seat,"发动")
	t.check(not activate.is_empty() and done.is_empty() and donor.hand_size()==2,"I05c host/remote group card stops at its actual Corruption prompt")
	t.check(not bridge.submit(1-seat,activate) and bridge.submit(seat,activate) and not bridge.submit(seat,activate),"I05c actual card parent keeps active Sunny ownership and rejects replay")
	for i in 2: await t.process_frame
	t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"石头")),"I05c host/remote card draw reaction accepts Sunny gesture")
	for i in 2: await t.process_frame
	t.check(not bridge.submit(seat,Sage.new().token(bridge,2,"剪刀")) and bridge.submit(2,Sage.new().token(bridge,2,"剪刀")),"I05c actual draw owner alone answers the second gesture")
	for i in 3: await t.process_frame
	t.check(done==[true] and donor.hand_size()==0 and actor.hand_size()==2 and game._pending_card_actions.is_empty(),"I05c host/remote paid group card finishes after transferring the exact draw")
	t.check(not bridge.submit(seat,activate) and game._choice_prompt_stack.is_empty(),"I05c group card leaves no obsolete action or input frame after resumption")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
