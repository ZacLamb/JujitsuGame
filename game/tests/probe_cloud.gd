extends Node
func _ready() -> void:
	for c in Game.characters():
		Game.delete_character(str(c.id))
	Game.new_character()
	Game.choose_style("judoka", "CloudTester", 0)
	Game.save_game()
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 20: await get_tree().process_frame
	var cs: CharSelect = main.find_children("*", "CharSelect", true, false)[0]
	cs._open_panel()
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/cloud_panel.png")
	cs._close_panel()
	var done := [false, ""]
	Cloud.authenticate("register", "probe%d@example.com" % (randi() % 100000), "oss12345", func(e): done[0] = true; done[1] = e)
	for i in 600:
		await get_tree().process_frame
		if done[0]: break
	print("CLOUD auth err='", done[1], "' logged=", Cloud.logged_in(), " email=", Cloud.email)
	for i in 60: await get_tree().process_frame
	print("CLOUD status=", Cloud.status)
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/cloud_signed.png")
	# "another device": nothing local, log in, the fighter comes down from the account
	var em := Cloud.email
	Cloud.logout()
	for c in Game.characters():
		Game.delete_character(str(c.id))
	print("CLOUD local chars after wipe=", Game.characters().size())
	done = [false, ""]
	Cloud.authenticate("login", em, "oss12345", func(e): done[0] = true; done[1] = e)
	for i in 600:
		await get_tree().process_frame
		if done[0] and Game.characters().size() > 0: break
	print("CLOUD after login chars=", Game.characters().map(func(c): return c.name), " err='", done[1], "'")
	Cloud.logout()
	get_tree().quit()
