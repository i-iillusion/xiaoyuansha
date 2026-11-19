extends SceneTree

const SALLY = "萨利·赛克斯"
var session: LanSession
var barrier
var child := false
var host_controller := false
var choose_sally := false
var port := 0
var size := 3
var mode := ""
var checks := 0
var failures := 0
var children: Array[int] = []
var child_logs: Array[String] = []
var acknowledgments: Dictionary = {}
var final_seat := -1
var smoke_seen := false
var boost_seen := false
var second_dodge_seen := false
var wrong_peer_checked := false
var stale_token := ""
var used_token := ""
var strike_step := 0

func _initialize():
	run.call_deferred()

func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + message)

func token(state: Dictionary, label: String, prefix: bool = false) -> String:
	for action in state.controls:
		if not action.disabled and (action.text.begins_with(label) if prefix else action.text == label):
			return action.id
	return ""

func choose(state: Dictionary, row: Dictionary) -> String:
	var button = token(state,"自动选牌")
	if not button.is_empty(): return button
	button = token(state,"出【闪】")
	if not button.is_empty(): return button
	if state.phase != TurnManager.Phase.PLAY: return ""
	if state.actor == row.seat:
		if row.gender == "female" and not row.sally.boosted and not smoke_seen:
			button = token(state,"确认抽烟")
			if not button.is_empty(): return button
			button = token(state,"· 【抽烟】",true)
			if not button.is_empty(): return button
			return state.targets.get(str(row.seat),"")
		if row.sally.boosted:
			if strike_step == 3:
				button = token(state,"是")
				if not button.is_empty(): strike_step = 4
				return button
			if strike_step == 2 and state.targeting:
				button = state.targets.get(str((row.seat+1)%state.players.size()),"")
				if not button.is_empty(): strike_step = 3
				return button
			if strike_step == 1 and state.labels.has("选择杀的属性"):
				button = token(state,"杀")
				if not button.is_empty(): strike_step = 2
				return button
			if strike_step == 0:
				for label in ["杀","基本牌","出牌"]:
					button = token(state,label)
					if not button.is_empty():
						if label == "杀": strike_step = 1
						return button
			return ""
	return token(state,"结束出牌")

func state_changed(state: Dictionary):
	var heroes = state.players.filter(func(row): return row.general == SALLY)
	if heroes.size() != 1: return
	var row: Dictionary = heroes[0]
	smoke_seen = smoke_seen or (row.gender == "male" and row.sally.smoking)
	boost_seen = boost_seen or (row.gender == "male" and not row.sally.smoking and row.sally.boosted)
	if state.actor != row.seat: # The boost belongs to Sally, while the response is local.
		second_dodge_seen = second_dodge_seen or state.labels.any(func(label): return "第2张" in label)
	if not child and not wrong_peer_checked:
		var target_seat = (row.seat+1)%state.players.size()
		var dodge = token(session.bridge.snapshot(target_seat),"出【闪】")
		if not dodge.is_empty():
			var peer = session.members.keys().filter(func(id): return session.members[id].seat != target_seat)[0]
			check(not session._apply_action(peer,session.match_id,dodge),"wrong seat cannot use the boosted Dodge window")
			stale_token = dodge
			wrong_peer_checked = true
	if final_seat >= 0 or state.owner != state.actor and token(state,"出【闪】").is_empty(): return
	var selected = choose(state,row)
	if not selected.is_empty() and selected != used_token:
		used_token = selected
		session.act.call_deferred(selected)

func progress_digest(state: Dictionary) -> String:
	var hero = state.players.filter(func(row): return row.general == SALLY)[0]
	return var_to_str([hero.seat,hero.gender,hero.hp,hero.sally,state.players.map(func(row): return row.hand_count)]).sha256_text()

