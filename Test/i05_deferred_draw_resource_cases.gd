extends RefCounted
const Base=preload("res://Test/i05_extra_draw_batch_cases.gd")
const Farming=preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await payments(t)
	await interleaving(t)
	await real_snatch(t)
	await signal_parity(t)
	await transaction_ids(t)
	for victims in [1,2]: await yudaxi_peaches(t,victims)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func payments(t):
	for kind in ["play","response","selection","automatic","old_blank","old_concrete","clear"]:
		var game=Base.new().fixture(t)
		var p=game.players[1]
		var original=CardBase.create(CardData.CardSubType.DODGE)
		p.hand.assign([original,null])
		var batch=game._draw_blank_cards(p,4)
		var old_ids=p.draw_hand_ids(0,2)
		var epoch=p.draw_hand_epoch()
		var expected=4
		if kind=="play":
			t.check(HandPayment.take_card(p,CardData.CardSubType.PEACH).sub_type==CardData.CardSubType.PEACH,"I05c ordinary declared payment consumes tracked original arbitrary card")
			expected=3
		elif kind=="response":
			t.check(HandPayment.take_player_response(p,CardData.CardSubType.STRIKE).sub_type==CardData.CardSubType.STRIKE,"I05c real response payment consumes tracked blank with normal declaration")
			expected=3
		elif kind=="selection":
			var indices: Array[int]=[0,3]
			var taken=HandSelection.new(p).take(indices,2)
			t.check(taken.size()==2 and taken[0]==original and taken[1]==null,"I05c selected mixed cost retains original card order and identity")
			expected=3
		elif kind=="automatic":
			t.check(p.take_hand_cards(2)==[null,null],"I05c automatic physical cost takes two original tail resources")
			expected=2
		elif kind=="old_blank": t.check(p.remove_from_hand(null),"I05c ordinary remove_from_hand can remove an older blank")
		elif kind=="old_concrete": t.check(p.remove_from_hand(original),"I05c ordinary remove_from_hand can remove an older concrete resource")
		else:
			game._discard_all_cards(p,true)
			expected=0
		t.check(batch.remaining_count()==expected,"I05c receipt counts only surviving originals after each physical payment path: "+kind)
		var later=CardBase.create(CardData.CardSubType.PEACH)
		p.append_hand_card_silent(later)
		p.append_hand_card_silent(null)
		var last_ids=p.draw_hand_ids(p.hand.size()-2,2)
		t.check(p.draw_hand_epoch()==epoch and not last_ids.has(old_ids[0]) and batch.remaining_count()==expected,"I05c known appends preserve original epoch and never reuse old card identities")
		var amount=batch.remaining_count()
		var claimed=batch.take(amount)
		t.check(claimed.size()==amount and claimed.all(func(card): return card==null) and p.hand.has(later),"I05c delayed batch claims survivors without stealing later concrete/blank cards: "+kind)
		t.check(p.draw_hand_index(last_ids[0],epoch)>=0 and p.draw_hand_index(last_ids[1],epoch)>=0,"I05c both later resources retain their own live identities after the delayed claim")
		if kind=="clear": t.check(not batch.valid() and not batch.closed,"I05c empty original batch has no physical claim; this does not decide Q10 RPS eligibility")
		await Farming.new().dispose(t,game)

func interleaving(t):
	for reverse in [false,true]:
		var game=Base.new().fixture(t)
		var p=game.players[1]
		var first=game._draw_blank_cards(p,2)
		var second=game._draw_blank_cards(p,3)
		t.check(first.valid() and second.valid() and first.remaining_count()==2 and second.remaining_count()==3,"I05c second genuine draw does not invalidate first batch or merge their identities")
		var a=second if reverse else first
		var b=first if reverse else second
		t.check(a.take(a.count).size()==a.count and b.valid() and b.remaining_count()==b.count,"I05c taking either batch rebases other batch by stable ids, not stale positions")
		t.check(b.take(b.count).size()==b.count and p.hand_size()==0,"I05c both batches can settle once in original or nested order without resource replacement")
		await Farming.new().dispose(t,game)
	var game=Base.new().fixture(t)
	var p=game.players[1]
	var batch=game._draw_blank_cards(p,2)
	var later=CardBase.create(CardData.CardSubType.DODGE)
	p.determined_cards.append(later)
	t.check(batch.valid() and batch.take(2)==[null,null] and p.determined_cards==[later],"I05c unrelated concrete hand-zone gains do not cancel a valid original draw or enter it")
	var fresh=game._draw_blank_cards(p,2)
	p.hand.append(null) # Unannounced mutation is intentionally not reconciled.
	t.check(not fresh.valid() and fresh.take(1).is_empty(),"I05c unknown raw hand mutations remain rejected without guessing original cards")
	await Farming.new().dispose(t,game)

