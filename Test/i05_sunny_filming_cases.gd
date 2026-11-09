extends RefCounted
const SUNNY = "桑尼·斯派"
const Farming = preload("res://Test/i05_david_farming_cases.gd")

func fixture(t, count := 5):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,count,GameModes.FREE_FOR_ALL)
	game.lan_enabled = true
	game._paipian_rules_enabled = true
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
		p.general_name = "稻草人"
		p.max_hp = 4
		p.hp = 2
	var source = game.players[0]
	source.general_name = SUNNY
	source.hand.assign([null,null])
	source.capture_game_start_state()
	game._hand_discard_override = func(s,n,_m): return s.defaults(n)
	game._set_input_player(source)
	return game

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await fees_and_healing(t)
	await invalidation(t)
	await selection_guards(t)
	await targets(t)
	await peter(t)
	await granted(t)
	await native(t)
	for seat in [0,1]:
		for mode in ["confirm","cancel_target","cancel_fee","timeout_callback","restore"]:
			await bridge_case(t,seat,mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func fees_and_healing(t):
	for kind in ["blank","hand_concrete","determined"]:
		var game = fixture(t)
		var p = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		var original = CardBase.create(CardData.CardSubType.DODGE)
		if kind == "hand_concrete": p.hand.assign([original,null])
		if kind == "determined": p.hand.assign([null]); p.determined_cards.append(original)
		game._hand_discard_override = func(s,n,mandatory):
			t.check(n==1 and not mandatory,"I05c filming fee is exactly one voluntary original hand card")
			return [1] if kind=="determined" else [0]
		var audience: Array[Player] = [a,b]
		t.check(await game._execute_paipian(p,audience)==1 and p.hand_size()==1 and a.hp==3 and b.hp==3 and p.hp==2,"I05c original one-card fee heals exactly two others: "+kind)
		if kind!="blank": t.check(game.deck._discard.count(original)==1,"I05c filming discards original concrete resource once without declaring a different card")
		game._hand_discard_override = func(s,n,_m): return s.defaults(n)
		t.check(await game._execute_paipian(p,audience)==1 and a.hp==4 and b.hp==4 and p.hand_size()==0,"I05c filming has no invented once-per-PLAY restriction")
		p.hand.append(null)
		t.check(await game._execute_paipian(p,audience)==1 and a.hp==4 and b.hp==4 and p.hand_size()==0,"I05c full-health targets remain legal and normal healing is capped")
		t.check(game._card_action_serial==0 and p.farm_hand_actions==0 and game._paipian_pending.is_empty(),"I05c filming fee is not USE/RESPONSE and releases execution ownership")
		await Farming.new().dispose(t,game)

func invalidation(t):
	for fault in ["cancel","stale_hand","phase","restore","general","disabled","reset","game_over","dead_target","reentry","mutate_array"]:
		var game = fixture(t)
		var p = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		var audience: Array[Player] = [a,b]
		var nested: Array = []
		game._hand_discard_override = func(snapshot,n,_mandatory):
			if fault=="cancel": return []
			if fault=="stale_hand": p.hand.append(null)
			if fault=="phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
			if fault=="restore": p.restore_game_start_state()
			if fault=="general": p.general_name="稻草人"
			if fault=="disabled": game._paipian_rules_enabled=false
			if fault=="reset": game.reset_game_over_state()
			if fault=="game_over": game._finish_game("平局","I05c pending filming termination fixture")
			if fault=="dead_target": a.hp=0
			if fault=="reentry": nested.append(await game._execute_paipian(p,audience))
			if fault=="mutate_array": audience.assign([game.players[3],game.players[4]])
			return snapshot.defaults(n)
		var result = await game._execute_paipian(p,audience)
		var succeeds = fault in ["reentry","mutate_array"]
		t.check(result==(1 if succeeds else (0 if fault=="cancel" else game.CHOICE_INVALID)) and game._paipian_pending.is_empty(),"I05c fee invalidation/cancellation releases owned lease: "+fault)
		t.check(p.hand_size()==(1 if succeeds else (3 if fault=="stale_hand" else 2)) and b.hp==(3 if succeeds else 2),"I05c obsolete payment cannot charge replacement resources or heal: "+fault)
		if fault=="reentry": t.check(nested==[0],"I05c reentrant filming cannot charge a second fee")
		if fault=="mutate_array": t.check(a.hp==3 and game.players[3].hp==2 and game.players[4].hp==2,"I05c original recipients cannot be swapped through caller array mutation")
		await Farming.new().dispose(t,game)

func targets(t):
	var game = fixture(t,6)
	var p = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	for bad in [[],[a],[a,a],[p,a],[a,b,game.players[3]]]:
		var list: Array[Player] = []
		list.assign(bad)
		t.check(await game._execute_paipian(p,list)==0 and p.hand_size()==2 and a.hp==2,"I05c filming rejects wrong target count, self and duplicates")
	a.general_name="布鲁斯·萨维奇"
	a.kneeling=true
	t.check(not game._paipian_target_valid(p,a),"I05c kneeling characters are not filming targets")
	a.kneeling=false
	a.general_name="稻草人"
	game._mountain_rules_enabled=true
	game._spawn_mountain_at(game.players[5],0,1)
	game._spawn_mountain_at(game.players[5],4,5)
	t.check(not game._paipian_target_valid(p,a) and game._paipian_target_valid(p,game.players[5]),"I05c filming respects mountain regions in both target modes")
	var mountain = game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))[0]
	t.check(not game._paipian_target_valid(p,mountain),"I05c mountains are not normal healing characters")
	await Farming.new().dispose(t,game)
	game = fixture(t)
	p = game.players[0]
	var owner = game.players[3]
	owner.general_name="克里斯·西弗"
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,owner)
	var id = game.unit_registry.id_for(dragon)
	t.check(not game._paipian_target_valid(p,dragon),"I05c unseen dragon cannot be selected for filming")
	var shown: Array[Player] = [p]
	game.fire_dragon_state.record_use(id,1,shown)
	dragon.hp=1
	var list: Array[Player] = [dragon,game.players[1]]
	t.check(game._paipian_target_valid(p,dragon) and await game._execute_paipian(p,list)==1 and dragon.hp==2,"I05c revealed intelligent dragon is a legal healing character")
	game._paipian_rules_enabled=false
	t.check(await game._execute_paipian(p,list)==0 and not GeneralData.get_available_random_generals().has(SUNNY),"I05c server capability remains private and does not open a general")
	await Farming.new().dispose(t,game)

