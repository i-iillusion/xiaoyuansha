extends SceneTree
const SIMBA="辛巴·古德曼"
var session: LanSession
var driver=preload("res://Test/lan_simba_driver.gd").new()
var child=false
var host_controller=false
var drop_case=false
var reserve_case=false
var cancel_case=false
var size=3
var mode=""
var port=0
var number=0
var children: Array[int]=[]
var child_logs: Array[String]=[]
var checks=0
var failures=0
var packets=0
var actions=0
var started=false
var finished=false
var aborted=false
var dropped=false
var digest=""
var final_state: Dictionary={}
var final_history: Array=[]
var facts: Array=[]
var old_roles: Array=[]
var stale_token=""
var wrong_checked=false
var wait_began=0
var reserve_observed=false
var greed_counts: Array=[]
var round_cleared=false
var barrier
var acknowledgments: Dictionary={}

func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func signature(state) -> String:
	return var_to_str(state.players.map(func(p): return [p.seat,p.hp,p.dead,p.hand_count,p.general,int(p.get("good_deed_marks",0)),int(p.get("tuanfei_extra_draws",0))])).sha256_text()
func notice(text:String):
	if text.begins_with("SIMBA_DONE:"):
		digest=text.trim_prefix("SIMBA_DONE:")
		final_state=session.latest.duplicate(true); final_history=session.history.entries.duplicate(true); finished=true
	if drop_case and ("本局中断" in text or "房主已断开" in text): aborted=true; finished=true
func state_changed(state):
	packets+=1
	if finished: return
	if not child and session.bridge!=null:
		var hero=session.bridge.game.players.filter(func(p): return p.general_name==SIMBA)[0].seat_index
		var view=session.bridge.snapshot(hero)
		if "是否发动【急救】" in "\n".join(view.labels) and ("令"+session.bridge.game.players[hero].player_name+"获得") in "\n".join(view.labels) and stale_token=="":
			var game=session.bridge.game
			greed_counts=[game.players[hero].hand_size(),game.players[1 if host_controller else 0].hand_size()]
			check(facts.size()==4 and not facts[3].settlement_completed,"natural bow, Duel and response complete; original Strike waits at real Emergency before damage-after rewards")
			stale_token=driver.helper.find(view,"发动")
			for peer in session.members:
				if session.members[peer].seat!=hero:
					wrong_checked=true
					check(not session._apply_action(peer,session.match_id,stale_token),"wrong peer cannot answer actual Simba Emergency window")
					break
	if state.owner==state.actor and "是否发动【急救】" in "\n".join(state.labels) and state.players.any(func(p): return p.general==SIMBA and ("令"+p.name+"获得") in "\n".join(state.labels)):
		if wait_began==0: wait_began=Time.get_ticks_msec()
		# A real client deliberates briefly, so authority can audit the
		# published window before the independent peer answers it.
		if Time.get_ticks_msec()-wait_began<150: return
		if drop_case:
			dropped=true; session.close(); finished=true; return
		if reserve_case:
			if wait_began==0: wait_began=Time.get_ticks_msec()
			if Time.get_ticks_msec()-wait_began<32000: return
	var token=driver.choose(state)
	if token!="": actions+=1; session.act.call_deferred(token)

