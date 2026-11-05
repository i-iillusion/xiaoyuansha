extends RefCounted

const PETER="彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹"
const PEACH=CardData.CardSubType.PEACH
const WINE=CardData.CardSubType.WINE

func fixture(t):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	game._peter_rules_enabled=true
	# Isolate the established Peach flow from the newly optional Sacrifice list.
	game._peter_exclusion_override=func(_p,_c,_k,_v): return []
	game.lan_enabled=true
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	for body in game.players:
		body.hand.clear()
		body.determined_cards.clear()
		body.hp=body.max_hp
	game.players[0].general_name=PETER
	game.players[1].hp=1
	return game

func dispose(t,game):
	game._game_over=true
	game.queue_free()
	for i in 3: await t.process_frame

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["source","self","wine","negative","concrete","denied","decline","timeout","disabled","other","sourceless"]:
		var game=fixture(t)
		var source=game.players[0]
		var victim=game.players[1]
		var third=game.players[2]
		var rescued_by=source if mode=="source" else (victim if mode in ["self","wine","negative","concrete"] else third)
		var sub=WINE if mode=="wine" else PEACH
		var original: CardBase
		if mode=="concrete":
			original=CardBase.create(PEACH)
			victim.determined_cards.append(original)
		else: rescued_by.hand.append(null)
		if mode=="negative": victim.hand.append(null)
		if rescued_by!=third: third.hand.append(null)
		var calls: Array=[]
		var blocked: Array=[]
		var offers: Array=[]
		var actions: Array=[]
		game.card_action_committed.connect(func(action): actions.append(action))
		game._peter_peach_override=func(p,target,valid):
			calls.append([p,target])
			t.check(valid.call() and target.hp<=0 and game._dying_contexts.has(target),"I05 Peter choice is in the actual current dying frame: "+mode)
			return 0 if mode=="decline" else (-1 if mode=="timeout" else 1)
		game._rescue_choice_override=func(rescuer,target,options):
			offers.append(rescuer)
			if mode not in ["decline","timeout","disabled","other","sourceless"]:
				blocked.append(not game._use_rescue_card(third,target,PEACH) and third.hand_size()==1)
			return sub if rescuer==rescued_by and options.has(sub) else -1
		if mode=="disabled": game._peter_rules_enabled=false
		if mode=="other": source.general_name="稻草人"
		var result=await game._deal_damage_result(null if mode=="sourceless" else source,victim,2 if mode=="negative" else 1,EffectChain.DamageType.PHYSICAL)
		var restricted=mode not in ["decline","timeout","disabled","other","sourceless"]
		t.check(not result.invalidated and (victim.is_dead() if mode=="denied" else victim.hp==1),"I05 genuine damage/rescue/death result: "+mode)
		t.check(calls.size()==(0 if mode in ["disabled","other","sourceless"] else 1),"I05 asks once for attributed Peter damage only: "+mode)
		t.check(not restricted or (not offers.has(third) and blocked.all(func(ok): return ok) and third.hand_size()==1),"I05 forbidden third party cannot receive or bypass a Peach payment: "+mode)
		var expected=0 if mode=="denied" else (2 if mode=="negative" else 1)
		t.check(actions.size()==expected and actions.all(func(a): return a.actor_body==rescued_by and a.settlement_completed and a.sub_type==sub),"I05 only real legal rescue creates completed card facts, no skill USE: "+mode)
		if original!=null: t.check(game.deck._discard.count(original)==1 and actions[0].card==original,"I05 self concrete Peach retains original identity and is discarded once")
		t.check(game._dying_contexts.is_empty() and game._pending_card_actions.is_empty(),"I05 finished frame retains no restriction or pending card lease: "+mode)
		await dispose(t,game)
	await self_saves(t)
	await repeat_entry(t)
	await nested(t)
	await invalidation(t)
	await bridge_cases(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func self_saves(t):
	for mode in ["egg","sage"]:
		var game=fixture(t)
		var victim=game.players[1]
		game.players[2].hand.append(null)
		game._peter_peach_override=func(_p,_v,_valid): return 1
		if mode=="egg":
			victim.general_name="克里斯·西弗"
			victim.fire_dragon_eggs=1
			game._rescue_choice_override=func(rescuer,target,options): return game.RESCUE_EGG if rescuer==target and options.has(game.RESCUE_EGG) else -1
		else:
			victim.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			victim.sage_activated=true
			game._sage_save_override=func(): return 1
		var result=await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
		t.check(not result.invalidated and victim.is_alive() and victim.hp==(2 if mode=="egg" else 5),"I05 active Peach restriction preserves actual self-save: "+mode)
		t.check((victim.fire_dragon_eggs==0) if mode=="egg" else (victim.get_armor()==-1 and victim.hand_size()==4),"I05 original egg/Sage payment and restoration still settle: "+mode)
		t.check(game.players[2].hand_size()==1 and game._dying_contexts.is_empty(),"I05 third-party Peach remains unspent after self-save and frame is retired")
		await dispose(t,game)

func repeat_entry(t):
	var game=fixture(t)
	var victim=game.players[1]
	victim.hand.append(null)
	game.players[2].hand.append(null)
	var choices: Array=[]
	game._peter_peach_override=func(_p,target,_valid):
		choices.append(game._dying_contexts[target])
		return 1 if choices.size()==1 else 0
	game._rescue_choice_override=func(_p,_v,options): return PEACH if options.has(PEACH) else -1
	await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
	t.check(victim.hp==1 and game.players[2].hand_size()==1,"I05 first restricted frame saves by victim's own Peach")
	await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
	t.check(victim.hp==1 and game.players[2].hand_size()==0 and choices.size()==2 and choices[0]!=choices[1],"I05 later dying is a fresh choice; prior restriction cannot leak")
	await dispose(t,game)

func nested(t):
	var game=fixture(t)
	var victim=game.players[1]
	var child=game.players[3]
	child.hp=1
	game.players[0].hand.append(null)
	game.players[2].hand.append(null)
	var nested_once: Array=[]
	game._peter_peach_override=func(_p,_v,_valid): return 1
	game._rescue_choice_override=func(rescuer,target,options):
		if target==victim and nested_once.is_empty():
			nested_once.append(game._dying_contexts[victim])
			await game._deal_damage_result(game.players[4],child,1,EffectChain.DamageType.PHYSICAL)
			t.check(nested_once[0].peter_peach_restricted and game._dying_contexts[victim]==nested_once[0],"I05 nested ordinary rescue does not erase parent restriction")
		return PEACH if target==child and rescuer==game.players[2] and options.has(PEACH) else -1
	await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
	t.check(child.hp==1 and victim.is_dead() and game.players[2].hand_size()==0,"I05 unblocked nested victim can receive third-party Peach while parent cannot")
	t.check(game._dying_contexts.is_empty(),"I05 both nested contexts cleanly retire")
	await dispose(t,game)

func invalidation(t):
	for fault in ["phase","reset","restore","source_dead","healed","space","registry","gate","reentry"]:
		var game=fixture(t)
		var victim=game.players[1]
		game.players[2].hand.append(null)
		var captured: Array=[]
		game._peter_peach_override=func(source,target,valid):
			captured.append(game._dying_contexts[target])
			match fault:
				"phase": game.turn_manager.current_phase=TurnManager.Phase.END
				"reset": game.reset_game_over_state()
				"restore": source.restore_game_start_state()
				"source_dead": source.mark_dead()
				"healed": target.heal(1)
				"space": game.turn_manager.rounds.relocate_before(3,1)
				"registry": game._reset_unit_registry()
				"gate": game._peter_rules_enabled=false
				"reentry": await game._resolve_dying(target,source,"damage",captured[0].effect_chain)
			return 1
		var result=await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
		t.check(captured.size()==1,"I05 choice cannot be duplicated by nested same-victim entry: "+fault)
		if fault=="reentry":
			t.check(not result.invalidated and captured[0].peter_peach_restricted and victim.is_dead(),"I05 same-context reentry cannot bypass the committed restriction")
		else:
			t.check(result.invalidated and not captured[0].peter_peach_restricted and game.players[2].hand_size()==1,"I05 stale choice never sets a ban or pays later rescue: "+fault)
		await dispose(t,game)

func bridge_cases(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	for mode in ["accept","cancel","timeout","invalid"]:
		var bridge=LanGameBridge.new()
		bridge._enable_peter_rules_for_tests=true
		t.root.add_child(bridge)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":PETER if seat==1 else "稻草人"})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 private Bridge fixture starts without public Peter opening")
		var game=bridge.game
		game._halt_countdown()
		game._peter_exclusion_override=func(_p,_c,_k,_v): return []
		game._sacrifice_actor_override=func(_p,_v,_n): return false
		game._duel_respond_override=func(): return false
		game._nullify_override=func(): return false
		for body in game.players:
			body.hand.clear()
			body.determined_cards.clear()
		game.players[2].hp=1
		game.players[3].hand.append(null)
		await helper.click(t,bridge,0,"结束出牌")
		for label in ["出牌","锦囊牌","普通锦囊","决斗"]: await helper.click(t,bridge,1,label)
		await t.create_timer(0.15).timeout
		game._target_confirm_override=func(): return 1
		var target=bridge.snapshot(1).targets.get("2","")
		t.check(target!="" and bridge.submit(1,target),"I05 actual B Duel pays and enters C dying, no seeded dying context")
		await helper.frames(t)
		var view=bridge.snapshot(1)
		var yes=load("res://Test/i04_movement_cases.gd").new().find(view,"发动禁桃")
		t.check(yes!="" and bridge.input_owner()==1 and not bridge.submit(3,yes),"I05 only source B can answer optional restriction")
		if mode=="invalid":
			game.turn_manager.current_phase=TurnManager.Phase.DRAW
			await helper.frames(t)
			t.check(not bridge.submit(1,yes) and not game.players[2].is_dead() and game.players[2].hp==0 and game.players[3].hand_size()==1,"I05 expired real Bridge window is technical invalidation, never timeout/normal rescue")
			t.check(game._dying_contexts.is_empty() and game._pending_card_actions.is_empty() and game.players[1].hand_size()==1,"I05 paid Duel remains paid but stale prompt cannot set ban, rescue, or leak a lease")
			game._game_over=true
			bridge.queue_free()
			await helper.frames(t)
			continue
		if mode=="timeout":
			t.check(game._countdown_active and game._step_remaining<=game.STEP_SECONDS,"I05 Q5 uses existing base response countdown")
			game._countdown_on_timeout.call()
		else: await helper.click(t,bridge,1,"发动禁桃" if mode=="accept" else "取消")
		await helper.frames(t)
		await helper.click(t,bridge,1,"放弃") # Source's own Peach is still legal.
		if mode!="accept":
			var peach=load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(3),"使用【桃】")
			t.check(peach!="" and bridge.input_owner()==3 and not bridge.submit(1,peach) and bridge.submit(3,peach),"I05 cancellation/timeout resumes actual third-party Peach, correct owner only")
			await helper.frames(t)
		t.check((game.players[2].is_dead() and game.players[3].hand_size()==1) if mode=="accept" else (game.players[2].hp==1 and game.players[3].hand_size()==0),"I05 actual restriction/normal rescue result: "+mode)
		t.check(bridge.input_owner()==1 and game.turn_manager.current_phase==TurnManager.Phase.PLAY and not bridge.submit(1,yes) and game._dying_contexts.is_empty() and game._pending_card_actions.is_empty(),"I05 returns original B PLAY, old skill command cannot replay")
		game._game_over=true
		bridge.queue_free()
		await helper.frames(t)
