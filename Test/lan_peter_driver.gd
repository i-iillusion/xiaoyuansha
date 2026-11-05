extends RefCounted
const PETER="彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹"
var helper=preload("res://Test/lan_mountain_driver.gd").new()
var last_signature=""
var source_step=0
var peter_step=0
var ready=false
var decline_immune=false

# The lord is public. Keep this continuing-game lifecycle separate from
# existing terminal-victory cases without inspecting any hidden identity.
func victim_for(players, hero:int) -> int:
	var source=1 if hero==0 else 0
	var preferred=2 if hero in [0,1] else 1
	if preferred!=source and preferred!=hero and players[preferred].identity!="主公": return preferred
	for seat in players.size():
		if seat!=source and seat!=hero and players[seat].identity!="主公": return seat
	return -1

func choose(state) -> String:
	if state.owner!=state.actor or state.ended: return ""
	var signature=var_to_str([state.owner,state.turn,state.phase,state.controls,state.targets])
	if signature==last_signature: return ""
	var hero=-1
	for p in state.players:
		if p.general==PETER: hero=p.seat
	if hero<0: return ""
	var source=1 if hero==0 else 0
	var victim=victim_for(state.players,hero)
	if state.players[victim].dead: return "" # Goal reached; do not advance the next turn while auditing final state.
	var token=""
	if helper.find(state,"免除此效果")!="":
		ready=true
		token=helper.find(state,"取消" if decline_immune else "免除此效果")
	elif helper.find(state,"发动禁桃")!="": token=helper.find(state,"发动禁桃")
	elif helper.find(state,"发动【关你屁事】")!="": token=helper.find(state,"发动【关你屁事】")
	elif helper.find(state,"确认禁止名单")!="":
		var picks=state.controls.filter(func(c): return c.toggle and not c.disabled and c.text.begins_with("禁止："))
		if picks.any(func(c): return c.pressed): token=helper.find(state,"确认禁止名单")
		else:
			for c in picks:
				if c.text.begins_with("禁止："+state.players[source].name): token=c.id; break
			if token=="" and not picks.is_empty(): token=picks[0].id
			if token=="": token=helper.find(state,"确认禁止名单")
	elif state.phase==TurnManager.Phase.DISCARD or helper.find(state,"确认弃牌")!="" or state.controls.any(func(c): return c.toggle and not c.disabled and "手牌" in c.text): token=helper.fee(state).token
	else:
		for label in ["放弃","不响应","不出","不使用","不救"]:
			if token=="": token=helper.find(state,label)
		if token=="" and state.actor!=state.turn: token=helper.find(state,"取消")
		if token=="" and state.actor==hero:
			if not ready: token=helper.find(state,"结束出牌")
			else:
				var route=["出牌","装备牌","武器","麒麟弓","出牌","锦囊牌","普通锦囊","决斗","@","是","出牌","锦囊牌","普通锦囊","决斗","@","是","出牌","基本牌","酒","出牌","基本牌","杀","杀","@","是","结束出牌"]
				if peter_step<route.size():
					token=(state.targets.get(str(victim),"") if state.targeting else "") if route[peter_step]=="@" else helper.find(state,route[peter_step])
					if token!="": peter_step+=1
				else: token=helper.find(state,"结束出牌")
		elif token=="" and state.actor==source:
			var route=["出牌","锦囊牌","普通锦囊","南蛮入侵","出牌","锦囊牌","普通锦囊","决斗","@","是","结束出牌"]
			if source_step<route.size():
				token=(state.targets.get(str(victim),"") if state.targeting else "") if route[source_step]=="@" else helper.find(state,route[source_step])
				if token!="": source_step+=1
			else: token=helper.find(state,"结束出牌")
		elif token=="": token=helper.find(state,"结束出牌")
	if token!="": last_signature=signature
	return token
