class_name AiPaceWait
extends Node

signal finished(accepted: bool)
var settled := false
var deadline: int
var valid: Callable
var eligible: Callable

func _process(_delta: float) -> void:
	if not valid.call() or not eligible.call(): complete(false)
	elif Time.get_ticks_usec() >= deadline: complete(true)

func complete(accepted: bool) -> void:
	if settled: return
	settled = true
	set_process(false)
	finished.emit(accepted)

func _exit_tree() -> void:
	complete(false)