func real_snatch(t):
	var game=Base.new().fixture(t)
	var source=game.players[0]
	var target=game.players[1]
	source.hand.assign([null])
	var original=game._draw_blank_cards(target,4)
	game._zone_pick_override=func(): return "hand"
	await game.execute_card_on_target(target,CardData.CardSubType.SNATCH)
	t.check(original.remaining_count()==3 and source.hand_size()==1 and game._draw_batches.size()==1,"I05c real paid Snatch moves an original card without creating a new draw batch")
	var later=game._draw_blank_cards(target,2)
	t.check(original.valid() and later.valid() and original.take(3).size()==3 and later.remaining_count()==2,"I05c delayed original draw survives actual transfer and subsequent separate draw")
	t.check(later.take(2).size()==2 and target.hand_size()==0 and game._pending_card_actions.is_empty(),"I05c native card flow and both batches finish with no duplicated action or resource")
	await Farming.new().dispose(t,game)

func signal_parity(t):
	var game=Base.new().fixture(t)
	var p=game.players[1]
	game._draw_blank_cards(p,2)
	var signals: Array=[]
	p.hand_updated.connect(func(): signals.append(true))
	p.append_hand_card_silent(null)
	p.take_hand_card_at(0)
	p.take_hand_cards(1)
	t.check(signals.is_empty(),"I05c silent payment helpers do not introduce intermediate awakening signals")
	p.add_to_hand(null)
	p.remove_from_hand(null)
	t.check(signals.size()==2,"I05c existing public add/remove retain exactly one hand_updated notification each")
	await Farming.new().dispose(t,game)

func transaction_ids(t):
	var game=Base.new().fixture(t)
	var p=game.players[1]
	var batch=game._draw_blank_cards(p,2)
	var tx=CardLossTransaction.new(game.players[0],"corruption",batch.loss_atoms(1))
	t.check(tx.valid(),"I05c prospective draw loss transaction binds the original stable identity")
	p.take_hand_card_at(0)
	p.append_hand_card_silent(null)
	t.check(not tx.valid() and batch.remaining_count()==1 and batch.take(1)==[null] and p.hand_size()==1,"I05c same-value same-count replacement cannot replay an old null-card loss transaction")
	await Farming.new().dispose(t,game)

func yudaxi_peaches(t,victims):
	var game=Base.new().fixture(t)
	var root=game.players[0]
	var donor=game.players[1]
	root.general_name="里奥·普利威尔"; root.max_hp=5; root.hp=0
	donor.general_name="大卫·法米尔"; donor.max_hp=4; donor.hp=4; donor.capture_game_start_state(); donor.hp=1
	donor.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); donor.sage_activated=true
	game.players[2].general_name="桑尼·斯派"; game.players[2].hp=4
	game.players[3].hp=1
	game.players[4].hp=1 if victims==2 else 4
	game.turn_manager.current_player_idx=4
	game._sage_save_override=func(): return true
	game._rescue_choice_override=func(rescuer,dying,options):
		return CardData.CardSubType.PEACH if rescuer==donor and dying in [game.players[3],game.players[4]] and options.has(CardData.CardSubType.PEACH) else -1
	await game._resolve_dying(root,null,"deferred_draw_rescue_fixture")
	var records=game._draw_batches.filter(func(batch): return batch.owner==donor)
	t.check(records.size()==1 and records[0].during_yudaxi and not game.yudaxi.is_active(),"I05c actual highest-priority Sage receipt remains attributed to its originating rule")
	var batch=records[0]
	var remaining=4-victims*2
	t.check(donor.hand_size()==remaining and batch.remaining_count()==remaining and game.players[3].hp==1 and game.players[4].hp==(1 if victims==2 else 2),"I05c real rescue pays exactly two original Peaches per negative-HP target before deferred processing")
	var later=game._draw_blank_cards(donor,2)
	t.check(batch.remaining_count()==remaining and later.remaining_count()==2,"I05c later post-rule draw cannot refill an exhausted or partially paid original Sage batch")
	t.check(batch.take(remaining).size()==remaining and later.remaining_count()==2 and donor.hand_size()==2,"I05c delayed physical claim gets only remaining originals, leaving all later cards intact")
	await Farming.new().dispose(t,game)