func run():
	for arg in OS.get_cmdline_user_args():
		if arg=="--lan-child": child=true
		if arg=="--host-controller": host_controller=true
		if arg=="--drop-case": drop_case=true
		if arg=="--reserve-case": reserve_case=true
		if arg=="--cancel-case": cancel_case=true
		if arg.begins_with("--players="): size=int(arg.trim_prefix("--players="))
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--child-number="): number=int(arg.trim_prefix("--child-number="))
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	if mode=="": mode=GameModes.CLASSIC if size==5 else GameModes.FREE_FOR_ALL
	driver.decline=cancel_case or reserve_case
	var holder=Node.new(); holder.name="SimbaHarness"; root.add_child(holder)
	session=LanSession.new(); session.name="Session"; holder.add_child(session)
	barrier=preload("res://Test/lan_simba_barrier.gd").new(); barrier.name="CompletionBarrier"; session.add_child(barrier)
	barrier.reported.connect(func(peer, stamp): acknowledgments[peer]=stamp)
	session.notice.connect(notice); session.state_received.connect(state_changed)
	if child:
		session.lobby_changed.connect(func(state):
			if finished or state.is_empty() or state.playing: return
			# Normal lobby choices put the two tested generals in adjacent
			# public roster entries; never rewrite assigned seats or space.
			var remotes=state.members.filter(func(m): return m.peer!=1)
			if remotes.is_empty(): return
			var first=remotes[0].peer
			for member in state.members:
				if member.peer==session.multiplayer.get_unique_id():
					var wanted=("凯文·罗本" if host_controller else SIMBA) if member.peer==first else "稻草人"
					if not member.ready or member.general!=wanted: session.choose(wanted,true))
		check(session.join_room("127.0.0.1","P%d"%number,port)==OK,"independent Simba client joins ENet")
	else:
		port=32000+randi_range(0,9000)
		check(session.host("P0",size,port,mode)==OK,"real Simba ENet authority starts")
		session.set_pace(AiActionPacer.Speed.FAST)
		check(LanSession.GENERALS.count(SIMBA)==1 and GeneralData.get_implementation_status(SIMBA)=="prototype","public roster offers Simba exactly once")
		session.choose(SIMBA if host_controller else "凯文·罗本",true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1,size):
			var log=ProjectSettings.globalize_path("res://.git/lan-tests/simba-client-%d-%d.log"%[port,i]); child_logs.append(log)
			var args=PackedStringArray(["--headless","--disable-render-loop","--log-file",log,"--path",ProjectSettings.globalize_path("res://"),"--script","res://Test/test_i05_simba_network.gd","--","--lan-child","--port="+str(port),"--players="+str(size),"--child-number="+str(i),"--mode="+mode])
			for flag in [[host_controller,"--host-controller"],[drop_case,"--drop-case"],[reserve_case,"--reserve-case"],[cancel_case,"--cancel-case"]]:
				if flag[0]: args.append(flag[1])
			var pid=OS.create_process(OS.get_executable_path(),args); check(pid>0,"launch independent Simba client"); children.append(pid)
	var deadline=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline and not finished:
		if not child and not started and session.members.size()==size and session.members.values().all(func(m): return m.ready):
			started=session.begin_match()
			if started:
				var game=session.bridge.game
				var hero=game.players.filter(func(p): return p.general_name==SIMBA)[0]
				check(hero.simba_lord_skill_enabled and hero.simba_wanci_enabled and hero.simba_good_deeds_enabled and hero.simba_tuanfei_enabled and hero.simba_emergency_enabled,"all five Simba capabilities enabled by normal authoritative roster without overrides")
				old_roles=game.players.map(func(p): return p.identity)
				game.card_action_committed.connect(func(e): facts.append(e))
		if not child and started and not drop_case and session.bridge!=null:
			var game=session.bridge.game
			var hero=game.players.filter(func(p): return p.general_name==SIMBA)[0]
			var view=session.bridge.snapshot(hero.seat_index)
			if reserve_case and "是否发动【急救】" in "\n".join(view.labels) and ("令"+hero.player_name+"获得") in "\n".join(view.labels) and game._step_remaining<=0 and game._bank_remaining>0 and game._bank_remaining<GameManager.BANK_SECONDS: reserve_observed=true
			if audit_native(game):
				session._publish_states(); final_state=session.latest.duplicate(true); final_history=session.history.entries.duplicate(true); digest=signature(final_state)
				session.set_process(false) # Freeze test publication only after the real completed parent; networking still polls.
				for key in session.members:
					if key!=1: session._remote_notice.rpc_id(key,"SIMBA_DONE:"+digest)
				finished=true
		await create_timer(0.02).timeout
	if not finished:
		var diagnostic=session.bridge.snapshot(0 if host_controller else 1) if not child and session.bridge!=null else session.latest
		print("DIAGNOSTIC ",driver.source_step,"/",driver.give_step," ",diagnostic.get("phase"),"/",diagnostic.get("actor")," ",diagnostic.get("labels")," ",diagnostic.get("controls"))
	check(finished,"natural Simba lifecycle or disconnect completes within original 45 seconds")
	check(packets>0 and (actions>0 or drop_case),"actual packets and own actions observed")
	if drop_case:
		check(dropped or aborted,"active Emergency disconnect aborts rather than forging victory")
		if not child: check(session.bridge==null and session.match_id=="","authority releases aborted match")
	elif finished:
		check(signature(final_state)==digest,"host and client agree on final public state")
		check(final_history.any(func(e): return e.kind=="skill" and "【做好事】" in e.text) and final_history.any(func(e): return "回收" in e.text and "【好事】" in e.text),"history reports actual Good Deed grants and pre-rescue recovery")
		check(final_history.any(func(e): return e.kind=="skill" and "【急救】" in e.text)==not (cancel_case or reserve_case),"confirmed or declined first Emergency is reported accurately")
		check(final_history.any(func(e): return "【万磁】" in e.text) and final_history.filter(func(e): return e.kind=="skill" and "【团费】" in e.text).size()==2,"public history retains natural Wanci and exactly two fee payouts")
	if finished and not drop_case:
		if child:
			barrier.report.rpc_id(1,signature(final_state))
			while not barrier.released and Time.get_ticks_msec()<deadline: await create_timer(0.02).timeout
			check(barrier.released,"authority synchronizes independent final snapshots before client shutdown")
		else:
			while acknowledgments.size()<children.size() and Time.get_ticks_msec()<deadline: await create_timer(0.02).timeout
			check(acknowledgments.size()==children.size() and acknowledgments.values().all(func(stamp): return stamp==digest),"every actual client acknowledges the same final state before transport teardown")
			barrier.release_clients.rpc()
	if not child:
		await create_timer(0.5).timeout
		for pid in children:
			if OS.is_process_running(pid):
				await create_timer(0.3).timeout
				if OS.is_process_running(pid): OS.kill(pid)
		for log in child_logs:
			var text=FileAccess.get_file_as_string(log)
			check("RESULT:" in text and "0 failures" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text and "FAIL " not in text,"independent Simba client log is clean")
	session.close(); await process_frame
	print("RESULT: %d asserts, %d failures"%[checks,failures]); quit(1 if failures else 0)

