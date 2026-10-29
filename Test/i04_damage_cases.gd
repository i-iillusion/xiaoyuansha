extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for effect in ["soul","blood","kevin","pofeng"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var source = game.players[0]
		var mountain = game._spawn_mountain_at(game.players[1],1,2)
		var asks: Array = []
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		game._rps_override = func(_p): asks.append("gesture"); return 0
		game._kaiwen_override = func(): asks.append("kevin"); return true
		game._bloodthirsty_override = func(): asks.append("blood"); return true
		game._soul_blade_activate_override = func(): asks.append("soul"); return true
		if effect == "kevin": source.general_name = "凯文·罗本"
		else:
			var weapon = {"soul":CardData.CardSubType.SOUL_BLADE,"blood":CardData.CardSubType.BLOODTHIRSTY_BLADE,"pofeng":CardData.CardSubType.POFENG_SPEAR}[effect]
			source.equip_card_to_slot("weapon",CardBase.create(weapon))
		source.soul_blade_activated = effect == "soul"
		source.hp = 2
		var hand = source.hand_size()
		# Actual damage + post-damage pipeline. Target selection and Dodge are
		# deliberately skipped here: this is Q14, not full legal killing terrain.
		var chain = game._new_damage_chain(source,mountain,CardBase.create(CardData.CardSubType.STRIKE),2,EffectChain.DamageType.PHYSICAL)
		chain.skip_targeting = true
		chain.skip_response = true
		await chain.start()
		t.check(chain.damage.committed and mountain.hp == 3 and not chain.continuation_invalid, "I04 Q14 committed terrain damage finishes without technical invalidation: "+effect)
		t.check(asks.is_empty() and not mountain.facedown and source.hp == 2 and source.hand_size() == hand, "I04 Q14 no terrain RPS prompt, gesture, flip, healing or draw: "+effect)
		t.check(chain.damage.events.has("after_take_damage") and ActorIdentity.key_for(game.players,game.unit_registry,mountain) == null, "I04 Q14 remaining damage hooks finish without assigning terrain an actor identity")
		t.check(source.hand_limit_bonus == (2 if effect == "pofeng" else 0), "I04 Q14 unrelated Pofeng damage benefit remains intact")
		t.check(await game._try_soul_blade(source,mountain) == 0 and await game._try_bloodthirsty(source,mountain,2) == 0 and await game._try_kaiwen_deal(source,mountain,2) == 0, "I04 Q14 direct optional-effect entry points also decline normally")
		# Both real fixed players and intelligent units must retain their existing
		# RPS behavior. Unit registration is a classification fixture, not a new
		# authorization for this source general to summon a dragon.
		if effect != "pofeng":
			for unit_target in [false,true]:
				var target = game.players[2]
				if unit_target:
					target = FireDragonState.create_body()
					var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,target,game.players[1])
					game.fire_dragon_state.attach(id)
				asks.clear()
				game._rps_override = func(p): asks.append("gesture"); return 0 if p == source else 2
				var result = 0
				var before_hand = source.hand_size()
				var before_hp = source.hp
				if effect == "soul": result = await game._try_soul_blade(source,target)
				elif effect == "blood": result = await game._try_bloodthirsty(source,target,1)
				else: result = await game._try_kaiwen_deal(source,target,1)
				t.check(result == 0 and asks.has("gesture"), "I04 Q14 player/intelligent-unit RPS still executes: %s/%s" % [effect,unit_target])
				t.check(target.facedown if effect == "soul" else (source.hp == before_hp+1 if effect == "blood" else source.hand_size() == before_hand+2), "I04 Q14 eligible target retains existing RPS reward: %s/%s" % [effect,unit_target])
		game._game_over = true
		game.queue_free()
		await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
