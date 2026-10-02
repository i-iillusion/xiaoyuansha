extends RefCounted

var suite

func check(ok: bool, label: String):
	suite.check(ok, "D04：" + label)

func run(host):
	suite = host
	var previous = [GameManager.selected_players, GameManager.selected_mode,
		GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for count in [2, 3, 5]:
		var traces: Array = []
		for repeat in 2:
			GameManager.selected_players = count
			GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL
			GameManager.selected_general = "稻草人"
			GameManager.random_general = false
			GameManager.random_identity = false
			var game = load("res://Scenes/Game.tscn").instantiate()
			game.set_script(load("res://Test/replay_game.gd"))
			game.auto_start = false
			suite.root.add_child(game)
			await suite.process_frame
			game.ai_driver.rng.seed = 7401
			# 使用生产默认出牌策略，0号响应钩子只模拟同样的自动选择。
			game._dodge_override = func(): return true
			game._aoe_override = func(): return true
			game._duel_respond_override = func(): return true
			game._duel_second_override = func(): return true
			game._nullify_override = func(): return false
			game._sacrifice_override = func(): return false
			game._hand_discard_override = func(snapshot, amount, _mandatory): return snapshot.defaults(amount)
			game._zone_pick_override = func(): return "hand"
			game._rescue_choice_override = func(rescuer, dying, options): return game._choose_ai_rescue(rescuer, dying, options)
			var winners: Array = []
			game.game_over.connect(func(winner): winners.append(winner))
			game.start_game()
			game._stop_countdown()
			for frame in 240:
				if game._game_over:
					break
				await suite.process_frame
			check(game._game_over and winners.size() == 1, "%d人从真实开局到唯一终局通知，重复%d" % [count, repeat])
			check(game.replay_violations.is_empty(), "%d人完整对局没有非法候选或实体牌重复归属" % count)
			var outcome = IdentityVictory.evaluate(game.players) if count == 5 else FreeForAllVictory.evaluate(game.players)
			check(not outcome.is_empty() and winners == [outcome.get("winner", "")], "%d人实际终局符合独立判胜器" % count)
			var terminal_state = game.replay_state()
			var terminal_actions = game.replay_actions.size()
			await suite.process_frame
			await suite.process_frame
			check(game.replay_state() == terminal_state and game.replay_actions.size() == terminal_actions
				and winners.size() == 1, "%d人终局后无额外行动、摸牌或重复通知" % count)
			var dead_cards_clear = true
			for p in game.players:
				if p.is_dead() and (p.hand_size() != 0 or not p.equipment.is_empty() or not p.judgment_cards.is_empty()):
					dead_cards_clear = false
			check(dead_cards_clear, "%d人最终死者已清牌且后续不重新摸牌" % count)
			var trace = {"actions": game.replay_actions, "logs": game.replay_logs,
				"final": game.replay_state(), "winners": winners}
			traces.append(trace)
			var folder = "res://.git/local-ci/D04"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			var file = FileAccess.open(folder + "/%d-%d.json" % [count, repeat], FileAccess.WRITE)
			file.store_string(JSON.stringify(trace))
			file.close()
			print("REPLAY %d/%d actions=%d winners=%s" % [count, repeat, game.replay_actions.size(), str(winners)])
			game._game_over = true # 仅停止已失败超时场景的清理，不计为成功或写进终局轨迹。
			game.queue_free()
			await suite.process_frame
		check(traces[0] == traces[1], "%d人相同种子完整动作/牌实例/日志/终局一致" % count)
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
