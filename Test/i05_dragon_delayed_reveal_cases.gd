extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Dragon=preload("res://Test/i03_summon_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for sub in [CardData.CardSubType.INDULGENCE,CardData.CardSubType.SUPPLY_SHORTAGE,CardData.CardSubType.BURNING_CAMP]:
		for concrete in [false,true]:
			for unit_source in [false,true]: await delayed(t,sub,concrete,unit_source)
	for seat in [0,1]: await bridge_case(t,seat)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func delayed(t,sub,concrete,unit_source):
	var game=Cards.new().fixture(t); var owner=game.players[3]; var sunny=game.players[4]
	owner.general_name="克里斯·西弗"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	var dragon=Dragon.new().seed_dragon(game,owner); var id=game.unit_registry.id_for(dragon)
	var source=dragon if unit_source else owner
	var original=CardBase.create(sub) if concrete else null
	if concrete: source.determined_cards.append(original)
	else: source.append_hand_card_silent(null)
	game.turn_manager.current_player_idx=owner.seat_index; game.turn_manager.current_unit_id=id if unit_source else ""
	var events: Array=[]; var batches: Array=[]
	game.card_action_committed.connect(func(e): events.append(e))
	t.check(not game.fire_dragon_state.is_revealed_to(id,sunny) and game.get_trick_targets(source,sub).has(sunny),"Delayed fixture starts hidden with a legal original target")
	await game.execute_card_on_target(sunny,sub)
	t.check(sunny.judgment_cards.size()==1 and source.hand_size()==0 and owner.hand_size()==0,"Actual delayed card enters target zone, not controller/dragon hand")
	t.check(events.size()==1 and events[0].actor_body==source and events[0].settlement_completed and game._pending_card_actions.is_empty(),"Delayed USE belongs to actual body and completes once")
	t.check(game.fire_dragon_state.is_revealed_to(id,sunny)==unit_source,"Q52 actual dragon delayed declaration reveals to target; ordinary player's use does not")
	t.check(not game.fire_dragon_state.is_revealed_to(id,game.players[0]),"Direct delayed declaration reveals only the designated target")
	if concrete: t.check(sunny.judgment_cards==[original] and not game.deck._discard.has(original),"Delayed concrete card retains original instance and is not prematurely discarded")
	# Explicit legal gift-PLAY prefix: Sunny can act before its own next judge,
	# so the old delay remains pending. This does not claim a natural Max run.
	game.players[1].general_name="麦克斯·欧尼斯特"
	game.turn_manager.current_unit_id=""; game.turn_manager.current_player_idx=1; game.turn_manager.play_actor_idx=4
	game.turn_manager.current_phase=TurnManager.Phase.PLAY; game.turn_manager._reset_turn_counts()
	dragon.hp=2; sunny.append_hand_card_silent(null)
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		batches.append(batch)
		t.check(valid.call() and batch.owner==dragon and batch.count==1 and owner.hand_size()==0,"Actual Harvest draw belongs to newly visible injured dragon and permits Sunny Greed")
		return 0
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	await game.play_card(CardData.CardSubType.HARVEST)
	t.check(batches.size()==(1 if unit_source else 0) and sunny.hand_size()==(1 if unit_source else 0) and dragon.hand_size()==0,"Visibility from real delayed USE controls actual Harvest/Greed, never a manual reveal")
	t.check(events.size()==2 and events[1].actor_body==sunny and events[1].turn_owner_seat==1 and events[1].settlement_completed,"Gifted Harvest retains separate turn owner and completes original event once")
	t.check(sunny.judgment_cards.size()==1 and game._pending_card_actions.is_empty(),"Gift PLAY neither judges nor discards the pending delay")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"Dragon delayed host/remote Bridge starts")
	var game=bridge.game; game._halt_countdown()
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	var owner=game.players[seat]; var target=game.players[4]
	owner.general_name="克里斯·西弗"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	var dragon=Dragon.new().seed_dragon(game,owner); var id=game.unit_registry.id_for(dragon)
	dragon.append_hand_card_silent(null)
	game.turn_manager.current_player_idx=seat; game.turn_manager.current_unit_id=id; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	game._target_confirm_override=func(): return true
	game._set_input_player(dragon); game._sync_all_ui()
	for label in ["出牌","锦囊牌","延时锦囊","乐不思蜀"]:
		var command=Sage.new().token(bridge,seat,label)
		t.check(not command.is_empty() and not bridge.submit(1-seat,command) and bridge.submit(seat,command),"Actual unit controller selects delayed card via opaque command: "+label)
		for i in 2: await t.process_frame
	# CardSelector emits its confirmed signal after its existing 0.1s tween.
	await t.create_timer(0.15).timeout
	var target_token=bridge.snapshot(seat).targets.get("4","")
	t.check(not target_token.is_empty() and not bridge.submit(1-seat,target_token) and bridge.submit(seat,target_token),"Actual dragon target token belongs only to host/remote controller")
	for i in 4: await t.process_frame
	t.check(target.judgment_cards.size()==1 and dragon.hand_size()==0 and owner.hand_size()==0,"Bridge real selected unit pays its own delayed card into original target zone")
	t.check(game.fire_dragon_state.is_revealed_to(id,target) and not game.fire_dragon_state.is_revealed_to(id,owner),"Bridge delayed USE reveals to target only, not automatically to controller")
	t.check(game._pending_card_actions.is_empty() and bridge.input_owner()==seat and not bridge.submit(seat,target_token),"Unit delayed event releases once and rejects old target command")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