func audit_native(game) -> bool:
	var hero=game.players.filter(func(p): return p.general_name==SIMBA)[0]
	var source=game.players.filter(func(p): return p.general_name=="凯文·罗本")[0]
	var extra=game._draw_batches.filter(func(b): return b.owner==source and b.context==ExtraDrawBatch.Context.EXTRA)
	var rewards=game._draw_batches.filter(func(b): return b.owner==hero and b.context==ExtraDrawBatch.Context.EXTRA)
	if extra.size()==2 and rewards.size()==1 and game.turn_manager.rounds.round_id>1 and hero.tuanfei_extra_draws==0: round_cleared=true
	if extra.size()!=4 or rewards.size()!=2 or not game._simba_deed_pending.is_empty() or not game._pending_card_actions.is_empty() or not game._choice_prompt_stack.is_empty(): return false
	var history=game.action_history.entries
	if not history.any(func(e): return e.kind=="skill" and "回收" in e.text and "【好事】" in e.text): return false
	check(facts.size()==7 and facts.all(func(e): return e.settlement_completed),"six native card USE facts and one actual Duel Kill response complete once; Simba skills fabricate none")
	check(extra.all(func(b): return b.count==2) and rewards.all(func(b): return b.count==1),"four natural Kevin two-card batches fund exactly two single-card Tuanfei rewards")
	check(round_cleared,"actual whole-round boundary discards first incomplete remainder before next round's source draws")
	var expected=hero.max_hp-3
	check(hero.hp==expected and source.hp==source.max_hp-1 and source.good_deed_marks==0,"native paid grants cross target max HP, then whole-marker recovery preserves actual damage and source HP")
	check(hero.good_deed_marks==(0 if cancel_case or reserve_case else 1),"first Emergency cancel/confirmation has exact own-mark effect; later Emergency declined")
	check(history.filter(func(e): return e.kind=="skill" and "【做好事】" in e.text).size()==expected,"Good Deed confirmation alone pays repeated HP costs; cancelled proposal has no effect")
	check(game.players.filter(func(p): return p!=hero and p!=source).all(func(p): return p.hp==p.max_hp),"failed Burning Camp never damages uninvolved neighbors")
	var fire=facts.filter(func(e): return e.sub_type==CardData.CardSubType.BURNING_CAMP)
	check(fire.size()==1 and game.deck._discard.count(fire[0].card)==1 and game.players.all(func(p): return p.judgment_cards.is_empty()),"Wanci discards original native Burning Camp once without generating new fire")
	check(wrong_checked and stale_token!="","real Emergency input lease and wrong peer rejection were observed")
	var peer=session.members.keys().filter(func(key): return session.members[key].seat==hero.seat_index)[0]
	check(not session._apply_action(peer,session.match_id,stale_token),"old Emergency token cannot replay after natural recovery and END")
	for seat in size:
		var snap=session.bridge.snapshot(seat)
		check(snap.players.all(func(row): return row.identity==PlayerObservation.visible_identity(game.players[row.seat],game.players[seat])),"natural identity observations remain viewer-specific")
	check(hero.hand_limit()==hero.hp+(2 if hero.identity=="主公" else 0),"public native lord hand limit uses actual authority, never grants brawl a lord skill")
	if reserve_case: check(reserve_observed,"original base step expires into real reserve without clock mutation")
	return true
