# 一次已经成立的使用/打出事实。弃牌费用、移牌与失败支付不创建此事件。
# 内部规则数据，不直接传给AI观察或公开UI；card保留本次原资源引用。
class_name CardActionEvent
extends RefCounted

enum Kind { USE, RESPONSE }

var id: int
var turn_id: int
var phase_id: int
var actor_seat: int
var turn_owner_seat: int
var kind: Kind
var sub_type: CardData.CardSubType
var card: CardBase
var from_hand: bool
var is_virtual: bool
# 成立与完成分离；仅由持有本次凭据的真实结算入口完成。
var settlement_completed: bool = false

func _init(serial: int, tm: TurnManager, actor: Player, resource: CardBase,
		action_kind: Kind, hand_origin: bool, virtual_use: bool):
	id = serial
	turn_id = tm.turn_id
	phase_id = tm.phase_id
	actor_seat = actor.seat_index
	turn_owner_seat = tm.current_player_idx
	kind = action_kind
	sub_type = resource.sub_type
	card = resource
	from_hand = hand_origin
	is_virtual = virtual_use
