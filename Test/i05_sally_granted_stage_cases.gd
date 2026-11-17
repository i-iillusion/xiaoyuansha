extends RefCounted

func snapshot(p: Player) -> Array:
	var values: Array = [p.hp,p.hand.duplicate(),p.determined_cards.duplicate()]
	for field in Player.GENERAL_STATE_FIELDS:
		var value = p.get(field)
		values.append(value.duplicate(true) if value is Dictionary or value is Array else value)
	return values

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0,1]:
		for phase in [TurnManager.Phase.PLAY,TurnManager.Phase.JUDGE,TurnManager.Phase.DRAW]:
			for state in ["female","protected","boosted","operation"]:
				var game = helper.fixture(t,seat); var owner = game.players[seat]
				owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true
				owner.sally_woman_enabled = true; owner.sally_smoke_uses = 3
				owner.hand.append(null)
				var original = CardBase.create(CardData.CardSubType.PEACH); owner.determined_cards.append(original)
				if state == "protected":
					owner.gender = "male"; owner.sally_smoke_active = true; owner.sally_smoke_pending_boost = true
				if state == "boosted":
					owner.gender = "male"; owner.sally_boost_turn = game.turn_manager.turn_id; owner.sally_female_end_turn = game.turn_manager.turn_id
				if state == "operation": owner.sally_surgery_active = true
				var giver = (seat+1)%5
				game.turn_manager.current_player_idx = giver; game.turn_manager.current_phase = TurnManager.Phase.START
				var frame = game.turn_manager.begin_standalone_phase(seat,phase)
				game._set_input_player(owner)
				var before = snapshot(owner); var history = game.action_history.entries.size()
				var facts: Array = []; game.card_action_committed.connect(func(e): facts.append(e))
				t.check(not frame.is_empty() and not game._can_use_sally_turn_skill(owner), "I05e-Q15 granted phase never qualifies as a complete personal turn")
				t.check(await game._perform_sally_smoking(owner) == 0 and await game._perform_sally_smoking(owner,true) == 0, "I05e-Q15 both smoking and operation are refused even with resources and three prior uses")
				t.check(snapshot(owner) == before and facts.is_empty() and game.action_history.entries.size() == history and game.deck._discard.count(original) == 0, "I05e-Q15 refused actions preserve HP, original hands, all general fields and past smoking effects")
				t.check(game._sally_skill_pending.is_empty() and game._choice_prompt_stack.is_empty(), "I05e-Q15 refused grant cannot open a timed action or leave a pending lease")
				var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
				var portrait = bridge.snapshot(seat).targets.get(str(seat),"")
				t.check(portrait != "" and bridge.submit(seat,portrait), "I05e-Q15 host/remote can inspect own detail during a granted phase")
				await t.process_frame
				var view = bridge.snapshot(seat)
				t.check(view.controls.filter(func(c): return "【抽烟】" in c.text or "【肺部手术】" in c.text).is_empty() and view.labels.any(func(s): return "【抽烟】" in s) and view.labels.any(func(s): return "【肺部手术】" in s), "I05e-Q15 detail keeps descriptions but offers no smoking/operation command")
				if phase == TurnManager.Phase.PLAY:
					t.check(view.controls.filter(func(c): return "【女人】" in c.text).size() == 1 and game._can_use_play_skill(owner), "I05e-Q15 special ban does not revoke other granted-PLAY skills")
				t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_player_idx == giver and snapshot(owner) == before, "I05e-Q15 finishing the granted stage preserves previous smoking effects and parent turn")
				bridge.game = null; bridge.queue_free(); await helper.dispose(t,game)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]