func selection_guards(t):
	for fault in ["disabled","wrong_general","empty_hand","equipment_only","wrong_actor","outside_play","one_other","stale_general","stale_phase","reset","end_play"]:
		var game=fixture(t)
		var p=game.players[0]
		var enter=fault in ["stale_general","stale_phase","reset","end_play"]
		if fault=="disabled": game._paipian_rules_enabled=false
		if fault=="wrong_general": p.general_name="稻草人"
		if fault in ["empty_hand","equipment_only"]: p.hand.clear()
		if fault=="equipment_only": p.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
		if fault=="wrong_actor": game.turn_manager.play_actor_idx=1
		if fault=="outside_play": game.turn_manager.current_phase=TurnManager.Phase.DRAW
		if fault=="one_other":
			for seat in [2,3,4]: game.players[seat].hp=0
		game._on_paipian_skill_clicked(p)
		t.check(game._is_paipian_targeting==enter,"I05c filming menu eligibility and stale selection setup: "+fault)
		if enter:
			if fault=="stale_general": p.restore_game_start_state()
			if fault=="stale_phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
			if fault=="reset": game.reset_game_over_state()
			if fault=="end_play":
				game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
				game.end_play_phase()
			game._on_paipian_target_click(game.players[1])
			t.check(not game._is_paipian_targeting and game._paipian_targets.is_empty(),"I05c changed general/phase/reset cannot retain stale avatar mode: "+fault)
		t.check(p.hand_size()==(0 if fault in ["empty_hand","equipment_only"] else 2) and game._card_action_serial==0,"I05c invalid menu/selection never pays a fee or declares a card: "+fault)
		await Farming.new().dispose(t,game)

func peter(t):
	for immune in [false,true]:
		var game = fixture(t)
		var p = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		a.general_name=load("res://Test/i05_peter_peach_cases.gd").PETER
		var asks: Array = []
		game._peter_ignore_override = func(target,audience,tag,valid):
			asks.append(target)
			t.check(audience==[a,b] and tag=="paipian" and valid.call() and p.hand_size()==1,"I05c Peter immunity sees original two-target audience after committed fee")
			return 1 if immune else 0
		var list: Array[Player] = [a,b]
		t.check(await game._execute_paipian(p,list)==1 and a.hp==(2 if immune else 3) and b.hp==3 and p.hand_size()==1,"I05c Peter ignores only his own healing and fee is not refunded")
		t.check(asks==[a] and game._paipian_pending.is_empty(),"I05c other target is not incorrectly offered Peter immunity")
		await Farming.new().dispose(t,game)

func granted(t):
	var game = fixture(t)
	var source = game.players[0]
	var actor = game.players[1]
	source.general_name="麦克斯·欧尼斯特"
	actor.general_name=SUNNY
	actor.hand.append(null)
	game.turn_manager.current_phase=TurnManager.Phase.START
	game._meiyong_override=func(): return true
	game._meiyong_option_override=func(): return 2
	game._meiyong_target_override=func(): return actor
	var action=func():
		t.check(game._play_actor()==actor and game.turn_manager.current_player_idx==0,"I05c genuine gifted PLAY preserves original turn owner")
		var list: Array[Player]=[source,game.players[2]]
		t.check(await game._execute_paipian(actor,list)==1 and source.hp==3 and game.players[2].hp==3,"I05c filming is legal inside Max granted PLAY")
		game.end_play_phase()
	action.call_deferred()
	t.check(await game._maybe_meiyong(source)==1 and game.turn_manager.current_phase==TurnManager.Phase.START and actor.hand_size()==0,"I05c filming completes granted PLAY and resumes donor START once")
	await Farming.new().dispose(t,game)

