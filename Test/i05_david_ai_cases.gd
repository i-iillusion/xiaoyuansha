extends RefCounted
const Core = preload("res://Test/i05_david_wrestling_core_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for fault in ["none", "field", "general", "gate"]:
		var game = Core.new().fixture(t)
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		game.lan_enabled = false
		game.turn_manager.current_player_idx = 1
		var p = game.players[1]
		p.hp = p.max_hp; p.hand.assign([null, null]); p.farm_empty_fields = 1
		p.wine_stacks = 1
		game.turn_manager._set_turn_count("strike", 1, 1)
		var actions = game._ai_play_candidates(game._ai_observation(p))
		var upgrades = actions.filter(func(a): return a.get("skill", "") == "farming_upgrade")
		t.check(upgrades.size() == 1, "I05b5 AI offers one legal upgrade action from its own public resources")
		if fault == "field": p.farm_empty_fields = 0
		elif fault == "general": p.general_name = "稻草人"
		elif fault == "gate": game._david_rules_enabled = false
		if fault != "none":
			await game._execute_ai_action(upgrades[0])
			t.check(p.hand_size() == 2 and p.farm_good_fields == 0 and game._farming_upgrade_pending.is_empty(), "I05b5 expired AI upgrade never pays old hand or creates field")
			t.check(not game._ai_play_candidates(game._ai_observation(p)).any(func(a): return a.get("skill", "") == "farming_upgrade"), "I05b5 AI does not reoffer illegal field/general/gate action")
		else:
			game.ai_driver.action_budget = 1 # One ordinary production decision, not a changed match limit.
			var result = await game.ai_driver.run(func(): return game._ai_observation(p), game._ai_play_candidates, game._execute_ai_action, func(): return true)
			t.check(result.actions == 1 and p.hand_size() == 0 and p.farm_good_fields == 1 and p.farm_empty_fields == 0, "I05b5 ordinary AI selects upgrade and really pays both hand cards through shared skill")
			t.check(p.farm_hand_actions == 0 and game._farming_upgrade_pending.is_empty(), "I05b5 AI upgrade costs never count as hand-card USE")
			p.hp -= 1
			var heal = game._ai_play_candidates(game._ai_observation(p)).filter(func(a): return a.sub == CardData.CardSubType.PEACH)
			t.check(heal.size() == 1, "I05b5 zero-hand AI can spend earned good field on legal self Peach")
			await game._execute_ai_action(heal[0])
			t.check(p.hp == p.max_hp and p.farm_good_fields == 0 and p.farm_empty_fields == 1 and p.farm_hand_actions == 0, "I05b5 AI shared virtual Peach returns empty field without inventing hand-use income")
		await Farming.new().dispose(t, game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]
