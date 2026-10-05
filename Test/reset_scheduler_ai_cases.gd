extends RefCounted

var suite
var game: GameManager

func run(host):
	suite = host
	game = host.game
	suite.reset_players()
	var scheduler = RuleScheduler.new()
	var old_context = RefCounted.new()
	var new_context = RefCounted.new()
	var done: Array = [false]
	var ran: Array = []
	scheduler.enqueue("old", func(_context, _stage): await suite.process_frame)
	scheduler.enqueue("old remainder", func(_context, _stage): ran.append("old remainder"))
	var restart = func():
		scheduler.reset()
		scheduler.enqueue("new", func(context, _stage):
			await suite.process_frame
			suite.check(scheduler._frames.size() == 1 and scheduler._frames.back().context == context, "E03e-22d-1：旧调度await不pop新帧")
			await suite.process_frame
			ran.append("new"))
		suite.check(await scheduler.checkpoint(new_context, "new stage"), "E03e-22d-1：新调度正常完成")
		done[0] = true
	restart.call_deferred()
	suite.check(not await scheduler.checkpoint(old_context, "old stage") and scheduler.is_paused(), "E03e-22d-1：重开旧检查点显式失效，新检查点仍暂停")
	while not done[0]: await suite.process_frame
	suite.check(ran == ["new"] and scheduler._frames.is_empty() and scheduler._pending.is_empty(), "E03e-22d-1：旧剩余规则不执行，新队列/帧正常清理")
	for stage in ["on_play_card", "before_deal_damage", "damage_applied"]:
		suite.reset_players()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var chain = game._new_damage_chain(game.players[0], game.players[1], null, 1, EffectChain.DamageType.PHYSICAL)
		var callback = chain.trigger_callback
		chain.trigger_callback = func(current, event, subject, source, data):
			if event == stage: game.reset_game_over_state()
			if event == stage: return false
			return await callback.call(current, event, subject, source, data)
		await chain.start()
		suite.check(chain.continuation_invalid and game.players[1].hp == (9 if stage == "damage_applied" else 10), "E03e-22d-1：真实效果链重开不继续旧伤害/后效，已提交伤害保留：" + stage)
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var reset = func(): game.reset_game_over_state()
	reset.call_deferred()
	suite.check(await game._show_choice_popup("重开独立通用窗口", ["确认"]) == GameManager.CHOICE_INVALID, "E03e-22d-1：普通通用窗口在原阶段同名重开即时失效，无须调用者另传条件")
	await suite.process_frame
	var connected = game.turn_manager.phase_changed.is_connected(game._on_phase_changed)
	if connected: game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 1
	game.turn_manager.play_actor_idx = 1
	var actor = game.players[1]
	actor.hp = 5
	actor.hand.assign([CardBase.create(CardData.CardSubType.PEACH)])
	var original_chooser = game.ai_driver.chooser
	done[0] = false
	var revision = game.turn_manager.get_context_revision()
	game.ai_driver.chooser = func(_view, _options):
		game.reset_game_over_state()
		game.ai_driver.chooser = func(_new_view, _new_options):
			await suite.process_frame
			await suite.process_frame
			await suite.process_frame
			return -1
		var next = func():
			await game._run_ai_play(actor)
			done[0] = true
		next.call_deferred()
		await suite.process_frame
		await suite.process_frame
		return 0
	await game._run_ai_play(actor)
	suite.check(actor.hand.size() == 1 and actor.hp == 5 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._ai_running_revisions.get(revision, -1) == game._dying_lifecycle_generation, "E03e-22d-1：旧AI答复不付牌/推进新阶段/清新执行锁")
	while not done[0]: await suite.process_frame
	suite.check(actor.hand.size() == 1 and actor.hp == 5 and game.turn_manager.current_phase == TurnManager.Phase.DISCARD and game._ai_running_revisions.is_empty(), "E03e-22d-1：重开相同阶段代次的新AI可执行并正常结束")
	game.ai_driver.chooser = original_chooser
	if connected: game.turn_manager.phase_changed.connect(game._on_phase_changed)
	suite.reset_players()
	game = null
	suite = null
