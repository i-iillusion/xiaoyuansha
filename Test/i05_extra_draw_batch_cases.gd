extends RefCounted
const Farming=preload("res://Test/i05_david_farming_cases.gd")

func fixture(t):
	var game=Farming.new().fixture(t)
	game._extra_draw_receipts_enabled=true
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	return game

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await resources(t)
	await stale(t)
	await stages(t)
	await initial(t)
	await yudaxi_context(t)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func resources(t):
	for zone in ["hand","determined"]:
		for amount in [1,3]:
			var game=fixture(t)
			var p=game.players[1]
			var original=CardBase.create(CardData.CardSubType.DODGE)
			p.hand.append(null)
			if zone=="hand": p.hand.append(original)
			else: p.determined_cards.append(original)
			var original_count=p.hand_size()
			var first=p.hand.size()
			var batch=game._draw_blank_cards(p,3)
			t.check(batch!=null and batch.owner==p and batch.count==3 and batch.is_extra() and batch.valid(),"I05c draw receipt records the exact newly appended batch after cards enter original hand")
			t.check(not batch.during_yudaxi and batch.serial==1 and game._draw_batches==[batch],"I05c receipt queue is capture-only, with explicit serial and priority fact")
			var atoms=batch.loss_atoms(amount)
			t.check(atoms.size()==amount and atoms[0].index==first and atoms.all(func(atom): return atom.card==null and atom.zone=="hand" and atom.owner==p),"I05c prospective loss refers only to this draw, excluding older blank/concrete cards")
			var taken=batch.take(amount)
			t.check(taken.size()==amount and taken.all(func(card): return card==null) and p.hand_size()==original_count+3-amount,"I05c batch claims exact arbitrary draw resources without concretizing a card")
			t.check((p.hand if zone=="hand" else p.determined_cards).has(original) and game.deck._discard.count(original)==0,"I05c older concrete Flash remains its original resource, never substituted for a new draw")
			t.check(batch.closed and batch.take(1).is_empty() and batch.loss_atoms(1).is_empty() and game._card_action_serial==0,"I05c claimed receipt cannot replay, declare USE/RESPONSE or silently discard old cards")
			await Farming.new().dispose(t,game)
	var game=fixture(t)
	var p=game.players[1]
	var batch=game._draw_blank_cards(p,2)
	t.check(batch.take(0).is_empty() and batch.take(3).is_empty() and batch.valid() and p.hand_size()==2,"I05c invalid claim count never partially removes the original draw")
	batch.close()
	t.check(not batch.valid() and batch.take(1).is_empty() and p.hand_size()==2,"I05c closing a receipt is not a card loss or an invented skill effect")
	var serial=game._draw_batch_serial
	t.check(game._draw_blank_cards(p,0)==null and game._draw_batch_serial==serial,"I05c zero-card draw creates no batch or serial")
	game._extra_draw_receipts_enabled=false
	t.check(game._draw_blank_cards(p,2)==null and p.hand_size()==4 and game._draw_batch_serial==serial,"I05c disabled private capture preserves legacy synchronous draws and allocates no records")
	await Farming.new().dispose(t,game)

func stale(t):
	for fault in ["append","remove","restore","reset","game_over","dying","dead"]:
		var game=fixture(t)
		var p=game.players[1]
		p.capture_game_start_state()
		var batch=game._draw_blank_cards(p,2)
		if fault=="append": p.hand.append(null)
		if fault=="remove": p.hand.pop_front()
		if fault=="restore": p.restore_game_start_state()
		if fault=="reset": game.reset_game_over_state()
		if fault=="game_over": game._finish_game("平局","draw receipt terminal fixture")
		if fault=="dying": p.hp=0
		if fault=="dead": p.mark_dead()
		var count=p.hand_size()
		t.check(not batch.valid() and batch.take(1).is_empty() and p.hand_size()==count,"I05c stale receipt never substitutes later cards or replays after restore/lifecycle: "+fault)
		if fault in ["reset","game_over"]: t.check(batch.closed and game._draw_batches.is_empty(),"I05c restart/terminal cleanup closes captured batches without moving cards")
		await Farming.new().dispose(t,game)

