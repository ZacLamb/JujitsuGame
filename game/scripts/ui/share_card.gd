class_name ShareCard
extends RefCounted
## Wordle-style Daily Challenge result: a row of colored squares (one per exchange) the player can
## copy or share to the community chat. The in-game preview draws squares with panels (no emoji font
## needed); the shared text uses emoji, which phones and chat apps render natively.

const CODES := {
	"G": {"emoji": "🟩", "color": Color(0.3, 0.75, 0.35), "meaning": "your attack landed"},
	"Y": {"emoji": "🟨", "color": Color(0.97, 0.8, 0.25), "meaning": "perfect timing"},
	"R": {"emoji": "🟥", "color": Color(0.85, 0.27, 0.24), "meaning": "attack shut down"},
	"B": {"emoji": "🟦", "color": Color(0.25, 0.5, 0.9), "meaning": "you defended"},
	"O": {"emoji": "🟧", "color": Color(0.95, 0.55, 0.2), "meaning": "opponent scored"},
	"S": {"emoji": "🏆", "color": Color(1.0, 0.85, 0.3), "meaning": "you got the tap"},
	"X": {"emoji": "💀", "color": Color(0.35, 0.35, 0.38), "meaning": "you tapped"},
}
const MAX_SQUARES := 24

static func game_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.origin + window.location.pathname"))
	return ""

static func build_text(daily: Dictionary, res: Dictionary, log: Array, pts: Vector2i, streak: int) -> String:
	var rule: Dictionary = Data.DAILY_RULES.get(daily.get("rule", ""), {"name": "Daily"})
	var lines: Array[String] = []
	lines.append("🥋 Tatame Daily · %s" % daily.get("date", ""))
	lines.append("Rule: %s · vs %s" % [rule.name, daily.get("opp", {}).get("name", "?")])
	var how := ""
	if res.get("by_sub", false):
		how = "tapped out" if res.get("sub", "") == "tap" else "by %s" % Data.MOVES.get(res.sub, {"name": "submission"}).name
	else:
		how = "on points %d–%d" % [pts.x, pts.y]
	lines.append("%s %s" % ["✅ WIN" if res.get("won", false) else "❌ LOSS", how])
	var sq := ""
	for c in log.slice(0, MAX_SQUARES):
		sq += CODES[c].emoji
	if sq != "":
		lines.append(sq)
	if res.get("won", false) and streak > 1:
		lines.append("🔥 %d-day streak" % streak)
	var url := game_url()
	if url != "":
		lines.append(url)
	if Data.COMMUNITY_URL != "":
		lines.append(Data.COMMUNITY_URL)
	return "\n".join(lines)

## In-game preview row of squares.
static func squares(log: Array) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	for c in log.slice(0, MAX_SQUARES):
		var p := Panel.new()
		p.custom_minimum_size = Vector2(22, 22)
		p.add_theme_stylebox_override("panel", UiKit.box(CODES[c].color, 4, Color(0, 0, 0, 0.5), 1))
		p.tooltip_text = CODES[c].meaning
		row.add_child(p)
	return row

## Opens the phone's share sheet when available, otherwise copies to the clipboard.
## Returns a short status for the button label.
static func share(text: String) -> String:
	DisplayServer.clipboard_set(text)
	if OS.has_feature("web"):
		var js := """(function(t){
			try { if (navigator.share) { navigator.share({text: t}).catch(function(){}); return 'shared'; } } catch(e) {}
			try { navigator.clipboard.writeText(t); return 'copied'; } catch(e) {}
			return 'copied';
		})(%s)""" % JSON.stringify(text)
		return str(JavaScriptBridge.eval(js))
	return "copied"
