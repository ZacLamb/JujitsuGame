extends Node
## Character select on the title screen (writes real saves in the headless user dir).
func _ready() -> void:
	for c in Game.characters():
		Game.delete_character(str(c.id))
	Game.new_character()
	Game.choose_style("guard", "Zac", 0)
	Game.new_character()
	Game.choose_style("wrestler", "Kaique", 1)
	Game.xp = 900
	Game.rank = 3
	Game.save_game()
	Game.new_character()   # unfinished creation: should not show
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/title_chars.png")
	print("chars: ", Game.characters().size())
	get_tree().quit()
