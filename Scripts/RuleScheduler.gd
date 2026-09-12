# 在结算边界执行单独规则；await 保留当前链及阶段，结束后从原处继续。
# 本类只提供机制，不实现【预大习】等技能的具体效果；规则裁定见 QA。
class_name RuleScheduler
extends RefCounted

var _pending: Array[Dictionary] = []
var _frames: Array[Dictionary] = []

func enqueue(rule_name: String, action: Callable, priority: int = 0):
	assert(action.is_valid())
	_pending.append({"name": rule_name, "action": action, "priority": priority})

func is_paused() -> bool:
	return not _frames.is_empty()

func checkpoint(context: RefCounted, stage: String):
	while not _pending.is_empty():
		# 相同优先级按入队顺序处理；这是调度默认值，不是技能争议的裁定。
		var next_index = 0
		for i in range(1, _pending.size()):
			if _pending[i]["priority"] > _pending[next_index]["priority"]:
				next_index = i
		var entry: Dictionary = _pending.pop_at(next_index)
		_frames.append({"context": context, "stage": stage, "rule": entry["name"]})
		await entry["action"].call(context, stage)
		_frames.pop_back()
