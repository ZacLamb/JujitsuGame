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
	# factions: origin decides the side, the starting town and the story
	check(Game.faction() == "brasil", "gringo origin is Time Brasil")
	for c in Data.CHAPTERS:
		check(Data.ZONES.has(c.zone) and Data.OPPONENTS.has(c.master), "chapter %s zone + master exist" % c.id)
	for f in Origins.FACTIONS:
		var path: Array = Origins.FACTIONS[f].path
		check(path.size() == 4 and int(Data.ZONES[path[0]].levels[0]) == 1 and int(Data.ZONES[path[3]].levels[1]) == 50, "%s levels 1 to 50" % f)
		for i in 3:
			check(int(Data.ZONES[path[i + 1]].levels[0]) == int(Data.ZONES[path[i]].levels[1]) + 1, "%s: %s follows %s" % [f, path[i + 1], path[i]])
		check(Data.chapters_for(f).size() == 5, "%s has five chapters" % f)
	Game.reset()
	Game.set_identity("texan", "male", 0.3)
	Game.choose_style("guard", "Tex", 0)
	check(Game.faction() == "usa" and Game.zone == "texas", "Team USA starts in Dry Creek, Texas")
	check(Game.quest_available("u1_passport") and not Game.quest_available("s1_passport"), "Team USA gets its own story, not Brasil's")
	check(str(Game.story_next()[0].get("id", "")) == "u1", "tracker on chapter u1")
	check(Game.quest_available("buckle_hunt"), "side quests are open to everyone")
	Game.set_level(46)
	check(not Game.quest_available("s5_arrive") and not Game.quest_locked_by_level("s4_arrive" if Data.QUESTS.has("s4_arrive") else "s5_arrive"), "the other faction's chapters stay closed")
	Game.reset()
	Game.set_identity("carioca", "female", 0.5)
	Game.choose_style("guard", "Bia", 0)
	check(Game.faction() == "brasil" and Game.zone == "caceres", "Time Brasil starts in Cáceres")
	check(not Game.quest_available("u1_passport"), "Brasil can't take Team USA's story")
	# faction war + rival shadows
	Game.war_pending = 0
	Game.add_war(5)
	check(Game.war_pending == 5, "wins queue war points")
	Game.war = {"last": {"winner": "brasil"}}
	var xm := Game.xp_mult()
	Game.war = {"last": {"winner": "usa"}}
	check(xm - Game.xp_mult() > 0.04, "last week's winners get +5% XP")
	Game.war = {}
	var shadow: Dictionary = load("res://scripts/main.gd").new().rival_opponent({"name": "Tex", "level": 30, "belt": 2, "style": "wrestler", "faction": "usa", "gi": "1a3fbf", "skin": 0.4})
	check(shadow.style == "pressure" and Data.display_level(float(shadow.level)) == 30 and shadow.rank == 12, "rival shadow mirrors the player: " + str([shadow.style, Data.display_level(float(shadow.level)), shadow.rank]))
	var p0 := Game.war_pending
	var rx := Game.record_rival({"won": true, "by_sub": true})
	check(rx > 0 and Game.war_pending == p0 + 15 and Game.unlocked.has("rival_win"), "beating a shadow: XP, war points, achievement")
	for id in Loot.VENDOR:
		for it in Loot.VENDOR[id]:
			check(not Loot.item(it).is_empty(), "vendor %s sells known item %s" % [id, it])
	print("PASS (0 failures)" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()
