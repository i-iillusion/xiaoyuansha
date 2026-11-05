extends RefCounted

const Cards = preload("res://Test/i05_peter_card_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await zhuangbi(t)
	await zhuangbi_bridge(t)
	await yudaxi(t)
	await swap_and_gay(t)
	await zhuangsha(t)
	await medicine_and_gather(t)
	await chain_damage(t)
	await burning_camp(t)
	await paid_skill_bridge(t)
	await card_partitions(t)
	await granted_play(t)
	await invalid_choices(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func zhuangbi(t):
	for n in [1,2,3]:
		for immune in [false,true]:
			var game=Cards.new().fixture(t)
			game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
			game.turn_manager.current_phase=TurnManager.Phase.PLAY
			game._set_input_player(game.players[0])
			var source=game.players[0]
			source.general_name="史蒂芬·彼特先斯"
			source.awoken=true
			source.hand.assign([null,null])
			var original=CardBase.create(CardData.CardSubType.DODGE)
			game.players[1].determined_cards.append(original)
			var targets: Array[Player]=[game.players[1]]
			for seat in range(2,n+1):
				game.players[seat].hand.append(null)
				targets.append(game.players[seat])
			var asks: Array=[]
			var punches: Array=[]
			var fees: Array=[]
			game._hand_discard_override=func(snapshot,count,_mandatory):
				fees.append(snapshot)
				return snapshot.defaults(count)
			game._peter_ignore_override=func(p,audience,tag,valid):
				asks.append(p)
				t.check(tag=="zhuangbi" and audience==targets and valid.call() and p.hand_size()==1,"I05 Q13 immunity precedes Peter's fee and retains original audience")
				return 1 if immune else 0
			game._rps_override=func(p):
				punches.append(p)
				return GameManager.RPS_ROCK if p==source else (GameManager.RPS_SCISSORS if p==game.players[2] else GameManager.RPS_PAPER)
			game._zhuangbi_again_override=func(): return false
			await game._execute_zhuangbi(targets)
			var skipped=immune and n>1
			t.check(asks.size()==(1 if n>1 else 0) and game.players[1].hand_size()==(1 if skipped else 0),"I05 Q13 only genuinely multi-target Zhuangbi can skip Peter's mandatory fee")
			t.check(fees.size()==n+1-(1 if skipped else 0) and punches.has(game.players[1])==not skipped,"I05 Q13 immune target neither pays nor punches, source pays exactly once")
			t.check(game.deck._discard.count(original)==(0 if skipped else 1),"I05 Q13 concrete Peter card retained on immunity, original discarded otherwise")
			if n>1:
				t.check(game.players[2].hp==(2 if skipped or n==2 else 3),"I05 Q13 success denominator excludes Peter: one win of two succeeds, one of three fails")
			t.check(source.hand_size()==1 and game._zhuangbi_execution_owner==-1 and game._choice_prompt_stack.is_empty(),"I05 Q13 no refunded source fee or retained execution lock")
			await Cards.new().dispose(t,game)

func card_partitions(t):
	for across in [false,true]:
		var game=Cards.new().fixture(t,6,0 if across else 2)
		load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,2)
		for body in game.players: body.hp=4
		game._aoe_override=func(): return false
		var source=game.players[1]
		source.hand.assign([null])
		var owner=game.players[0 if across else 2]
		owner.general_name=Cards.PETER
		owner.hp=2
		var asks: Array=[]
		game._peter_ignore_override=func(p,scope,_tag,_v): asks.append(p); t.check(scope.size()==5,"I05 mountain filtering does not shrink original declaration"); return 1
		await Cards.new().play(game,"aoe")
		t.check(asks.size()==(0 if across else 1) and owner.hp==2,"I05 cross-mountain Peter is not prompted; same-region Peter can ignore AOE")
		t.check(game.players[3].hp==3 and source.hand_size()==0 and game._pending_card_actions.is_empty(),"I05 multi immunity preserves same-region others and actual paid card completion")
		await Cards.new().dispose(t,game)

func granted_play(t):
	var game=Cards.new().fixture(t)
	var source=game.players[0]
	var actor=game.players[2]
	source.general_name="麦克斯·欧尼斯特"
	actor.hand.assign([null])
	game.turn_manager.current_phase=TurnManager.Phase.START
	game._aoe_override=func(): return false
	game._meiyong_override=func(): return true
	game._meiyong_option_override=func(): return 2
	game._meiyong_target_override=func(): return actor
	var facts: Array=[]
	game.card_action_committed.connect(func(a): facts.append(a))
	game._peter_ignore_override=func(_p,_s,_k,_v): return 1
	var action=func():
		t.check(game._play_actor()==actor and game.turn_manager.current_phase==TurnManager.Phase.PLAY,"I05 granted PLAY uses actual recipient as paid card actor")
		await Cards.new().play(game,"aoe")
		t.check(game.players[1].hp==2 and game.players[3].hp==2 and facts.size()==1 and facts[0].actor_body==actor,"I05 immunity applies within actual gifted PLAY, not to gifting source's imaginary card")
		game.end_play_phase()
	action.call_deferred()
	await game._maybe_meiyong(source)
	t.check(game.turn_manager.current_phase==TurnManager.Phase.START and game.turn_manager.current_player_idx==0 and game._meiyong_execution_owner==-1 and game._pending_card_actions.is_empty(),"I05 gifted immunity settles and returns to original START")
	await Cards.new().dispose(t,game)

func invalid_choices(t):
	for mode in ["restart","phase","reset","disabled","registry","invalid_reply"]:
		var game=Cards.new().fixture(t)
		var actor=game.players[0]
		var target=game.players[1]
		game._peter_ignore_override=func(_p,_s,_k,_valid):
			match mode:
				"restart": game._dying_lifecycle_generation+=1
				"phase": game.turn_manager.current_phase=TurnManager.Phase.START
				"reset": target.awakening_revision+=1
				"disabled": game._peter_rules_enabled=false
				"registry": game.unit_registry.reset()
			return 123 if mode=="invalid_reply" else 1
		await Cards.new().play(game,"aoe")
		t.check(target.hp==2 and game.players[2].hp==3 and actor.hand_size()==0 and game._pending_card_actions.is_empty(),"I05 stale immune reply abandons continuation without refund or subsequent target damage: "+mode)
		t.check(game._choice_prompt_stack.is_empty(),"I05 stale immune reply leaves no input lease: "+mode)
		await Cards.new().dispose(t,game)

func yudaxi(t):
	var game=Cards.new().fixture(t)
	var leo=game.players[0]
	leo.general_name="里奥·普利威尔"
	leo.hand.clear()
	leo.hp=0
	for seat in [2,3,4]: game.players[seat].hp=5
	var asks: Array=[]
	game._peter_ignore_override=func(_p,_s,_k,_v): asks.append(true); return 1
	await game._resolve_dying(leo,null,"damage")
	t.check(asks.is_empty() and game.players[1].is_dead() and leo.hp==1,"I05 Q15 Yudaxi deducts Peter's two HP without offering ordinary multi-effect immunity")
	t.check(game.yudaxi.results.size()==1 and game.yudaxi.results[0].deaths==1 and game._dying_contexts.is_empty(),"I05 Q15 Peter's final death counts normally for Leo; no stale dying frame")
	await Cards.new().dispose(t,game)

func zhuangbi_bridge(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var finder=load("res://Test/i04_movement_cases.gd").new()
	for choice in ["accept","cancel","timeout"]:
		var bridge=LanGameBridge.new()
		bridge._enable_peter_rules_for_tests=true
		t.root.add_child(bridge)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":"史蒂芬·彼特先斯" if seat==0 else (Cards.PETER if seat==1 else "稻草人")})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 Q13 actual Bridge roster starts")
		var game=bridge.game
		game._halt_countdown()
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		game.players[0].awoken=true
		game.players[0].hand.assign([null,null])
		var fee=CardBase.create(CardData.CardSubType.DODGE)
		game.players[1].determined_cards.append(fee)
		game.players[2].hand.append(null)
		game._hand_discard_override=func(snapshot,count,_mandatory): return snapshot.defaults(count)
		game._rps_override=func(p): return GameManager.RPS_ROCK if p==game.players[0] else (GameManager.RPS_PAPER if p==game.players[1] else GameManager.RPS_SCISSORS)
		game._zhuangbi_again_override=func(): return false
		game._sacrifice_actor_override=func(_p,_t,_a): return false
		var inspect=bridge.snapshot(0).targets.get("0","")
		t.check(inspect!="" and bridge.submit(0,inspect),"I05 Q13 opens actor's actual details")
		await helper.frames(t)
		await helper.click(t,bridge,0,"装逼")
		for seat in [1,2]:
			var token=bridge.snapshot(0).targets.get(str(seat),"")
			t.check(token!="" and bridge.submit(0,token),"I05 Q13 selects actual original target by Bridge token")
			await helper.frames(t)
		await helper.click(t,bridge,0,"确认装逼")
		var token=finder.find(bridge.snapshot(1),"免除此效果")
		t.check(token!="" and bridge.input_owner()==1 and not bridge.submit(0,token) and game.players[0].hand_size()==1 and game.players[1].hand_size()==1,"I05 Q13 Peter owns immunity after source fee, before mandatory recipient fees")
		if choice=="timeout": game._countdown_on_timeout.call()
		else: await helper.click(t,bridge,1,"免除此效果" if choice=="accept" else "取消")
		await helper.frames(t)
		t.check(game.players[1].hand_size()==(1 if choice=="accept" else 0) and game.deck._discard.count(fee)==(0 if choice=="accept" else 1),"I05 Q13 native confirmation or decline controls the original concrete fee")
		t.check(game.players[2].hp==4 and game.players[2].hand_size()==0 and bridge.input_owner()==0 and game._zhuangbi_execution_owner==-1 and not bridge.submit(1,token),"I05 Q13 real settlement preserves other target, restores PLAY and rejects old immunity token")
		game._game_over=true
		bridge.queue_free()
		await helper.frames(t)

func swap_and_gay(t):
	for kind in ["swap","empty_swap","gay"]:
		for accepted in [false,true]:
			var game=Cards.new().fixture(t)
			var source=game.players[0]
			var target=game.players[1]
			source.general_name="比尔·盖伊" if kind=="gay" else "麦克斯·欧尼斯特"
			source.hp=2
			source.gender=target.gender
			game._hand_discard_override=func(snapshot,count,_m): return snapshot.defaults(count)
			var first=CardBase.create(CardData.CardSubType.LIANNU)
			var second=CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			target.equip_card_to_slot("weapon",first)
			if kind!="empty_swap": game.players[2].equip_card_to_slot("weapon",second)
			var asked: Array=[]
			game._peter_ignore_override=func(_p,audience,tag,valid):
				asked.append(tag)
				t.check(source.hand_size()==0 and audience.size()==2 and audience.has(target) and valid.call(),"I05 Q14/Q16 optional immunity follows actual skill payment")
				return 1 if accepted else 0
			if kind=="gay":
				game._gay_x_override=func(): return 1
				await game._execute_gay(source,target)
				t.check(source.hp==3 and target.hp==(2 if accepted else 3) and game._gay_used and game._gay_execution_owner==-1,"I05 Q16 refusal only suppresses Peter healing, caster heals and phase use is consumed")
			else:
				var zones: Array=["weapon","done"]
				game._lanzhonghou_zone_override=func(): return zones.pop_front()
				await game._run_lanzhonghou(target,game.players[2])
				t.check(target.get_equipment_card("weapon")== (first if accepted else (null if kind=="empty_swap" else second)) and game.players[2].get_equipment_card("weapon")== (null if accepted and kind=="empty_swap" else (second if accepted else first)),"I05 Q14 immunity preserves both original slots atomically, including an empty slot")
				t.check(game._lanzhonghou_used and game._lanzhonghou_execution_owner==-1 and game._lanzhonghou_pending.is_empty(),"I05 Q14 paid skill use remains consumed, swap ownership released")
			t.check(asked.size()==1 and source.hand_size()==0 and game._pending_card_actions.is_empty(),"I05 paid skill immunity never refunds its fee or creates a card-use receipt")
			await Cards.new().dispose(t,game)

func zhuangsha(t):
	for accepted in [false,true]:
		var game=Cards.new().fixture(t,6)
		var victim=game.players[0]
		victim.general_name="安普提·斯丢皮得"
		victim.hp=1
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		var punched: Array=[]
		game._peter_ignore_override=func(_p,audience,tag,valid):
			t.check(tag=="zhuangsha" and audience.size()==5 and valid.call(),"I05 Q17 original opponent audience stays fixed during optional refusal")
			return 1 if accepted else 0
		game._rps_override=func(p):
			punched.append(p)
			return GameManager.RPS_ROCK if p==victim else (GameManager.RPS_SCISSORS if p.seat_index in [2,3] else GameManager.RPS_PAPER)
		await game._deal_damage_result(game.players[5],victim,1,EffectChain.DamageType.PHYSICAL)
		t.check(punched.has(game.players[1])==not accepted and victim.is_alive()==accepted,"I05 Q17 refused Peter never punches or counts: 2/4 saves, 2/5 fails")
		t.check(victim.hp==(1 if accepted else 0) and game._dying_contexts.is_empty(),"I05 Q17 genuine dying resolution finishes without leaking rescue state")
		await Cards.new().dispose(t,game)

func medicine_and_gather(t):
	for kind in ["medicine","gather"]:
		var game=Cards.new().fixture(t)
		if kind=="medicine":
			game.players[0].general_name="克里斯·西弗"
			game.turn_manager.current_phase=TurnManager.Phase.DRAW
			game.players[1].hand.append(null)
			game.players[2].hand.append(null)
			game._medicine_choice_override=func(_p,_options): return [game.players[1],game.players[2]]
		else:
			game.players[0].general_name="吉姆·芒顿"
			game._spawn_mountain_at(game.players[0],1,2)
			game._spawn_mountain_at(game.players[0],4,0)
			game._jim_gather_choice_override=func(_p,options,_valid): return options.find("heal")
			game._hand_discard_override=func(snapshot,count,_m): return snapshot.defaults(count)
		var asked: Array=[]
		game._peter_ignore_override=func(_p,audience,tag,_v): asked.append(tag); t.check(audience.size()==2,"I05 remaining paid multi-skills retain declared target pair"); return 1
		if kind=="medicine":
			var result=await game._maybe_steal_medicine(game.players[0])
			t.check(result==1 and game.players[0].hand_size()==2 and game.players[1].hand_size()==1 and game.players[2].hand_size()==0,"I05 Peter refuses dual medicine theft; other transfer and replaced-draw cost remain")
		else:
			var result=await game._activate_jushan(game.players[0])
			t.check(result==1 and game.players[0].hp==4 and game.players[1].hp==2 and game.players[2].hp==3 and game.players[0].hand_size()==0,"I05 Gather immunity only skips Peter; caster's payment and other recipient heal remain")
		t.check(asked.size()==1 and game._pending_card_actions.is_empty(),"I05 remaining multi-skills do not create synthetic card facts")
		await Cards.new().dispose(t,game)

func chain_damage(t):
	for sub in [CardData.CardSubType.FIRE_STRIKE,CardData.CardSubType.THUNDER_STRIKE]:
		var game=Cards.new().fixture(t)
		game.players[0].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
		for seat in [1,2,3]: game.players[seat].chained=true
		var asks: Array=[]
		game._peter_ignore_override=func(_p,_s,_k,_v): asks.append(true); return 1
		await game.execute_card_on_target(game.players[2],sub)
		t.check(asks.is_empty() and game.players[1].hp==1 and game.players[2].hp==2 and game.players[3].hp==2,"I05 Q18 paid single-target elemental Strike never offers immunity to existing chain damage")
		t.check(not game.players[1].chained and not game.players[2].chained and not game.players[3].chained and game.players[0].hand_size()==0,"I05 Q18 ordinary propagation consumes links and original paid card once")
		await Cards.new().dispose(t,game)

func burning_camp(t):
	for center_seat in [0,1]:
		var game=Cards.new().fixture(t)
		for p in game.players: p.hand.clear()
		var center=game.players[center_seat]
		var original=CardBase.create(CardData.CardSubType.BURNING_CAMP)
		original.source_seat=2
		center.judgment_cards.append(original)
		var asks: Array=[]
		game._peter_ignore_override=func(_p,_s,_k,_v): asks.append(true); return 1
		t.check(await game._run_judgment(center,false),"I05 Q22 actual original Burning Camp judgment completes")
		t.check(asks.is_empty() and game.players[1].hp==1 and game.deck._discard.count(original)==1,"I05 Q22 single-target delayed card offers no immunity to center or adjacent Peter")
		t.check(game._has_delayed_card(game.players[1 if center_seat==0 else 2],CardData.CardSubType.BURNING_CAMP),"I05 Q22 original fire still generates its ordinary neighbor judgment card")
		await Cards.new().dispose(t,game)

func paid_skill_bridge(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var finder=load("res://Test/i04_movement_cases.gd").new()
	for kind in ["swap","gay"]:
		for accepted in [false,true]:
			var bridge=LanGameBridge.new()
			bridge._enable_peter_rules_for_tests=true
			t.root.add_child(bridge)
			var roster: Array[Dictionary]=[]
			for seat in 5: roster.append({"name":"P%d"%seat,"general":("麦克斯·欧尼斯特" if kind=="swap" else "比尔·盖伊") if seat==0 else (Cards.PETER if seat==1 else "稻草人")})
			t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 actual paid skill Bridge starts: "+kind)
			# Both real generals have an optional START skill; decline it normally.
			await helper.click(t,bridge,0,"取消")
			var game=bridge.game
			game._halt_countdown()
			for p in game.players: p.hand.clear(); p.determined_cards.clear()
			var source=game.players[0]
			var target=game.players[1]
			source.hand.append(null)
			source.hp=2
			target.hp=2
			target.gender=source.gender
			game._hand_discard_override=func(snapshot,count,_m): return snapshot.defaults(count)
			game._gay_x_override=func(): return 1
			var zones: Array=["weapon","done"]
			game._lanzhonghou_zone_override=func(): return zones.pop_front()
			var weapon=CardBase.create(CardData.CardSubType.LIANNU)
			target.equip_card_to_slot("weapon",weapon)
			var inspect=bridge.snapshot(0).targets.get("0","")
			t.check(inspect!="" and bridge.submit(0,inspect),"I05 paid skills open actual details")
			await helper.frames(t)
			await helper.click(t,bridge,0,"没用" if kind=="swap" else "Gay")
			for seat in ([1,2] if kind=="swap" else [1]):
				var token=bridge.snapshot(0).targets.get(str(seat),"")
				t.check(token!="" and bridge.submit(0,token),"I05 paid skill selects original target with actual Bridge token")
				await helper.frames(t)
			var token=finder.find(bridge.snapshot(1),"免除此效果")
			t.check(token!="" and bridge.input_owner()==1 and source.hand_size()==0 and not bridge.submit(0,token),"I05 paid skill immunization belongs to Peter after actual fee")
			await helper.click(t,bridge,1,"免除此效果" if accepted else "取消")
			await helper.frames(t)
			if kind=="swap":
				t.check(target.get_equipment_card("weapon")== (weapon if accepted else null) and game.players[2].get_equipment_card("weapon")== (null if accepted else weapon),"I05 real swap immunity preserves both slots or completes original transfer")
			else:
				t.check(source.hp==3 and target.hp==(2 if accepted else 3),"I05 real Gay immunity preserves caster healing only")
			t.check(bridge.input_owner()==0 and not bridge.submit(1,token) and game._choice_prompt_stack.is_empty(),"I05 paid skill returns source PLAY and refuses stale immunity token")
			game._game_over=true
			bridge.queue_free()
			await helper.frames(t)
