# Presentation-only gate. No payment, random decision or rule mutation here.
class_name AiActionPacer
extends RefCounted

enum Speed { SLOW, STANDARD, FAST }
const SECONDS = [1.2, 0.6, 0.0]
# Preserve the existing speed until PACE01b exposes the menu setting.
var speed: Speed = Speed.FAST
var wait_override: Callable # Dedicated test clock, not a response timeout.

func before_action(owner: Node, valid: Callable, eligible: Callable) -> bool:
	var reference = weakref(owner)
	var tree = owner.get_tree()
	if tree == null or owner.is_queued_for_deletion() or not valid.call() or not eligible.call(): return false
	var seconds: float = SECONDS[speed]
	if seconds <= 0: return true
	var gate = AiPaceWait.new()
	gate.valid = valid
	gate.eligible = eligible
	gate.deadline = Time.get_ticks_usec() + int(seconds * 1000000)
	owner.add_child(gate)
	# Resolve while the owner's script still exists, not a timer resuming after
	# the scene has already been destroyed.
	var exiting = gate.complete.bind(false)
	owner.tree_exiting.connect(exiting)
	if wait_override.is_valid():
		gate.set_process(false)
		_finish_clock.call_deferred(gate, seconds, wait_override)
	var accepted: bool = await gate.finished
	var current = reference.get_ref()
	if current != null and current.tree_exiting.is_connected(exiting): current.tree_exiting.disconnect(exiting)
	if is_instance_valid(gate): gate.queue_free()
	return accepted and current != null and not current.is_queued_for_deletion() \
		and current.is_inside_tree() and valid.call() and eligible.call()

func _finish_clock(gate: AiPaceWait, seconds: float, clock: Callable) -> void:
	await clock.call(seconds)
	if is_instance_valid(gate) and not gate.settled:
		gate.complete(gate.valid.call() and gate.eligible.call())
