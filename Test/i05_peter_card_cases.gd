extends RefCounted
const PETER="彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹"

func fixture(t,count:=5,owner:=1):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,count,GameModes.FREE_FOR_ALL)
	game.lan_enabled=true
	game._peter_rules_enabled=true
	game._peter_exclusion_override=func(_p,_c,_k,_v): return []
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._nullify_override=func(): return false
	game._duel_respond_override=func(): return false
	for body in game.players:
		body.hand.clear()
		body.determined_cards.clear()
		body.hp=3
	game.players[owner].general_name=PETER
	game.players[owner].max_hp=3
	game.players[owner].hp=2
	game.players[0].hand.append(null)
	return game

func dispose(t,game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t,game)

func play(game,kind):
	match kind:
		"aoe": await game._play_aoe(CardData.CardSubType.STRIKE,"南蛮入侵","杀")
		"volley": await game._play_aoe(CardData.CardSubType.DODGE,"万箭齐发","闪")
		"garden": await game._play_peach_garden()
		"harvest": await game._play_harvest()
		"disarm": await game._play_disarm()

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for count in [2,5]:
		for kind in ["aoe","volley","garden","harvest","disarm"]:
			for accepted in [false,true]:
				var game=fixture(t,count)
				var owner=game.players[1]
				var asks: Array=[]
				var actions: Array=[]
				game.card_action_committed.connect(func(a): actions.append(a))
				game._peter_ignore_override=func(p,audience,_kind,valid):
					asks.append(audience.duplicate())
					t.check(p==owner and audience.has(owner) and audience.size()==(count-1 if kind in ["aoe","volley"] else count) and valid.call(),"I05 original declared audience survives per-target processing: %s/%d"%[kind,count])
					return 1 if accepted else 0
				if kind=="disarm":
					for p in game.players: p.equip_card_to_slot("mount_1",CardBase.create(CardData.CardSubType.MOUNT_PLUS))
				await play(game,kind)
				var immune=accepted and (count>2 or kind not in ["aoe","volley"])
				t.check(asks.size()==(0 if count==2 and kind in ["aoe","volley"] else 1),"I05 one-target South/Volley never opens immunity, two-target Garden does")
				if kind in ["aoe","volley"]: t.check(owner.hp==(2 if immune else 1),"I05 only own damage is skipped; singleton still hurts")
				if kind=="garden": t.check(owner.hp==(2 if immune else 3) and game.players[0].hp==4,"I05 refusing own Garden never cancels source healing")
				if kind=="harvest": t.check(owner.hand_size()==(0 if immune else 1) and game.players[0].hand_size()==2,"I05 refusing Harvest never cancels others' draw")
				if kind=="disarm": t.check(owner.get_equip_slots().size()==(1 if immune else 0) and owner.hand_size()==(0 if immune else 1),"I05 immunity prevents equipment loss and replacement draw together")
				t.check(actions.size()==1 and actions[0].settlement_completed and game.deck._discard.has(actions[0].card) and game._pending_card_actions.is_empty(),"I05 original entity paid once; skill never creates a second card fact")
				await dispose(t,game)
	await chains_and_strikes(t)
	await own_groups(t)
	await borrowed(t)
	await replacement_and_retired_source(t)
	await bridge(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func chains_and_strikes(t):
	for kind in ["iron","strike"]:
		for count in [1,2]:
			var game=fixture(t)
			var owner=game.players[1]
			var other=game.players[2]
			var asked: Array=[]
			game._peter_ignore_override=func(_p,scope,_k,_v): asked.append(scope.size()); return 1
			var targets: Array[Player]=[owner]
			if count==2: targets.append(other)
			if kind=="iron": await game._execute_iron_chain(targets)
			else:
				if count==2:
					game.players[0].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
					await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
				else: await game.execute_card_on_target(owner,CardData.CardSubType.STRIKE)
			t.check(asked==([2] if count==2 else []),"I05 card audience is explicit for original single/multi Iron/Strike")
			t.check((not owner.chained if count==2 else owner.chained) if kind=="iron" else owner.hp==(2 if count==2 else 1),"I05 multi immunity suppresses only own actual effect")
			if count==2: t.check(other.chained if kind=="iron" else other.hp==2,"I05 other original target still resolves normally")
			t.check(game.players[0].hand_size()==0 and game._pending_card_actions.is_empty(),"I05 no refunded source card or pending frame after immunity")
			await dispose(t,game)

func own_groups(t):
	for kind in ["garden","harvest"]:
		var game=fixture(t,5,0)
		game._peter_ignore_override=func(_p,_s,_k,_v): return 0
		game._peter_exclusion_override=func(owner,candidates,tag,valid):
			t.check(owner==game.players[0] and not candidates.has(owner) and valid.call() and tag in ["peach_garden","harvest"],"I05 Q11 owner may select other declared targets only")
			return [game.players[1],game.players[3]]
		await play(game,kind)
		for seat in range(1,5):
			var skipped=seat in [1,3]
			t.check((game.players[seat].hp==(3 if skipped else 4)) if kind=="garden" else game.players[seat].hand_size()==(0 if skipped else 2),"I05 Q11 only chosen B/D lose effect, C/E still resolve")
		t.check(game.players[0].hp==3 if kind=="garden" else game.players[0].hand_size()==1,"I05 owner's own Garden/Harvest benefit remains")
		await dispose(t,game)

func borrowed(t):
	var game=fixture(t)
	var first=game.players[1]
	var weapon=CardBase.create(CardData.CardSubType.LIANNU)
	first.equip_card_to_slot("weapon",weapon)
	var asks: Array=[]
	game._peter_ignore_override=func(_p,_s,_k,_v): asks.append(true); return 1
	game._borrowed_second_target_override=func(options): return options.find(game.players[2])
	game._borrowed_strike_override=func(_p,_t,_o): return -1
	await game.execute_card_on_target(first,CardData.CardSubType.BORROWED_SWORD)
	t.check(asks.is_empty() and first.get_weapon()==-1 and game.players[0].determined_cards.has(weapon),"I05 Q4 Borrow itself cannot be immunized because a second target was chosen")
	await dispose(t,game)

func bridge(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	var find=load("res://Test/i04_movement_cases.gd").new()
	for choice in ["accept","cancel","timeout"]:
		var bridge=LanGameBridge.new()
		bridge._enable_peter_rules_for_tests=true
		t.root.add_child(bridge)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":PETER if seat==1 else "稻草人"})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 native response windows remain actual Bridge-controlled")
		var game=bridge.game
		game._halt_countdown()
		game._nullify_override=func(): return false
		game._sacrifice_actor_override=func(_p,_t,_a): return false
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		game.players[0].hand.append(null)
		game.players[1].hp=2
		for label in ["出牌","锦囊牌","普通锦囊","南蛮入侵"]: await helper.click(t,bridge,0,label)
		await t.create_timer(0.15).timeout
		var token=find.find(bridge.snapshot(1),"免除此效果")
		t.check(token!="" and bridge.input_owner()==1 and not bridge.submit(0,token),"I05 only actual Peter target owns optional multi-effect immunity")
		if choice=="timeout": game._countdown_on_timeout.call()
		else: await helper.click(t,bridge,1,"免除此效果" if choice=="accept" else "取消")
		await helper.frames(t)
		t.check(game.players[1].hp==(2 if choice=="accept" else 1) and game.players[2].hp==4,"I05 real immunity or decline preserves other AOE targets")
		t.check(bridge.input_owner()==0 and not bridge.submit(1,token) and game._pending_card_actions.is_empty(),"I05 response returns original PLAY, consumed immune token cannot replay")
		game._game_over=true
		bridge.queue_free()
		await helper.frames(t)

func replacement_and_retired_source(t):
	for garden in [false,true]:
		var game=fixture(t,5,0 if garden else 1)
		var leo=game.players[2]
		leo.general_name="里奥·普利威尔"
		leo.prep_tokens=1
		var original=CardData.CardSubType.BARBARIAN_INVASION if garden else CardData.CardSubType.DUEL
		var final_sub=CardData.CardSubType.PEACH_GARDEN if garden else CardData.CardSubType.BARBARIAN_INVASION
		var actions: Array=[]
		var scopes: Array=[]
		game.card_action_committed.connect(func(a): actions.append(a))
		game._prep_replace_override=func(_l,actor,_fixed,current,options):
			t.check(actor==game.players[0] and current==original and options.has(final_sub),"I05 prep offers final group on original paid action")
			return final_sub
		game._peter_ignore_override=func(_p,audience,tag,_valid):
			scopes.append([audience.size(),tag])
			return 0 if garden else 1
		game._peter_exclusion_override=func(_p,_c,tag,valid):
			t.check(garden and tag=="peach_garden" and valid.call(),"I05 own Garden exclusions follow final replacement type")
			return [game.players[1],game.players[3]]
		if garden: await play(game,"aoe")
		else: await game.execute_card_on_target(game.players[1],original)
		t.check(scopes==([[5,"peach_garden"]] if garden else [[4,"aoe"]]),"I05 replacement immunity uses final declared group, not raw original single target")
		t.check(actions.size()==1 and actions[0].sub_type==original and actions[0].settlement_completed and game.deck._discard.has(actions[0].card) and game._pending_card_actions.is_empty(),"I05 prep and Peter never rewrite or duplicate original paid card fact")
		if garden:
			t.check(game.players[0].hp==3 and game.players[1].hp==3 and game.players[2].hp==4 and game.players[3].hp==3 and game.players[4].hp==4,"I05 replaced own South becomes Garden including caster; only selected B/D skipped")
		else:
			t.check(game.players[1].hp==2 and game.players[2].hp==2 and game.players[3].hp==2 and game.players[4].hp==2,"I05 Duel replaced to South allows Peter immunity, preserves expanded others")
		t.check(leo.prep_tokens==0,"I05 replacement spends one old marker, no extra Peter card-use marker")
		await dispose(t,game)
	var game=fixture(t,5,3)
	var caster=game.players[0]
	var leo=game.players[1]
	caster.hp=2
	leo.general_name="里奥·普利威尔"
	leo.hp=1
	game.players[3].hp=3
	game.players[2].hp=5
	game.players[4].hp=5
	var asked: Array=[]
	var facts: Array=[]
	game.card_action_committed.connect(func(a): facts.append(a))
	game._peter_ignore_override=func(_p,audience,tag,_v):
		if tag!="aoe": return 0
		asked.append(audience.duplicate())
		t.check(caster.is_dead() and audience.size()==4,"I05 source retirement preserves original multi-target declaration")
		return 1
	await play(game,"aoe")
	t.check(caster.is_dead() and leo.hp==1 and game.players[3].hp==1 and asked.size()==1,"I05 existing Yudaxi revives Leo; Peter can ignore remaining unsourced South")
	t.check(game.players[2].hp==2 and game.players[4].hp==2,"I05 source death and Peter immunity do not cancel other original recipients")
	t.check(facts.size()==1 and facts[0].settlement_completed and game._pending_card_actions.is_empty(),"I05 original paid AOE completes after source retires")
	await dispose(t,game)
