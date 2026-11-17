extends RefCounted

func begin(game, owner, operation, result): result.append(await game._perform_sally_smoking(owner,operation))

func token(bridge,seat,text):
	var controls = bridge.snapshot(seat).controls.filter(func(c): return not c.disabled and c.text == text)
	return controls[0].id if controls.size() == 1 else ""

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0,1]:
		for operation in [false,true]:
			for mode in ["confirm","cancel","timeout","close","reset","disable","phase","lifecycle","reentry"]:
				var game = helper.fixture(t,seat); var owner = game.players[seat]
				owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true
				owner.sally_smoke_uses = 3 if operation else 0
				var original = CardBase.create(CardData.CardSubType.PEACH)
				owner.determined_cards.append(original)
				var facts: Array = []; game.card_action_committed.connect(func(e): facts.append(e))
				var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
				var result: Array = []; begin(game,owner,operation,result); await t.process_frame
				t.check(result.is_empty() and game._choice_prompt_stack.size() == 1 and bridge.input_owner() == seat, "I05e4b1 host/remote action owns one actual optional prompt")
				var prompt = game._choice_prompt_stack.back().overlay
				var action: String
				if operation:
					var options = bridge.snapshot(seat).controls.filter(func(c): return c.toggle)
					game._step_remaining = 7.0
					t.check(options.size() == 1 and not bridge.submit((seat+1)%5,options[0].id) and bridge.submit(seat,options[0].id), "I05e4b1 surgery selects original concrete fee through owner token")
					t.check(owner.determined_cards == [original] and game._step_remaining <= 7.0 and not owner.sally_surgery_pending, "I05e4b1 surgery selection neither pays nor restarts countdown")
					action = token(bridge,seat,"确认弃牌")
				else: action = token(bridge,seat,"确认抽烟")
				t.check(action != "" and not bridge.submit((seat+1)%5,action), "I05e4b1 wrong peer cannot confirm another body's skill")
				match mode:
					"confirm": bridge.submit(seat,action)
					"cancel": bridge.submit(seat,token(bridge,seat,"取消发动" if operation else "取消"))
					"timeout": game._countdown_on_timeout.call()
					"close": prompt.queue_free()
					"reset": owner.restore_game_start_state(); bridge.submit(seat,action)
					"disable": owner.sally_smoking_enabled = false; bridge.submit(seat,action)
					"phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
						bridge.submit(seat,action)
					"lifecycle": game._dying_lifecycle_generation += 1; bridge.submit(seat,action)
					"reentry":
						t.check(await game._perform_sally_smoking(owner,operation) == 0 and await game._perform_jiegui_discard(owner) == 0, "I05e4b1 active skill lease prevents reentry and overlapping voluntary action")
						bridge.submit(seat,token(bridge,seat,"取消发动" if operation else "取消"))
				for i in 4: await t.process_frame
				var applied = mode == "confirm"
				var expected = 1 if applied else (0 if mode in ["cancel","timeout","reentry"] else GameManager.CHOICE_INVALID)
				t.check(result == [expected] and game._sally_skill_pending.is_empty() and game._choice_prompt_stack.is_empty(), "I05e4b1 optional decline/timeout/technical invalidation and lease cleanup: "+mode)
				t.check(owner.hp == (2 if applied and not operation else 3) and owner.gender == ("male" if applied and not operation else "female"), "I05e4b1 HP/gender commit only after actual confirmation")
				t.check(game.deck._discard.count(original) == int(applied and operation) and owner.hand_size() == (0 if applied and operation else 1) and facts.is_empty(), "I05e4b1 surgery discards original once; neither skill forges card USE")
				t.check(owner.sally_surgery_pending == (applied and operation) and not owner.sally_surgery_active and owner.sally_smoke_active == (applied and not operation), "I05e4b1 operation stays pending; smoke establishes only on success")
				t.check(not bridge.submit(seat,action), "I05e4b1 consumed confirmation token cannot repeat resource payment")
				bridge.game = null; bridge.queue_free(); await helper.dispose(t,game)
	await dying(t,helper)
	await guards_and_gift(t,helper)
	await resources_and_detail(t,helper)
	await interrupted_sage(t,helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func dying(t,helper):
	for mode in ["peach","sage","fatal"]:
		var game = helper.fixture(t); var owner = game.players[0]
		owner.sally_smoking_enabled = true; owner.hp = 1
		var original = CardBase.create(CardData.CardSubType.PEACH)
		owner.determined_cards.append(original)
		var armor: CardBase
		if mode == "sage":
			armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
			owner.equip_card_to_slot("armor",armor); owner.sage_activated = true
			game._sage_save_override = func(): return true
		var seen: Array = []
		game._rescue_choice_override = func(p,q,options):
			seen.append([owner.gender,owner.sally_smoke_active,owner.sally_smoke_uses])
			return CardData.CardSubType.PEACH if mode == "peach" and p == owner and q == owner and options.has(CardData.CardSubType.PEACH) else -1
		var result: Array = []; begin(game,owner,false,result); await t.process_frame
		var prompt = game._choice_prompt_stack.back().overlay
		prompt.find_children("*","Button",true,false)[0].pressed.emit()
		for i in 10: await t.process_frame
		t.check(not seen.is_empty() and seen.all(func(row): return row == ["female",false,1]), "I05e4b1 real cost rescue precedes male/smoking state: "+mode)
		if mode == "sage":
			t.check(result == [GameManager.SallySkillOutcome.RESET_TERMINATED] and owner.hp == 3 and owner.gender == "female" and owner.hand_size() == 4, "I05e4b1 Q14 actual Sage restores female 3/3 and draws four, terminates original smoking")
			t.check(owner.sally_smoke_uses == 0 and not owner.sally_smoke_active and not owner.sally_smoke_pending_boost and game.deck._discard.count(original) == 1 and game.deck._discard.count(armor) == 1, "I05e4b1 Q14 keeps reset zero history, no reapplication or old resource refund")
		elif mode == "peach":
			t.check(result == [1] and owner.hp == 1 and owner.gender == "male" and owner.sally_smoke_uses == 1 and owner.sally_smoke_active, "I05e4b1 ordinary Peach rescue continues confirmed smoking")
		else:
			t.check(result == [GameManager.SallySkillOutcome.COST_FATAL] and owner.is_dead() and not owner.sally_smoke_active and owner.gender == "female", "I05e4b1 final cost death never establishes smoking state")
		await helper.dispose(t,game)

func guards_and_gift(t,helper):
	var game = helper.fixture(t); var owner = game.players[0]
	t.check(await game._perform_sally_smoking(owner) == 0, "I05e4b1 other private abilities never enable smoking")
	owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true; owner.hand.append(null)
	t.check(await game._perform_sally_smoking(owner,true) == 0, "I05e4b1 operation cannot start before three activations")
	owner.gender = "male"
	t.check(await game._perform_sally_smoking(owner) == 0, "I05e4b1 male body cannot smoke")
	owner.gender = "female"
	game.turn_manager.current_player_idx = 1; game.turn_manager.play_actor_idx = 1
	t.check(await game._perform_sally_smoking(owner) == 0, "I05e4b1 another body's PLAY cannot authorize smoking")
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_phase(0,TurnManager.Phase.PLAY)
	var result: Array = []; begin(game,owner,false,result); await t.process_frame
	game._choice_prompt_stack.back().overlay.find_children("*","Button",true,false)[0].pressed.emit()
	for i in 3: await t.process_frame
	t.check(result == [1] and owner.hp == 2 and owner.sally_smoke_active, "I05e4b1 actual granted PLAY permits confirmed smoke cost and state")
	t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_player_idx == 1, "I05e4b1 smoking returns to suspended giver START")
	await helper.dispose(t,game)