func run():
	for arg in OS.get_cmdline_user_args():
		if arg == "--lan-child": child = true
		if arg == "--host-controller": host_controller = true
		if arg == "--choose-sally": choose_sally = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--players="): size = int(arg.trim_prefix("--players="))
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
	if mode.is_empty(): mode = GameModes.CLASSIC if size == 5 else GameModes.FREE_FOR_ALL
	var holder = Node.new()
	root.add_child(holder)
	session = LanSession.new()
	session.name = "Session"
	holder.add_child(session)
	barrier = preload("res://Test/lan_simba_barrier.gd").new()
	barrier.name = "CompletionBarrier"
	session.add_child(barrier)
	barrier.reported.connect(func(peer, digest): acknowledgments[peer] = digest)
	session.state_received.connect(state_changed)
	if child:
		session.notice.connect(func(message):
			if message.begins_with("SALLY_DONE:"):
				final_seat = int(message.trim_prefix("SALLY_DONE:"))
				barrier.report.rpc_id(1,progress_digest(session.latest)))
		session.lobby_changed.connect(func(state):
			if state.is_empty() or state.playing: return
			for member in state.members:
				if member.peer == session.multiplayer.get_unique_id() and not member.ready:
					session.choose(SALLY if choose_sally else "稻草人",true))
		check(session.join_room("127.0.0.1","Remote",port)==OK,"independent Sally client joins ENet")
	else:
		port = 26000 + randi_range(0,10000)
		check(session.host("Host",size,port,mode)==OK,"real Sally ENet host starts")
		session.choose(SALLY if host_controller else "稻草人",true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1,size):
			var path = ProjectSettings.globalize_path("res://.git/lan-tests/sally-%d-%d.log" % [port,i])
			child_logs.append(path)
			var args = PackedStringArray(["--headless","--disable-render-loop","--log-file",path,"--path",ProjectSettings.globalize_path("res://"),"--script","res://Test/test_i05_sally_network.gd","--","--lan-child","--port="+str(port),"--players="+str(size),"--mode="+mode])
			if i == 1 and not host_controller: args.append("--choose-sally")
			var pid = OS.create_process(OS.get_executable_path(),args)
			check(pid > 0,"independent client process launched")
			if pid > 0: children.append(pid)
	var deadline = Time.get_ticks_msec() + 45000
	var started := false
	var facts: Array = []
	while Time.get_ticks_msec() < deadline and final_seat < 0:
		if not child and not started and session.members.size() == size and session.members.values().all(func(member): return member.ready):
			started = session.begin_match()
			if started:
				var game = session.bridge.game
				var heroes = game.players.filter(func(p): return p.general_name == SALLY)
				check(heroes.size()==1 and heroes[0].has_jiegui() and heroes[0].has_sally_lieqi() and heroes[0].has_sally_woman() and SallySmokingState.enabled(heroes[0]) and heroes[0].sally_surgery_enabled,"public lobby enables all five capabilities")
				game.card_action_committed.connect(func(event): facts.append(event))
		if not child and started:
			var game = session.bridge.game
			var hero = game.players.filter(func(p): return p.general_name == SALLY)[0]
			var target = game.players[(hero.seat_index+1)%size]
			if facts.size() == 3 and facts.all(func(event): return event.settlement_completed):
				check(facts[0].actor_body == hero and facts[0].sub_type == CardData.CardSubType.STRIKE and facts.slice(1).all(func(event): return event.actor_body == target and event.sub_type == CardData.CardSubType.DODGE),"natural Strike consumes two independent Dodge responses")
				check(hero.hp == hero.max_hp-1 and target.hp == target.max_hp and wrong_peer_checked and not session.bridge.submit(target.seat_index,stale_token),"smoking fee, dodged Strike and stale response token agree at authority")
				final_seat = target.seat_index
				session._publish_states()
				session.set_process(false)
				for peer in session.members:
					if peer != 1: session._remote_notice.rpc_id(peer,"SALLY_DONE:"+str(final_seat))
		await create_timer(0.02).timeout
	if final_seat < 0: print("DIAGNOSTIC ",session.latest.get("actor")," ",session.latest.get("labels")," ",session.latest.get("controls")," strike step=",strike_step)
	check(final_seat >= 0 and smoke_seen and boost_seen,"natural smoking and next-turn boost observed within original deadline")
	if final_seat >= 0:
		if session.latest.actor == final_seat:
			check(second_dodge_seen,"response owner observes the second-Dodge prompt")
		if child:
			while not barrier.released and Time.get_ticks_msec()<deadline: await create_timer(0.02).timeout
			check(barrier.released,"client receives synchronized completion")
		else:
			var digest = progress_digest(session.latest)
			while acknowledgments.size()<children.size() and Time.get_ticks_msec()<deadline: await create_timer(0.02).timeout
			check(acknowledgments.size()==children.size() and acknowledgments.values().all(func(value): return value==digest),"all clients agree on final public state")
			barrier.release_clients.rpc()
	if not child:
		await create_timer(0.5).timeout
		for pid in children:
			if OS.is_process_running(pid): OS.kill(pid)
		for path in child_logs:
			var log = FileAccess.get_file_as_string(path)
			check("0 failures" in log and "FAIL " not in log and "SCRIPT ERROR" not in log,"independent client assertions succeeded")
			if failures > 0: print(log.right(4000))
	session.close()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks,failures])
	quit(1 if failures else 0)
