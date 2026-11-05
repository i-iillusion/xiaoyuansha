extends RefCounted

var host_step := 0
var killer_step := 0
var last_signature := ""
var target_id := ""

func find(state, text: String) -> String:
	for control in state.controls:
		if not control.disabled and control.text==text: return control.id
	for control in state.controls:
		if not control.disabled and text in control.text: return control.id
	return ""

func fee(state) -> Dictionary:
	var confirm=find(state,"确认弃牌")
	if confirm!="": return {"token":confirm,"done":true}
	for control in state.controls:
		if control.toggle and not control.disabled and not control.pressed: return {"token":control.id,"done":false}
	return {"token":"","done":false}

func choose(state) -> String:
	if state.owner!=state.actor or state.ended: return ""
	var signature=var_to_str([state.owner,state.turn,state.phase,state.controls,state.targets])
	if signature==last_signature: return ""
	var token=""
	if state.phase==TurnManager.Phase.DISCARD:
		token=fee(state).token
	elif state.actor==0:
		token=host(state)
	elif state.actor==1:
		token=killer(state)
	else:
		token=find(state,"结束出牌")
	if token!="": last_signature=signature
	return token

func host_button(state,text: String) -> String:
	var token=find(state,text)
	if token!="": host_step+=1
	return token

func host(state) -> String:
	match host_step:
		0:
			var wanted="山甲 玩家1→玩家2；山乙 玩家%d→玩家1" % state.count
			var token=find(state,wanted)
			if token!="": host_step=1
			return token
		1,5,10:
			var token=state.targets.get("0","")
			if token!="": host_step+=1
			return token
		2: return host_button(state,"护山")
		3: return host_button(state,"山1")
		4,9,13:
			var reply=fee(state)
			if reply.done: host_step+=1
			return reply.token
		6: return host_button(state,"移山")
		7: return host_button(state,"山2")
		8: return host_button(state,"玩家1→山1")
		11: return host_button(state,"聚山")
		12: return host_button(state,"较多侧")
		14: return host_button(state,"结束出牌")
		15:
			if state.phase==TurnManager.Phase.START and state.units.size()==1:
				for control in state.controls:
					if not control.disabled and "→" in control.text:
						host_step=16
						return control.id
	return ""

func killer(state) -> String:
	var route={0:"出牌",1:"装备牌",2:"武器",3:"连弩",4:"出牌",5:"基本牌",6:"酒",7:"出牌",8:"基本牌",9:"杀",10:"火杀",12:"是",13:"出牌",14:"基本牌",15:"杀",16:"火杀",18:"是",19:"结束出牌"}
	if killer_step in [11,17]:
		for unit in state.units:
			if unit.kind!=UnitRegistry.Kind.MOUNTAIN or not state.targets.has(unit.id): continue
			if target_id=="": target_id=unit.id
			if unit.id==target_id:
				killer_step+=1
				return state.targets[unit.id]
	elif route.has(killer_step):
		var token=find(state,route[killer_step])
		if token!="": killer_step+=1
		return token
	return ""
