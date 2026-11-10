extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for concrete in [false,true]:
		for mode in ["win","decline","tie","stale"]: await classic(t,concrete,mode)
	await ambitious(t)
	await counter(t)
	await excluded(t,false)
	await excluded(t,true)
	for visible in [false,true]: await dragon_reward(t,visible)
	for seat in [0,1]: await bridge_case(t,seat)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func roles(game,penalty:=false):
	game.game_mode=GameModes.CLASSIC
	var identities=["主公","忠臣","反贼","反贼","内奸"] if penalty else ["忠臣","反贼","主公","反贼","内奸"]
	for i in 5: game.players[i].identity=identities[i]

func classic(t,concrete,mode):
	var game=Cards.new().fixture(t); roles(game)
	var killer=game.players[0]; var victim=game.players[1]; var sunny=game.players[4]
	victim.hp=1; victim.append_hand_card_silent(null)
	victim.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.RENWANG_DUN))
	victim.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	var older=CardBase.create(CardData.CardSubType.DODGE); killer.append_hand_card_silent(older)
	var original=CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
	if concrete: killer.determined_cards.append(original)
	else: killer.append_hand_card_silent(null)
	game._dodge_override=func(): return false
	var seen: Array=[]; var actions: Array=[]; var done: Array=[]
	game.card_action_committed.connect(func(a): actions.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._corruption_choice_override=func(_p,batch,stage,valid):
		if stage=="tie": return 0
		seen.append(batch)
		t.check(valid.call() and batch.owner==killer and batch.count==3 and killer.hand_size()==4,"I05c identity reward enters actual killer hand with older cards excluded from batch")
		t.check(victim.is_dead() and victim.identity_revealed and victim.hand_size()==0 and victim.equipment.is_empty() and victim.judgment_cards.is_empty(),"I05c kill reward is strictly after final death, identity reveal and original cleanup")
		await t.process_frame
		t.check(done.is_empty() and actions.size()==1,"I05c original paid Strike/death parent waits for kill reward reaction")
		if mode=="stale": sunny.restore_game_start_state()
		return -1 if mode=="decline" else 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny or mode=="tie" else GameManager.RPS_SCISSORS
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	t.check(seen.size()==1 and sunny.hand_size()==(3 if mode=="win" else (1 if mode=="tie" else 0)) and killer.hand.has(older),"I05c kill reward win/tie/decline/invalid preserves exact original batch and old card")
	t.check(done.size()==(0 if mode=="stale" else 1) and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"I05c kill-reward reaction finishes or invalidates original chain without reopening dead victim")
	t.check(game.deck._discard.count(actions[0].card)==1 and (not concrete or actions[0].card==original),"I05c reward reaction cannot repay arbitrary/concrete original Strike")
	await game._resolve_dying(victim,killer,"no_replay_death_reward")
	t.check(seen.size()==1 and game._draw_batches.size()==1,"I05c already finalized victim cannot produce a second kill-reward batch")
	await Farming.new().dispose(t,game)

func ambitious(t):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.AMBITIOUS)
	game._corruption_rules_enabled=true
	for p in game.players: p.general_name="稻草人"; p.clear_hand_silent(); p.determined_cards.clear()
	var victim=game.players.filter(func(p): return p.identity=="奸雄")[0]
	var killer=game.players.filter(func(p): return p!=victim and p.identity!="主公")[0]
	var sunny=game.players.filter(func(p): return p!=victim and p!=killer)[0]; sunny.general_name=Cards.SUNNY
	victim.hp=1
	killer.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW)); killer.append_hand_card_silent(null)
	game.turn_manager.current_player_idx=killer.seat_index; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	game._dodge_override=func(): return false
	game._rescue_choice_override=func(_p,_t,_o): return -1
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._corruption_choice_override=func(_p,batch,_s,valid):
		t.check(valid.call() and batch.owner==killer and batch.count==3 and victim.is_dead(),"I05c natural six-player ambitious role receives same exact three-card kill reward")
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	t.check(sunny.hand_size()==3 and killer.hand_size()==0 and victim.identity=="奸雄" and victim.identity_revealed,"I05c ambitious victim reward transfers without inventing a lord declaration or identity swap")
	t.check(game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"I05c ambitious reward returns parent death/Strike with no dangling context")
	await Farming.new().dispose(t,game)

func counter(t):
	var game=Cards.new().fixture(t); roles(game)
	var killer=game.players[0]; var victim=game.players[1]; var sunny=game.players[4]
	killer.general_name="大卫·法米尔"; victim.hp=1; sunny.hp=1; killer.append_hand_card_silent(null)
	game._dodge_override=func(): return false
	game._wrestling_choice_override=func(_p,_v): return 1
	game._corruption_choice_override=func(_p,_b,_s,_v): return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	var done: Array=[]; game.card_action_completed.connect(func(a): done.append(a))
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	t.check(victim.is_dead() and sunny.is_dead() and killer.hand_size()==3,"I05c actual David may protect already-drawn kill reward and counter-kill Sunny before original death parent completes")
	t.check(done.size()==2 and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(),"I05c nested identity deaths, counter Duel and original Strike complete once with no duplicate reward")
	await Farming.new().dispose(t,game)

