extends RefCounted
const Cards=preload("res://Test/i05_peter_card_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await duel(t)
	await iron_and_aoe(t)
	await judgments(t)
	await independent_cards(t)
	await invalid_selections(t)
	await virtual_and_payment_guards(t)
	await final_targets_and_region(t)
	await bridge(t)
	await judgment_bridge(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func duel(t):
	for ban in [false,true]:
		var game=Cards.new().fixture(t,5,2)
		game.players[3].hand.append(null)
		game.players[4].hand.append(null)
		var asks: Array=[]
		var responders: Array=[]
		var facts: Array=[]
		game.card_action_committed.connect(func(a): facts.append(a))
		game._peter_exclusion_override=func(owner,candidates,kind,valid):
			t.check(owner==game.players[2] and kind=="nullification" and valid.call() and not candidates.has(game.players[0]) and not candidates.has(game.players[1]),"I05 counter list protects original source/target before the first payment")
			t.check(game.players[0].hand_size()==0 and facts.size()==1,"I05 original Duel already paid, no counter paid before list confirmation")
			asks.append(kind)
			return [game.players[3]] if ban else []
		game._nullify_override=func():
			responders.append(game._input_seat)
			return game._input_seat in [3,4] and game.players[game._input_seat].hand_size()>0
		await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
		t.check(asks.size()==1 and game.players[3].hand_size()==(1 if ban else 0) and (not responders.has(3) if ban else responders.has(3)),"I05 selected D cannot receive or pay a counter; decline is not reasked on anti-counter")
		t.check(game.players[1].hp==(3 if ban else 2) and game.players[4].hand_size()==0,"I05 untouched counter parity: one counter cancels Duel, two restore it")
		t.check(facts.size()==(2 if ban else 3) and facts.all(func(a): return a.settlement_completed) and game._pending_card_actions.is_empty(),"I05 only original and physically paid counters produce completed facts")
		await Cards.new().dispose(t,game)

func iron_and_aoe(t):
	for ban in [false,true]:
		var game=Cards.new().fixture(t,5,3)
		game.players[4].hand.append(null)
		var asks: Array=[]
		game._peter_exclusion_override=func(_p,candidates,_kind,_valid):
			t.check(not candidates.has(game.players[0]) and not candidates.has(game.players[1]) and not candidates.has(game.players[2]),"I05 dual Iron protects every declared target, not only the current segment")
			asks.append(true)
			return [game.players[4]] if ban else []
		game._nullify_override=func(): return game._input_seat==4 and game.players[4].hand_size()>0
		var targets: Array[Player]=[game.players[1],game.players[2]]
		await game._execute_iron_chain(targets)
		t.check(asks.size()==1 and game.players[1].chained==ban and game.players[2].chained,"I05 Q19-b whole-card list or decline persists across both target segments without reprompt")
		t.check(game.players[4].hand_size()==(1 if ban else 0) and game._pending_card_actions.is_empty(),"I05 second segment cannot bypass the committed E exclusion")
		await Cards.new().dispose(t,game)
	var game=Cards.new().fixture(t)
	game.players[3].hand.append(null)
	var asks: Array=[]
	game._peter_exclusion_override=func(_p,_c,_k,_v): asks.append(true); return [game.players[3]]
	game._peter_ignore_override=func(_p,_s,_k,_v): return 0
	game._nullify_override=func(): return game._input_seat==3 and game.players[3].hand_size()>0
	await Cards.new().play(game,"aoe")
	t.check(asks.is_empty() and game.players[3].hand_size()==0 and game.players[1].hp==2,"I05 Q19-a all original AOE targets protected: D may counter for first Peter target")
	t.check(game.players[2].hp==2 and game.players[3].hp==2 and game.players[4].hp==2,"I05 original D counter does not remove later original targets from AOE")
	await Cards.new().dispose(t,game)

func judgments(t):
	for sub in [CardData.CardSubType.INDULGENCE,CardData.CardSubType.BURNING_CAMP]:
		for ban in [false,true]:
			var game=Cards.new().fixture(t,5,3)
			game.turn_manager.current_player_idx=1
			game.turn_manager.current_phase=TurnManager.Phase.JUDGE
			var holder=game.players[1]
			var original=CardBase.create(sub)
			original.source_seat=0
			holder.judgment_cards.append(original)
			var asks: Array=[]
			game._peter_exclusion_override=func(_p,candidates,kind,valid):
				asks.append(true)
				t.check(kind=="nullification" and valid.call() and candidates.has(game.players[0]) and not candidates.has(holder) and holder.judgment_cards.has(original) and holder.hp==3,"I05 Q20 current holder protected; original placing A can be banned before judgment")
				return [game.players[0]] if ban else []
			game._nullify_override=func(): return game._input_seat==0 and game.players[0].hand_size()>0
			t.check(await game._run_judgment(holder,false),"I05 actual judgment/counter chain completes")
			t.check(asks.size()==1 and game.players[0].hand_size()==(1 if ban else 0) and game.deck._discard.count(original)==1,"I05 delayed original placing actor is filtered before physical counter payment")
			if sub==CardData.CardSubType.BURNING_CAMP:
				t.check(holder.hp==(2 if ban else 3) and game._has_delayed_card(game.players[0],sub)==ban,"I05 Fire judgment applies only after list and counter chain; ordinary spread unchanged")
			else: t.check(game.turn_manager.skip_play_phase==ban,"I05 delayed LE uses same holder-only response protection")
			await Cards.new().dispose(t,game)

func independent_cards(t):
	var game=Cards.new().fixture(t,5,2)
	game.players[0].hand.append(null)
	game.players[3].hand.append(null)
	var asks: Array=[]
	game._peter_exclusion_override=func(_p,_c,_k,_v):
		asks.append(true)
		return [game.players[3]] if asks.size()==1 else []
	game._nullify_override=func(): return game._input_seat==3 and game.players[3].hand_size()>0
	await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
	await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
	t.check(asks.size()==2 and game.players[1].hp==2 and game.players[3].hand_size()==0,"I05 fresh second original card gets an independent list, never inherits the first ban")
	t.check(game.players[0].hand_size()==0 and game._pending_card_actions.is_empty(),"I05 repeated original actions retain ordinary quotas and one payment each")
	await Cards.new().dispose(t,game)

func invalid_selections(t):
	for mode in ["source","target","duplicate","phase","reset"]:
		var game=Cards.new().fixture(t,5,2)
		game.players[3].hand.append(null)
		game._peter_exclusion_override=func(_p,_c,_k,_v):
			match mode:
				"source": return [game.players[0]]
				"target": return [game.players[1]]
				"duplicate": return [game.players[3],game.players[3]]
				"phase": game.turn_manager.current_phase=TurnManager.Phase.START
				"reset": game.players[2].awakening_revision+=1
			return [game.players[3]]
		await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
		t.check(game.players[0].hand_size()==0 and game.players[1].hp==3 and game.players[3].hand_size()==1 and game._pending_card_actions.is_empty(),"I05 invalid counter list abandons continuation, no refund or forbidden payment: "+mode)
		await Cards.new().dispose(t,game)

func bridge(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var finder=load("res://Test/i04_movement_cases.gd").new()
	for choice in ["accept","cancel","timeout"]:
		var b=LanGameBridge.new()
		b._enable_peter_rules_for_tests=true
		t.root.add_child(b)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":Cards.PETER if seat==2 else "稻草人"})
		t.check(b.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 counter native Bridge starts")
		var game=b.game
		game._halt_countdown()
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		for seat in [0,3,4]: game.players[seat].hand.append(null)
		game._duel_respond_override=func(): return false
		game._sacrifice_actor_override=func(_p,_t,_a): return false
		game._target_confirm_override=func(): return 1
		game._nullify_override=func(): return game._input_seat in [3,4] and game.players[game._input_seat].hand_size()>0
		for label in ["出牌","锦囊牌","普通锦囊","决斗"]: await helper.click(t,b,0,label)
		await t.create_timer(0.15).timeout
		var target=b.snapshot(0).targets.get("1","")
		t.check(target!="" and b.submit(0,target),"I05 actual paid Duel opens Peter before the first counter")
		await helper.frames(t)
		var old=finder.find(b.snapshot(2),"发动【关你屁事】")
		t.check(old!="" and b.input_owner()==2 and not b.submit(0,old),"I05 only Peter owns pre-counter selection")
		if choice=="timeout": game._countdown_on_timeout.call()
		elif choice=="cancel": await helper.click(t,b,2,"取消")
		else:
			game._step_remaining=7.0
			await helper.click(t,b,2,"发动【关你屁事】")
			t.check(game._step_remaining<=7.0 and game._step_remaining>0,"I05 counter selection inherits one remaining base budget")
			var view=b.snapshot(2)
			t.check(not view.controls.any(func(c): return c.text.begins_with("禁止：P0") or c.text.begins_with("禁止：P1")),"I05 actual list excludes source and original target")
			var stale=finder.find(view,"确认禁止名单")
			await helper.click(t,b,2,"禁止：P3")
			t.check(not b.submit(2,stale),"I05 changed counter list rejects old confirm token")
			await helper.click(t,b,2,"确认禁止名单")
		await helper.frames(t)
		t.check(game.players[1].hp==(5 if choice=="accept" else 4) and game.players[3].hand_size()==(1 if choice=="accept" else 0) and game.players[4].hand_size()==0,"I05 real counter selection controls legal payments and original parity")
		t.check(b.input_owner()==0 and not b.submit(2,old) and game._pending_card_actions.is_empty(),"I05 counter skill returns source PLAY, old token cannot replay")
		game._game_over=true
		b.queue_free()
		await helper.frames(t)

func judgment_bridge(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var finder=load("res://Test/i04_movement_cases.gd").new()
	var b=LanGameBridge.new()
	b._enable_peter_rules_for_tests=true
	t.root.add_child(b)
	var roster: Array[Dictionary]=[]
	for seat in 5: roster.append({"name":"P%d"%seat,"general":Cards.PETER if seat==2 else "稻草人"})
	t.check(b.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 fire judgment native Bridge starts")
	var game=b.game
	game._halt_countdown()
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game.players[0].hand.append(null)
	var original=CardBase.create(CardData.CardSubType.BURNING_CAMP)
	original.source_seat=0
	game.players[1].judgment_cards.append(original)
	game._nullify_override=func(): return game._input_seat==0 and game.players[0].hand_size()>0
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	await helper.click(t,b,0,"结束出牌")
	t.check(game.turn_manager.current_phase==TurnManager.Phase.JUDGE and game.players[1].hp==5 and game.players[1].judgment_cards.has(original),"I05 Q20-b normal START enters JUDGE and pauses before original fire")
	await helper.click(t,b,2,"发动【关你屁事】")
	t.check(not b.snapshot(2).controls.any(func(c): return c.text.begins_with("禁止：P1")),"I05 Q20-b judged B cannot be banned")
	await helper.click(t,b,2,"禁止：P0")
	await helper.click(t,b,2,"确认禁止名单")
	await helper.frames(t)
	t.check(game.players[0].hand_size()==1 and game.players[1].hp==4 and game.players[2].hp==2,"I05 Q20-b original placing A cannot counter; Fire then hurts center and ordinary neighbors")
	t.check(b.input_owner()==1 and game.turn_manager.current_phase==TurnManager.Phase.PLAY and game.players[2].judgment_cards.size()==1,"I05 Q20-b actual judgment continues to B PLAY, future spread remains a new pending judgment")
	game._game_over=true
	b.queue_free()
	await helper.frames(t)

func virtual_and_payment_guards(t):
	for ban in [false,true]:
		var game=Cards.new().fixture(t,5,2)
		var ampiti=game.players[3]
		ampiti.general_name="安普提·斯丢皮得"
		ampiti.hp=1
		game._peter_ignore_override=func(_p,_s,_k,_v): return 0
		game._peter_exclusion_override=func(_p,_c,_k,_v): return [ampiti] if ban else []
		var offered: Array=[]
		var facts: Array=[]
		game.card_action_committed.connect(func(a): facts.append(a))
		game._nullify_override=func(): offered.append(game._input_seat); return game._input_seat==3
		game._yes_ah_override=func(): return "skill"
		game._rps_override=func(p): return GameManager.RPS_ROCK if p==ampiti else GameManager.RPS_PAPER
		await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
		t.check(ampiti.hp==(1 if ban else 0) and ampiti.is_dead()==not ban and offered.has(3)==not ban,"I05 excluded virtual responder gets no skill menu or life fee; allowed paid virtual counter survives death")
		t.check(game.players[1].hp==(2 if ban else 3) and facts.size()==(1 if ban else 2) and facts.all(func(a): return a.settlement_completed),"I05 physical/virtual original parity and completion remain unchanged by pre-counter scope")
		await Cards.new().dispose(t,game)
	var game=Cards.new().fixture(t,5,2)
	game.players[0].hand.clear()
	game.players[3].hand.append(null)
	var targets: Array[Player]=[game.players[1]]
	var trick=game._new_peter_trick_scope(game.players[0],targets)
	trick.asked=true
	game._nullify_override=func():
		if game._input_seat!=3: return false
		# Permission mutation is a fault-injection boundary, not a new game rule.
		trick.excluded.append(game.players[3])
		return true
	var result=await game._ask_nullification_chain_result("permission boundary",Callable(),game.players[0],game.players[1],trick)
	t.check(result==GameManager.NullificationOutcome.INVALIDATED and game.players[3].hand_size()==1 and game._pending_card_actions.is_empty(),"I05 permission is revalidated after intention, before actual card payment")
	await Cards.new().dispose(t,game)

func final_targets_and_region(t):
	var game=Cards.new().fixture(t,5,2)
	var leo=game.players[3]
	leo.general_name="里奥·普利威尔"
	leo.prep_tokens=1
	game.players[4].hand.append(null)
	game._prep_replace_override=func(_p,_a,_t,_sub,_options): return CardData.CardSubType.BARBARIAN_INVASION
	var asks: Array=[]
	game._peter_exclusion_override=func(_p,_c,_k,_v): asks.append(true); return [game.players[4]]
	game._peter_ignore_override=func(_p,_s,_k,_v): return 0
	game._nullify_override=func(): return game._input_seat==4 and game.players[4].hand_size()>0
	var facts: Array=[]
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
	t.check(asks.is_empty() and game.players[4].hand_size()==0 and game.players[1].hp==3 and game.players[2].hp==1,"I05 PREP final AOE protects expanded original target E, not raw Duel's singleton only")
	t.check(facts.size()==2 and facts[0].sub_type==CardData.CardSubType.DUEL and leo.prep_tokens==0,"I05 scope uses final effect audience but preserves paid original card and marker timing")
	await Cards.new().dispose(t,game)
	game=Cards.new().fixture(t,5,4)
	var weapon=CardBase.create(CardData.CardSubType.LIANNU)
	game.players[1].equip_card_to_slot("weapon",weapon)
	game._borrowed_second_target_override=func(options): return options.find(game.players[2])
	game._borrowed_strike_override=func(_p,_t,_o): return -1
	var offered: Array=[]
	game._peter_exclusion_override=func(_p,candidates,_k,_v):
		offered.append(true)
		t.check(not candidates.has(game.players[0]) and not candidates.has(game.players[1]) and not candidates.has(game.players[2]),"I05 Borrowed protects its source and both explicitly selected original target roles")
		return []
	await game.execute_card_on_target(game.players[1],CardData.CardSubType.BORROWED_SWORD)
	t.check(offered.size()==1 and game.players[0].determined_cards.has(weapon),"I05 Borrowed's immunity exception does not erase original counter protection or weapon transfer")
	await Cards.new().dispose(t,game)
	game=Cards.new().fixture(t,6,0)
	load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,2)
	game.players[1].hand.assign([null])
	game.players[3].hand.append(null)
	asks=[]
	game._peter_exclusion_override=func(_p,_c,_k,_v): asks.append(true); return []
	game._nullify_override=func(): return game._input_seat==3 and game.players[3].hand_size()>0
	await game.execute_card_on_target(game.players[2],CardData.CardSubType.DUEL)
	t.check(asks.is_empty() and game.players[3].hand_size()==0 and game.players[2].hp==3,"I05 opposite-region observer Peter cannot open an interference window for same-region Duel")
	await Cards.new().dispose(t,game)
