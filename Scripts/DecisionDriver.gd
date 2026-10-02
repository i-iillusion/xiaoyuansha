# 决策器只接收值快照和合法候选；支付/规则执行由对局共同入口负责。
class_name DecisionDriver
extends RefCounted

var action_budget: int = 32
var chooser: Callable
var rng = RandomNumberGenerator.new()

func _init(seed_value: int = 1):
	rng.seed = seed_value

# 返回原因由调用者决定是否推进阶段；预算只是自主出牌防挂保护。
func run(observe: Callable, candidates: Callable, execute: Callable, valid: Callable) -> Dictionary:
	var executed = 0
	while executed < action_budget:
		if not valid.call():
			return {"reason": "stale", "actions": executed}
		var observation: Dictionary = observe.call()
		var options: Array = candidates.call(observation)
		if options.is_empty():
			return {"reason": "end", "actions": executed}
		var index: int
		if chooser.is_valid():
			index = await chooser.call(observation.duplicate(true), options.duplicate(true))
		else:
			index = rng.randi_range(0, options.size() - 1)
		if not valid.call():
			return {"reason": "stale", "actions": executed}
		if index < 0 or index >= options.size():
			return {"reason": "end", "actions": executed}
		# 每次执行后重新观察，不复用旧候选；失败也消耗防挂预算。
		await execute.call(options[index].duplicate(true))
		executed += 1
	return {"reason": "budget" if valid.call() else "stale", "actions": executed}
