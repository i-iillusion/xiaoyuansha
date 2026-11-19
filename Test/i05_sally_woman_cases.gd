extends RefCounted

func begin(game, owner, result): result.append(await game._perform_sally_woman(owner))

func token(bridge, seat, text):
	var controls = bridge.snapshot(seat).controls.filter(func(c): return not c.disabled and c.text == text)
	return controls[0].id if controls.size() == 1 else ""

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0,1]:
		for mode in ["any", "concrete", "cancel", "timeout", "close", "owner_reset", "target_reset", "disable", "hand", "gender", "phase", "lifecycle", "target_dead", "ended", "overlap"]:
			var game = helper.fixture(t,seat)
			var owner = game.players[seat]; var target = game.players[(seat+1)%5]
			owner.sally_woman_enabled = true
			owner.hand.append(null)
			var card = CardBase.create(CardData.CardSubType.DODGE)
			owner.determined_cards.append(card)
			var facts: Array = []; game.card_action_committed.connect(func(e): facts.append(e))
			var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
			var result: Array = []; begin(game,owner,result)
			await t.process_frame
			t.check(result.is_empty() and game._choice_prompt_stack.size() == 1 and bridge.input_owner() == seat, "I05e3 private woman owns one real timed window for host/remote")
			var prompt = game._choice_prompt_stack.back().overlay
			t.check(not game._sally_woman_target_allowed(owner,owner) and token(bridge,seat,"目标："+owner.player_name) == "", "I05e3 SA-Q12 Woman excludes self in authoritative validation and host/remote target buttons")
			var target_token = token(bridge,seat,"目标："+target.player_name)
			t.check(target_token != "" and not bridge.submit((seat+1)%5,target_token) and bridge.submit(seat,target_token), "I05e3 target selection is restricted to actual input peer")
			game._step_remaining = 7.0
			var card_token = token(bridge,seat,"弃牌2：闪" if mode == "concrete" else "弃牌1：任意牌（未具体化）")
			t.check(card_token != "" and bridge.submit(seat,card_token), "I05e3 arbitrary and already-concrete fee selections use actual opaque buttons")
			t.check(target.gender == "male" and owner.hand_size() == 2 and game._step_remaining <= 7.0 and not prompt.confirm.disabled, "I05e3 target/card selections share countdown without payment or effect")
			match mode:
				"any", "concrete": bridge.submit(seat, token(bridge,seat,"确认发动女人"))
				"cancel": bridge.submit(seat, token(bridge,seat,"取消发动女人"))
				"timeout": game._countdown_on_timeout.call()
				"close": prompt.queue_free()
				"owner_reset": owner.restore_game_start_state(); prompt.confirm.pressed.emit()
				"target_reset": target.restore_game_start_state(); prompt.confirm.pressed.emit()
				"disable": owner.sally_woman_enabled = false; prompt.confirm.pressed.emit()
				"hand": owner.hand.append(null); prompt.confirm.pressed.emit()
				"gender": target.gender = "none"; prompt.confirm.pressed.emit()
				"phase":
					game.turn_manager.current_phase = TurnManager.Phase.END
					game.turn_manager.current_phase = TurnManager.Phase.PLAY
					prompt.confirm.pressed.emit()
				"lifecycle": game._dying_lifecycle_generation += 1; prompt.confirm.pressed.emit()
				"target_dead": target.hp = 0; target.mark_dead(); prompt.confirm.pressed.emit()
				"ended": game._finish_game("平局","I05e3 engineering termination")
				"overlap":
					t.check(await game._perform_sally_woman(owner) == 0 and game._choice_prompt_stack.size() == 1, "I05e3 woman cannot reenter or overlap other play skills")
					prompt.find_children("*","Button",true,false).back().pressed.emit()
			for i in 4: await t.process_frame
			var committed = mode in ["any","concrete"]
			var expected = 1 if committed else (0 if mode in ["cancel","timeout","overlap"] else GameManager.CHOICE_INVALID)
			t.check(result == [expected] and game._sally_woman_pending.is_empty() and game._choice_prompt_stack.is_empty(), "I05e3 explicit activation/decline/technical result and lease cleanup: "+mode)
			t.check(owner.hand_size() == (1 if committed else (3 if mode == "hand" else 2)) and game.deck._discard.count(card) == int(mode == "concrete"), "I05e3 one original fee only on final confirmation: "+mode)
			t.check(target.gender == ("female" if committed else ("none" if mode == "gender" else "male")) and facts.is_empty(), "I05e3 no virtual USE or gender changes from stale/unconfirmed skill: "+mode)
			t.check(not bridge.submit(seat,target_token) and not bridge.submit(seat,card_token), "I05e3 stale target/fee tokens cannot repeat skill")
			if committed:
				t.check(game.action_history.entries.any(func(e): return e.kind == "skill" and "【女人】" in e.text), "I05e3 confirmed woman publishes skill result")
				target.restore_game_start_state()
				t.check(target.gender == "male", "I05e3 affected general restores its own opening gender")
			bridge.game = null; bridge.queue_free()
			await helper.dispose(t,game)
	await gifted_and_guards(t,helper)
	await detail_and_topology(t,helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func gifted_and_guards(t,helper):
	var game = helper.fixture(t); var owner = game.players[0]
	owner.hand.append(null)
	t.check(await game._perform_sally_woman(owner) == 0, "I05e3 Jiegui enable does not enable Woman")
	owner.sally_woman_enabled = true
	game.turn_manager.current_player_idx = 1; game.turn_manager.play_actor_idx = 1
	t.check(await game._perform_sally_woman(owner) == 0 and owner.hand_size() == 1, "I05e3 cannot pay Woman in another actor's PLAY")
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_phase(0,TurnManager.Phase.PLAY)
	var result: Array = []; begin(game,owner,result); await t.process_frame
	var prompt = game._choice_prompt_stack.back().overlay
	var buttons = prompt.find_children("*","Button",true,false)
	var target_button = buttons.filter(func(b): return b.text == "目标："+game.players[1].player_name)
	var fee_button = buttons.filter(func(b): return b.text == "弃牌1：任意牌（未具体化）")
	t.check(target_button.size() == 1 and fee_button.size() == 1, "I05e3 granted PLAY selects an actual other target and original fee after self exclusion")
	target_button[0].pressed.emit(); fee_button[0].pressed.emit(); prompt.confirm.pressed.emit()
	for i in 3: await t.process_frame
	t.check(result == [1] and game.players[1].gender == "female" and owner.hand_size() == 0, "I05e3 real granted PLAY accepts one confirmed Woman fee")
	t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_player_idx == 1, "I05e3 gender action restores suspended parent START")
	await helper.dispose(t,game)

