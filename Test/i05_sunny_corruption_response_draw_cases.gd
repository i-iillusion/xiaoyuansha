extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for concrete in [false,true]:
		for mode in ["win","decline","stale"]: await bagua(t,concrete,mode)
	for receive in [false,true]:
		for mode in ["win","tie","stale"]: await kaiwen(t,receive,mode)
	await bagua_source_death(t)
	await bagua_armor_loss(t)
	for seat in [0,1]:
		await bridge_case(t,seat,false)
		await bridge_case(t,seat,true)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func bagua(t,concrete,mode):
	var game=Cards.new().fixture(t); var defender=game.players[1]; var sunny=game.players[4]
	game.players[0].append_hand_card_silent(null)
	defender.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
	var original=CardBase.create(CardData.CardSubType.DODGE) if concrete else null
	if concrete: defender.determined_cards.append(original)
	else: defender.append_hand_card_silent(null)
	game._dodge_override=func(): return true
	var actions: Array=[]; var done: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		t.check(valid.call() and batch.owner==defender and defender.hand_size()==1 and actions.size()==2 and actions[1].kind==CardActionEvent.Kind.RESPONSE,"I05c actual Dodge is already paid before Bagua extra draw can be stolen")
		await t.process_frame
		t.check(defender.hp==4 and done.is_empty(),"I05c Bagua reaction suspends both original Strike and Dodge completion")
		if mode=="stale": sunny.restore_game_start_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	await game.execute_card_on_target(defender,CardData.CardSubType.STRIKE)
	t.check(defender.hp==4 and defender.hand_size()==(0 if mode=="win" else 1) and sunny.hand_size()==(1 if mode=="win" else 0),"I05c paid Dodge still prevents damage after Bagua reward moves or remains")
	t.check(actions.size()==2 and done.size()==(0 if mode=="stale" else 2) and game._pending_card_actions.is_empty(),"I05c actual Strike/Dodge complete once or release technical invalidation together")
	t.check(game.deck._discard.count(actions[1].card)==1 and (not concrete or actions[1].card==original),"I05c Bagua reward cannot repay or replace original concrete/arbitrary Dodge")
	await Farming.new().dispose(t,game)

func kaiwen(t,receive,mode):
	var game=Cards.new().fixture(t); var source=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	var owner=target if receive else source
	owner.general_name="凯文·罗本"
	owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.RENWANG_DUN)) # Legal target, not bare-running.
	source.append_hand_card_silent(null); source.wine_stacks=1
	game._dodge_override=func(): return false
	var asks: Array=[]; var batches: Array=[]; var punches: Array=[]; var greed: Array[bool]=[false]
	game._kaiwen_override=func():
		asks.append(true)
		t.check(batches.size()==asks.size()-1 or mode=="tie","I05c each Kevin point waits until the previous winning reward fully resolves")
		return true
	game._corruption_choice_override=func(_s,batch,_stage,valid):
		batches.append(batch); greed[0]=true
		t.check(valid.call() and batch.owner==owner and batch.count==2 and owner.hand_size()==2 and target.hp==2,"I05c each Kevin reward enters original hand after already committed two-point damage")
		await t.process_frame
		if mode=="stale": sunny.restore_game_start_state()
		return 0
	game._rps_override=func(p):
		punches.append(p)
		if greed[0]:
			if p==owner: greed[0]=false
			return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
		return GameManager.RPS_ROCK if mode=="tie" or p==owner else GameManager.RPS_SCISSORS
	var done: Array=[]; game.card_action_completed.connect(func(a): done.append(a))
	await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
	var points=1 if mode=="stale" else 2
	t.check(asks.size()==points and batches.size()==(0 if mode=="tie" else points),"I05c Kevin single ties do not repeat or create Corruption; each later point remains independent")
	t.check(target.hp==2 and sunny.hand_size()==(4 if mode=="win" else 0),"I05c Kevin receive/deal reward reaction never rolls back original damage")
	t.check(punches.size()==(4 if mode=="tie" else (2 if mode=="stale" else 8)),"I05c Kevin and each Corruption use separate explicit one-round RPS results")
	t.check(done.size()==(0 if mode=="stale" else 1) and game._pending_card_actions.is_empty(),"I05c Kevin reward returns original damage chain once, distinguishing technical invalidation")
	await Farming.new().dispose(t,game)