func resources_and_detail(t,helper):
	var game = helper.fixture(t); var owner = game.players[0]
	owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true
	owner.sally_smoke_uses = 1; owner.hp = 1; owner.hand.assign([null,null])
	var rescues: Array = []; var facts: Array = []
	game.card_action_committed.connect(func(e): facts.append(e))
	game._rescue_choice_override = func(p,q,options):
		rescues.append([owner.hp,owner.gender,owner.sally_smoke_active])
		return CardData.CardSubType.PEACH if p == owner and q == owner and options.has(CardData.CardSubType.PEACH) else -1
	var result: Array = []; begin(game,owner,false,result); await t.process_frame
	game._choice_prompt_stack.back().overlay.find_children("*","Button",true,false)[0].pressed.emit()
	for i in 6: await t.process_frame
	t.check(result == [1] and owner.hp == 1 and owner.hand_size() == 0 and owner.gender == "male" and owner.sally_smoke_uses == 2, "I05e4b1 second smoke pays two into negative HP and actually uses two Peaches before establishing state")
	t.check(rescues.any(func(row): return row[0] == -1) and rescues.any(func(row): return row[0] == 0) and rescues.all(func(row): return row[1] == "female" and not row[2]), "I05e4b1 negative and zero HP rescue steps never pre-establish smoking")
	t.check(facts.size() == 2 and facts.all(func(e): return e.kind == CardActionEvent.Kind.USE and e.from_hand and not e.is_virtual and e.actor_body == owner and e.card.sub_type == CardData.CardSubType.PEACH and e.settlement_completed), "I05e4b1 exactly two real self-rescue Peach USE facts complete; skill costs never forge card events")
	await helper.dispose(t,game)
	for seat in [0,1]:
		game = helper.fixture(t,seat); owner = game.players[seat]
		owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true; owner.sally_smoke_uses = 3
		owner.hand.append(null)
		var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
		var portrait = bridge.snapshot(seat).targets.get(str(seat),"")
		t.check(bridge.submit(seat,portrait), "I05e4b1 host/remote own portrait opens real skill detail")
		await t.process_frame
		var smoke = bridge.snapshot(seat).controls.filter(func(c): return "【抽烟】" in c.text)
		var operate = bridge.snapshot(seat).controls.filter(func(c): return "【肺部手术】" in c.text)
		t.check(smoke.size() == 1 and operate.size() == 1 and bridge.snapshot((seat+1)%5).controls.is_empty(), "I05e4b1 exactly one owner-only smoke and operation action")
		t.check(bridge.submit(seat,operate[0].id), "I05e4b1 detail dispatch opens actual operation prompt")
		await t.process_frame
		var options = bridge.snapshot(seat).controls.filter(func(c): return c.toggle)
		t.check(options.size() == 1 and bridge.submit(seat,options[0].id) and bridge.submit(seat,token(bridge,seat,"确认弃牌")), "I05e4b1 arbitrary hand fee can be selected and confirmed via actual opaque controls")
		for i in 3: await t.process_frame
		t.check(owner.hand_size() == 0 and owner.sally_surgery_pending and not owner.sally_surgery_active and owner.hp == 3 and owner.sally_smoke_uses == 3, "I05e4b1 arbitrary operation fee is discarded without concretization or early benefit")
		bridge.game = null; bridge.queue_free(); await helper.dispose(t,game)