func detail_and_topology(t,helper):
	var game = helper.fixture(t)
	var owner = game.players[0]
	owner.sally_woman_enabled = true; owner.hand.append(null)
	var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
	var portrait = bridge.snapshot(0).targets.get("0","")
	t.check(portrait != "" and bridge.submit(0,portrait), "I05e3 actual own portrait opens Woman detail")
	await t.process_frame
	var actions = bridge.snapshot(0).controls.filter(func(c): return "【女人】" in c.text)
	t.check(actions.size() == 1 and bridge.snapshot(1).controls.is_empty(), "I05e3 exactly one owner-only Woman detail action")
	t.check(bridge.submit(0,actions[0].id), "I05e3 actual detail dispatch enters Woman selection")
	await t.process_frame
	t.check(token(bridge,0,"取消发动女人") != "" and bridge.submit(0,token(bridge,0,"取消发动女人")), "I05e3 detail invocation remains cancellable without payment")
	for i in 3: await t.process_frame
	game._mountain_rules_enabled = true
	game.players[4].general_name = "吉姆·芒顿"
	var mountain = game._spawn_mountain_at(game.players[4],0,1)
	game._spawn_mountain_at(game.players[4],3,4)
	t.check(not game._sally_woman_target_allowed(owner,mountain) and not game._sally_woman_target_allowed(owner,game.players[1]) and game._sally_woman_target_allowed(owner,game.players[4]), "I05e3 Woman rejects mountain bodies and isolated players while same-region player remains valid")
	bridge.game = null; bridge.queue_free(); await helper.dispose(t,game)
	game = helper.fixture(t); owner = game.players[0]
	owner.sally_woman_enabled = true
	game.players[3].general_name = "克里斯·安德森"
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,game.players[3])
	t.check(not game._sally_woman_target_allowed(owner,dragon), "I05e3 unseen dragon cannot be chosen by Woman")
	var audience: Array[Player] = [owner]
	game.fire_dragon_state.record_use(game.unit_registry.id_for(dragon),1,audience)
	t.check(not game._sally_woman_target_allowed(owner,dragon) and dragon.gender == "none", "I05e6-Q1 revealed dragon is a unit and cannot be changed by Woman")
	owner.hand.append(null)
	var result: Array = []; begin(game,owner,result); await t.process_frame
	var prompt = game._choice_prompt_stack.back().overlay
	var targets = prompt.find_children("*","Button",true,false)
	t.check(not targets.any(func(b): return b.text == "目标："+dragon.player_name) and targets.any(func(b): return b.text == "目标："+game.players[3].player_name), "I05e6-Q1 real prompt excludes the revealed unit and still offers its controller")
	targets.filter(func(b): return b.text == "取消发动女人")[0].pressed.emit()
	for i in 3: await t.process_frame
	t.check(result == [0] and owner.hand_size() == 1 and dragon.gender == "none", "I05e6-Q1 no unit mutation or card payment on cancellation")
	await helper.dispose(t,game)