func excluded(t,penalty):
	var game=Cards.new().fixture(t); var killer=game.players[0]; var victim=game.players[1]
	if penalty: roles(game,true); killer.general_name="大卫·法米尔"
	victim.hp=1
	killer.append_hand_card_silent(null); killer.append_hand_card_silent(null)
	killer.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	game._dodge_override=func(): return false
	var seen: Array=[]
	game._corruption_choice_override=func(_p,_b,_s,_v): seen.append(true); return 0
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	t.check(seen.is_empty() and game._draw_batches.is_empty(),"I05c FFA has no reward; lord-loyalist penalty is cleanup rather than a greedy draw")
	t.check(killer.hand_size()==(0 if penalty else 1) and (killer.get_weapon()==-1 if penalty else killer.get_weapon()==CardData.CardSubType.QINGGANG_SWORD),"I05c ordinary FFA resources or mandatory lord penalty keep prior rules, never invoke David prevention")
	await Farming.new().dispose(t,game)

func dragon_reward(t,visible):
	var game=Cards.new().fixture(t); roles(game)
	var owner=game.players[3]; owner.general_name="克里斯·西弗"
	var dragon=load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,owner)
	var id=game.unit_registry.id_for(dragon)
	if visible:
		var shown: Array[Player]=[game.players[4]]
		game.fire_dragon_state.record_use(id,1,shown) # Established visibility boundary, not a new reveal rule.
		game._card_action_serial=1 # The later real Strike must not reuse that established action id.
	dragon.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
	dragon.append_hand_card_silent(null)
	game.turn_manager.current_unit_id=id # Existing registered unit-turn fixture; summoning prefix remains I03.
	var victim=game.players[1]; victim.hp=1
	game._dodge_override=func(): return false
	var seen: Array=[]; var done: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==dragon and dragon.hand_size()==3 and owner.hand_size()==0,"I05c kill reward belongs to actual dragon body, not its controller")
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==game.players[4] else GameManager.RPS_SCISSORS
	game.card_action_completed.connect(func(a): done.append(a))
	await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
	t.check(victim.is_dead() and seen.size()==(1 if visible else 0),"I05c dragon's reward reaction requires prior visibility to Sunny, never just the kill reveal to victim")
	t.check(dragon.hand_size()==(0 if visible else 3) and owner.hand_size()==0 and game.players[4].hand_size()==(3 if visible else 0),"I05c intelligent-unit reward remains on exact unit or moves once to eligible Sunny")
	t.check(done.size()==1 and done[0].actor_key==id and game._pending_card_actions.is_empty(),"I05c dragon's paid Strike retains unit identity through reward/dying continuation")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c death-reward Bridge starts natural classic identities")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear()
	var sunny=game.players[seat]; sunny.general_name=Cards.SUNNY
	var victim=game.players.filter(func(p): return p!=sunny and p.identity=="反贼")[0]
	var killer=game.players.filter(func(p): return p!=sunny and p!=victim and p.identity!="主公")[0]
	victim.hp=1; killer.append_hand_card_silent(null); killer.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
	game.turn_manager.current_player_idx=killer.seat_index; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	game._dodge_override=func(): return false
	game._rescue_choice_override=func(_p,_t,_o): return -1
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	var done: Array=[]
	var run=func():
		await game.execute_card_on_target(victim,CardData.CardSubType.STRIKE)
		done.append(true)
	run.call_deferred()
	for i in 2: await t.process_frame
	var activate=Sage.new().token(bridge,seat,"发动")
	t.check(not activate.is_empty() and done.is_empty() and victim.is_dead() and victim.identity_revealed and killer.hand_size()==3,"I05c host/remote reward window appears after final reveal and before death parent returns")
	t.check(not bridge.submit(killer.seat_index,activate) and bridge.submit(seat,activate),"I05c reward belongs to killer but only active Sunny may initiate Corruption")
	for i in 2: await t.process_frame
	t.check(bridge.submit(seat,Sage.new().token(bridge,seat,"石头")),"I05c host/remote kill-reward Sunny gesture accepted")
	for i in 2: await t.process_frame
	t.check(bridge.submit(killer.seat_index,Sage.new().token(bridge,killer.seat_index,"剪刀")),"I05c actual killer owns kill-reward second gesture")
	for i in 3: await t.process_frame
	t.check(done==[true] and sunny.hand_size()==3 and killer.hand_size()==0 and game._dying_contexts.is_empty(),"I05c host/remote kill reward transfers before original death/Strike resumes once")
	t.check(game._pending_card_actions.is_empty() and not bridge.submit(seat,activate),"I05c final kill-reward continuation has no reusable old token")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
