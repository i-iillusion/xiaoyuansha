# 预大习的独立结算帧。扣血不是伤害；救援和最终死亡交给主控统一入口。
class_name YudaxiResolver
extends RefCounted

# 工程安全阈值，不是固定玩法数字；只统计规则步骤，不统计等待玩家输入。
var step_limit: int = 5000
var steps_used: int = 0
var aborted: bool = false
var results: Array[Dictionary] = []
var _owners: Array[Player] = []

func is_active() -> bool:
	return not _owners.is_empty()

func _step(stopped: Callable, on_limit: Callable) -> bool:
	if aborted or stopped.call():
		return false
	if steps_used >= maxi(step_limit, 1):
		aborted = true
		on_limit.call()
		return false
	steps_used += 1
	return true

func resolve(owner: Player, targets_for: Callable, settle_dying: Callable,
		draw_cards: Callable, stopped: Callable, on_limit: Callable):
	if _owners.has(owner):
		return
	if not is_active():
		steps_used = 0
		aborted = false
		results.clear()
	_owners.append(owner)
	var deaths := 0
	if _step(stopped, on_limit):
		# 每帧保存发动时目标快照；轮到时再次检查，子帧不能覆盖父帧游标。
		var targets: Array[Player] = targets_for.call(owner)
		for target in targets:
			if not _step(stopped, on_limit):
				break
			if not target.is_alive() or _owners.has(target):
				continue
			target.hp -= 2
			if target.is_dying():
				await settle_dying.call(target)
				if aborted or stopped.call():
					break
				# 只统计这次扣血目标最终死亡。子帧的其他死亡不透传给父帧。
				if target.is_dead():
					deaths += 1
		if _step(stopped, on_limit) and deaths > 0 and not owner.is_dead():
			owner.hp = deaths # 回复至 X，不叠加旧负体力，也不按普通回复封顶。
			draw_cards.call(owner, deaths)
	results.append({"owner": owner, "deaths": deaths, "aborted": aborted})
	_owners.pop_back()
