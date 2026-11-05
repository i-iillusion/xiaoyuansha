extends RefCounted

func fixture(t):
	var game=load("res://Test/i05_peter_peach_cases.gd").new().fixture(t)
	game.players[1].hp=5
	game.players[3].hand.append(null)
	game.players[4].hand.append(null)
	game._peter_peach_override=func(_p,_t,_v): return 0
	game._duel_respond_override=func(): return false
	game._nullify_override=func(): return false
	return game

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["partial","all","decline","other","sourceless","strike","duel","concrete","virtual","forged","duplicate"]:
		var game=fixture(t)
		var victim=game.players[1]
		var source=game.players[0]
		var d=game.players[3]
		var e=game.players[4]
		var original: CardBase
		if mode=="concrete":
			e.hand.clear()
			original=CardBase.create(CardData.CardSubType.SACRIFICE)
			e.determined_cards.append(original)
		if mode=="virtual":
			e.general_name="安普提·斯丢皮得"
			e.hp=1
			e.hand.clear()
			game._yes_ah_override=func(): return "skill"
			game._rps_override=func(body): return game.RPS_ROCK if body==e else game.RPS_PAPER
		var offers: Array=[]
		var asks: Array=[]
		var actions: Array=[]
		game.card_action_committed.connect(func(a): actions.append(a))
		game._peter_exclusion_override=func(owner,candidates,kind,valid):
			if kind=="nullification": return [] # Isolate the established damage-response cases.
			asks.append(candidates)
			t.check(owner==source and kind=="sacrifice" and valid.call() and not candidates.has(source),"I05 source owns current valid third-party Sacrifice selection: "+mode)
			if candidates.has(victim): return [] # A transferred injury is a separate window.
			t.check(not candidates.has(victim) and candidates.has(d) and candidates.has(e),"I05 protects source/victim but permits arbitrary legal third parties")
			if mode=="forged": return [source]
			if mode=="duplicate": return [d,d]
			if mode=="all": return [d,e]
			return [] if mode=="decline" else [d]
		game._sacrifice_actor_override=func(body,target,_amount):
			if target!=victim: return false
			offers.append(body)
			return body==d or body==e
		if mode=="other": source.general_name="稻草人"
		var result
		if mode in ["strike","duel"]:
			source.hand.append(null)
			await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE if mode=="strike" else CardData.CardSubType.DUEL)
		else:
			result=await game._deal_damage_result(null if mode=="sourceless" else source,victim,1,EffectChain.DamageType.PHYSICAL)
		if mode in ["forged","duplicate"]:
			t.check(result.invalidated and victim.hp==5 and d.hand_size()==1 and e.hand_size()==1 and actions.is_empty(),"I05 forged/duplicate exclusion cannot commit or charge responders: "+mode)
		else:
			var no_protector=mode=="all"
			var first=d if mode in ["decline","other","sourceless"] else e
			t.check(victim.hp==(4 if no_protector else 5),"I05 exclusion alters protection, not the original damage formula: "+mode)
			t.check(offers==[game.players[2],source] if no_protector else offers==([game.players[2],d] if first==d else [game.players[2],e]),"I05 Q48 original downstream order survives selected-player filtering: "+mode)
			if not no_protector: t.check(first.is_dead() if mode=="virtual" else first.hp==4,"I05 legal physical/virtual responder receives independent settlement: "+mode)
			t.check(d.hand_size()==(0 if first==d and not no_protector else 1),"I05 excluded D keeps its exact original resource")
			var counters=actions.filter(func(a): return a.sub_type==CardData.CardSubType.SACRIFICE)
			t.check(counters.size()==(0 if no_protector else 1) and actions.all(func(a): return a.settlement_completed),"I05 optional skill is not a card USE; legal original/Sacrifice facts complete")
			if original!=null: t.check(counters[0].card==original and game.deck._discard.count(original)==1,"I05 concrete Sacrifice remains the same original instance")
			if mode=="virtual": t.check(counters[0].is_virtual and not game.deck._discard.has(counters[0].card),"I05 paid virtual Sacrifice survives responder death, no fake physical card")
			if mode in ["other","sourceless"]: t.check(asks.is_empty(),"I05 observer Peter cannot ban another or unsourced damage")
		t.check(game._pending_card_actions.is_empty(),"I05 selected list retires with its damage response, no pending facts")
		await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t,game)
	await bridge_cases(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func bridge_cases(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var find=load("res://Test/i04_movement_cases.gd").new()
	for mode in ["partial","cancel","timeout","invalid"]:
		var bridge=LanGameBridge.new()
		bridge._enable_peter_rules_for_tests=true
		t.root.add_child(bridge)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":load("res://Test/i05_peter_peach_cases.gd").PETER if seat==0 else "稻草人"})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 actual source-controlled Bridge starts")
		var game=bridge.game
		game._peter_ignore_override=func(_p,_s,_k,_v): return 0
		game._halt_countdown()
		game._nullify_override=func(): return false
		game._duel_respond_override=func(): return false
		game._peter_peach_override=func(_p,_t,_v): return 0
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		game.players[0].hand.append(null)
		game.players[3].hand.append(null)
		game.players[4].hand.append(null)
		for text in ["出牌","锦囊牌","普通锦囊","决斗"]: await helper.click(t,bridge,0,text)
		await t.create_timer(0.15).timeout
		game._target_confirm_override=func(): return 1
		var target=bridge.snapshot(0).targets.get("1","")
		t.check(target!="" and bridge.submit(0,target),"I05 actual paid Duel reaches before-damage exclusion window")
		await helper.frames(t)
		await helper.click(t,bridge,0,"取消") # Decline the new pre-counter list, then test the original Sacrifice UI.
		var first=find.find(bridge.snapshot(0),"发动【关你屁事】")
		t.check(first!="" and not bridge.submit(3,first),"I05 only damage source owns optional skill confirmation")
		# Explicit already-spent budget boundary, not an accelerated game clock.
		game._step_remaining=7.0
		await helper.click(t,bridge,0,"发动【关你屁事】")
		t.check(game._step_remaining<=7.0 and game._step_remaining>0,"I05 Q10 selection carries remaining base countdown, no refreshed 30s")
		var view=bridge.snapshot(0)
		t.check(not view.controls.any(func(c): return c.text.begins_with("禁止：P0") or c.text.begins_with("禁止：P1")),"I05 actual list excludes damage source and victim")
		t.check(view.controls.any(func(c): return c.text.begins_with("禁止：P3") and "4号" in c.text),"I05 public fixed seat labels disambiguate participant choices")
		var old_confirm=find.find(view,"确认禁止名单")
		await helper.click(t,bridge,0,"禁止：P3")
		t.check(not bridge.submit(0,old_confirm),"I05 changed selection invalidates stale confirmation token")
		if mode=="invalid":
			game.turn_manager.current_phase=TurnManager.Phase.DRAW
			await helper.frames(t)
			t.check(game.players[1].hp==5 and game.players[0].hand_size()==0 and game.players[3].hand_size()==1 and game._pending_card_actions.is_empty(),"I05 stale selected list stops without refunding paid Duel or applying damage")
		else:
			if mode=="timeout": game._countdown_on_timeout.call()
			else: await helper.click(t,bridge,0,"确认禁止名单" if mode=="partial" else "取消")
			await helper.frames(t)
			var protector=4 if mode=="partial" else 3
			t.check(bridge.input_owner()==protector,"I05 only confirmed list changes actual Sacrifice priority: "+mode)
			await helper.click(t,bridge,protector,"舍己为人")
			# The transferred injury is independent. Source may decide again;
			# declining leaves the other protector legal in that new response.
			await helper.click(t,bridge,0,"取消")
			await helper.click(t,bridge,3 if protector==4 else 4,"放弃")
			t.check(game.players[1].hp==5 and game.players[protector].hp==4 and game.players[protector].hand_size()==0,"I05 paid Sacrifice transfers exactly one real damage")
			t.check(bridge.input_owner()==0 and game._pending_card_actions.is_empty() and not bridge.submit(0,first),"I05 completes both facts and returns original PLAY without reusable skill commands")
		game._game_over=true
		bridge.queue_free()
		await helper.frames(t)
