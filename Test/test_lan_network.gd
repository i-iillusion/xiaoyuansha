extends SceneTree

const Driver = preload("res://Test/lan_autoplayer.gd")
var session: LanSession
var children: Array[int] = []
var checks := 0
var failures := 0
var child := false
var port := 0
var started := false
var final_seen := false
var last_token := ""
var exit_at := 0
var driver = Driver.new()
var child_logs: Array[String] = []
var size := 2
var mode := ""
var actions := 0
var drop_on_match := false
var drop_case := false
var interrupted := false
var saved_game: GameManager
var history_digest := ""
var pace_checked := false
var space_case := false
var shifted_seen := false
var unit_case := false
var units_seen := false
var owns_dragon := false
var unit_reply_submitted := false
var unit_removal_seen := false
var unit_input_started := false
var unit_input_result := -2
var unit_dragon: Player
var medicine_case := false
var medicine_seen := false
var owns_medicine := false
var medicine_replied := false
var medicine_seeded := false
var egg_seen := false
var summon_case := false
var summon_seen := false
var summoned_body_seen := false
var summon_paid := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + text)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--lan-child": child = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--players="): size = int(arg.trim_prefix("--players="))
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg == "--drop-on-match": drop_on_match = true
		if arg == "--drop-case": drop_case = true
		if arg == "--space-case": space_case = true
		if arg == "--unit-case": unit_case = true
		if arg == "--medicine-case": medicine_case = true
		if arg == "--summon-case": summon_case = true
	var holder = Node.new()
	holder.name = "LanHarness"
	root.add_child(holder)
	session = LanSession.new()
	session.name = "Session"
	holder.add_child(session)
	session.notice.connect(func(text): print("NOTICE ", text))
	session.state_received.connect(_state)
	exit_at = Time.get_ticks_msec() + 45000
	if child:
		session.lobby_changed.connect(func(state):
			if state.is_empty(): return
			for member in state.members:
				if member.peer == session.multiplayer.get_unique_id() and not member.ready and not state.playing:
					session.choose("稻草人", true))
		check(session.join_room("127.0.0.1", "Remote", port) == OK, "client ENet start")
	else:
		port = 26000 + randi_range(0, 10000)
		check(session.host("Host", size, port, mode) == OK, "host ENet start")
		check(session.set_pace(AiActionPacer.Speed.SLOW), "host configures slow pace before match")
		session.choose("稻草人", true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1, size):
			var child_log = ProjectSettings.globalize_path("res://.git/lan-tests/client-%d-%d.log" % [port, i])
			child_logs.append(child_log)
			var args = PackedStringArray(["--headless", "--disable-render-loop", "--log-file", child_log, "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://Test/test_lan_network.gd", "--", "--lan-child", "--port=" + str(port)])
			if drop_case: args.append("--drop-on-match")
			if space_case: args.append("--space-case")
			if unit_case: args.append("--unit-case")
			if medicine_case: args.append("--medicine-case")
			if summon_case: args.append("--summon-case")
			var pid = OS.create_process(OS.get_executable_path(), args)
			check(pid > 0, "independent client process launched")
			if pid > 0: children.append(pid)
	while Time.get_ticks_msec() < exit_at:
		if not child and not started and session.members.size() == size:
			if (medicine_case or summon_case) and not medicine_seeded and session.members.values().all(func(member): return bool(member.ready)):
				# Authorized metadata allocation fixture, not a released general menu.
				# Same server bridge/opening, ordinary HP, roles, phases and victory.
				var peers = session.members.keys().filter(func(peer): return peer != 1)
				session.members[peers[0]].general = "克里斯·西弗"
				medicine_seeded = true
			if session.begin_match():
				started = true
				check(true, "%d ready humans started" % size)
				if unit_case: _seed_unit_case()
				if space_case:
					# Prepared legal spatial fixture; the actual skill window is tested
					# independently. Do not alter fixed rows, roles, health or input.
					var game = session.bridge.game
					check(game.turn_manager.rounds.relocate_before(size-1,1), "authorized shifted-space fixture prepared")
					game._layout_player_panels()
					check(game.players.map(func(p): return p.seat_index) == range(size), "spatial movement never reorders fixed player rows")
				if drop_case:
					saved_game = session.bridge.game
					saved_game._rps_choice(saved_game.players[1], "disconnect case")
		if not child and unit_case and started and not unit_input_started and session.bridge != null:
			var game = session.bridge.game
			if game.turn_manager.current_phase == TurnManager.Phase.PLAY and session.bridge._root() == null and not session.bridge._targeting():
				unit_input_started = true
				_run_unit_choice()
		if drop_case and started and session.bridge == null:
			interrupted = true
			break
		if final_seen: break
		await create_timer(0.03).timeout
	if drop_case:
		check(interrupted and not session.lobby.playing and session.members.size() == 1, "disconnect aborts match and resets room")
		check(session.match_id == "", "interrupted match token removed")
		await process_frame
		check(not is_instance_valid(saved_game), "pending response scene freed after disconnect")
	elif not drop_on_match:
		check(final_seen, "full network game reaches real victory")
		check(actions > 0, "local peer submitted real UI actions")
		if medicine_case:
			check(medicine_seen, "peer received actual medicine skill history over ENet")
			check(egg_seen, "peer received actual egg payment and heal over ENet")
			if owns_medicine: check(medicine_replied, "remote Chris selected actual medicine combination")
		if summon_case:
			check(summon_seen and summoned_body_seen, "peer received paid actual summon and independent body over ENet")
			if owns_medicine: check(summon_paid, "remote Chris confirmed three original fee cards")
		if space_case: check(shifted_seen, "peer actually received and used changed spatial order")
		if unit_case:
			check(units_seen, "peer received separate unit rows over real ENet")
			check(unit_removal_seen, "peer received actual final-owner disappearance history")
			if owns_dragon: check(unit_reply_submitted, "remote intelligent controller answered its real window")
			if not child: check(unit_input_result == 0, "authority received unit-controller confirmation without advancing another player's turn")
	if not child and final_seen:
		var old_match = session.match_id
		session.return_to_lobby()
		check(session.bridge == null and not session.lobby.playing, "return to room after victory")
		check(not session._apply_action(1, old_match, last_token), "old match command rejected")
		await create_timer(0.3).timeout
	# Allow reliable final state to reach the client before host closes.
	if not child: await create_timer(0.5).timeout
	session.close()
	await process_frame
	for pid in children:
		if OS.is_process_running(pid):
			await create_timer(0.3).timeout
			if OS.is_process_running(pid): OS.kill(pid)
	if not child:
		for child_log in child_logs:
			var log_text = FileAccess.get_file_as_string(child_log)
			check("RESULT:" in log_text and "0 failures" in log_text and "SCRIPT ERROR" not in log_text and "ERROR:" not in log_text and "FAIL " not in log_text, "independent client validation/log clean")
			if not history_digest.is_empty(): check("LOG_DIGEST " + history_digest in log_text, "remote public history matches host")
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _seed_unit_case() -> void:
	# Authorized post-registration fixture only, not an enabled summoning skill.
	# Keep the ordinary roster, HP, identities, phases and victory rules intact.
	var game = session.bridge.game
	var dragon_owner = game.players[1]
	var mountain_owner = game.players[0]
	if game.game_mode != GameModes.FREE_FOR_ALL:
		dragon_owner = game.players.filter(func(p): return p.identity == "反贼" and p.seat_index != 0)[0]
		mountain_owner = game.players.filter(func(p): return p.identity == "主公")[0]
	var helper = load("res://Test/i02_lifecycle_cases.gd").new()
	unit_dragon = helper.add_unit(game, UnitRegistry.Kind.FIRE_DRAGON, dragon_owner)
	helper.add_unit(game, UnitRegistry.Kind.MOUNTAIN, mountain_owner)
	check(dragon_owner.seat_index != 0 and game.unit_registry.active_units().size() == 2, "unit transport fixture has independent remote controller")
	check(unit_dragon.hand_size() == 0 and game.players.map(func(p): return p.seat_index) == range(size), "unit fixture keeps initial blank hand/fixed player IDs intact")

