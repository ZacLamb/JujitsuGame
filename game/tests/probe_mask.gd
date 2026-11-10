extends Node
func _ready() -> void:
	var z: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "pantanal"
	var w := World.new()
	add_child(w)
	w.build(z)
	var out := ""
	for iz in range(-90, 91, 6):
		var line := ""
		for ix in range(-90, 91, 4):
			var h := w.height(ix, iz)
			line += "B" if w._is_blocked(ix, iz) else ("#" if h > 0.05 else ("~" if h < -0.3 else "."))
		out += "%4d %s\n" % [iz, line]
	print(out)
	get_tree().quit()