func bagua_source_death(t):
	var game=Cards.new().fixture(t); var source=game.players[0]; var defender=game.players[1]
	game.players[4].general_name="稻草人"; source.general_name=Cards.SUNNY; source.hp=1
	defender.general_name="大卫·法米尔"
	defender.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
	source.append_hand_card_silent(null); defender.append_hand_card_silent(null)
	game._dodge_override=func(): return true
	game._wrestling_choice_override=func(_p,_v): return 1
	game._corruption_choice_override=func(_s,_b,_k,_v): return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==source else GameManager.RPS_SCISSORS
	var done: Array=[]; game.card_action_completed.connect(func(a): done.append(a))
	await game.execute_card_on_target(defender,CardData.CardSubType.STRIKE)
	t.check(source.is_dead() and defender.hp==4 and defender.hand_size()==1,"I05c Bagua reward protection may kill original Strike user without undoing paid Dodge")
	t.check(done.size()==3 and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"I05c original Strike, paid Dodge and actual David counter each complete after nested source death")
	await Farming.new().dispose(t,game)

func bagua_armor_loss(t):
	var game=Cards.new().fixture(t); var defender=game.players[1]; var sunny=game.players[4]
	defender.general_name="大卫·法米尔"
	defender.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
	defender.append_hand_card_silent(null); game.players[0].append_hand_card_silent(null)
	var leo=game.players[2]; leo.general_name="里奥·普利威尔"; leo.prep_tokens=1
	game._dodge_override=func(): return true
	game._wrestling_choice_override=func(_p,_v): return 1
	game._prep_replace_override=func(_leo,user,_target,_sub,_options): return CardData.CardSubType.DISARM if user==defender else -1
	var seen: Array=[]; var done: Array=[]
	game._corruption_choice_override=func(_s,batch,_stage,_valid):
		seen.append(batch)
		return 0 if seen.size()==1 else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game.card_action_completed.connect(func(a): done.append(a))
	await game.execute_card_on_target(defender,CardData.CardSubType.STRIKE)
	t.check(defender.get_armor()==-1 and leo.prep_tokens==0 and seen.size()==2,"I05c actual nested counter Disarm removes already-triggered Bagua and creates a distinct compensation batch")
	t.check(defender.hp==4 and defender.hand_size()==2 and sunny.hand_size()==0,"I05c committed Dodge survives armor loss; original and later rewards are not confused")
	t.check(done.size()==3 and game._pending_card_actions.is_empty(),"I05c paid Strike, Dodge and replaced counter finish once after original Bagua leaves")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,is_kevin):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c response reward Bridge starts for host/remote Sunny")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var sunny=game.players[seat]; sunny.general_name=Cards.SUNNY
	var target=game.players[2]; var hp=target.hp
	game.players[0].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
	game.players[0].append_hand_card_silent(null)
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._dodge_override=func(): return not is_kevin
	if is_kevin:
		target.general_name="凯文·罗本"; target.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.RENWANG_DUN))
		game._kaiwen_override=func(): return true
	else:
		target.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN)); target.append_hand_card_silent(null)
	var done: Array=[]
	var run=func():
		await game.execute_card_on_target(target,CardData.CardSubType.STRIKE)
		done.append(true)
	run.call_deferred()
	for i in 2: await t.process_frame
	if is_kevin:
		t.check(bridge.submit(2,Sage.new().token(bridge,2,"石头")),"I05c Kevin original RPS belongs to damage recipient")
		for i in 2: await t.process_frame
		t.check(bridge.submit(0,Sage.new().token(bridge,0,"剪刀")),"I05c Kevin original opponent answers before separate Corruption window")
		for i in 2: await t.process_frame
	var activate=Sage.new().token(bridge,seat,"发动")
	t.check(not activate.is_empty() and done.is_empty() and target.hand_size()==(2 if is_kevin else 1),"I05c host/remote sees reward prompt with damage/response parent still pending")
	t.check(not bridge.submit(1-seat,activate) and bridge.submit(seat,activate),"I05c only active Sunny may confirm the nested reward reaction")
	for i in 2: await t.process_frame
	t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"石头")),"I05c actual reward reaction begins a distinct Sunny RPS")
	for i in 2: await t.process_frame
	t.check(bridge.submit(2,Sage.new().token(bridge,2,"剪刀")),"I05c actual reward owner retains second gesture ownership")
	for i in 3: await t.process_frame
	t.check(done==[true] and target.hp==hp-(1 if is_kevin else 0) and target.hand_size()==0 and sunny.hand_size()==(2 if is_kevin else 1),"I05c host/remote reward finishes before original Strike/damage completes once")
	t.check(game._pending_card_actions.is_empty() and not bridge.submit(seat,activate),"I05c response/damage reward leaves no reusable original or choice receipt")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
