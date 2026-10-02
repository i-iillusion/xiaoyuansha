# C03：伤害链逐点询问；默认拼点平局重做，装傻为单次猜拳例外。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "C03：" + label)

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	for kind in ["kaiwen_deal", "kaiwen_receive", "bloodthirsty"]:
		for mode in ["decline", "mixed", "stale"]:
			suite.reset_players()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var source: Player = game.players[0]
			var target: Player = game.players[1]
			var owner: Player = target if kind == "kaiwen_receive" else source
			if kind.begins_with("kaiwen"):
				owner.general_name = "凯文·罗本"
			else:
				source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
				source.hp = 6
			var asks: Array = []
			var decisions = func():
				asks.append(true)
				return mode != "decline" and asks.size() == 2
			game._kaiwen_override = decisions
			game._bloodthirsty_override = decisions
			var choices: Array = [0, 0, 0, 2]
			var calls: Array = []
			game._rps_override = func(p):
				calls.append(p)
				if mode == "stale":
					game.turn_manager.current_phase = TurnManager.Phase.END
					game.turn_manager.current_phase = TurnManager.Phase.PLAY
				return choices.pop_front()
			await game._deal_damage(source, target, 2, EffectChain.DamageType.PHYSICAL)
			check(target.hp == 8 and asks.size() == 2, "两点伤害只结算一次并逐点询问：" + kind + mode)
			check(calls.size() == (0 if mode == "decline" else (1 if mode == "stale" else 4)), "拒绝不拼点，发动后平局重猜，过期立即停止：" + kind + mode)
			if kind == "bloodthirsty":
				check(source.hp == (7 if mode == "mixed" else 6), "只在当前有效拼点获胜后回复一次")
			else:
				check(owner.hand_size() == (2 if mode == "mixed" else 0), "只在当前有效拼点获胜后摸两张")
	for wins in [1, 2]:
		suite.reset_players()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var dying: Player = game.players[0]
		dying.general_name = "安普提·斯丢皮得"
		dying.hp = 0
		# 四个其他玩家；两胜、一平、一负恰好达标，平局不可重新询问。
		var choices: Array = [0, 2, 0, 2 if wins == 2 else 1, 0, 0, 0, 1]
		game._rps_override = func(_p): return choices.pop_front()
		await game._try_zhuangsha(dying)
		check(choices.is_empty() and dying.hp == (1 if wins == 2 else 0), "装傻四名对手赢两人即回复，平局只算一次")
	game._rps_override = Callable()
	game._kaiwen_override = Callable()
	game._bloodthirsty_override = Callable()
	suite.reset_players()
	game.turn_manager.current_phase = phase