func native(t):
	var game = fixture(t)
	game.lan_enabled=false
	game._hand_discard_override=Callable()
	var p=game.players[0]
	game._open_player_detail(p)
	var popup=game._detail_popup_root.get_child(0)
	var buttons=popup._skills_container.get_children().filter(func(n): return n is Button and "【拍片】" in n.text)
	t.check(buttons.size()==1,"I05c native private detail exposes exactly one filming action")
	if not buttons.is_empty(): buttons[0].pressed.emit()
	game._on_paipian_target_click(game.players[1])
	game._on_paipian_target_click(game.players[2])
	game._on_paipian_target_click(game.players[3])
	t.check(game._paipian_targets==[game.players[1],game.players[2]] and not game._confirm_target_btn.disabled,"I05c native avatar toggles enforce exactly two targets")
	game._confirm_target_btn.pressed.emit()
	await t.process_frame
	var prompts=game.get_node("UI").get_children().filter(func(n): return n is HandDiscardPrompt and not n.is_queued_for_deletion())
	t.check(prompts.size()==1,"I05c native confirmation opens real one-card fee picker")
	var chosen: Array[int]=[0]
	if not prompts.is_empty(): prompts[0].submit(chosen)
	for i in 3: await t.process_frame
	t.check(p.hand_size()==1 and game.players[1].hp==3 and game.players[2].hp==3 and not game._is_paipian_targeting,"I05c native callback pays and heals without leftover target mode")
	await Farming.new().dispose(t,game)

func bridge_case(t,seat,mode):
	var bridge=LanGameBridge.new()
	t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 3: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05c real Bridge starts before explicit private Sunny fixture")
	var game=bridge.game
	game._halt_countdown()
	game._paipian_rules_enabled=true
	var p=game.players[seat]
	p.general_name=SUNNY
	p.capture_game_start_state()
	p.hand.assign([null,null])
	p.determined_cards.clear()
	for target in game.players: target.hp=target.max_hp-1
	var frame: Dictionary={}
	if seat==1:
		game.turn_manager.current_phase=TurnManager.Phase.START
		frame=game.turn_manager.begin_standalone_play(seat)
		game._do_play(0)
		game._halt_countdown()
	game._set_input_player(p)
	game._open_player_detail(p)
	var skill=""
	for control in bridge.snapshot(seat).controls:
		if "【拍片】" in control.text: skill=control.id
	t.check(not skill.is_empty() and not bridge.submit(1-seat,skill) and bridge.submit(seat,skill),"I05c filming menu uses actor-owned opaque Bridge token")
	var old_target=""
	for target in game.players:
		if target==p: continue
		var token=bridge.snapshot(seat).targets.get(str(target.seat_index),"")
		old_target=token
		t.check(not token.is_empty() and not bridge.submit(1-seat,token) and bridge.submit(seat,token),"I05c remote avatar targets reject wrong seat and select original recipients")
	var confirm=FarmingToken(bridge,seat,"确认拍片（2/2 名目标）")
	t.check(not confirm.is_empty(),"I05c two remote targets enable shared confirmation button")
	if mode=="cancel_target":
		var cancel=FarmingToken(bridge,seat,"取消选择")
		t.check(not cancel.is_empty() and bridge.submit(seat,cancel),"I05c remote target cancellation leaves fee unpaid")
	else:
		t.check(bridge.submit(seat,confirm),"I05c remote confirmation opens original hand fee")
		if mode=="confirm":
			var pick=""
			for control in bridge.snapshot(seat).controls:
				if "任意牌" in control.text: pick=control.id; break
			t.check(not pick.is_empty() and not bridge.submit(1-seat,pick) and bridge.submit(seat,pick),"I05c real remote hand toggle is owner-only")
			var pay=FarmingToken(bridge,seat,"确认弃牌")
			t.check(not pay.is_empty() and bridge.submit(seat,pay) and not bridge.submit(seat,pay),"I05c exact one-card confirmation token is consumed once")
		elif mode=="cancel_fee":
			var cancel=FarmingToken(bridge,seat,"取消发动")
			t.check(not cancel.is_empty() and bridge.submit(seat,cancel),"I05c remote voluntary hand fee can be cancelled")
		elif mode=="timeout_callback": game._choice_prompt_stack.back().answer.submit(-1)
		else: p.restore_game_start_state()
	for i in 4: await t.process_frame
	t.check(p.hand_size()==(1 if mode=="confirm" else 2) and game.players[1-seat].hp==game.players[1-seat].max_hp-(0 if mode=="confirm" else 1),"I05c Bridge confirmation/cancel/timeout callback/restore retain exact fee and effect: "+mode)
	t.check(not game._is_paipian_targeting and game._paipian_pending.is_empty() and not bridge.submit(seat,skill) and not bridge.submit(seat,old_target),"I05c completed remote mode rejects stale detail/target tokens and releases lease")
	if seat==1: t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_phase==TurnManager.Phase.START,"I05c remote gifted PLAY returns to donor phase")
	game._game_over=true
	bridge.queue_free()
	for i in 3: await t.process_frame

func FarmingToken(bridge,seat,text):
	return load("res://Test/i05_david_upgrade_cases.gd").new().token(bridge,seat,text)
