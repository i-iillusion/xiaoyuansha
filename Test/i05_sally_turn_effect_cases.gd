extends RefCounted

func wait_play(t,game,seat):
	for i in 90:
		if game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.turn_manager.current_player_idx == seat: return true
		await t.process_frame
	return false

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	var game = helper.fixture(t); var owner = game.players[0]; var tm = game.turn_manager
	owner.sally_smoking_enabled = true; owner.sally_surgery_enabled = true; owner.sally_smoke_uses = 3
	owner.gender = "male"; owner.sally_smoke_active = true; owner.sally_smoke_pending_boost = true
	var fee = CardBase.create(CardData.CardSubType.PEACH); owner.determined_cards.append(fee)
	var actions = load("res://Test/i05_sally_smoking_action_cases.gd").new()
	var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
	var result: Array = []; actions.begin(game,owner,true,result); await t.process_frame
	var cards = bridge.snapshot(0).controls.filter(func(c): return c.toggle)
	t.check(cards.size() == 1 and bridge.submit(0,cards[0].id), "I05e4b2 actual surgery selects original fee")
	t.check(bridge.submit(0,actions.token(bridge,0,"确认弃牌")), "I05e4b2 actual surgery confirms through owner bridge")
	for i in 4: await t.process_frame
	t.check(result == [1] and owner.sally_surgery_due_round == tm.rounds.round_id+1 and not owner.sally_surgery_active and game.deck._discard.count(fee) == 1, "I05e4b2 surgery records actual next round, never current turn id")
	var initial_round = tm.rounds.round_id
	game.end_play_phase(); t.check(await wait_play(t,game,1), "I05e4b2 original full turn ends naturally")
	for seat in range(1,5):
		if seat == 4: owner.facedown = true
		game.end_play_phase()
		t.check(await wait_play(t,game,seat+1 if seat<4 else 1), "I05e4b2 complete actual first rotation, including flipped Sally skip")
	t.check(tm.rounds.round_id == initial_round+1 and not owner.facedown and owner.sally_surgery_active and not owner.sally_surgery_pending and SallySmokingState.cost(owner) == 0, "I05e4b2 next round matures surgery even when owner's entire turn is skipped")
	t.check(owner.sally_smoke_active and owner.sally_smoke_pending_boost and owner.gender == "male" and owner.hand_size() == 0, "I05e4b2 flipped skip neither consumes smoking effects nor draws cards")
	for seat in range(1,5):
		game.end_play_phase(); t.check(await wait_play(t,game,seat+1 if seat<4 else 0), "I05e4b2 actual next rotation reaches normal Sally START")
	t.check(tm.rounds.round_id == initial_round+2 and not owner.sally_smoke_active and not owner.sally_smoke_pending_boost and SallySmokingState.doubles_response(owner,tm.turn_id) and owner.gender == "male", "I05e4b2 next normal START exchanges protection for current-turn boost")
	game.end_play_phase(); t.check(await wait_play(t,game,1), "I05e4b2 boosted turn finishes naturally")
	t.check(owner.gender == "female" and owner.sally_boost_turn == -1 and owner.sally_surgery_active, "I05e4b2 actual END restores gender and retires boost, not surgery")
	owner.restore_game_start_state(); game._advance_sally_round_effects()
	t.check(owner.sally_surgery_due_round == -1 and not owner.sally_surgery_active and not owner.sally_surgery_pending and not owner.sally_smoke_active, "I05e4b2 general restoration removes operation deadline and prevents later reactivation")
	bridge.game = null; bridge.queue_free(); await helper.dispose(t,game)
	await end_continuation(t,helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func end_continuation(t,helper):
	var game = helper.fixture(t); var owner = game.players[0]; var tm = game.turn_manager
	tm.phase_changed.disconnect(game._on_phase_changed)
	owner.sally_smoking_enabled = true; owner.gender = "male"; owner.sally_smoke_active = true; owner.sally_smoke_pending_boost = true
	tm.current_phase = TurnManager.Phase.START
	await game._do_start(0)
	var simba = game.players[4]; simba.general_name = "辛巴·古德曼"; simba.simba_tuanfei_enabled = true; simba.tuanfei_extra_draws = 3
	var sunny = game.players[3]; sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	var observed: Array = []
	game._corruption_choice_override = func(_p,_batch,_stage,_valid):
		observed.append([owner.gender,SallySmokingState.doubles_response(owner,tm.turn_id)])
		return -1
	tm.current_phase = TurnManager.Phase.END
	await game._do_end(0)
	t.check(observed == [["female",true]] and simba.hand_size() == 1, "I05e4b2 female at END entry, boost retained throughout actual reward/Corruption continuation")
	t.check(owner.sally_boost_turn == -1 and tm.current_player_idx == 1, "I05e4b2 boost expires only after full END continuation commits")
	await helper.dispose(t,game)
