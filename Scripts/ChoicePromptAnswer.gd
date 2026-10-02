# 每个选择窗口独享一次答复，失效与主动取消分别返回。
class_name ChoicePromptAnswer
extends RefCounted

const INVALID: int = -2
signal answered(choice: int)
var settled := false
var allowed: Callable

func submit(choice: int):
	if settled:
		return
	if allowed.is_valid() and not allowed.call():
		choice = INVALID
	settled = true
	allowed = Callable()
	answered.emit(choice)
