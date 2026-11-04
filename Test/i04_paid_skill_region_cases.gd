extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for general in ["杰基·斯特朗","史蒂芬·彼特先斯"]:
		for walls in [0,1,2]:
			for concrete in [false,true]:
				var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
				load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,walls)
				var actor = game.players[1]
				var target = game.players[0]
				actor.general_name = general
				actor.awoken = true # Keep mandatory awakening outside this region test.
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
				game.turn_manager.play_actor_idx = 1
				game._set_input_player(actor)
				actor.hand.assign([null,null])
				actor.determined_cards.clear()
				target.hand.clear()
				target.determined_cards.clear()
				if concrete: target.determined_cards.append(CardBase.create(CardData.CardSubType.DODGE))
				else: target.hand.append(null)
				game._hand_discard_override = func(snapshot,count,_mandatory): return snapshot.defaults(count)
				game._rps_override = func(p): return game.RPS_ROCK if p == actor else game.RPS_SCISSORS
				game._zhuangbi_again_override = func(): return false
				game.players[3].hand.clear()
				game.players[3].determined_cards.clear()
				var bridge = LanGameBridge.new()
				bridge.game = game
				game._is_campus_targeting = general == "杰基·斯特朗"
				game._is_zhuangbi_targeting = not game._is_campus_targeting
				t.check(bridge._declaration_target_allowed(target) == (walls < 2) and bridge._declaration_target_allowed(game.players[3]) == false, "I04 Bridge declaration gate excludes cross-region and empty-hand targets")
				game._is_campus_targeting = false
				game._is_zhuangbi_targeting = false
				bridge.free()
				var hp = target.hp
				var paid = game.deck._discard.size()
				if general == "杰基·斯特朗": await game._execute_campus_dominator(actor,target)
				else:
					var targets: Array[Player] = [target]
					await game._execute_zhuangbi(targets)
				var blocked = walls == 2
				t.check(actor.hand_size() == (2 if blocked else 1) and target.hand_size() == (1 if blocked else 0), "I04 paid skill region rejects before either fee; single/no wall preserves payment: " + general)
				t.check(target.hp == hp - (0 if blocked else 1) and game.deck._discard.size() == paid + (0 if blocked or not concrete else 1), "I04 paid skill region prevents cross-wall damage without erasing legal same-region settlement")
				t.check(game._campus_execution_owner == -1 and game._zhuangbi_execution_owner == -1, "I04 region rejection and completed skill both release execution ownership")
				if blocked:
					var rev = game.turn_manager.get_context_revision()
					t.check(not game._paid_skill_rps_valid(actor,target,rev) and game._paid_skill_rps_valid(actor,game.players[3],rev), "I04 post-await validity separates cross-region and same-region opponents")
				await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
