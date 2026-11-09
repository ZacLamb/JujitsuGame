extends Node
## Main story + gi/no-gi path checks. godot --headless tests/test_story.tscn
var fails := 0
func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: ", m)
	else:
		print("ok   ", m)

func _ready() -> void:
	await get_tree().process_frame
	Game.test_mode = true
	Game.reset()
	Game.style = "guard"
	# data integrity: every story quest's giver, chapter, opponents and requirements exist
	for id in Data.QUESTS:
		var q: Dictionary = Data.QUESTS[id]
		check(Data.QUEST_GIVERS.has(q.giver), "%s giver exists" % id)
		for r in q.get("requires", []):
			check(Data.QUESTS.has(r), "%s requires %s exists" % [id, r])
		for o in q.obj:
			if o.type == "beat":
				for oid in o.ids:
					check(Data.OPPONENTS.has(oid), "%s beats known opponent %s" % [id, oid])
			if o.type == "quests":
				for qid in o.ids:
					check(Data.QUESTS.has(qid), "%s counts known quest %s" % [id, qid])
			if o.type == "achievement":
				for aid in o.ids:
					check(not Data.achievement(aid).is_empty(), "%s needs known achievement %s" % [id, aid])
	for p in Data.PATHS:
		for mid in Data.PATHS[p].moves:
			check(Data.MOVES.has(mid), "path move %s exists" % mid)
	# chapter 1 flow
	check(Game.quest_available("s1_passport"), "story starts at level 1")
	Game.accept_quest("s1_passport")
	check(not Game.quest_ready("s1_passport"), "passport needs town quests")
	Game.quests["terere_run"] = {"state": "done", "count": {}}
	Game.quests["know_town"] = {"state": "done", "count": {}}
	check(Game.quest_ready("s1_passport"), "two town quests vouch for you")
	Game.complete_quest("s1_passport")
	check(not Game.quest_available("s1_liga"), "Men in Gold waits for level 3")
	Game.set_level(3)
	check(Game.quest_available("s1_liga"), "Men in Gold at level 3")
	check(str(Game.story_next()[1]).contains("Men in Gold"), "tracker points at the next story quest: " + str(Game.story_next()[1]))
	# stamp + path
	for id in ["s1_liga", "s1_training", "s1_copa"]:
		Game.quests[id] = {"state": "done", "count": {}}
	Game.set_level(10)
	Game.accept_quest("s1_onca")
	Game.wins["onca"] = 1
	check(Game.quest_ready("s1_onca"), "beating Onça readies the stamp quest")
	Game.complete_quest("s1_onca")
	check(Game.stamps.has("Academia Onça"), "first stamp")
	Game.accept_quest("s1_path")
	check(Game.quest_state("s1_path") == "active" and not Game.quest_ready("s1_path"), "path quest waits for a choice")
	Game.kit = "gi"
	Game.rank = 4
	check(Game.knows("cross_collar"), "gi: cross collar (rank 3) known at rank 4 before choosing")
	Game.set_path("nogi")
	check(Game.quest_ready("s1_path"), "choosing a path completes the quest")
	check(not Game.knows("cross_collar"), "no-gi path: gi signatures come 5 ranks later")
	Game.rank = 8
	check(Game.knows("cross_collar"), "...and arrive at rank 8")
	Game.kit = "nogi"
	check(not Game.knows("cross_collar"), "collar chokes need a gi on")
	var m := Game.mods()
	Game.kit = "gi"
	var m2 := Game.mods()
	check(float(m.get("dmg_all", 0.0)) - float(m2.get("dmg_all", 0.0)) > 0.09, "path mastery: +10% in your kit")
	Game.money = 100
	check(not Game.set_path("gi"), "retraining costs money")
	Game.money = 600
	check(Game.set_path("gi") and Game.money == 100 and Game.path == "gi", "retrain for R$500")
	print("PASS (0 failures)" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()