func stages(t):
	for role in ["normal","bill","david"]:
		var game=fixture(t)
		var donor=game.players[0]
		var target=game.players[1]
		donor.general_name="麦克斯·欧尼斯特"
		if role=="bill": target.general_name="比尔·盖伊"
		if role=="david": target.general_name="大卫·法米尔"; target.farm_good_fields=2
		game.turn_manager.current_phase=TurnManager.Phase.START
		game._meiyong_override=func(): return true
		game._meiyong_option_override=func(): return 1
		game._meiyong_target_override=func(): return target
		t.check(await game._maybe_meiyong(donor)==1 and game._draw_batches.size()==2,"I05c genuine Max gifted DRAW records source reward and recipient stage separately")
		var fee_reward=game._draw_batches[0]
		var phase_draw=game._draw_batches[1]
		t.check(fee_reward.owner==donor and fee_reward.count==1 and fee_reward.is_extra(),"I05c QA-T324 Max skill draws one EXTRA despite giving away DRAW")
		t.check(phase_draw.owner==target and not phase_draw.is_extra() and phase_draw.context==ExtraDrawBatch.Context.DRAW_PHASE and phase_draw.count==2+({"normal":0,"bill":1,"david":2}[role]),"I05c gifted DRAW with ordinary/Bill/good-field modifiers remains a phase draw: "+role)
		t.check(game.turn_manager.current_phase==TurnManager.Phase.START and game._card_action_serial==0,"I05c receipt capture preserves actual gifted phase return and creates no card action")
		await Farming.new().dispose(t,game)
	var game=fixture(t)
	game.turn_manager.current_phase=TurnManager.Phase.DRAW
	var target=game.players[1]
	target.general_name="史蒂芬·彼特先斯"
	target.awoken=true
	game._awaken_pick_override=func(): return 1
	await game._do_awaken(target)
	var batch=game._draw_batches[0]
	t.check(batch.owner==target and batch.count==2 and batch.is_extra() and target.awake_choice==1,"I05c Q5 awakening inside another player's DRAW records EXTRA without changing the original phase")
	await Farming.new().dispose(t,game)

func initial(t):
	load("res://Test/h02_integration_cases.gd").new().prepare(5,GameModes.FREE_FOR_ALL)
	var game=load("res://Scenes/Game.tscn").instantiate()
	game.auto_start=false
	game._extra_draw_receipts_enabled=true
	t.root.add_child(game)
	game.start_game(); game._halt_countdown()
	var deal=game._draw_batches.filter(func(batch): return batch.context==ExtraDrawBatch.Context.INITIAL_DEAL)
	t.check(deal.size()==5 and deal.all(func(batch): return batch.count==4 and not batch.is_extra()),"I05c Q4 normal initialization explicitly labels all five original four-card deals")
	t.check(game._draw_batches.all(func(batch): return batch.context in [ExtraDrawBatch.Context.INITIAL_DEAL,ExtraDrawBatch.Context.DRAW_PHASE]),"I05c real opening uses semantic draw contexts instead of global START/PLAY guesses")
	await Farming.new().dispose(t,game)

func yudaxi_context(t):
	var game=fixture(t)
	var root=game.players[0]
	var saved=game.players[1]
	root.general_name="里奥·普利威尔"
	root.hp=0
	saved.general_name="大卫·法米尔"; saved.max_hp=4; saved.hp=4; saved.capture_game_start_state(); saved.hp=1
	saved.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	saved.sage_activated=true
	for seat in [2,3,4]: game.players[seat].hp=4
	game.players[2].general_name="桑尼·斯派"
	game.turn_manager.current_player_idx=4
	game._rescue_choice_override=func(_r,_v,_o): return -1
	game._sage_save_override=func(): return true
	await game._resolve_dying(root,null,"draw_batch_context_fixture")
	var records=game._draw_batches.filter(func(batch): return batch.owner==saved)
	t.check(records.size()==1 and records[0].count==4 and records[0].is_extra() and records[0].during_yudaxi,"I05c actual Yudaxi rescue/Sage draw captures rule-active origin at the moment of drawing")
	t.check(not game.yudaxi.is_active() and records[0].during_yudaxi and saved.hand_size()==4,"I05c ending Yudaxi cannot erase its origin metadata; deferred Corruption policy remains a separate ruling")
	await Farming.new().dispose(t,game)