func interrupted_sage(t,helper):
	var game = helper.fixture(t); var owner = game.players[0]
	owner.sally_smoking_enabled = true; owner.hp = 1
	owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	owner.sage_activated = true; game._sage_save_override = func(): return true
	game._rescue_choice_override = func(_p,_q,_o): return -1
	var sunny = game.players[1]; sunny.general_name = "桑尼·斯派"; sunny.max_hp = 4; sunny.hp = 4
	var seen: Array = []
	game._corruption_choice_override = func(_p,batch,_stage,_valid): seen.append(batch.owner); return GameManager.CHOICE_INVALID
	var result: Array = []; begin(game,owner,false,result); await t.process_frame
	game._choice_prompt_stack.back().overlay.find_children("*","Button",true,false)[0].pressed.emit()
	for i in 10: await t.process_frame
	t.check(seen == [owner] and result == [GameManager.CHOICE_INVALID], "I05e4b1 actual Sage draw Corruption interruption propagates instead of being swallowed as normal reset termination")
	t.check(owner.hp == 3 and owner.gender == "female" and owner.sally_smoke_uses == 0 and not owner.sally_smoke_active and owner.hand_size() == 4 and game._sally_skill_pending.is_empty(), "I05e4b1 nested invalidation preserves committed Sage restoration/draw and never revives original smoking")
	await helper.dispose(t,game)
