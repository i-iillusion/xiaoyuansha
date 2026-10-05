extends "res://Test/standalone_grant_cases.gd"

func configure(actor: Player, wins: int):
	actor.general_name = "史蒂芬·彼特先斯"
	actor.hp = 2
	actor.awoken = true
	actor.hand.assign([null, null, null, null, null, null])
	game._zhuangbi_blocked_this_phase = false
	game._zhuangbi_again_override = func(): return false
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game._rps_override = func(p):
		return GameManager.RPS_ROCK if p == actor else (GameManager.RPS_SCISSORS if p.seat_index <= wins else GameManager.RPS_PAPER)
	for p in game.players:
		if p != actor: p.hand.assign([null])

func run(host):
	suite = host
	game = host.game
	var connected = game.turn_manager.phase_changed.is_connected(game._on_phase_changed)
	if connected: game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	for n in range(1, 5):
		for wins in range(n + 1):
			suite.reset_players()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			configure(game.players[0], wins)
			var targets: Array[Player] = []
			for seat in range(1, n + 1): targets.append(game.players[seat])
			var damaged: Array = []
			var collect = func(_hp, p):
				if p.hp == 9 and not damaged.has(p.seat_index): damaged.append(p.seat_index)
			for p in targets: p.hp_changed.connect(collect.bind(p))
			await game._execute_zhuangbi(targets)
			var success = wins >= ceili(n / 2.0)
			suite.check(game.players[0].hand.size() == 5 and targets.all(func(p): return p.hand.is_empty()), "E03-R02：1～4目标每种胜负均完整独立强制付费")
			suite.check(targets.all(func(p): return p.hp == (9 if success and p.seat_index <= wins else 10)) and game.turn_manager.current_phase == (TurnManager.Phase.PLAY if success else TurnManager.Phase.DISCARD), "E03-R02：向上取整成功阈值/超过半数失败结束普通出牌：%d人/%d胜" % [n, wins])
			var expected: Array = []
			if success:
				for seat in range(1, wins + 1): expected.append(seat)
			suite.check(damaged == expected and not game._zhuangbi_blocked_this_phase, "E03-R02：成功按拼点顺序逐个伤害输家，无旧各半禁用")
			for p in targets: p.hp_changed.disconnect(collect.bind(p))
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	configure(game.players[0], 2)
	game.players[0].hp = 1
	game._paixiong_override = func(): return false # 明确不发动拍胸脯，反伤确实进入死亡结算。
	game.players[0].identity = "忠臣"
	game.players[4].identity = "主公"
	game.players[1].identity = "忠臣"
	game.players[2].identity = "反贼"
	game.players[3].identity = "内奸"
	game.players[1].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.THORN_ARMOR))
	var calls: Array = []
	game._rps_override = func(p):
		calls.append(p)
		return GameManager.RPS_ROCK if p.seat_index == 0 else (GameManager.RPS_PAPER if calls.size() > 4 else GameManager.RPS_SCISSORS)
	await game._execute_zhuangbi([game.players[1], game.players[2]] as Array[Player])
	suite.check(game.players[0].is_dead() and game.players[1].hp == 9 and game.players[2].hp == 9 and not game._game_over, "E03-R02/TIME-04：第一输家荆棘反伤令发动者最终死亡，第二输家仍受无源1伤")
	suite.check(calls.size() == 6 and game.players[0].hand.is_empty(), "E03-R02/TIME-04：来源死亡不重做费用/拼点，不再询问死人重新发动")
	setup_human()
	var source = game.players[1]
	configure(game.players[0], 0)
	source.hand.assign([null])
	var act = func():
		await game._execute_zhuangbi([game.players[2], game.players[3], game.players[4]] as Array[Player])
	act.call_deferred()
	var result = await game._maybe_meiyong(source)
	suite.check(result == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.current_player_idx == 1 and game.players[0].hand.size() == 5 and source.hand.size() == 2, "E03-R02/22d-Q1：获赠出牌装逼失败结束后恢复源START，B不额外弃至2，A不代弃")
	await suite.process_frame
	suite.reset_players()
	game._paixiong_override = Callable()
	game._rps_override = Callable()
	game._meiyong_override = Callable()
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	if connected: game.turn_manager.phase_changed.connect(game._on_phase_changed)
	game = null
	suite = null
