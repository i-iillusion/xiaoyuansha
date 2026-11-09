# I05c-4a: one physical draw receipt, not skill authorization or scheduling.
# The caller decides whether/when Corruption may act, including Q9 priority.
# A failed snapshot is a safety failure, not permission to cancel a committed
# effect: authorized intervening moves must be reconciled by the caller.
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
var _snapshot: HandSelection
var _indices: Array[int] = []
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
	_snapshot=HandSelection.new(p)
	for index in range(first,first+amount): _indices.append(index)

func is_extra() -> bool:
	return context==Context.EXTRA

func valid() -> bool:
	return not closed and _snapshot!=null and is_instance_valid(owner) and owner.is_alive() \
		and owner.awakening_revision==_general_revision and owner.hand==_snapshot.hand \
		and owner.determined_cards==_snapshot.determined and (not _allowed.is_valid() or _allowed.call())

func loss_atoms(amount: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not valid() or amount<=0 or amount>count: return result
	for index in _indices.slice(0,amount):
		result.append({"owner":owner,"zone":"hand","index":index,"card":_snapshot.cards[index]})
	return result

# The original arbitrary cards remain arbitrary. No declaration, discard,
# destination or card-action fact is manufactured by claiming this receipt.
func take(amount: int) -> Array[CardBase]:
	var empty: Array[CardBase]=[]
	if not valid() or amount<=0 or amount>count: return empty
	var selected: Array[int]=[]
	selected.assign(_indices.slice(0,amount))
	var result=_snapshot.take(selected,amount)
	if result.size()==amount: closed=true
	return result

func close():
	closed=true
