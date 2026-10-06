extends RefCounted

# 防御性注入落位失败；不声称存在正常玩法插入点。
class RejectMountPlayer extends Player:
	var reject_mount := true
	func equip_mount_card(card: CardBase) -> bool:
		return false if reject_mount else super.equip_mount_card(card)

var suite
var game: GameManager
var events: Array[CardActionEvent] = []

func reset():
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._pending_determined_card = null
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
	events.clear()

func run(host):
	suite = host
	game = host.game
	var old_phase = game.turn_manager.current_phase
	var collect = func(event): events.append(event)
	var completed: Array[CardActionEvent] = []
	var finish = func(event): completed.append(event)
	game.card_action_committed.connect(collect)
	game.card_action_completed.connect(finish)
	for sub in [CardData.CardSubType.LIANNU, CardData.CardSubType.RENWANG_DUN,
		CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS,
		CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS]:
		for concrete in [false, true]:
			for replacing in [false, true]:
				reset()
				completed.clear()
				var p: Player = game.players[0]
				var category = CardData.get_equipment_slot_type(sub)
				var slot = "mount_1" if category == "mount" else category
				var old_card: CardBase = null
				if replacing:
					if category == "mount":
						for mount_slot in Player.MOUNT_SLOTS:
							p.equip_card_to_slot(mount_slot, CardBase.create(CardData.CardSubType.MOUNT_PLUS))
					else:
						p.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.QINGLONG_BLADE
							if category == "weapon" else CardData.CardSubType.BAGUA_ZHEN))
					old_card = p.get_equipment_card(slot)
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete:
					p.determined_cards.append(original)
				else:
					p.hand.append(null)
				if replacing:
					game._weapon_replace_override = func(): return false
					game._mount_replace_override = func(): return "cancel"
					await game.play_card(sub)
					suite.check(events.is_empty() and p.hand_size() == 1 and p.get_equipment_card(slot) == old_card,
						"E02d3：取消替换不发使用事件、不支付")
					game._weapon_replace_override = func():
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
						return true
					game._mount_replace_override = func():
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
						return slot
					await game.play_card(sub)
					suite.check(events.is_empty() and p.hand_size() == 1 and p.get_equipment_card(slot) == old_card,
						"E02d3：过期替换不发使用事件、不支付")
				game._weapon_replace_override = func(): return true
				game._mount_replace_override = func(): return slot
				await game.play_card(sub)
				var installed = p.get_equipment_card(slot)
				suite.check(completed == events and completed.size() == 1 and completed[0].settlement_completed,
					"F02b-1c：六类装备空槽/替换均有唯一完成事实")
				suite.check(events.size() == 1 and p.hand_size() == 0 and installed != null,
					"E02d3：六类装备空槽/替换、任意/具体来源成功只发一次")
				if events.size() == 1:
					var event = events[0]
					suite.check(event.card == installed and (not concrete or event.card == original)
						and event.sub_type == sub and event.actor_seat == 0
						and event.kind == CardActionEvent.Kind.USE and event.from_hand and not event.is_virtual,
						"E02d3：装备事件保存落位原牌及使用来源")
				if replacing:
					suite.check(game.deck._discard.count(old_card) == 1,
						"E02d3：替换旧牌只入弃一次且不另发用牌事件")
	for category in ["weapon", "armor", "mount"]:
		for concrete in [false, true]:
			reset()
			completed.clear()
			var p: Player = game.players[0]
			p.general_name = "安普提·斯丢皮得"
			var sub = CardData.CardSubType.LIANNU if category == "weapon" else (
				CardData.CardSubType.RENWANG_DUN if category == "armor" else CardData.CardSubType.MOUNT_PLUS)
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete:
				p.determined_cards.append(original)
			else:
				p.hand.append(null)
			game._sao_type_override = func(): return "cancel"
			await game._do_sao_hide(p, false)
			suite.check(events.is_empty() and p.hand_size() == 1, "E02d3：取消暗置不发事件")
			game._sao_type_override = func(): return category
			await game._do_sao_hide(p, false)
			var hidden = p.hidden_equip_card
			suite.check(completed == events and completed.size() == 1 and completed[0].settlement_completed,
				"F02b-1c：暗置完成唯一，明置不另计使用")
			suite.check(events.size() == 1 and p.hand_size() == 0 and hidden != null,
				"E02d3：三类装备实际暗置只发一次使用事件")
			if events.size() == 1:
				suite.check(events[0].card == hidden and (not concrete or hidden == original)
					and events[0].sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
					and events[0].from_hand and not events[0].is_virtual,
					"E02d3：暗置保留原牌，事件牌名记录暗置时点")
			game._sao_reveal_sub_override = func(): return sub
			await game._do_sao_reveal(p)
			suite.check(events.size() == 1 and hidden.sub_type == sub
				and events[0].sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
				"E02d3：明置不再发事件且不改写历史牌名")
	for concrete in [false, true]:
		reset()
		var original_player: Player = game.players[0]
		var actor = RejectMountPlayer.new()
		actor.seat_index = 0
		actor.general_name = "稻草人"
		game.players[0] = actor
		var original: CardBase = CardBase.create(CardData.CardSubType.MOUNT_PLUS) if concrete else null
		if concrete:
			actor.determined_cards.append(original)
			game._pending_determined_card = original
		else:
			actor.hand.append(null)
		await game.play_card(CardData.CardSubType.MOUNT_PLUS)
		suite.check(events.is_empty() and actor.equipment.is_empty() and actor.hand_size() == 1
			and (actor.determined_cards == [original] if concrete else actor.hand == [null]),
			"E02d3：防御性落位失败退回原手牌区，不发事件、不具体化任意牌")
		actor.reject_mount = false
		await game.play_card(CardData.CardSubType.MOUNT_PLUS)
		suite.check(events.size() == 1 and actor.hand_size() == 0
			and (not concrete or events[0].card == original),
			"E02d3：落位失败后下一合法操作仍只记录一次原牌使用")
		game.players[0] = original_player
		actor.free()
		reset()
		var old_armor = CardBase.create(CardData.CardSubType.RENWANG_DUN)
		original_player.equip_card_to_slot("armor", old_armor)
		var incoming: CardBase = CardBase.create(CardData.CardSubType.LIANNU) if concrete else null
		if concrete:
			original_player.determined_cards.append(incoming)
		else:
			original_player.hand.append(null)
		var ok = game._replace_play_equipment_if_current(original_player, "armor", CardData.CardSubType.LIANNU,
			CardData.CardSubType.RENWANG_DUN, old_armor, game.turn_manager.get_context_revision())
		suite.check(not ok and events.is_empty() and original_player.get_equipment_card("armor") == old_armor
			and original_player.hand_size() == 1 and game.deck._discard.is_empty(),
			"E02d3：防御性错槽替换失败回装旧牌、退回支付且不发事件")
	game._weapon_replace_override = Callable()
	game._mount_replace_override = Callable()
	game._sao_type_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game.card_action_committed.disconnect(collect)
	game.card_action_completed.disconnect(finish)
	reset()
	game.turn_manager.current_phase = old_phase
