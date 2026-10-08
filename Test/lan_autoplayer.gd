extends RefCounted

# Test-only UI driver. It sees exactly the same filtered state as a remote player.
var played_revision := -1

func choose(state: Dictionary) -> String:
	if state.is_empty() or state.get("ended", false): return ""
	var controls: Array = state.get("controls", [])
	if state.get("targeting", false):
		var confirmation = controls.any(func(x): return "确认" in x.text or "确定" in x.text or x.text == "是")
		if not confirmation:
			for player in state.players:
				if player.seat != state.actor and not player.dead:
					return state.targets.get(str(player.seat), "")
	if played_revision == int(state.revision):
		for action in controls:
			if action.text == "结束出牌" and not action.disabled: return action.id
	# Decline responses/rescue; pay normal declarations through the actual widgets.
	for text in ["不出", "放弃", "不救", "不使用", "自动选牌", "石头", "确认", "确定", "是", "锦囊牌", "普通锦囊", "决斗", "出牌"]:
		for action in controls:
			if text in action.text and not action.disabled:
				if action.text == "决斗": played_revision = int(state.revision)
				return action.id
	for action in controls:
		if "结束" in action.text and not action.disabled: return action.id
	return ""
