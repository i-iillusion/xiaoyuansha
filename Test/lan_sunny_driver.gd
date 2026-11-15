extends RefCounted
const SUNNY="桑尼·斯派"
var helper=preload("res://Test/lan_mountain_driver.gd").new()
var last_signature=""
var source_step=0
var hero_step=0
var ready=false
var decline=false
var finished=false
var target_cursor=0
var spy_targets: Array=[]
var cancel_filming=false
var cancel_spy=false

func choose(state) -> String:
	if state.owner!=state.actor or state.ended or finished: return ""
	var signature=var_to_str([state.owner,state.turn,state.phase,state.controls,state.targets])
	if signature==last_signature: return ""
	var hero=-1
	for p in state.players:
		if p.general==SUNNY: hero=p.seat
	if hero<0: return ""
	var source=1 if hero==0 else 0
	var victim=(source+1)%state.count
	if victim==hero: victim=(source+state.count-1)%state.count
	var text="\n".join(state.labels)
	var token=""
	if decline and state.actor==hero and state.targeting:
		if hero_step==2 and not cancel_filming:
			cancel_filming=true; hero_step=0; token=helper.find(state,"取消")
		elif hero_step==8 and not cancel_spy:
			cancel_spy=true; hero_step=6; token=helper.find(state,"取消")
		if token!="": last_signature=signature; return token
	if "本次额外摸的牌发动【贪污】" in text:
		ready=true
		token=helper.find(state,"取消" if decline else "发动")
	elif helper.find(state,"石头")!="": token=helper.find(state,"石头" if state.actor==hero else "剪刀")
	elif helper.find(state,"确认弃牌")!="" or state.controls.any(func(c): return c.toggle and not c.disabled):
		token=helper.fee(state).token
	else:
		for label in ["放弃","不响应","不出","不使用","不救"]:
			if token=="":
				# Only the initial Duel's target responds once. Its source
				# then declines, producing real damage and a legal Harvest draw.
				if state.actor==victim and "【决斗】" in text and helper.find(state,"杀")!="": token=helper.find(state,"杀")
				else: token=helper.find(state,label)
		if token=="" and state.actor!=state.turn: token=helper.find(state,"取消")
		if token=="" and state.phase==TurnManager.Phase.DISCARD: token=helper.fee(state).token
		if token=="" and state.actor==source:
			var route=["出牌","装备牌","武器","麒麟弓","出牌","锦囊牌","普通锦囊","决斗","@victim","是","出牌","基本牌","杀","杀","@hero","是","出牌","锦囊牌","普通锦囊","五谷丰登","结束出牌"]
			if source_step<route.size():
				var step=route[source_step]
				if step.begins_with("@"):
					token=state.targets.get(str(victim if step=="@victim" else hero),"") if state.targeting else ""
				else: token=helper.find(state,step)
				if token!="": source_step+=1
			else: token=helper.find(state,"结束出牌")
		elif token=="" and state.actor==hero:
			if not ready: token=helper.find(state,"结束出牌")
			else:
				match hero_step:
					0,6: token=state.targets.get(str(hero),"")
					1: token=helper.find(state,"拍片")
					2: token=state.targets.get(str(source),"") if state.targeting else ""
					3: token=state.targets.get(str(victim),"") if state.targeting else ""
					4: token=helper.find(state,"确认拍片")
					5:
						# Card fee is handled above. Leaving it advances only
						# after the real healing has completed.
						if helper.find(state,"结束出牌")!="": hero_step=6; return choose_after_fee(state)
					7: token=helper.find(state,"间谍")
					8,9:
						if spy_targets.is_empty():
							for p in state.players:
								if p.identity!="主公": spy_targets.append(p.seat)
						if spy_targets.size()>=2 and state.targeting: token=state.targets.get(str(spy_targets[hero_step-8]),"")
					10: token=helper.find(state,"确认间谍")
					11: finished=true
				if token!="": hero_step+=1
		elif token=="": token=helper.find(state,"结束出牌")
	if token!="": last_signature=signature
	return token

func choose_after_fee(state) -> String:
	if state.mode==GameModes.FREE_FOR_ALL:
		finished=true
		return ""
	# Re-open own public detail; the normal skill button is the only entry.
	var hero=state.players.filter(func(p): return p.general==SUNNY)[0].seat
	var token=state.targets.get(str(hero),"")
	if token!="": hero_step=7; last_signature=var_to_str([state.owner,state.turn,state.phase,state.controls,state.targets])
	return token
