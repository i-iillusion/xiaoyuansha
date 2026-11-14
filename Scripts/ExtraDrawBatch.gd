# I05c-4a: one physical draw receipt, not skill authorization or scheduling.
# The caller decides whether/when Corruption may act under adopted rulings.
# Player-owned hand mutations retain per-position ids across legal intervening
# payments/appends. Unknown direct mutations invalidate the tracking epoch.
class_name ExtraDrawBatch
extends RefCounted

enum Context { EXTRA, DRAW_PHASE, INITIAL_DEAL }
var owner: Player
var serial: int
var context: Context
var count: int
var during_yudaxi: bool
var lifecycle: int
var closed := false
var reaction_started := false
var corruption_exempt := false # Q11: only the originating Yudaxi success reward.
var allow_dying_owner := false # Q16: explicit awakening reward only.
var _card_ids: Array[int] = []
var _tracking_epoch: int
var _general_revision: int
var _allowed: Callable

func _init(p: Player, first: int, amount: int, kind: Context, number: int,
		inside_yudaxi: bool, generation: int, allowed: Callable = Callable()):
	owner=p
	serial=number
	context=kind
	count=amount
	during_yudaxi=inside_yudaxi
	lifecycle=generation
	_allowed=allowed
	if not is_instance_valid(p) or amount<=0 or first<0 or first+amount>p.hand.size():
		closed=true
		return
	_general_revision=p.awakening_revision
	_card_ids=p.draw_hand_ids(first,amount)
	_tracking_epoch=p.draw_hand_epoch()

func is_extra() -> bool:
	return context==Context.EXTRA

func valid() -> bool:
	return _resource_current() and (owner.is_alive() or (allow_dying_owner and owner.is_dying())) and not owner.unit_disappeared and remaining_count()>0

func _resource_current() -> bool:
	return not closed and is_instance_valid(owner) and owner.awakening_revision==_general_revision \
		and (not _allowed.is_valid() or _allowed.call()) and owner.draw_hand_epoch()==_tracking_epoch

func remaining_count() -> int:
	return remaining_indices().size()

func remaining_indices() -> Array[int]:
	var result: Array[int]=[]
	if not _resource_current(): return result
	for id in _card_ids:
		var index=owner.draw_hand_index(id,_tracking_epoch)
		if index>=0: result.append(index)
	return result

func loss_atoms(amount: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not valid() or amount<=0 or amount>remaining_count(): return result
	for index in remaining_indices().slice(0,amount):
		result.append({"owner":owner,"zone":"hand","index":index,"card":owner.hand[index],
			"draw_id":owner.draw_hand_ids(index,1)[0],"draw_epoch":_tracking_epoch})
	return result

# The original arbitrary cards remain arbitrary. No declaration, discard,
# destination or card-action fact is manufactured by claiming this receipt.
func take(amount: int) -> Array[CardBase]:
	var empty: Array[CardBase]=[]
	if not valid() or amount<=0 or amount>remaining_count(): return empty
	var selected: Array[int]=[]
	selected.assign(remaining_indices().slice(0,amount))
	var result=HandSelection.new(owner).take(selected,amount)
	if result.size()==amount: closed=true
	return result

func close():
	closed=true
