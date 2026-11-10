extends RefCounted
const Cards=preload("res://Test/i05_sunny_corruption_card_draw_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")
const Sage=preload("res://Test/i05_sunny_corruption_sage_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for path in ["wine","peach","lightning","indulgence","weapon","armor","mount","replace_weapon","replace_armor","replace_mount"]:
		for concrete in [false,true]:
			for mode in ["decline","win"]: await payment(t,path,concrete,mode)
	for path in ["wine","indulgence","replace_weapon"]: await payment(t,path,false,"stale")
	for seat in [0,1]:
		for path in ["wine","indulgence","replace_weapon"]: await bridge_case(t,seat,path)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func payment(t,path,concrete,mode):
	var game=Cards.new().fixture(t); var owner=game.players[0]; var target=game.players[1]; var sunny=game.players[4]
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	if path=="peach": owner.hp=2
	var sub=CardData.CardSubType.WINE
	match path:
		"peach": sub=CardData.CardSubType.PEACH
		"lightning": sub=CardData.CardSubType.LIGHTNING
		"indulgence": sub=CardData.CardSubType.INDULGENCE
		"weapon","replace_weapon": sub=CardData.CardSubType.LIANNU
		"armor","replace_armor": sub=CardData.CardSubType.BAGUA_ZHEN
		"mount","replace_mount": sub=CardData.CardSubType.MOUNT_MINUS
	var original=CardBase.create(sub) if concrete else null
	if concrete:
		owner.determined_cards.append(original)
		if path in ["weapon","replace_weapon","armor","replace_armor"]: game.equipment_pool.claim(sub,original)
	else: owner.append_hand_card_silent(null)
	var old: CardBase
	if path=="replace_weapon":
		old=CardBase.create(CardData.CardSubType.QINGLONG_BLADE); owner.equip_card_to_slot("weapon",old); game.equipment_pool.claim(old.sub_type,old)
	if path=="replace_armor":
		old=CardBase.create(CardData.CardSubType.TENGJIA); owner.equip_card_to_slot("armor",old); game.equipment_pool.claim(old.sub_type,old)
	if path=="replace_mount":
		for slot in Player.MOUNT_SLOTS: owner.equip_card_to_slot(slot,CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		old=owner.get_equipment_card("mount_1")
	game._weapon_replace_override=func(): return true
	game._mount_replace_override=func(): return "mount_1"
	var used: Array=[]; var done: Array=[]; var seen: Array=[]; var picked: Array=[]
	game.card_action_committed.connect(func(a): used.append(a))
	game.card_action_completed.connect(func(a): done.append(a))
	game._corruption_choice_override=func(_p,batch,_stage,valid):
		seen.append(batch)
		t.check(valid.call() and batch.owner==owner and batch.count==2 and owner.max_hp==2 and owner.hand_size()==2 and used.size()==1 and done.is_empty(),"I05c ordinary paid use awaits complete awakening before card completion: "+path)
		t.check(picked.is_empty() and owner.awake_choice==0 and (path!="wine" or owner.wine_stacks==0),"I05c ordinary payment is settled before awakening; Wine effect waits for immunity")
		await t.process_frame
		if mode=="stale": sunny.restore_game_start_state()
		return 0 if mode=="win" else -1
	game._rps_override=func(p): return GameManager.RPS_ROCK if p==sunny else GameManager.RPS_SCISSORS
	game._awaken_pick_override=func():
		picked.append(true)
		t.check(seen.size()==1 and done.is_empty(),"I05c ordinary original use remains incomplete until mandatory immunity: "+path)
		return 3
	if path=="indulgence": await game.execute_card_on_target(target,sub)
	else: await game.play_card(sub)
	var invalid=mode=="stale"
	t.check(seen.size()==1 and picked.size()==(0 if invalid else 1) and done.size()==(0 if invalid else 1) and game._pending_card_actions.is_empty(),"I05c ordinary use completes once or releases old receipt on invalidation: "+path)
	t.check(owner.hand_size()==(0 if mode=="win" else 2) and owner.max_hp==2 and owner.hp==2,"I05c ordinary use preserves actual awakened hand/HP without repeating reward: "+path)
	t.check(used.size()==1 and (not concrete or used[0].card==original),"I05c original concrete/arbitrary use is recorded once: "+path)
	if path in ["wine","peach"]:
		t.check(game.deck._discard.count(used[0].card)==1 and (path!="wine" or owner.wine_stacks==(0 if invalid else 1)),"I05c basic card original payment is discarded once and invalid Wine does not apply")
	elif path in ["lightning","indulgence"]:
		var recipient=target if path=="indulgence" else owner
		t.check(recipient.judgment_cards==[used[0].card] and not game.deck._discard.has(used[0].card),"I05c delayed card retains its paid original judgment placement across awakening: "+path)
	else:
		var slot="weapon" if path.ends_with("weapon") else "armor" if path.ends_with("armor") else "mount_1"
		t.check(owner.get_equipment_card(slot)==used[0].card and not game.deck._discard.has(used[0].card),"I05c equipped original stays committed throughout awakening: "+path)
		if old!=null: t.check(game.deck._discard.count(old)==1,"I05c old equipment leaves once, with no rollback or repeated replacement")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,path):
	var bridge=LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05c ordinary use Bridge starts without identity HP modifiers")
	var game=bridge.game; game._halt_countdown(); game._corruption_rules_enabled=true
	for p in game.players: p.clear_hand_silent(); p.determined_cards.clear(); p.hp=p.max_hp
	game.turn_manager.current_player_idx=seat; game.turn_manager.current_phase=TurnManager.Phase.PLAY
	var owner=game.players[seat]; var target=game.players[seat+1]
	owner.general_name="史蒂芬·彼特先斯"; owner.max_hp=3; owner.hp=3; owner.capture_game_start_state()
	var old: CardBase
	if path=="replace_weapon":
		old=CardBase.create(CardData.CardSubType.QINGLONG_BLADE); owner.equip_card_to_slot("weapon",old); game.equipment_pool.claim(old.sub_type,old)
	owner.append_hand_card_silent(null); game._set_input_player(owner); game.players[4].general_name=Cards.SUNNY
	game._weapon_replace_override=func(): return true
	var seen: Array=[]; var done: Array=[]
	game._corruption_choice_override=func(_p,batch,_s,_v): seen.append(batch.count); return -1
	var run=func():
		if path=="indulgence": await game.execute_card_on_target(target,CardData.CardSubType.INDULGENCE)
		else: await game.play_card(CardData.CardSubType.WINE if path=="wine" else CardData.CardSubType.LIANNU)
		done.append(true)
	run.call_deferred()
	for i in 3: await t.process_frame
	var choice=Sage.new().token(bridge,seat,"不能成为【南蛮入侵】和【万箭齐发】的目标")
	t.check(not choice.is_empty() and seen==[2] and done.is_empty() and owner.hand_size()==2,"I05c host/remote ordinary paid use waits at actual mandatory immunity")
	t.check(not bridge.submit(1-seat,choice) and bridge.submit(seat,choice),"I05c ordinary paid use keeps correct host/remote immunity ownership")
	for i in 4: await t.process_frame
	t.check(done==[true] and owner.max_hp==2 and owner.hp==2 and owner.hand_size()==2 and seen==[2],"I05c ordinary host/remote payment awakens once without another reward batch")
	var applied=owner.wine_stacks==1 if path=="wine" else target.judgment_cards.size()==1 if path=="indulgence" else owner.get_weapon()==CardData.CardSubType.LIANNU and game.deck._discard.count(old)==1
	t.check(applied,"I05c ordinary host/remote effect/atomic replacement remains committed exactly once")
	t.check(bridge.input_owner()==seat and game._pending_card_actions.is_empty() and not bridge.submit(seat,choice),"I05c ordinary host/remote use restores controller with no replay token")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