func _run_unit_choice() -> void:
	var game = session.bridge.game
	game._set_input_player(unit_dragon)
	unit_input_result = await game._show_choice_popup("单位登记联机控制者验收", ["确认", "取消"], func(): return game.unit_registry.contains_active(unit_dragon), false)
	if is_instance_valid(game) and not game._game_over:
		game._set_input_player(game.players[game.turn_manager.get_play_actor_idx()])
		game._history_event("unit_input_verified", "单位控制者完成联机确认")

func _state(state: Dictionary) -> void:
	if summon_case:
		owns_medicine = owns_medicine or state.players[state.actor].general == "克里斯·西弗"
		summon_seen = summon_seen or session.history.entries.any(func(event): return event.kind == "unit_summoned")
		summoned_body_seen = summoned_body_seen or state.units.any(func(unit): return unit.kind == UnitRegistry.Kind.FIRE_DRAGON and unit.hp == 3 and unit.hand_count == 0 and unit.summoner == unit.controller)
	if medicine_case:
		owns_medicine = owns_medicine or state.players[state.actor].general == "克里斯·西弗"
		medicine_seen = medicine_seen or session.history.entries.any(func(event): return event.kind == "skill" and "【偷药品】" in event.text)
		egg_seen = egg_seen or session.history.entries.any(func(event): return event.kind == "skill" and "弃置1颗【火龙蛋】" in event.text)
	if unit_case:
		if state.units.size() == 2: units_seen = true
		for unit in state.units:
			if unit.kind == UnitRegistry.Kind.FIRE_DRAGON and unit.controller == state.actor: owns_dragon = true
	if space_case:
		var expected: Array = [0, int(state.count)-1]
		for seat in range(1,int(state.count)-1): expected.append(seat)
		if state.get("space",[]) == expected: shifted_seen = true
	if not pace_checked:
		check(state.space.size() == state.count and state.space.all(func(seat): return state.space.count(seat) == 1 and state.players[seat].seat == seat) and state.round >= 1, "wire space and round preserve permanent row IDs")
		check(GameModes.playable(state.mode, state.count) and state.count == state.players.size(), "explicit supported mode matches wire player count")
		check(state.players.all(func(p): return p.identity == "" if state.mode == GameModes.FREE_FOR_ALL else (p.identity != "" if p.seat == state.actor else (p.dead or p.identity in ["", "主公"]))), "observer identity values match declared mode without live hidden-role leakage")
		check(state.pace == AiActionPacer.Speed.SLOW and session.pace == state.pace, "authority pace synchronized to real peer")
		check(not session.set_pace(AiActionPacer.Speed.FAST), "live match rejects pace changes")
		if child: check(session.bridge == null, "client does not run a rule bridge")
		pace_checked = true
	if drop_on_match:
		check(not state.ended, "client disconnects during active match")
		final_seen = true
		session.close.call_deferred()
		return
	if state.ended:
		# Consume all bounded reliable batches before treating the client as done.
		if session.history.sequence < int(state.history.last): return
		check(session.history.sequence > 0, "network history received through final result")
		check(session.history.entries.any(func(e): return "游戏结束！" in e.text), "network history contains terminal result")
		if unit_case:
			# Cache only after the complete matched final history arrives; returning
			# to the lobby intentionally clears the client's old match history.
			unit_removal_seen = session.history.entries.any(func(e): return e.kind == "unit_removed" and e.details.get("reason") == "summoner_lost")
		history_digest = var_to_str(session.history.entries).sha256_text()
		print("LOG_DIGEST ", history_digest)
		final_seen = true
		return
	var token: String
	if summon_case:
		# Test strategy uses only the same owner-filtered controls as a client.
		# Select three fee slots; never overwrite HP, hand contents or phases.
		var summon = state.controls.filter(func(control): return control.text == "召唤火龙" and not control.disabled)
		var fee = state.labels.any(func(label): return label == "选择弃置 3 张手牌（技能费用，可取消）")
		if not summon.is_empty(): token = summon[0].id
		elif fee:
			var cards = state.controls.filter(func(control): return control.toggle and not control.pressed and not control.disabled)
			var chosen = state.controls.filter(func(control): return control.toggle and control.pressed)
			if chosen.size() < 3 and not cards.is_empty(): token = cards[0].id
			else:
				var confirm = state.controls.filter(func(control): return control.text == "确认弃牌" and not control.disabled)
				if not confirm.is_empty():
					token = confirm[0].id
					summon_paid = true
	if token.is_empty(): token = driver.choose(state)
	if ((medicine_case and not medicine_seen) or (summon_case and not summon_seen)) and state.actor == 0:
		# Legal player strategy: let the remote first draw occur before attacking.
		var end = state.controls.filter(func(control): return control.text == "结束出牌" and not control.disabled)
		if not end.is_empty(): token = end[0].id
	if token.is_empty() or token == last_token: return
	if medicine_case and state.controls.any(func(control): return control.id == token and control.text.begins_with("获得：")):
		medicine_replied = true
	if unit_case and state.labels.has("单位登记联机控制者验收") and state.controls.any(func(control): return control.id == token and control.text == "确认"):
		unit_reply_submitted = true
	last_token = token
	actions += 1
	print("INPUT seat=", state.actor, " status=", state.status, " controls=", state.controls.map(func(x): return x.text))
	session.act.call_deferred(token)
