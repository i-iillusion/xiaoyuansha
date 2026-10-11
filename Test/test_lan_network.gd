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
var actions := 0
var drop_on_match := false
var drop_case := false
var interrupted := false
var saved_game: GameManager
var history_digest := ""

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
		if arg == "--drop-on-match": drop_on_match = true
		if arg == "--drop-case": drop_case = true
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
		check(session.host("Host", size, port) == OK, "host ENet start")
		session.choose("稻草人", true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1, size):
			var child_log = ProjectSettings.globalize_path("res://.git/lan-tests/client-%d-%d.log" % [port, i])
			child_logs.append(child_log)
			var args = PackedStringArray(["--headless", "--disable-render-loop", "--log-file", child_log, "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://Test/test_lan_network.gd", "--", "--lan-child", "--port=" + str(port)])
			if drop_case: args.append("--drop-on-match")
			var pid = OS.create_process(OS.get_executable_path(), args)
			check(pid > 0, "independent client process launched")
			if pid > 0: children.append(pid)
	while Time.get_ticks_msec() < exit_at:
		if not child and not started and session.members.size() == size:
			if session.begin_match():
				started = true
				check(true, "%d ready humans started" % size)
				if drop_case:
					saved_game = session.bridge.game
					saved_game._rps_choice(saved_game.players[1], "disconnect case")
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

func _state(state: Dictionary) -> void:
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
		history_digest = var_to_str(session.history.entries).sha256_text()
		print("LOG_DIGEST ", history_digest)
		final_seen = true
		return
	var token = driver.choose(state)
	if token.is_empty() or token == last_token: return
	last_token = token
	actions += 1
	print("INPUT seat=", state.actor, " status=", state.status, " controls=", state.controls.map(func(x): return x.text))
	session.act.call_deferred(token)
