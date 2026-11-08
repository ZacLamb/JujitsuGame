extends Node
## How far modelled players get in Circuito runs (random card picks). Run: godot --headless tests/circuit_balance.tscn
func _ready() -> void:
	Game.test_mode = true
	for setup in [["caceres-ish", 3, ["onca"]], ["chapada-ish", 13, ["onca", "jacare"]], ["rio-ish", 19, ["onca", "jacare", "cachoeira"]]]:
		Game.reset()
		Game.choose_style("passer", "Bot", 0)
		Game.rank = setup[1]
		for id in setup[2]:
			Game.wins[id] = 1
		for skill in ["average", "skilled"]:
			var hist := [0, 0, 0, 0, 0, 0]
			for n in 60:
				var run := Circuit.new_run(n)
				while not run.over():
					if not run.offers.is_empty():
						run.perks.append(run.offers[randi() % run.offers.size()])
						run.offers = []
					var sim := RollSim.new()
					Team.setup_sim(sim, Team.you(), run.current(), run.stamina, 1.0, n * 31 + run.round, {"roles": false, "rule": "", "perks": run.perks})
					var bot := RollBot.new(skill, n * 7 + run.round)
					var r: Dictionary = bot.play(sim)
					run.apply(r, sim.stamina / sim.max_stamina)
				hist[run.round] += 1
			print("%-12s %-8s wins per run %s  champion %d%%" % [setup[0], skill, str(hist), int(100.0 * hist[5] / 60.0)])
	get_tree().quit()
