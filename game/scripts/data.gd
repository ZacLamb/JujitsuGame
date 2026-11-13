extends Node
## Static game data: positions, techniques, opponents, belts, achievements, landmarks.

# Community link shown on the title screen and journal. Leave empty to hide the button.
const COMMUNITY_URL := ""
const COMMUNITY_LABEL := "Join the community"

# ---------------------------------------------------------------- positions
# A position is always described from the perspective of the person "on top"
# (for BACK, "top" is the one who has the back).
const POS_STANDING := "standing"
const POS_GUARD := "guard"
const POS_HALF := "half"
const POS_SIDE := "side"
const POS_MOUNT := "mount"
const POS_BACK := "back"

const POSITION_NAMES := {
	"standing": "Standing",
	"guard": "Guard",
	"half": "Half Guard",
	"side": "Side Control",
	"mount": "Mount",
	"back": "Back Control",
}

# Role labels: what you are called in each position.
static func role_label(pos: String, top: bool) -> String:
	match pos:
		"standing":
			return "Standing"
		"guard":
			return "In their guard" if top else "Closed guard (bottom)"
		"half":
			return "Passing half guard" if top else "Half guard (bottom)"
		"side":
			return "Side control (top)" if top else "Under side control"
		"mount":
			return "Mounted (top)" if top else "Under mount"
		"back":
			return "You have the back" if top else "They have your back"
	return pos

const QA_KEY := "oss-tatame-qa"   # #qa=<key>&roll=... enables the dev URL shortcuts

# ---------------------------------------------------------------- techniques
# role: "any" (standing), "top" or "bottom".
# result: [position, actor_is_top] or "sub" for submissions.
# pts: IBJJF-style points (takedown 2, sweep 2, pass 3, mount 4, back 4).
# diff: 0 easy .. 3 hard (shrinks the timing window).
# rank: minimum rank index needed (0 = white belt no stripes, 4 = 4 stripes, 5 = blue).
## Belt-gated techniques that only some classes learn (everything else in the belt curriculum is
## shared: the fundamentals every jiu-jitsu player knows). Class tree techniques: TalentTrees.
## Bicos: odd jobs around town where your jiu-jitsu helps somebody out. Once a day each; the
## minigame is a drill's (mash / timing / arrows) and your attribute makes it easier.
## at: position relative to the zone's job anchor (Vila Nova square in Cáceres).
const JOBS := {
	"caceres": [
		{"id": "net", "name": "Pull In the Net", "who": "Seu Dito, fisherman", "attr": "grip", "kind": "timing", "at": Vector3(-30, 0, 6),
			"ask": "The river's full of pacu today and my hands are shot. Grip that net and pull on my count, three times.",
			"tip": "Grip on his count. Three pulls.", "done": "Seu Dito throws you a pacu and a thumbs up.", "fail": "The net slips. Seu Dito sighs and pulls it alone.", "xp": 45, "money": 12, "item": "pacu"},
		{"id": "cooler", "name": "Carry the Cooler", "who": "Dona Lurdes", "attr": "strength", "kind": "mash", "at": Vector3(-8, 0, -12),
			"ask": "Querido, the tereré cooler weighs more than me. Fireman's carry it to the stand?",
			"tip": "Tap fast. Lift with the legs, not the back.", "done": "Dona Lurdes pours you a tereré on the house.", "fail": "You set it down halfway. Dona Lurdes laughs and calls her nephew.", "xp": 40, "money": 10, "item": "terere"},
		{"id": "goat", "name": "Catch the Runaway Goat", "who": "Seu Tonho", "attr": "iq", "kind": "arrows", "at": Vector3(14, 0, 16),
			"ask": "My goat Fofinha escaped again! She jukes left, she jukes right. Read her and shoot the single leg!",
			"tip": "Read where she cuts. Answer it.", "done": "Single leg, clean finish. Fofinha is home and Seu Tonho owes you one.", "fail": "Fofinha sprawls. Fofinha wins. Fofinha is a better wrestler than you.", "xp": 50, "money": 14, "item": ""},
		{"id": "tent", "name": "Hold the Market Tent", "who": "Seu Jorge", "attr": "flexibility", "kind": "timing", "at": Vector3(6, 0, -10),
			"ask": "Wind's taking my awning! Base out and hold the poles when the gusts hit.",
			"tip": "Base out on every gust. Three of them.", "done": "The tent stays up. Seu Jorge gives you pão de queijo for the road.", "fail": "The awning flies off. At least nobody got hurt.", "xp": 40, "money": 10, "item": "pao_queijo"},
	],
}

const CLASS_MOVES := {
	"osoto_gari": ["judoka"], "o_goshi": ["judoka"], "harai_goshi": ["judoka"], "back_armbar": ["judoka", "guard"],
	"guillotine": ["wrestler", "passer"], "ankle_pick": ["wrestler"], "body_lock_td": ["wrestler", "passer"],
	"flower_sweep": ["guard"], "arm_drag_back": ["guard", "athlete"], "deep_half": ["guard", "athlete"], "lasso_sweep": ["guard"],
	"kneebar": ["athlete"], "toe_hold": ["athlete"],
	"north_south": ["passer", "wrestler"], "stack_pass": ["passer"], "smash_pass": ["passer", "wrestler"], "paper_cutter": ["passer"],
	"mounted_triangle": ["guard", "passer"]}

## Submission chains: when one doesn't finish (or gets defended), the next is already there.
const CHAINS := {"guard_armbar": "triangle", "triangle": "omoplata", "omoplata": "guard_armbar", "triangle_armbar": "omoplata",
	"gogoplata": "triangle", "kimura_guard": "guard_armbar", "rnc": "bow_arrow", "bow_arrow": "back_armbar", "back_armbar": "rnc",
	"twister": "rnc", "cross_collar": "mount_armbar", "mount_armbar": "mounted_triangle", "ezekiel": "mount_armbar",
	"mounted_triangle": "mount_armbar", "americana": "top_kimura", "top_kimura": "americana", "paper_cutter": "baseball_choke",
	"baseball_choke": "north_south", "north_south": "paper_cutter", "half_kimura": "toe_hold", "toe_hold": "half_kimura",
	"straight_ankle": "kneebar", "kneebar": "straight_ankle", "guillotine": "darce", "darce": "guillotine"}

## Can a class learn this technique at all?
static func class_ok(move_id: String, style: String) -> bool:
	return not CLASS_MOVES.has(move_id) or style in CLASS_MOVES[move_id]

## Zone bosses: an entrance line, a signature technique (a slow, heavy version of a real move, with
## its own warning) and a second phase when they're half worn down.
const BOSS := {
	"onca": {"sig": "arm_drag_back", "sig_name": "Bote da Onça", "sig_en": "The Jaguar's Pounce", "phase": "Good. Now I stop playing with my food."},
	"jacare": {"sig": "smash_pass", "sig_name": "Giro da Morte", "sig_en": "The Death Roll", "phase": "The swamp is patient. I am not. Again!"},
	"cachoeira": {"sig": "flower_sweep", "sig_name": "Queda d'Água", "sig_en": "The Waterfall", "phase": "Water finds every gap. Let's see yours."},
	"leao": {"sig": "cross_collar", "sig_name": "Mordida do Leão", "sig_en": "The Lion's Bite", "phase": "Fifty years on this mat. You think I tire?"},
	"boone": {"sig": "blast_double", "sig_name": "Lone Star Blast", "sig_en": "Lone Star Blast", "phase": "Alright, kid. Now we wrestle."},
	"gator": {"sig": "smash_pass", "sig_name": "Swamp Roll", "sig_en": "Swamp Roll", "phase": "Hundred degrees in here and you're the one sweating."},
	"sol": {"sig": "flower_sweep", "sig_name": "Vortex Sweep", "sig_en": "Vortex Sweep", "phase": "Breathe. The second half is where it begins."},
	"dale": {"sig": "guillotine", "sig_name": "Garage Door", "sig_en": "The Garage Door", "phase": "Thirty years in this garage. Round two."},
}

const MOVES := {
	# --- standing
	"double_leg": {"name": "Double-Leg Takedown", "pos": "standing", "role": "any", "result": ["guard", true], "pts": 2, "diff": 1, "cost": 14, "type": "takedown", "rank": 0},
	"single_leg": {"name": "Single-Leg Takedown", "pos": "standing", "role": "any", "result": ["half", true], "pts": 2, "diff": 0, "cost": 12, "type": "takedown", "rank": 0},
	"pull_guard": {"name": "Pull Guard", "pos": "standing", "role": "any", "result": ["guard", false], "pts": 0, "diff": 0, "cost": 4, "type": "guard", "rank": 0},
	"osoto_gari": {"name": "Osoto Gari (Judo Trip)", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 3, "cost": 16, "type": "takedown", "rank": 2},
	# --- closed guard, bottom
	"scissor_sweep": {"name": "Scissor Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 1, "cost": 12, "type": "sweep", "rank": 0},
	"hip_bump": {"name": "Hip Bump Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 1, "cost": 12, "type": "sweep", "rank": 1},
	"guard_armbar": {"name": "Armbar from Guard", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 0},
	"triangle": {"name": "Triangle Choke", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 1},
	"arm_drag_back": {"name": "Arm Drag to Back", "pos": "guard", "role": "bottom", "result": ["back", true], "pts": 4, "diff": 3, "cost": 14, "type": "back", "rank": 2},
	# --- closed guard, top
	"toreando": {"name": "Toreando Pass", "pos": "guard", "role": "top", "result": ["side", true], "pts": 3, "diff": 2, "cost": 14, "type": "pass", "rank": 0},
	"knee_cut_half": {"name": "Open & Knee Cut", "pos": "guard", "role": "top", "result": ["half", true], "pts": 0, "diff": 0, "cost": 10, "type": "pass", "rank": 0},
	# --- half guard, bottom
	"old_school": {"name": "Old School Sweep", "pos": "half", "role": "bottom", "result": ["half", true], "pts": 2, "diff": 1, "cost": 12, "type": "sweep", "rank": 0},
	"recover_guard": {"name": "Recover Closed Guard", "pos": "half", "role": "bottom", "result": ["guard", false], "pts": 0, "diff": 0, "cost": 8, "type": "escape", "rank": 0},
	"half_kimura": {"name": "Kimura from Half", "pos": "half", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 0},
	# --- half guard, top
	"knee_slice": {"name": "Knee Slice Pass", "pos": "half", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 12, "type": "pass", "rank": 0},
	"top_kimura": {"name": "Kimura from Top", "pos": "half", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 0},
	# --- side control, top
	"mount_up": {"name": "Knee Slide to Mount", "pos": "side", "role": "top", "result": ["mount", true], "pts": 4, "diff": 1, "cost": 12, "type": "advance", "rank": 0},
	"americana": {"name": "Americana", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 1, "cost": 14, "type": "sub", "rank": 0},
	# --- side control, bottom
	"shrimp_guard": {"name": "Shrimp to Guard", "pos": "side", "role": "bottom", "result": ["guard", false], "pts": 0, "diff": 1, "cost": 10, "type": "escape", "rank": 0},
	"underhook_half": {"name": "Underhook to Half", "pos": "side", "role": "bottom", "result": ["half", false], "pts": 0, "diff": 0, "cost": 8, "type": "escape", "rank": 0},
	# --- mount, top
	"mount_armbar": {"name": "Armbar from Mount", "pos": "mount", "role": "top", "result": "sub", "pts": 0, "diff": 1, "cost": 14, "type": "sub", "rank": 0},
	"cross_collar": {"name": "Cross Collar Choke", "pos": "mount", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 3},
	"mount_to_back": {"name": "Take the Back", "pos": "mount", "role": "top", "result": ["back", true], "pts": 4, "diff": 1, "cost": 10, "type": "back", "rank": 2},
	# --- mount, bottom
	"upa": {"name": "Upa (Bridge & Roll)", "pos": "mount", "role": "bottom", "result": ["guard", true], "pts": 2, "diff": 1, "cost": 14, "type": "sweep", "rank": 0},
	"elbow_knee": {"name": "Elbow-Knee Escape", "pos": "mount", "role": "bottom", "result": ["half", false], "pts": 0, "diff": 1, "cost": 10, "type": "escape", "rank": 0},
	# --- back, top
	"rnc": {"name": "Rear Naked Choke", "pos": "back", "role": "top", "result": "sub", "pts": 0, "diff": 1, "cost": 14, "type": "sub", "rank": 0},
	"bow_arrow": {"name": "Bow & Arrow Choke", "pos": "back", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 3},
	# --- back, bottom
	"back_escape": {"name": "Hand Fight & Turn In", "pos": "back", "role": "bottom", "result": ["guard", true], "pts": 0, "diff": 2, "cost": 12, "type": "escape", "rank": 0},
	# --- more techniques, unlocked by belt (IBJJF-style: leg locks come later)
	"flower_sweep": {"name": "Flower Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 1, "cost": 12, "type": "sweep", "rank": 3},
	"knee_on_belly": {"name": "Knee on Belly", "pos": "side", "role": "top", "result": ["side", true], "pts": 2, "diff": 1, "cost": 10, "type": "advance", "rank": 4},
	"guillotine": {"name": "Guillotine Choke", "pos": "standing", "role": "any", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 6},
	"kimura_guard": {"name": "Kimura from Guard", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 7},
	"deep_half": {"name": "Deep Half Sweep", "pos": "half", "role": "bottom", "result": ["side", true], "pts": 2, "diff": 2, "cost": 14, "type": "sweep", "rank": 9},
	"back_armbar": {"name": "Armbar from the Back", "pos": "back", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 10},
	"straight_ankle": {"name": "Straight Ankle Lock", "pos": "guard", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 0},
	"north_south": {"name": "North-South Choke", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 12},
	"mounted_triangle": {"name": "Mounted Triangle", "pos": "mount", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 13},
	"kneebar": {"name": "Kneebar", "pos": "half", "role": "top", "result": "sub", "pts": 0, "diff": 3, "cost": 16, "type": "sub", "rank": 15},
	# --- talent / style techniques (rank 99 = unlocked only by a style or talent)
	"snap_down": {"name": "Snap Down & Go Behind", "pos": "standing", "role": "any", "result": ["back", true], "pts": 4, "diff": 2, "cost": 14, "type": "back", "rank": 99},
	"uchi_mata": {"name": "Uchi Mata", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 15, "type": "takedown", "rank": 99},
	"flying_armbar": {"name": "Flying Armbar", "pos": "standing", "role": "any", "result": "sub", "pts": 0, "diff": 3, "cost": 22, "type": "sub", "rank": 99},
	"omoplata": {"name": "Omoplata", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 99},
	"berimbolo": {"name": "Berimbolo", "pos": "guard", "role": "bottom", "result": ["back", true], "pts": 4, "diff": 2, "cost": 16, "type": "back", "rank": 99},
	"leg_drag": {"name": "Leg Drag Pass", "pos": "guard", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 13, "type": "pass", "rank": 99},
	"darce": {"name": "D'Arce Choke", "pos": "half", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 99},
	"ezekiel": {"name": "Ezekiel Choke", "pos": "mount", "role": "top", "result": "sub", "pts": 0, "diff": 1, "cost": 13, "type": "sub", "rank": 99},
	# --- class techniques (belt-gated, only the listed classes learn them; see CLASS_MOVES)
	"ankle_pick": {"name": "Ankle Pick", "pos": "standing", "role": "any", "result": ["half", true], "pts": 2, "diff": 1, "cost": 12, "type": "takedown", "rank": 2},
	"o_goshi": {"name": "O Goshi (Hip Throw)", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 1, "cost": 13, "type": "takedown", "rank": 2},
	"stack_pass": {"name": "Stack Pass", "pos": "guard", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 13, "type": "pass", "rank": 3},
	"toe_hold": {"name": "Toe Hold", "pos": "half", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 4},
	"body_lock_td": {"name": "Body Lock Takedown", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 15, "type": "takedown", "rank": 5},
	"harai_goshi": {"name": "Harai Goshi", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 15, "type": "takedown", "rank": 5},
	"lasso_sweep": {"name": "Lasso Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 2, "cost": 13, "type": "sweep", "rank": 6},
	"smash_pass": {"name": "Smash Pass", "pos": "half", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 14, "type": "pass", "rank": 6},
	"paper_cutter": {"name": "Paper Cutter Choke", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 9},
	# --- class talent techniques (rank 99: taught by your class tree; see TalentTrees.CLASS_TEACH)
	"high_crotch": {"name": "High Crotch", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 15, "type": "takedown", "rank": 99},
	"sumi_gaeshi": {"name": "Sumi Gaeshi", "pos": "standing", "role": "any", "result": ["mount", true], "pts": 2, "diff": 2, "cost": 15, "type": "takedown", "rank": 99},
	"gogoplata": {"name": "Gogoplata", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99},
	"imanari_roll": {"name": "Imanari Roll", "pos": "standing", "role": "any", "result": "sub", "pts": 0, "diff": 3, "cost": 20, "type": "sub", "rank": 99},
	"baseball_choke": {"name": "Baseball Bat Choke", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99},
	"twister": {"name": "Twister", "pos": "back", "role": "top", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99},
	"crucifix": {"name": "Crucifix Choke", "pos": "back", "role": "top", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99},
	"triangle_armbar": {"name": "Triangle Armbar", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99},
	# --- spec-exclusive techniques (rank 99: only your spec knows them; see Specs)
	"chain_sub": {"name": "Armbar-Triangle Chain", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 18, "type": "sub", "rank": 99, "spec": "sub_hunter"},
	"lumberjack": {"name": "Lumberjack Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 1, "cost": 13, "type": "sweep", "rank": 99, "spec": "sweeper"},
	"worm_sweep": {"name": "Worm Guard Sweep", "pos": "guard", "role": "bottom", "result": ["side", true], "pts": 2, "diff": 2, "cost": 14, "type": "sweep", "rank": 99, "spec": "lapel_guard"},
	"blast_double": {"name": "Blast Double", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 16, "type": "takedown", "rank": 99, "spec": "chain_wrestler"},
	"tilt_back": {"name": "Tilt to the Back", "pos": "side", "role": "top", "result": ["back", true], "pts": 4, "diff": 2, "cost": 14, "type": "back", "rank": 99, "spec": "rider"},
	"peek_out": {"name": "Ghost Escape", "pos": "side", "role": "bottom", "result": ["half", true], "pts": 0, "diff": 2, "cost": 12, "type": "escape", "rank": 99, "spec": "scrambler"},
	"seoi_nage": {"name": "Ippon Seoi Nage", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 16, "type": "takedown", "rank": 99, "spec": "thrower"},
	"kuzushi_snap": {"name": "Kuzushi Snap-Down", "pos": "standing", "role": "any", "result": ["back", true], "pts": 2, "diff": 3, "cost": 15, "type": "back", "rank": 99, "spec": "grip_fighter"},
	"kesa_armlock": {"name": "Kesa Gatame Armlock", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99, "spec": "newaza"},
	"heel_hook": {"name": "Inside Heel Hook", "pos": "half", "role": "bottom", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99, "spec": "leg_locker"},
	"kiss_dragon": {"name": "Kiss of the Dragon", "pos": "guard", "role": "bottom", "result": ["back", true], "pts": 4, "diff": 3, "cost": 16, "type": "back", "rank": 99, "spec": "berimbolo"},
	"tech_standup": {"name": "Kipping Escape", "pos": "mount", "role": "bottom", "result": ["half", false], "pts": 0, "diff": 1, "cost": 10, "type": "escape", "rank": 99, "spec": "gas_tank"},
	"over_under": {"name": "Over-Under Pass", "pos": "guard", "role": "top", "result": ["side", true], "pts": 3, "diff": 2, "cost": 16, "type": "pass", "rank": 99, "spec": "smash"},
	"x_pass": {"name": "X-Pass", "pos": "half", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 12, "type": "pass", "rank": 99, "spec": "speed"},
	"smount_armbar": {"name": "S-Mount Armbar", "pos": "mount", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99, "spec": "mount_hunter"},
}

const SUB_FLAVOR := {
	"guard_armbar": "hips up, thumb to the sky",
	"triangle": "angle off, pull the head",
	"half_kimura": "figure-four grip, rotate",
	"top_kimura": "figure-four grip, crank",
	"americana": "paint the floor",
	"mount_armbar": "spin and fall back",
	"cross_collar": "deep grips, elbows wide",
	"rnc": "squeeze, elbows in",
	"bow_arrow": "collar and pants, pull",
	"flying_armbar": "jump, swing, hips up",
	"omoplata": "sit up, roll the shoulder",
	"darce": "arm through, squeeze",
	"ezekiel": "sleeve grip, saw the neck",
	"guillotine": "arm under the chin, hips up",
	"kimura_guard": "figure-four, sit up, rotate",
	"back_armbar": "slide the leg over, extend",
	"straight_ankle": "blade under the Achilles, arch",
	"north_south": "shoulder on the jaw, sprawl",
	"mounted_triangle": "lock the legs, pull the arm across",
	"kneebar": "hug the leg, hips through",
}

## Match commentary: {a} = attacker, {d} = defender, {m} = technique.
const COMMENTARY := {
	"takedown": ["{a} shoots in and finishes the {m}!", "What a {m} from {a}! Flat on the mat.", "{a} changes levels... {m}! Beautiful."],
	"sweep": ["{a} off the bottom with the {m}! The crowd loves it.", "{m}! {a} reverses the position.", "From nowhere, {a} hits the {m}."],
	"pass": ["{a} slices through the guard: {m}!", "Pressure, pressure... {a} passes with the {m}.", "{m}! {d} couldn't hold the guard."],
	"advance": ["{a} climbs higher: {m}.", "{m}. {a} is building the pressure.", "{a} moves up: {m}, and {d} is in trouble."],
	"back": ["{a} takes the back! {m}!", "Seatbelt on. {a} is behind {d}.", "{m}! Hooks in, {a} is there."],
	"escape": ["{d} bridges out: {m}!", "Escape! {a} recovers with the {m}.", "{a} won't stay down: {m}."],
	"guard": ["{a} sits to guard.", "{a} pulls guard, inviting {d} in.", "{a} takes it to the ground: {m}."],
}

static func commentary(move_id: String, attacker: String, defender: String) -> String:
	var m: Dictionary = MOVES[move_id]
	var lines: Array = COMMENTARY.get(m.type, ["{a}: {m}."])
	var line: String = lines[randi() % lines.size()]
	if m.type == "escape":
		line = line.replace("{d}", attacker)
	return line.format({"a": attacker, "d": defender, "m": m.name})

static func moves_for(pos: String, top: bool) -> Array:
	var out: Array = []
	for id in MOVES:
		var m: Dictionary = MOVES[id]
		if m.pos != pos:
			continue
		if pos == "standing" or (m.role == "top") == top:
			out.append(id)
	return out

# ---------------------------------------------------------------- belts
const BELTS := [
	{"name": "White", "color": Color(0.95, 0.95, 0.93)},
	{"name": "Blue", "color": Color(0.12, 0.33, 0.85)},
	{"name": "Purple", "color": Color(0.45, 0.2, 0.65)},
	{"name": "Brown", "color": Color(0.42, 0.26, 0.13)},
	{"name": "Black", "color": Color(0.08, 0.08, 0.08)},
]

# rank index -> belt index and stripes. 0..4 white, 5..9 blue, etc.
static func belt_of(rank: int) -> int:
	return clampi(rank / 5, 0, BELTS.size() - 1)

static func stripes_of(rank: int) -> int:
	return rank % 5

static func rank_name(rank: int) -> String:
	var s := stripes_of(rank)
	var b: String = BELTS[belt_of(rank)].name
	if s == 0:
		return Tx.f("%s Belt", b)
	return Tx.f("%s Belt, %d stripe%s", [b, s, "" if s == 1 else "s"])

# Combat level used by the timing formulas.
static func rank_level(rank: int) -> float:
	return 1.0 + float(rank) * 0.55

## The 1-50 level shown to players for a fighter's combat strength (same scale as Game.player_level).
static func display_level(combat_level: float) -> int:
	return clampi(int(round(1.0 + 2.0 * (combat_level - 1.0) / 0.55)), 1, 60)

## WoW-style "con" color: how dangerous a fighter at opp_lv is for a player at player_lv.
static func con_color(opp_lv: int, player_lv: int) -> Color:
	var d := opp_lv - player_lv
	if d >= 5:
		return Color(1.0, 0.25, 0.22)    # red: you will probably lose
	if d >= 3:
		return Color(1.0, 0.55, 0.15)    # orange: hard
	if d >= -2:
		return Color(1.0, 0.88, 0.25)    # yellow: even
	if d >= -7:
		return Color(0.35, 0.95, 0.35)   # green: easy
	return Color(0.62, 0.62, 0.62)       # gray: no challenge

static func zone_levels(z: String) -> String:
	var lv: Array = ZONES[z].levels
	return Tx.f("Lv %d–%d", [lv[0], lv[1]])

const XP_PER_STRIPE := 100

# ---------------------------------------------------------------- opponents (zone 1)
# level drives AI speed, reaction windows and move choice.
const OPPONENTS := {
	"rafa": {"name": "Rafa", "title": "Plaza regular", "rank": 0, "level": 1.3, "tutor": true, "pace": 1.35, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.78, 0.57, 0.4),
		"pos": Vector3(6, 0, 4), "style": "balanced",
		"intro": "Ei, gringo! Bora treinar? (Let's train?) I just started too, go easy.",
		"win": "Boa! You caught me. Go find the academia by the cathedral.",
		"lose": "Haha, tap early, tap often. Again later?"},
	"cida": {"body": "female", "name": "Cida", "title": "Riverbank runner", "rank": 3, "level": 2.0, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(-46, 0, -18), "style": "guard", "extra": ["omoplata"],
		"intro": "I train every morning before the sun gets mean. Guard player. Watch the triangle.",
		"win": "Sweep me like that again and I'm telling my professor.",
		"lose": "My legs are everywhere, né? Come back with better posture."},
	"tiago": {"name": "Tiago", "title": "Market wrestler", "rank": 5, "level": 2.6, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.86, 0.66, 0.5),
		"pos": Vector3(31, 0, -25), "style": "pressure", "extra": ["snap_down"],
		"intro": "Wrestled in school. I shoot doubles and I don't stop. Ready?",
		"win": "Good hips. Most people just fall over.",
		"lose": "Pressure, pressure, pressure. That's the game."},
	"peixe": {"name": "Peixe", "title": "Fisherman, blue belt", "rank": 7, "level": 3.1, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.62, 0.42, 0.28),
		"pos": Vector3(-52, 0, 30), "style": "back", "extra": ["berimbolo"],
		"intro": "They call me Peixe (fish). Slippery. If I get your back, it's over.",
		"win": "You held me down like a net. Respect.",
		"lose": "Like a fish, see? Hooks in, and goodbye."},
	"onca": {"name": "Mestre Onça", "title": "Gym boss, purple belt", "rank": 10, "level": 4.35, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.5, 0.34, 0.22),
		"pos": Vector3(0, 0, -50), "style": "submission", "boss": true, "extra": ["darce", "ezekiel", "omoplata", "leg_drag"],
		"intro": "So you beat the town. On my mat, every mistake costs a limb. Oss.",
		"win": "Oss. Kneel. You've earned this. Welcome to blue belt.",
		"lose": "Again. The mat doesn't lie. Come back stronger."},
	# ---------------- Zone 2: Pantanal
	"bruna": {"body": "female", "name": "Bruna", "title": "Ranch hand", "rank": 7, "level": 4.3, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.72, 0.52, 0.36),
		"pos": Vector3(-40, 0, 22), "style": "guard", "extra": ["omoplata", "berimbolo", "triangle"], "zone": "pantanal",
		"intro": "I wrestle calves before breakfast, gringo. Your guard passing better be good.",
		"win": "Okay, okay. You can come help with the cattle anytime.",
		"lose": "Legs like lassos. Next time."},
	"zeca": {"name": "Zeca", "title": "Boat guide", "rank": 9, "level": 4.9, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(38, 0, -34), "style": "pressure", "extra": ["leg_drag", "darce", "snap_down"], "zone": "pantanal",
		"intro": "Thirty years on these rivers. I've wrestled jacarés. You're easier.",
		"win": "Ha! The river humbles everyone. Today it was me.",
		"lose": "Heavy, né? Like a wet canoe."},
	"tuca": {"name": "Tuca", "title": "Park ranger, purple belt", "rank": 10, "level": 5.4, "gi": Color(0.32, 0.4, 0.22), "skin": Color(0.6, 0.42, 0.28),
		"pos": Vector3(-18, 0, -44), "style": "back", "extra": ["berimbolo", "bow_arrow", "rnc", "snap_down"], "zone": "pantanal",
		"intro": "I track jaguars for a living. I'll track your back.",
		"win": "Good defense. The onça would be proud.",
		"lose": "Seatbelt, hooks, sleep. Like clockwork."},
	"neide": {"body": "female", "name": "Dona Neide", "title": "Old-school killer, purple belt", "rank": 12, "level": 5.9, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.66, 0.47, 0.32),
		"pos": Vector3(53, 0, 26), "style": "submission", "extra": ["ezekiel", "omoplata", "cross_collar", "darce"], "zone": "pantanal",
		"intro": "Sixty-two years old, meu filho. Don't go easy. I won't.",
		"win": "Lindo! Your grandmother would be proud.",
		"lose": "Never underestimate the old lady with the gi."},
	"jacare": {"name": "Mestre Jacaré", "title": "Fazenda boss, brown belt", "rank": 15, "level": 7.3, "gi": Color(0.42, 0.26, 0.13), "skin": Color(0.48, 0.32, 0.2),
		"pos": Vector3(64, 0, 58), "style": "submission", "boss": true, "extra": ["darce", "ezekiel", "omoplata", "leg_drag", "berimbolo", "bow_arrow"], "zone": "pantanal",
		"intro": "Onça sent you? Then you know the rules. My mat, my swamp. Oss.",
		"win": "The swamp respects you now. Purple belt. Wear it well.",
		"lose": "The jacaré waits. The jacaré always wins in the end."},
	# ---------------- Zone 3: Chapada dos Guimarães
	"iara": {"body": "female", "name": "Iara", "title": "Waterfall guide, purple belt", "rank": 12, "level": 6.9, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.7, 0.5, 0.34),
		"pos": Vector3(26, 0, 6), "style": "guard", "extra": ["omoplata", "berimbolo", "triangle", "guard_armbar"], "zone": "chapada",
		"intro": "I swim under the Véu de Noiva every morning. Cold water, warm guard.",
		"win": "Strong passing. The waterfall would be jealous.",
		"lose": "Flow like water, gringo. You fought like a rock."},
	"biro": {"name": "Biro", "title": "Rock climber, purple belt", "rank": 13, "level": 7.4, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.8, 0.6, 0.45),
		"pos": Vector3(-30, 0, -40), "style": "pressure", "extra": ["leg_drag", "darce", "ezekiel", "knee_slice"], "zone": "chapada",
		"intro": "Fingers like hooks from the cliffs. Once I grip, I don't let go.",
		"win": "Okay, your grips are better than mine. Don't tell anyone.",
		"lose": "Crimp grip, gringo. You can't escape a crimp grip."},
	"joaquim": {"name": "Joaquim", "title": "Crystal seller, purple belt", "rank": 14, "level": 7.9, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(46, 0, 34), "style": "submission", "extra": ["ezekiel", "cross_collar", "omoplata", "bow_arrow"], "zone": "chapada",
		"intro": "The crystals say you will lose. But the crystals have been wrong before.",
		"win": "The crystals... were wrong. Take this one, for luck.",
		"lose": "The crystals are never wrong twice."},
	"rita": {"body": "female", "name": "Rita", "title": "Trail runner, brown belt", "rank": 16, "level": 8.3, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.62, 0.42, 0.28),
		"pos": Vector3(-8, 0, -58), "style": "back", "extra": ["berimbolo", "bow_arrow", "snap_down", "rnc"], "zone": "chapada",
		"intro": "I run the plateau trail twice a day. Let's see if your gas tank keeps up.",
		"win": "You outlasted me. That doesn't happen.",
		"lose": "Cardio is a technique too, gringo."},
	"gaucho": {"name": "Gaúcho", "title": "Visiting competitor, brown belt", "rank": 17, "level": 8.7, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.9, 0.72, 0.6),
		"pos": Vector3(-52, 0, 30), "style": "pressure", "extra": ["leg_drag", "darce", "uchi_mata", "ezekiel"], "zone": "chapada",
		"intro": "Came up from Porto Alegre for the Chapada open. You're my warm-up, tchê.",
		"win": "Bah! Good roll, tchê. See you at the Worlds.",
		"lose": "Warm-up's done. Thanks, tchê."},
	"cachoeira": {"name": "Mestre Cachoeira", "title": "Chapada boss, black belt", "rank": 20, "level": 9.85, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.42, 0.28, 0.18),
		"pos": Vector3(40, 0, 52), "style": "submission", "boss": true,
		"extra": ["darce", "ezekiel", "omoplata", "leg_drag", "berimbolo", "bow_arrow", "uchi_mata", "flying_armbar", "cross_collar"], "zone": "chapada",
		"intro": "Onça and Jacaré were my students. Show me what they taught you. Oss.",
		"win": "Brown belt. One step from the black. The mat is your home now.",
		"lose": "The waterfall wears down the rock over a thousand years. Come back."},
	# ---------------- Zone 4: Rio de Janeiro
	"dudu": {"name": "Dudu", "title": "Surfer, brown belt", "rank": 17, "level": 9.6, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.78, 0.55, 0.38),
		"pos": Vector3(22, 0, 40), "style": "balanced", "extra": ["berimbolo", "uchi_mata", "flying_armbar", "leg_drag"], "zone": "rio",
		"intro": "Waves are flat today, mermão. Guess I'll surf on you instead.",
		"win": "Caramba! You roll like a local. Valeu!",
		"lose": "Tá maluco? Go eat an açaí and try again."},
	"luana": {"body": "female", "name": "Luana", "title": "Beach volleyball pro, brown belt", "rank": 18, "level": 10.0, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.66, 0.45, 0.3),
		"pos": Vector3(-30, 0, 42), "style": "back", "extra": ["berimbolo", "bow_arrow", "snap_down", "rnc"], "zone": "rio",
		"intro": "Sand training makes your legs like steel. You're about to find out.",
		"win": "Nice! You read the berimbolo before I even spun.",
		"lose": "Sand in your gi and a choke on your neck. Classic Copacabana."},
	"baiano": {"name": "Baiano", "title": "Capoeira mestre, brown belt", "rank": 18, "level": 10.5, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.36, 0.23, 0.15),
		"pos": Vector3(52, 0, 27), "style": "guard", "extra": ["berimbolo", "omoplata", "triangle", "flying_armbar"], "zone": "rio",
		"intro": "Ginga, gringo. Capoeira taught me to move. Jiu-jitsu taught me to finish.",
		"win": "Axé! Your base is stronger than my ginga.",
		"lose": "The berimbau plays, and you dance to my rhythm."},
	"tatu": {"name": "Tatu", "title": "Morro social project coach, black belt", "rank": 20, "level": 10.9, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.45, 0.3, 0.2),
		"pos": Vector3(36, 0, -42), "style": "pressure", "extra": ["leg_drag", "darce", "ezekiel", "knee_slice"], "zone": "rio",
		"intro": "I teach forty kids up here for free. They all watch me roll. Don't embarrass yourself.",
		"win": "The kids are clapping for you. Come teach a class sometime.",
		"lose": "Pressure, gringo. Up here we grow up under pressure."},
	"bia": {"body": "female", "name": "Professora Bia", "title": "Competition coach, black belt", "rank": 21, "level": 11.4, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.88, 0.7, 0.56),
		"pos": Vector3(-68, 0, 36), "style": "submission", "extra": ["ezekiel", "cross_collar", "omoplata", "bow_arrow", "darce"], "zone": "rio",
		"intro": "I train world champions at sunrise on the Arpoador. Let's see what Mato Grosso sent me.",
		"win": "Technical, patient, dangerous. Leão will want to see you.",
		"lose": "Good roll. Tap a little earlier next time; I can see the sunset from here."},
	"leao": {"name": "Grão-Mestre Leão", "title": "Rio boss, coral belt legend", "rank": 24, "level": 12.35, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.62, 0.45, 0.32),
		"pos": Vector3(10, 0, -24), "style": "balanced", "boss": true,
		"extra": ["darce", "ezekiel", "omoplata", "leg_drag", "berimbolo", "bow_arrow", "uchi_mata", "flying_armbar", "cross_collar", "snap_down"], "zone": "rio",
		"intro": "Onça, Jacaré, Cachoeira... I gave them their black belts. Now show me yours is earned. Oss.",
		"win": "Kneel, gringo. You came to Brazil a tourist. You leave a black belt. Oss.",
		"lose": "The black belt is just a white belt who never quit. Come back tomorrow."},
	# ---------------- Zone 5: San Diego (America do Norte)
	"tyler": {"name": "Tyler", "title": "Surfer, brown belt", "rank": 17, "level": 10.4, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.9, 0.72, 0.56),
		"pos": Vector3(22, 0, 42), "style": "guard", "extra": ["berimbolo", "omoplata", "lasso_sweep", "triangle"], "zone": "socal",
		"intro": "Dude, a Brazilian passport? Sick. I learned from YouTube and the ocean. Let's flow.",
		"win": "Gnarly. You roll like the old tapes my coach shows us.",
		"lose": "Inverted guard, bro. The ocean taught me that."},
	"brooke": {"body": "female", "name": "Brooke", "title": "College wrestler, brown belt", "rank": 18, "level": 10.8, "gi": Color(0.12, 0.2, 0.45), "skin": Color(0.78, 0.58, 0.42),
		"pos": Vector3(-36, 0, 6), "style": "pressure", "extra": ["high_crotch", "body_lock_td", "snap_down", "darce"], "zone": "socal",
		"intro": "Four years of Division I. I don't pull guard. You're going down, then you're staying down.",
		"win": "Okay. That scramble was disgusting. Respect.",
		"lose": "Mat returns are a lifestyle."},
	"marcus": {"name": "Marcus", "title": "Veteran, black belt", "rank": 20, "level": 11.4, "gi": Color(0.33, 0.36, 0.25), "skin": Color(0.4, 0.27, 0.18),
		"pos": Vector3(56, 0, -30), "style": "pressure", "extra": ["knee_slice", "smash_pass", "north_south", "paper_cutter"], "zone": "socal",
		"intro": "Twenty years in the service, fifteen on the mat. Slow is smooth, smooth is fast. Ready?",
		"win": "Good discipline. Whoever taught you did it right.",
		"lose": "Pressure first. Submission second. Every time."},
	"kenji": {"name": "Kenji", "title": "Leg lock nerd, black belt", "rank": 21, "level": 11.8, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.82, 0.66, 0.5),
		"pos": Vector3(-52, 0, -42), "style": "submission", "extra": ["toe_hold", "kneebar", "straight_ankle", "darce"], "zone": "socal",
		"intro": "I've watched four thousand hours of instructionals. Your knees are a solved problem.",
		"win": "Interesting. You hid your heel. I'll need to rewatch my notes.",
		"lose": "Inside heel hook, outside position. Textbook."},
	"dale": {"name": "Coach Dale", "title": "The Garage, black belt", "rank": 24, "level": 12.6, "gi": Color(0.12, 0.12, 0.14), "skin": Color(0.86, 0.64, 0.48), "boss": true,
		"pos": Vector3(-18, 0, -40), "style": "submission", "extra": ["toe_hold", "kneebar", "darce", "high_crotch", "body_lock_td", "straight_ankle", "berimbolo"], "zone": "socal",
		"intro": "Grew up wrestling, fell in love with jiu-jitsu off a VHS from Brazil. Thirty years in this garage. Show me what Leão gave you.",
		"win": "Four stamps and now The Garage. Oss, brother. Brazil taught me, and you just reminded me why.",
		"lose": "Leg locks are part of jiu-jitsu now. Leão knows it. Come back."},
	"sterling": {"name": "Brock Sterling", "title": "Gold League USA champion", "rank": 22, "level": 12.2, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.9, 0.74, 0.6),
		"pos": Vector3(40, 0, 10), "style": "balanced", "extra": ["darce", "body_lock_td", "kneebar", "bow_arrow", "flying_armbar"], "liga": true, "zone": "socal",
		"intro": "My dad funds the Liga Ouro. Every gym on this coast will be a Gold League by summer. You're a speed bump, passport boy.",
		"win": "...My dad's going to pull out. Brazil was supposed to be easy money.",
		"lose": "Gold always wins. Especially in America."},
	# ---------------- Liga Ouro (main story): gold gis, bought belts
	"valdir": {"name": "Valdir", "title": "Liga Ouro recruiter", "rank": 6, "level": 3.3, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.8, 0.6, 0.45),
		"pos": Vector3(-12, 0, 14), "style": "pressure", "extra": ["snap_down", "americana"], "liga": true,
		"intro": "Nice gi. Shame about the academy. In a month it's a Liga Ouro franchise, and you'll pay R$ 900 a stripe. Want a discount? Tap now.",
		"win": "...the Patrão is not going to like this.",
		"lose": "See? Gold beats cotton. Sign up at the plaza, gringo."},
	"brutus": {"name": "Brutus", "title": "Liga Ouro enforcer", "rank": 11, "level": 6.4, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.6, 0.42, 0.3),
		"pos": Vector3(-28, 0, 14), "style": "pressure", "extra": ["darce", "leg_drag", "snap_down"], "liga": true, "zone": "pantanal",
		"intro": "These ranch boys signed with the Liga. Contracts are contracts. You want to tear one up? Go through me.",
		"win": "Fine. Keep your cowboys. The Sucuri has more of us.",
		"lose": "Pressure is a business model, gringo."},
	"rico": {"name": "Rico Dourado", "title": "Liga Ouro 'black belt'", "rank": 18, "level": 9.3, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.85, 0.66, 0.5),
		"pos": Vector3(24, 0, 36), "style": "submission", "extra": ["darce", "omoplata", "kneebar", "bow_arrow"], "liga": true, "zone": "chapada",
		"intro": "Black belt, paid in full. The resort opens next month and the waterfall comes with it. Roll for it?",
		"win": "Okay. Maybe the belt was... a little expensive for what I got.",
		"lose": "Money can't buy skill? I just bought both."},
	"dourado": {"name": "O Campeão Dourado", "title": "Liga Ouro champion", "rank": 23, "level": 12.6, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(-6, 0, -30), "style": "balanced", "extra": ["darce", "berimbolo", "bow_arrow", "flying_armbar", "leg_drag", "kneebar"], "liga": true, "zone": "rio",
		"intro": "The Patrão paid for every medal I own. I still earned the ones he didn't. Let's see what a passport is worth.",
		"win": "Four stamps... I never had one. Tell Leão I want to start over. White belt.",
		"lose": "Gold always wins in the end, gringo."},
	# ================ Team USA · Dry Creek, Texas (Lv 1-10)
	"cody": {"name": "Cody", "title": "Courthouse square regular", "rank": 0, "level": 1.3, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.9, 0.72, 0.56),
		"pos": Vector3(6, 0, 4), "style": "balanced", "zone": "texas",
		"intro": "Howdy! You new? I've been training three whole weeks. Wanna roll? I'll go easy, promise.",
		"win": "Well shoot. You got me. Coach Mae's gym is behind the courthouse, go tell her I sent you.",
		"lose": "Tap early, tap often, partner. Come back anytime."},
	"jolene": {"body": "female", "name": "Jolene", "title": "Swimming hole lifeguard", "rank": 3, "level": 2.0, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.86, 0.66, 0.5),
		"pos": Vector3(-50, 0, -12), "style": "guard", "extra": ["omoplata"], "zone": "texas",
		"intro": "I sit up in that chair all summer working on my guard in my head. Let's see if it works on land.",
		"win": "Okay, okay, you passed it. Don't tell the other lifeguards.",
		"lose": "Legs everywhere, huh? Posture up next time, cowboy."},
	"travis": {"name": "Travis", "title": "High school wrestler", "rank": 5, "level": 2.6, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(40, 0, -22), "style": "pressure", "extra": ["snap_down"], "zone": "texas",
		"intro": "State qualifier, 152 pounds. I don't pull guard. I shoot. You ready?",
		"win": "Good hips, man. Coach'd yell at me for that one.",
		"lose": "Wrestling's the best base in the world. That's just facts."},
	"duke": {"name": "Duke", "title": "Rodeo clown, blue belt", "rank": 7, "level": 3.1, "gi": Color(0.8, 0.15, 0.15), "skin": Color(0.78, 0.57, 0.4),
		"pos": Vector3(48, 0, 34), "style": "back", "extra": ["berimbolo"], "zone": "texas",
		"intro": "I get on the backs of angry bulls for a living. You're a lot smaller than a bull.",
		"win": "Ha! Bucked off. That's a first since '09.",
		"lose": "Eight seconds on the back. That's all I ever need."},
	"boone": {"name": "Coach Boone", "title": "Lone Star BJJ, purple belt", "rank": 10, "level": 4.35, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.82, 0.62, 0.46),
		"pos": Vector3(0, 0, -50), "style": "submission", "boss": true, "extra": ["darce", "ezekiel", "omoplata", "leg_drag"], "zone": "texas",
		"intro": "Mae says you've been winning around town. On my mat, every mistake costs you a limb. Let's go.",
		"win": "Hell of a roll. Kneel down. That's a blue belt, and you earned every thread of it.",
		"lose": "Again. The mat doesn't lie, son. Come back when you're tougher."},
	"chad": {"name": "Chad", "title": "Gold League USA recruiter", "rank": 6, "level": 3.3, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.92, 0.76, 0.62),
		"pos": Vector3(-12, 0, 14), "style": "pressure", "extra": ["snap_down", "americana"], "liga": true, "zone": "texas",
		"intro": "Bro. Lone Star is about to be a Gold League USA franchise location. $399 a month, belts sold separately. Want the founding member rate? Tap now.",
		"win": "...Mr. Sterling is not gonna love this.",
		"lose": "See? Gold beats cotton. Sign up online, bro."},
	# ================ Team USA · Saw Grass Landing, Everglades (Lv 11-20)
	"lacey": {"body": "female", "name": "Lacey", "title": "Airboat tour guide", "rank": 7, "level": 4.3, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.88, 0.7, 0.55),
		"pos": Vector3(-40, 0, 22), "style": "guard", "extra": ["omoplata", "berimbolo", "triangle"], "zone": "everglades",
		"intro": "I wrangle tourists and gators all day. Your guard passing better be quicker than a gator's tail.",
		"win": "Alright, you're real. Come out on the boat sometime.",
		"lose": "Legs like a gator's jaws, honey. Next time."},
	"skeeter": {"name": "Skeeter", "title": "Bait shop owner", "rank": 9, "level": 4.9, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.78, 0.57, 0.4),
		"pos": Vector3(38, 0, -34), "style": "pressure", "extra": ["leg_drag", "darce", "snap_down"], "zone": "everglades",
		"intro": "Thirty years selling bait in this swamp. I've wrestled gators. You're easier.",
		"win": "Hah! The swamp humbles everybody. Today it was me.",
		"lose": "Pressure like August humidity, boy."},
	"rusty": {"name": "Rusty", "title": "Park ranger, purple belt", "rank": 10, "level": 5.4, "gi": Color(0.33, 0.36, 0.25), "skin": Color(0.62, 0.42, 0.28),
		"pos": Vector3(-18, 0, -44), "style": "back", "extra": ["berimbolo", "bow_arrow", "rnc", "snap_down"], "zone": "everglades",
		"intro": "I track pythons through the sawgrass for a living. Finding your back won't take long.",
		"win": "Slipped me like a water moccasin. Respect.",
		"lose": "Hooks in. Tracked and bagged."},
	"marisol": {"body": "female", "name": "Marisol", "title": "Cuban grappler, purple belt", "rank": 12, "level": 5.9, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.66, 0.45, 0.3),
		"pos": Vector3(52, 0, 22), "style": "submission", "extra": ["ezekiel", "omoplata", "cross_collar", "darce"], "zone": "everglades",
		"intro": "My grandfather learned from a Brazilian in Miami in the eighties. I learned from him. Ready?",
		"win": "Eso! Clean. Abuelo would've liked you.",
		"lose": "Collar chokes, mijo. Old school never dies."},
	"gator": {"name": "Captain Gator", "title": "The Gator Pit, brown belt", "rank": 15, "level": 7.3, "gi": Color(0.42, 0.26, 0.13), "skin": Color(0.7, 0.5, 0.36),
		"pos": Vector3(60, 0, 52), "style": "submission", "boss": true, "extra": ["darce", "ezekiel", "omoplata", "leg_drag", "berimbolo", "bow_arrow"], "zone": "everglades",
		"intro": "Boone's student, huh? Down here we train in a tin shed at a hundred degrees. Let's see if you melt.",
		"win": "You didn't melt. Purple belt. Get outta my swamp before it eats you.",
		"lose": "The swamp always wins. Hydrate and come back."},
	"rex": {"name": "Rex", "title": "Gold League USA enforcer", "rank": 11, "level": 6.4, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.72, 0.52, 0.38),
		"pos": Vector3(-28, 0, -8), "style": "pressure", "extra": ["snap_down", "top_kimura", "darce"], "liga": true, "zone": "everglades",
		"intro": "These swamp gyms are signing with Gold League one way or another. You want to make it the hard way?",
		"win": "Fine. The contracts are in the fish camp. Take 'em.",
		"lose": "Sign on the line, swamp rat."},
	# ================ Team USA · Red Rock, Sedona (Lv 21-30)
	"willow": {"body": "female", "name": "Willow", "title": "Yoga teacher, purple belt", "rank": 12, "level": 6.9, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.88, 0.7, 0.56),
		"pos": Vector3(20, 0, 20), "style": "guard", "extra": ["omoplata", "berimbolo", "triangle", "guard_armbar"], "zone": "sedona",
		"intro": "Breathe in. Breathe out. Now try to pass my guard. Namaste.",
		"win": "Beautiful flow. The vortex is with you today.",
		"lose": "Flexibility is a superpower. Stretch more."},
	"dusty": {"name": "Dusty", "title": "Rock climber, purple belt", "rank": 13, "level": 7.4, "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.82, 0.62, 0.46),
		"pos": Vector3(-28, 0, -40), "style": "pressure", "extra": ["leg_drag", "darce", "ezekiel", "knee_slice"], "zone": "sedona",
		"intro": "Ten years on these red walls. My grips don't open. Wanna test 'em?",
		"win": "Lost my grip. That never happens on the rock.",
		"lose": "Grip strength. That's all this sport is."},
	"sage": {"body": "female", "name": "Sage", "title": "Crystal shop owner, purple belt", "rank": 14, "level": 7.9, "gi": Color(0.55, 0.3, 0.7), "skin": Color(0.62, 0.42, 0.28),
		"pos": Vector3(48, 0, 34), "style": "submission", "extra": ["ezekiel", "cross_collar", "omoplata", "bow_arrow"], "zone": "sedona",
		"intro": "My crystals say you'll lose. My chokes say the same. Ready?",
		"win": "The crystals were wrong. Don't tell my customers.",
		"lose": "Amethyst never lies."},
	"colt": {"name": "Colt", "title": "Jeep tour driver, brown belt", "rank": 16, "level": 8.3, "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.72, 0.52, 0.38),
		"pos": Vector3(-8, 0, -58), "style": "back", "extra": ["berimbolo", "bow_arrow", "snap_down", "rnc"], "zone": "sedona",
		"intro": "I bounce tourists over rocks all day. Hang on to something.",
		"win": "Rough ride. Tip your driver.",
		"lose": "Seatbelt, buddy. Should've worn one."},
	"ramon": {"name": "Ramón", "title": "Hotshot firefighter, brown belt", "rank": 17, "level": 8.7, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.55, 0.38, 0.26),
		"pos": Vector3(-52, 0, 30), "style": "pressure", "extra": ["leg_drag", "darce", "uchi_mata", "ezekiel"], "zone": "sedona",
		"intro": "I dig fire lines in this heat for sixteen hours straight. Five minutes with you is a break.",
		"win": "Okay, you've got gas. Join the crew sometime.",
		"lose": "Cardio like a wildfire."},
	"sol": {"name": "Master Sol", "title": "Vortex Jiu-Jitsu, black belt", "rank": 20, "level": 9.85, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.62, 0.45, 0.32),
		"pos": Vector3(46, 0, -6), "style": "submission", "boss": true,
		"extra": ["darce", "ezekiel", "omoplata", "leg_drag", "berimbolo", "bow_arrow", "uchi_mata", "flying_armbar", "cross_collar"], "zone": "sedona",
		"intro": "Boone and Gator were my students. Show me what the road taught you.",
		"win": "Brown belt. One step from the black. The coast is waiting.",
		"lose": "The desert is patient. So am I. Again, when you're ready."},
	"skyler": {"name": "Skyler Sterling", "title": "Gold League USA heir", "rank": 18, "level": 9.3, "gi": Color(0.86, 0.68, 0.16), "skin": Color(0.92, 0.76, 0.62),
		"pos": Vector3(24, 0, 2), "style": "submission", "extra": ["darce", "ezekiel", "kneebar", "toe_hold"], "liga": true, "zone": "sedona",
		"intro": "My family is buying this whole valley. A wellness resort with a Gold League academy in every lobby. You're in my way.",
		"win": "My brother Brock will hear about this. He's in San Diego.",
		"lose": "Money and technique. I have both."},
}

const ZONES := {
	"caceres": {"levels": [1, 10], "name": "Cáceres", "sub": "Mato Grosso", "rank": 0, "boss": "onca", "spawn": Vector3(0, 0, 24), "collect": "Tereré cups"},
	"pantanal": {"levels": [11, 20], "name": "Pantanal Norte", "sub": "Transpantaneira", "rank": 5, "boss": "jacare", "spawn": Vector3(-82, 0, -4), "collect": "Arara feathers"},
	"chapada": {"levels": [21, 30], "name": "Chapada dos Guimarães", "sub": "Red cliffs and waterfalls", "rank": 10, "boss": "cachoeira", "spawn": Vector3(-80, 0, 40), "collect": "Quartz crystals"},
	"rio": {"levels": [31, 50], "name": "Rio de Janeiro", "sub": "Where jiu-jitsu grew up", "rank": 15, "boss": "leao", "spawn": Vector3(-84, 0, 6), "collect": "Green coconuts"},
	"texas": {"levels": [1, 10], "name": "Dry Creek", "sub": "Texas Hill Country · América do Norte", "rank": 0, "boss": "boone", "spawn": Vector3(0, 0, 24), "collect": "Rodeo buckles", "continent": "america"},
	"everglades": {"levels": [11, 20], "name": "Saw Grass Landing", "sub": "Florida Everglades · América do Norte", "rank": 5, "boss": "gator", "spawn": Vector3(-82, 0, -4), "collect": "Gator teeth", "continent": "america"},
	"sedona": {"levels": [21, 30], "name": "Red Rock", "sub": "Sedona, Arizona · América do Norte", "rank": 10, "boss": "sol", "spawn": Vector3(-80, 0, 40), "collect": "Vortex crystals", "continent": "america"},
	"socal": {"levels": [31, 50], "name": "San Diego", "sub": "California · América do Norte", "rank": 15, "boss": "dale", "spawn": Vector3(-82, 0, 6), "collect": "Sand dollars", "continent": "america"},
}

# ---------------------------------------------------------------- daily challenge
const DAILY_RULES := {
	"sub_only": {"name": "Submission Only", "desc": "Points don't count. Tap them or it's a loss."},
	"bad_spot": {"name": "Worst-Case Start", "desc": "You start mounted on the bottom."},
	"back_taken": {"name": "Back Taken", "desc": "You start with your back taken. Survive, then win."},
	"tired": {"name": "Last Round", "desc": "You start at half stamina."},
	"sprint": {"name": "Sprint Match", "desc": "Only two minutes on the clock."},
	"top_start": {"name": "King of the Hill", "desc": "You start in mount. Finish it."},
}
const DAILY_NAMES := ["Visiting Gringo", "Mystery Competitor", "Open Mat Shark", "Traveling Grappler", "Old-School Killer", "Comp Team Captain"]

## Builds today's challenge from a date string (YYYY-MM-DD) so everyone gets the same one.
static func daily_challenge(date_str: String, player_rank: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tatame-" + date_str)
	var rules := DAILY_RULES.keys()
	var rule: String = rules[rng.randi() % rules.size()]
	var styles := ["guard", "pressure", "back", "submission", "balanced"]
	var opp_rank := clampi(player_rank + rng.randi_range(0, 2), 1, 24)
	var extras: Array = []
	for id in MOVES:
		if int(MOVES[id].rank) == 99 and rng.randf() < 0.45:
			extras.append(id)
	var name_: String = DAILY_NAMES[rng.randi() % DAILY_NAMES.size()]
	var opp := {"name": name_, "title": "Daily Challenge", "rank": opp_rank, "level": rank_level(player_rank) + 0.35 + rng.randf() * 0.7,
		"gi": [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)][rng.randi() % 3],
		"skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), rng.randf()),
		"style": styles[rng.randi() % styles.size()], "extra": extras, "zone": "",
		"intro": Tx.f("Today's challenge: %s. %s", [DAILY_RULES[rule].name, DAILY_RULES[rule].desc]),
		"win": "Oss. Same time tomorrow?", "lose": "Tomorrow's a new day. Oss."}
	return {"date": date_str, "rule": rule, "opp": opp}

## Continents: Brasil (the bus) and América do Norte (a flight away).
const CONTINENTS := {"brasil": "Brasil", "america": "América do Norte"}
const FLIGHT_COST := 300
static func continent_of(z: String) -> String:
	return str(ZONES.get(z, {}).get("continent", "brasil"))

static func zone_of(opp_id: String) -> String:
	return OPPONENTS[opp_id].get("zone", "caceres")

const BOSS_REQUIRED_WINS := 3

# ---------------------------------------------------------------- landmarks & collectibles
const LANDMARKS := {
	"plaza": {"name": "Praça (Town Plaza)", "pos": Vector3(0, 0, 8), "radius": 12.0},
	"cathedral": {"name": "The Cathedral", "pos": Vector3(0, 0, -20), "radius": 10.0},
	"academia": {"name": "Academia Onça (Gym)", "pos": Vector3(0, 0, -52), "radius": 9.0},
	"river": {"name": "Rio Paraguai Riverbank", "pos": Vector3(-50, 0, 0), "radius": 14.0},
	"gate": {"name": "Pantanal Gate", "pos": Vector3(78, 0, 0), "radius": 10.0},
	"market": {"name": "Feira (Street Market)", "pos": Vector3(30, 0, -22), "radius": 10.0},
	"p_bus": {"name": "Transpantaneira Bus Stop", "pos": Vector3(-82, 0, -4), "radius": 10.0, "zone": "pantanal"},
	"p_fazenda": {"name": "Fazenda Jacaré", "pos": Vector3(60, 0, 54), "radius": 14.0, "zone": "pantanal"},
	"p_tower": {"name": "Ranger Tower", "pos": Vector3(-18, 0, -48), "radius": 10.0, "zone": "pantanal"},
	"p_dock": {"name": "Boat Dock", "pos": Vector3(38, 0, -38), "radius": 10.0, "zone": "pantanal"},
	"p_ranch": {"name": "Cattle Ranch", "pos": Vector3(-40, 0, 26), "radius": 14.0, "zone": "pantanal"},
	"p_lagoon": {"name": "Lagoa dos Jacarés", "pos": Vector3(10, 0, 20), "radius": 14.0, "zone": "pantanal"},
	"c_bus": {"name": "Chapada Bus Stop", "pos": Vector3(-80, 0, 40), "radius": 10.0, "zone": "chapada"},
	"c_falls": {"name": "Véu de Noiva Waterfall", "pos": Vector3(20, 0, 2), "radius": 14.0, "zone": "chapada"},
	"c_village": {"name": "Vila da Chapada", "pos": Vector3(42, 0, 44), "radius": 16.0, "zone": "chapada"},
	"c_rocks": {"name": "Cidade de Pedra", "pos": Vector3(-30, 0, -50), "radius": 16.0, "zone": "chapada"},
	"c_mirante": {"name": "Mirante: Center of South America", "pos": Vector3(30, 0, -70), "radius": 10.0, "zone": "chapada"},
	"c_cave": {"name": "Caverna Aroe Jari", "pos": Vector3(-64, 0, -8), "radius": 9.0, "zone": "chapada"},
	"r_bus": {"name": "Rodoviária Novo Rio", "pos": Vector3(-84, 0, 6), "radius": 10.0, "zone": "rio"},
	"r_beach": {"name": "Copacabana Beach", "pos": Vector3(0, 0, 42), "radius": 16.0, "zone": "rio"},
	"r_arpoador": {"name": "Pedra do Arpoador", "pos": Vector3(-74, 0, 46), "radius": 10.0, "zone": "rio"},
	"r_sugarloaf": {"name": "Pão de Açúcar Cable Car", "pos": Vector3(62, 0, 40), "radius": 10.0, "zone": "rio"},
	"r_cristo": {"name": "Corcovado Summit", "pos": Vector3(-46, 0, -62), "radius": 9.0, "zone": "rio"},
	"r_morro": {"name": "The Morro", "pos": Vector3(38, 0, -50), "radius": 14.0, "zone": "rio"},
	"s_airport": {"name": "Lindbergh Shuttle Stop", "pos": Vector3(-82, 0, 6), "radius": 10.0, "zone": "socal"},
	"s_pier": {"name": "Ocean Beach Pier", "pos": Vector3(48, 0, 50), "radius": 12.0, "zone": "socal"},
	"s_boardwalk": {"name": "The Boardwalk", "pos": Vector3(0, 0, 28), "radius": 14.0, "zone": "socal"},
	"s_garage": {"name": "The Garage", "pos": Vector3(-18, 0, -40), "radius": 10.0, "zone": "socal"},
	"s_tacos": {"name": "Taco Truck Row", "pos": Vector3(30, 0, -10), "radius": 10.0, "zone": "socal"},
	"s_cliffs": {"name": "Sunset Cliffs", "pos": Vector3(-72, 0, 46), "radius": 12.0, "zone": "socal"},
	"x_square": {"name": "Courthouse Square", "pos": Vector3(0, 0, 8), "radius": 12.0, "zone": "texas"},
	"x_gym": {"name": "Lone Star BJJ", "pos": Vector3(0, 0, -52), "radius": 9.0, "zone": "texas"},
	"x_creek": {"name": "Dry Creek Swimming Hole", "pos": Vector3(-56, 0, 0), "radius": 14.0, "zone": "texas"},
	"x_rodeo": {"name": "Rodeo Grounds", "pos": Vector3(52, 0, 40), "radius": 14.0, "zone": "texas"},
	"x_feed": {"name": "Feed & Tack", "pos": Vector3(30, 0, -22), "radius": 10.0, "zone": "texas"},
	"x_bus": {"name": "Greyhound Stop", "pos": Vector3(80, 0, 0), "radius": 10.0, "zone": "texas"},
	"e_bus": {"name": "Tamiami Trail Bus Stop", "pos": Vector3(-82, 0, -4), "radius": 10.0, "zone": "everglades"},
	"e_pit": {"name": "The Gator Pit", "pos": Vector3(60, 0, 52), "radius": 14.0, "zone": "everglades"},
	"e_ranger": {"name": "Ranger Station", "pos": Vector3(-18, 0, -48), "radius": 10.0, "zone": "everglades"},
	"e_dock": {"name": "Airboat Dock", "pos": Vector3(38, 0, -38), "radius": 10.0, "zone": "everglades"},
	"e_fishcamp": {"name": "Fish Camp", "pos": Vector3(-40, 0, 26), "radius": 14.0, "zone": "everglades"},
	"e_hammock": {"name": "Cypress Hammock", "pos": Vector3(10, 0, 20), "radius": 14.0, "zone": "everglades"},
	"d_bus": {"name": "Sedona Shuttle Stop", "pos": Vector3(-80, 0, 40), "radius": 10.0, "zone": "sedona"},
	"d_bell": {"name": "Bell Rock", "pos": Vector3(10, 0, -16), "radius": 14.0, "zone": "sedona"},
	"d_uptown": {"name": "Uptown", "pos": Vector3(42, 0, 40), "radius": 16.0, "zone": "sedona"},
	"d_cathedral": {"name": "Cathedral Rock", "pos": Vector3(-34, 0, -52), "radius": 16.0, "zone": "sedona"},
	"d_vortex": {"name": "Airport Mesa Vortex", "pos": Vector3(30, 0, -70), "radius": 10.0, "zone": "sedona"},
	"d_creek": {"name": "Oak Creek Canyon", "pos": Vector3(-64, 0, -8), "radius": 10.0, "zone": "sedona"},
}

# ---------------------------------------------------------------- academy wars
## Territories: rival academies plant flags at landmarks. Take one with a 3v3; hold it for +10% XP
## in that zone; rivals counterattack 8-16 real hours later and you have 24 hours to defend.
const TERRITORIES := {
	"t_plaza": {"name": "Praça", "zone": "caceres", "pos": Vector3(10, 0, 15), "academy": "Tatame Livre"},
	"t_river": {"name": "Riverbank", "zone": "caceres", "pos": Vector3(-46, 0, 7), "academy": "Rio Negro Team"},
	"t_market": {"name": "Feira", "zone": "caceres", "pos": Vector3(30, 0, -11), "academy": "Cuiabá Combat"},
	"t_ranch": {"name": "Cattle Ranch", "zone": "pantanal", "pos": Vector3(-40, 0, 16), "academy": "Pantanal Fight"},
	"t_dock": {"name": "Boat Dock", "zone": "pantanal", "pos": Vector3(38, 0, -28), "academy": "Jacaré BJJ"},
	"t_tower": {"name": "Ranger Tower", "zone": "pantanal", "pos": Vector3(-18, 0, -38), "academy": "Ilha Grappling"},
	"t_village": {"name": "Vila da Chapada", "zone": "chapada", "pos": Vector3(42, 0, 32), "academy": "Cachoeira Team"},
	"t_rocks": {"name": "Cidade de Pedra", "zone": "chapada", "pos": Vector3(-30, 0, -38), "academy": "Tatame Livre"},
	"t_mirante": {"name": "Mirante", "zone": "chapada", "pos": Vector3(30, 0, -60), "academy": "Rio Negro Team"},
	"t_beach": {"name": "Copacabana", "zone": "rio", "pos": Vector3(8, 0, 36), "academy": "Copacabana Top Team"},
	"t_arpoador": {"name": "Arpoador", "zone": "rio", "pos": Vector3(-68, 0, 40), "academy": "Arpoador BJJ"},
	"t_morro": {"name": "The Morro", "zone": "rio", "pos": Vector3(41, 0, -40), "academy": "Projeto Morro"},
	"t_boardwalk": {"name": "The Boardwalk", "zone": "socal", "pos": Vector3(-8, 0, 32), "academy": "Gold League USA"},
	"t_cliffs": {"name": "Sunset Cliffs", "zone": "socal", "pos": Vector3(-64, 0, 38), "academy": "Coastline Grappling"},
	"t_canyon": {"name": "Canyon Trails", "zone": "socal", "pos": Vector3(50, 0, -56), "academy": "Desert Rose BJJ"},
	"t_courthouse": {"name": "Courthouse Square", "zone": "texas", "pos": Vector3(10, 0, 15), "academy": "Hill Country BJJ"},
	"t_drycreek": {"name": "Swimming Hole", "zone": "texas", "pos": Vector3(-52, 0, 15), "academy": "Lone Star Combat"},
	"t_feedstore": {"name": "Feed & Tack", "zone": "texas", "pos": Vector3(30, 0, -11), "academy": "Gold League USA"},
	"t_fishcamp": {"name": "Fish Camp", "zone": "everglades", "pos": Vector3(-40, 0, 16), "academy": "Swamp Rat MMA"},
	"t_airdock": {"name": "Airboat Dock", "zone": "everglades", "pos": Vector3(38, 0, -28), "academy": "Gulf Coast Grappling"},
	"t_ranger": {"name": "Ranger Station", "zone": "everglades", "pos": Vector3(-18, 0, -38), "academy": "Gold League USA"},
	"t_uptown": {"name": "Uptown", "zone": "sedona", "pos": Vector3(42, 0, 28), "academy": "Vortex Collective"},
	"t_bellrock": {"name": "Bell Rock", "zone": "sedona", "pos": Vector3(20, 0, -6), "academy": "Desert Rose BJJ"},
	"t_oakcreek": {"name": "Oak Creek", "zone": "sedona", "pos": Vector3(-58, 0, -2), "academy": "Gold League USA"},
}
const ACADEMY_COLORS := {"Tatame Livre": Color(0.9, 0.9, 0.85), "Rio Negro Team": Color(0.15, 0.15, 0.2), "Cuiabá Combat": Color(0.85, 0.3, 0.2),
	"Pantanal Fight": Color(0.3, 0.55, 0.3), "Jacaré BJJ": Color(0.4, 0.45, 0.2), "Ilha Grappling": Color(0.2, 0.6, 0.75),
	"Cachoeira Team": Color(0.5, 0.75, 0.95), "Copacabana Top Team": Color(0.95, 0.75, 0.2), "Arpoador BJJ": Color(0.95, 0.5, 0.3),
	"Projeto Morro": Color(0.6, 0.3, 0.75), "Gold League USA": Color(0.86, 0.68, 0.16), "Coastline Grappling": Color(0.25, 0.5, 0.7),
	"Hill Country BJJ": Color(0.75, 0.55, 0.3), "Lone Star Combat": Color(0.2, 0.3, 0.7), "Swamp Rat MMA": Color(0.35, 0.45, 0.25),
	"Gulf Coast Grappling": Color(0.2, 0.65, 0.65), "Vortex Collective": Color(0.6, 0.35, 0.8), "Desert Rose BJJ": Color(0.85, 0.4, 0.35)}
const YOUR_ACADEMY_COLOR := Color(0.1, 0.55, 0.32)

static func territories_in(zone: String) -> Array:
	var out: Array = []
	for id in TERRITORIES:
		if TERRITORIES[id].zone == zone:
			out.append(id)
	return out

static func landmarks_in(zone: String) -> Array:
	var out: Array = []
	for id in LANDMARKS:
		if LANDMARKS[id].get("zone", "caceres") == zone:
			out.append(id)
	return out

const COLLECTIBLES := {
	"caceres": [Vector3(18, 0.8, 18), Vector3(-30, 0.8, 40), Vector3(48, 0.8, -48), Vector3(-20, 0.8, -60), Vector3(62, 0.8, 38), Vector3(-58, 0.8, -50)],
	"pantanal": [Vector3(-60, 0.8, -60), Vector3(-10, 0.8, 70), Vector3(68, 0.8, -71), Vector3(84, 0.8, 10), Vector3(20, 0.8, -12), Vector3(-75, 0.8, 60)],
	"chapada": [Vector3(-66, 0.8, -12), Vector3(60, 0.8, -60), Vector3(-10, 0.8, 70), Vector3(-30, 0.8, -78), Vector3(75, 0.8, 20), Vector3(12, 0.8, -4)],
	"rio": [Vector3(-14, 0.8, 50), Vector3(44, 0.8, 46), Vector3(-82, 0.8, 40), Vector3(-40, 0.8, -46), Vector3(52, 0.8, -60), Vector3(-56, 0.8, -8)],
	"texas": [Vector3(18, 0.8, 18), Vector3(-30, 0.8, 40), Vector3(48, 0.8, -48), Vector3(-20, 0.8, -66), Vector3(64, 0.8, 52), Vector3(-44, 0.8, -40)],
	"everglades": [Vector3(-60, 0.8, -60), Vector3(-13, 0.8, 63), Vector3(70, 0.8, -70), Vector3(87, 0.8, 10), Vector3(20, 0.8, -12), Vector3(-75, 0.8, 60)],
	"sedona": [Vector3(-62, 0.8, -20), Vector3(60, 0.8, -60), Vector3(-10, 0.8, 70), Vector3(-26, 0.8, -78), Vector3(75, 0.8, 20), Vector3(0, 0.8, 8)],
	"socal": [Vector3(-24, 0.8, 46), Vector3(70, 0.8, 44), Vector3(-60, 0.8, 52), Vector3(10, 0.8, -60), Vector3(66, 0.8, -50), Vector3(-40, 0.8, -12)],
}

const TERERE_CUPS := [
	Vector3(18, 0.8, 18), Vector3(-30, 0.8, 40), Vector3(48, 0.8, -48),
	Vector3(-20, 0.8, -60), Vector3(62, 0.8, 38), Vector3(-58, 0.8, -50),
]

const NEST_POS := Vector3(-36, 10.6, 52)

# ---------------------------------------------------------------- achievements
const ACHIEVEMENTS := [
	{"id": "first_roll", "name": "First Roll", "desc": "Finish your first roll."},
	{"id": "first_tap", "name": "First Tap", "desc": "Win a roll by submission."},
	{"id": "raid_sucuri", "name": "Shed Your Skin", "desc": "Clear Covil da Sucuri with your academy party."},
	{"id": "raid_gold", "name": "Hostile Takeover", "desc": "Clear the Gold Compound with your party."},
	{"id": "dng_basement", "name": "Underground", "desc": "Clear the Basement Gym."},
	{"id": "dng_docks", "name": "First Rule", "desc": "Clear Fight Club at the Docks."},
	{"id": "dng_night", "name": "Fair Play", "desc": "Clear the Night Tournament."},
	{"id": "dng_warehouse", "name": "Unmasked", "desc": "Clear the Lucha Warehouse."},
	{"id": "dng_tower", "name": "Penthouse", "desc": "Clear Sterling Tower."},
	{"id": "dng_temple", "name": "The Hidden Way", "desc": "Clear the Hidden Temple."},
	{"id": "dungeons_all", "name": "Dungeon Crawler", "desc": "Clear 25 dungeons.", "goal": 25},
	{"id": "jobs_done", "name": "Good Neighbor", "desc": "Help out around town 10 times.", "goal": 10},
	{"id": "chest_first", "name": "X Marks the Spot", "desc": "Find a hidden chest."},
	{"id": "chest_zone", "name": "Treasure Map", "desc": "Find every hidden chest in one zone."},
	{"id": "chest_hunter", "name": "Treasure Hunter", "desc": "Loot 25 hidden chests.", "goal": 25},
	{"id": "tapped", "name": "Tap Early, Tap Often", "desc": "Get submitted. It happens to everyone."},
	{"id": "points_win", "name": "Points Fighter", "desc": "Win a roll on points."},
	{"id": "triangle_win", "name": "Triangle Club", "desc": "Finish someone with a triangle choke."},
	{"id": "armbar_win", "name": "Thumb to the Sky", "desc": "Finish someone with an armbar."},
	{"id": "choke_win", "name": "Go to Sleep", "desc": "Finish someone with a rear naked choke."},
	{"id": "takedowns", "name": "Takedown Artist", "desc": "Land 5 takedowns.", "goal": 5},
	{"id": "sweeps", "name": "Sweep the Leg", "desc": "Land 5 sweeps.", "goal": 5},
	{"id": "passes", "name": "Pressure Passer", "desc": "Pass the guard 5 times.", "goal": 5},
	{"id": "backs", "name": "Seatbelt Secured", "desc": "Take the back 3 times.", "goal": 3},
	{"id": "perfect", "name": "Perfect Reads", "desc": "Interrupt 10 techniques with the right counter.", "goal": 10},
	{"id": "escapes", "name": "Houdini", "desc": "Escape 3 submissions.", "goal": 3},
	{"id": "iron_lungs", "name": "Iron Lungs", "desc": "Win without dropping under 30% stamina."},
	{"id": "giant_slayer", "name": "Giant Slayer", "desc": "Beat someone 2+ belts or 5+ stripes above you."},
	{"id": "explorer", "name": "Know the Town", "desc": "Discover every landmark in Cáceres.", "goal": 6},
	{"id": "p_explorer", "name": "Pantaneiro", "desc": "Discover every landmark in the Pantanal.", "goal": 6},
	{"id": "feathers", "name": "Arara Collector", "desc": "Find all 6 arara feathers in the Pantanal.", "goal": 6},
	{"id": "jaguar", "name": "Onça Pintada", "desc": "Spot the jaguar hiding in the Pantanal.", "hidden": true},
	{"id": "purple_belt", "name": "Purple Belt", "desc": "Get promoted by Mestre Jacaré."},
	{"id": "travel", "name": "Road Trip", "desc": "Ride the bus down the Transpantaneira."},
	{"id": "drills", "name": "Drill Sergeant", "desc": "Complete 10 training drills.", "goal": 10},
	{"id": "pantanal_king", "name": "Rei do Pantanal", "desc": "Beat every fighter in the Pantanal."},
	{"id": "c_explorer", "name": "Chapadeiro", "desc": "Discover every landmark in the Chapada.", "goal": 6},
	{"id": "crystals", "name": "Good Vibes", "desc": "Find all 6 quartz crystals in the Chapada.", "goal": 6},
	{"id": "brown_belt", "name": "Brown Belt", "desc": "Get promoted by Mestre Cachoeira."},
	{"id": "chapada_king", "name": "Lord of the Plateau", "desc": "Beat every fighter in the Chapada."},
	{"id": "r_explorer", "name": "Carioca da Gema", "desc": "Discover every landmark in Rio.", "goal": 6},
	{"id": "coconuts", "name": "Água de Coco", "desc": "Find all 6 green coconuts in Rio.", "goal": 6},
	{"id": "black_belt", "name": "Black Belt", "desc": "Get promoted by Grão-Mestre Leão."},
	{"id": "rio_king", "name": "Rei do Rio", "desc": "Beat every fighter in Rio."},
	{"id": "s_explorer", "name": "Local, Bro", "desc": "Discover every landmark in San Diego.", "goal": 6},
	{"id": "sanddollars", "name": "Beachcomber", "desc": "Find all 6 sand dollars in San Diego.", "goal": 6},
	{"id": "socal_king", "name": "King of the Coast", "desc": "Beat every fighter in San Diego."},
	{"id": "flight", "name": "Passport Control", "desc": "Fly to another continent."},
	{"id": "x_explorer", "name": "Howdy, Neighbor", "desc": "Discover every landmark in Dry Creek.", "goal": 6},
	{"id": "buckles", "name": "All Hat, All Cattle", "desc": "Find all 6 rodeo buckles in Dry Creek.", "goal": 6},
	{"id": "texas_king", "name": "King of the Hill Country", "desc": "Beat every fighter in Dry Creek."},
	{"id": "e_explorer", "name": "Swamp Rat", "desc": "Discover every landmark in the Everglades.", "goal": 6},
	{"id": "gator_teeth", "name": "Tooth Fairy", "desc": "Find all 6 gator teeth in the Everglades.", "goal": 6},
	{"id": "glades_king", "name": "King of the Swamp", "desc": "Beat every fighter in the Everglades."},
	{"id": "d_explorer", "name": "Red Rock Pilgrim", "desc": "Discover every landmark in Red Rock.", "goal": 6},
	{"id": "vortex_crystals", "name": "Aligned Chakras", "desc": "Find all 6 vortex crystals in Red Rock.", "goal": 6},
	{"id": "sedona_king", "name": "Lord of the Mesa", "desc": "Beat every fighter in Red Rock."},
	{"id": "pan_am", "name": "Pan-American", "desc": "Earn a stamp on two continents."},
	{"id": "duel_win", "name": "Live and Learn", "desc": "Win a live duel against another player."},
	{"id": "arena_win", "name": "On the Ladder", "desc": "Win a ranked arena match."},
	{"id": "arena_1200", "name": "Climber", "desc": "Reach 1200 arena rating in a week."},
	{"id": "on_foot", "name": "On Foot", "desc": "Walk into a new zone along the road instead of taking the bus."},
	{"id": "road_brasil", "name": "Estrada Real", "desc": "Set foot in every zone from Cáceres to Rio."},
	{"id": "road_usa", "name": "Coast to Coast", "desc": "Set foot in every zone from Dry Creek to San Diego."},
	{"id": "two_continents", "name": "Two Continents", "desc": "Visit a zone in both América do Sul and América do Norte."},
	{"id": "arena_champion", "name": "Arena Champion", "desc": "Finish a week at #1 on the ranked ladder.", "hidden": true},
	{"id": "duel_10", "name": "Mat Champion", "desc": "Win 10 live duels.", "goal": 10},
	{"id": "honor_gear", "name": "Earned, Not Bought", "desc": "Buy a piece of faction gear with Honor."},
	{"id": "rival_win", "name": "For the Faction", "desc": "Beat a rival faction player's shadow."},
	{"id": "rival_10", "name": "War Hero", "desc": "Beat 10 rival faction shadows.", "goal": 10},
	{"id": "cristo", "name": "Arms Wide Open", "desc": "Climb Corcovado to the statue.", "hidden": true},
	{"id": "first_medal", "name": "On the Podium", "desc": "Win a medal at a competition."},
	{"id": "first_gold", "name": "Campeão", "desc": "Win gold at a competition."},
	{"id": "grand_slam", "name": "Grand Slam", "desc": "Win gold at all four regional competitions.", "goal": 4},
	{"id": "world_champ", "name": "Campeão Mundial", "desc": "Win the Campeonato Mundial at black belt."},
	{"id": "quest_1", "name": "Helping Hand", "desc": "Complete your first quest."},
	{"id": "quests_10", "name": "Friend of Brazil", "desc": "Complete 10 quests.", "goal": 10},
	{"id": "quests_all", "name": "Everybody Knows the Gringo", "desc": "Complete every quest.", "goal": 22},
	{"id": "first_loot", "name": "Fresh Gear", "desc": "Get your first piece of gear."},
	{"id": "legendary", "name": "Legendary", "desc": "Own a legendary piece of gear."},
	{"id": "leglock_win", "name": "Leg Locker", "desc": "Finish someone with a straight ankle lock or a kneebar."},
	{"id": "guillotine_win", "name": "Off With His Head", "desc": "Finish someone with a guillotine."},
	{"id": "grip_master", "name": "Grip Master", "desc": "Max out Grip Control in 10 rolls.", "goal": 10},
	{"id": "mob_kills", "name": "Dono da Rua", "desc": "Beat 25 street rollers in the open world.", "goal": 25},
	{"id": "team_win", "name": "Família", "desc": "Win a 5v5 team match."},
	{"id": "flag_taken", "name": "Plant the Flag", "desc": "Take a territory from a rival academy."},
	{"id": "flag_defended", "name": "Hold the Line", "desc": "Defend a territory from a counterattack."},
	{"id": "zone_owner", "name": "Dono da Área", "desc": "Hold every territory in a zone."},
	{"id": "circuit_final", "name": "Final Boss", "desc": "Reach the final of a Circuito run."},
	{"id": "circuit_champ", "name": "Campeão do Circuito", "desc": "Win a whole Circuito run."},
	{"id": "circuit_titles", "name": "Circuit Legend", "desc": "Win 3 Circuito runs.", "goal": 3},
	{"id": "team_clean", "name": "Clean Sheet", "desc": "Win a 5v5 without losing a fighter."},
	{"id": "team_wins", "name": "Team Captain", "desc": "Win 5 team matches.", "goal": 5},
	{"id": "behind_falls", "name": "Behind the Veil", "desc": "Find the secret behind the waterfall.", "hidden": true},
	{"id": "daily_1", "name": "Desafio do Dia", "desc": "Win a Daily Challenge."},
	{"id": "daily_3", "name": "On a Roll", "desc": "Win Daily Challenges 3 days in a row.", "goal": 3},
	{"id": "daily_7", "name": "Every Day Is Leg Day", "desc": "Win Daily Challenges 7 days in a row.", "goal": 7},
	{"id": "mat_days_7", "name": "Mat Rat", "desc": "Log in 7 days in a row.", "goal": 7},
	{"id": "reads_25", "name": "Read the Room", "desc": "Counter 25 techniques.", "goal": 25},
	{"id": "reads_250", "name": "Mind Reader", "desc": "Counter 250 techniques.", "goal": 250},
	{"id": "read_streak_10", "name": "Untouchable", "desc": "Counter 10 techniques in a row without a wrong read or getting caught.", "goal": 10},
	{"id": "escapes_5", "name": "Houdini", "desc": "Escape 5 finishes.", "goal": 5},
	{"id": "feint_read", "name": "Not Fooled", "desc": "Counter a feint."},
	{"id": "grade_s", "name": "Flawless Roll", "desc": "Earn an S on a roll report."},
	{"id": "sig_read", "name": "Saw It Coming", "desc": "Read a zone boss's signature technique."},
	{"id": "practice_90", "name": "Drilled", "desc": "Score 90% or better in a practice drill."},
	{"id": "mat_days_30", "name": "Lives at the Academy", "desc": "Log in 30 days in a row.", "goal": 30},
	{"id": "terere", "name": "Tereré Time", "desc": "Find all 6 tereré cups.", "goal": 6},
	{"id": "nest", "name": "Tuiuiú Spotter", "desc": "Find the tuiuiú nest high above the river."},
	{"id": "first_stripe", "name": "First Stripe", "desc": "Earn your first stripe."},
	{"id": "undefeated", "name": "King of Cáceres", "desc": "Beat every fighter in town."},
	{"id": "blue_belt", "name": "Blue Belt", "desc": "Get promoted by Mestre Onça."},
	{"id": "jumper", "name": "Too Much Açaí", "desc": "Jump 100 times.", "goal": 100, "hidden": true},
	{"id": "chose_style", "name": "Choose Your Path", "desc": "Pick your fighting style."},
	{"id": "talented", "name": "Talented", "desc": "Spend 5 talent points.", "goal": 5},
	{"id": "capstone", "name": "Capstone", "desc": "Learn a final-tier talent."},
	{"id": "peak", "name": "Peak Physique", "desc": "Raise any attribute to 12."},
	{"id": "signature_win", "name": "Signature Move", "desc": "Win a roll using your style's signature technique."},
]

static func achievement(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.id == id:
			return a
	return {}

# ---------------------------------------------------------------- competitions (campeonatos)
# PvE tournaments in your belt division. Opponents use the same profile shape as a player
# "ghost" (name, style, rank, level, gi, skin, extra), so real players can be dropped into
# brackets later (async PvP) without changing the roll code.
const COMPS := {
	"copa_caceres": {"name": "Copa Cáceres", "zone": "caceres", "min_rank": 0, "rounds": 3, "power": 0.0,
		"blurb": "The town championship, held at the academia. Everyone's cousin is in the bracket."},
	"pantanal_open": {"name": "Pantanal Open", "zone": "pantanal", "min_rank": 0, "rounds": 3, "power": 0.25,
		"blurb": "Ranch hands and river guides, all gas and grips. Held in the fazenda barn."},
	"chapada_open": {"name": "Chapada Open", "zone": "chapada", "min_rank": 0, "rounds": 3, "power": 0.45,
		"blurb": "Competitors come from all over Mato Grosso. Cold mornings, hot matches."},
	"rio_open": {"name": "Rio International Open", "zone": "rio", "min_rank": 0, "rounds": 3, "power": 0.7,
		"blurb": "Teams from every corner of Brazil and abroad. The bracket is stacked."},
	"socal_open": {"name": "Pan-American Open", "zone": "socal", "min_rank": 0, "rounds": 4, "power": 0.95,
		"blurb": "Gi and no-gi divisions, teams from both continents. The Gold League sponsored half the bracket."},
	"dry_creek_open": {"name": "Dry Creek Open", "zone": "texas", "min_rank": 0, "rounds": 3, "power": 0.0,
		"blurb": "Held in the high school gym. Half the bracket are wrestlers, the other half are their dads."},
	"glades_open": {"name": "Everglades Open", "zone": "everglades", "min_rank": 0, "rounds": 3, "power": 0.25,
		"blurb": "A tin shed, no AC and a gator in the parking lot. Bring water."},
	"red_rock_open": {"name": "Red Rock Open", "zone": "sedona", "min_rank": 0, "rounds": 3, "power": 0.45,
		"blurb": "Competitors from all over the Southwest. Cold desert mornings, hot matches."},
	"mundial": {"name": "Campeonato Mundial", "zone": "rio", "min_rank": 20, "rounds": 4, "power": 1.1,
		"blurb": "The world championship. Black belts only. Sixteen in the bracket, one on top."},
}
const ROUND_NAMES := {3: ["Quarterfinal", "Semifinal", "Final"], 4: ["Round of 16", "Quarterfinal", "Semifinal", "Final"]}
const COMP_FIRST := ["Thiago", "Lucas", "Mateus", "Rafael", "Bruno", "Diego", "Felipe", "Gustavo", "Leandro", "Marcelo",
	"Renan", "Vinícius", "Caio", "Igor", "Jonas", "Murilo", "Otávio", "Paulo", "Sandro", "Wellington",
	"Kenji", "Marco", "Andrés", "Liam", "Nikolai", "Sami", "Tomás", "Jake"]
const COMP_LAST := ["Silva", "Souza", "Oliveira", "Pereira", "Costa", "Rodrigues", "Almeida", "Nascimento", "Lima", "Araújo",
	"Ribeiro", "Carvalho", "Gomes", "Martins", "Rocha", "Barbosa", "Moreira", "Teixeira"]
const ACADEMIES := ["Academia Onça", "Jacaré BJJ", "Cachoeira Team", "Leão Jiu-Jitsu", "Tatame Livre", "Pantanal Fight",
	"Ilha Grappling", "Copacabana Top Team", "Projeto Morro", "Arpoador BJJ", "Cuiabá Combat", "Rio Negro Team"]
const MEDAL_ORDER := ["", "bronze", "silver", "gold"]

## Builds a seeded bracket for the player's belt division. entries[0] is the player.
## path[i] is the opponent the player meets in round i if they keep winning.
static func comp_bracket(comp_id: String, player_rank: int, player_name: String, nonce: int) -> Dictionary:
	var c: Dictionary = COMPS[comp_id]
	var rounds: int = c.rounds
	var size := 1 << rounds
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d-%d" % [comp_id, player_rank / 5, nonce])
	var belt := belt_of(player_rank)
	var entries: Array = [{"name": player_name, "academy": "Gringo BJJ", "power": 0.0, "player": true}]
	var used := {}
	var styles := ["guard", "pressure", "back", "submission", "balanced"]
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
	var specials: Array = []
	for id in MOVES:
		if int(MOVES[id].rank) == 99:
			specials.append(id)
	while entries.size() < size:
		var nm := "%s %s" % [COMP_FIRST[rng.randi() % COMP_FIRST.size()], COMP_LAST[rng.randi() % COMP_LAST.size()]]
		if used.has(nm):
			continue
		used[nm] = true
		var r := clampi(belt * 5 + rng.randi_range(0, 4), 0, 24)
		var extras: Array = []
		for s in specials:
			if rng.randf() < 0.12 + 0.1 * belt:
				extras.append(s)
		entries.append({"name": nm, "academy": ACADEMIES[rng.randi() % ACADEMIES.size()], "power": rng.randf(),
			"opp": {"name": nm, "title": Tx.f("%s Belt", BELTS[belt].name), "rank": r, "level": 0.0,
				"gi": gis[rng.randi() % gis.size()], "skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), rng.randf()),
				"style": styles[rng.randi() % styles.size()], "extra": extras, "zone": "",
				"intro": "Oss. Good luck.", "win": "Good match. Go get that medal.", "lose": "Next time, gringo."}})
	# the player's opponent in each round: the stronger survivor of the section they would meet
	var path: Array = []
	for rd in rounds:
		var hi := 1 << rd
		var best: Dictionary = {}
		for i in range(hi, hi * 2):
			if best.is_empty() or float(entries[i].power) + rng.randf() * 0.35 > float(best.power):
				best = entries[i]
		var o: Dictionary = best.opp.duplicate()
		o.level = rank_level(player_rank) - 0.45 + rd * 0.4 + float(c.power) * 0.6 + float(best.power) * 0.3
		o.academy = best.academy
		path.append(o)
	return {"id": comp_id, "entries": entries, "path": path, "round": 0, "belt": belt, "rounds": rounds}

static func round_name(rounds: int, rd: int) -> String:
	return ROUND_NAMES[rounds][rd]

# ---------------------------------------------------------------- quests
# Givers stand around each zone with a "!" (quest available) or "?" (ready to turn in).
# Objective types: collect {zone,n} · drill {n} · beat {ids} · landmarks {ids} · count_landmarks {zone,n}
# · sub_wins {n} · win {n} (zone rolls) · medal {comp} · reach {pos,radius,label} · daily_wins {n}
const QUEST_GIVERS := {
	"lurdes": {"name": "Dona Lurdes", "zone": "caceres", "pos": Vector3(9, 0, 15), "shirt": Color(0.9, 0.35, 0.45), "skin": 0.55},
	"kaique": {"name": "Kaique", "zone": "caceres", "pos": Vector3(7, 0, -39), "shirt": Color(0.95, 0.95, 0.95), "skin": 0.75},
	"bene": {"name": "Seu Bené", "zone": "caceres", "pos": Vector3(-50, 0, -8), "shirt": Color(0.35, 0.55, 0.75), "skin": 0.8},
	"juninho": {"name": "Juninho", "zone": "caceres", "pos": Vector3(26, 0, -15), "shirt": Color(0.95, 0.8, 0.25), "skin": 0.45},
	"rosa": {"name": "Tia Rosa", "zone": "caceres", "pos": Vector3(-40, 0, 22), "shirt": Color(0.55, 0.75, 0.45), "skin": 0.65},
	"lia": {"name": "Ranger Lia", "zone": "pantanal", "pos": Vector3(-13, 0, -42), "shirt": Color(0.4, 0.5, 0.3), "skin": 0.4},
	"tonhao": {"name": "Tonhão", "zone": "pantanal", "pos": Vector3(-33, 0, 31), "shirt": Color(0.75, 0.3, 0.25), "skin": 0.6},
	"ana": {"name": "Ana", "zone": "pantanal", "pos": Vector3(-74, 0, 3), "shirt": Color(0.2, 0.6, 0.85), "skin": 0.5},
	"bebeto": {"name": "Bebeto", "zone": "pantanal", "pos": Vector3(52, 0, 46), "shirt": Color(0.42, 0.26, 0.13), "skin": 0.7},
	"caio": {"name": "Caio", "zone": "chapada", "pos": Vector3(-71, 0, 34), "shirt": Color(0.95, 0.55, 0.2), "skin": 0.3},
	"cristal": {"name": "Dona Cristal", "zone": "chapada", "pos": Vector3(47, 0, 30), "shirt": Color(0.7, 0.5, 0.85), "skin": 0.5},
	"nanda": {"name": "Nanda", "zone": "chapada", "pos": Vector3(-36, 0, -6), "shirt": Color(0.3, 0.7, 0.6), "skin": 0.35},
	"jaci": {"name": "Jaci", "zone": "chapada", "pos": Vector3(30, 0, 8), "shirt": Color(0.95, 0.9, 0.85), "skin": 0.6},
	"jorge": {"name": "Seu Jorge", "zone": "rio", "pos": Vector3(-18, 0, 36.5), "shirt": Color(0.98, 0.8, 0.2), "skin": 0.85},
	"dandara": {"name": "Dandara", "zone": "rio", "pos": Vector3(31, 0, -37), "shirt": Color(0.95, 0.95, 0.95), "skin": 0.9},
	"mike": {"name": "Mike from Ohio", "zone": "rio", "pos": Vector3(-62, 0, -18), "shirt": Color(0.95, 0.45, 0.6), "skin": 0.05},
	"rafinha": {"name": "Rafinha", "zone": "rio", "pos": Vector3(-58, 0, 38), "shirt": Color(0.15, 0.3, 0.75), "skin": 0.45},
	# main story (gold markers)
	"tati": {"name": "Professora Tati", "zone": "caceres", "pos": Vector3(-7, 0, -39), "shirt": Color(0.1, 0.1, 0.12), "skin": 0.6, "story": true, "body": "female"},
	"iracema": {"name": "Dona Iracema", "zone": "pantanal", "pos": Vector3(72, 0, 53), "shirt": Color(0.6, 0.35, 0.2), "skin": 0.65, "story": true, "body": "female"},
	"iara": {"name": "Iara", "zone": "chapada", "pos": Vector3(34, 0, 46), "shirt": Color(0.3, 0.55, 0.75), "skin": 0.55, "story": true, "body": "female"},
	"bia": {"name": "Professora Bia", "zone": "rio", "pos": Vector3(4, 0, -16), "shirt": Color(0.95, 0.95, 0.95), "skin": 0.8, "story": true, "body": "female"},
	"rae": {"name": "Professor Rae", "zone": "socal", "pos": Vector3(-74, 0, 14), "shirt": Color(0.1, 0.1, 0.12), "skin": 0.55, "story": true},
	"carmen": {"name": "Abuela Carmen", "zone": "socal", "pos": Vector3(28, 0, -4), "shirt": Color(0.85, 0.3, 0.3), "skin": 0.5, "body": "female"},
	"jayden": {"name": "Jayden", "zone": "socal", "pos": Vector3(-6, 0, 24), "shirt": Color(0.2, 0.7, 0.75), "skin": 0.3},
	"dottie": {"name": "Dottie", "zone": "texas", "pos": Vector3(9, 0, 15), "shirt": Color(0.9, 0.55, 0.65), "skin": 0.2, "body": "female"},
	"earl": {"name": "Earl", "zone": "texas", "pos": Vector3(-24, 0, -12), "shirt": Color(0.6, 0.25, 0.2), "skin": 0.3},
	"wyatt": {"name": "Wyatt", "zone": "texas", "pos": Vector3(26, 0, -15), "shirt": Color(0.3, 0.5, 0.85), "skin": 0.15},
	"rosita": {"name": "Abuela Rosita", "zone": "texas", "pos": Vector3(-40, 0, 22), "shirt": Color(0.55, 0.75, 0.45), "skin": 0.55, "body": "female"},
	"ranger_dee": {"name": "Ranger Dee", "zone": "everglades", "pos": Vector3(-13, 0, -42), "shirt": Color(0.4, 0.5, 0.3), "skin": 0.75, "body": "female"},
	"junior": {"name": "Junior", "zone": "everglades", "pos": Vector3(-33, 0, 31), "shirt": Color(0.95, 0.6, 0.2), "skin": 0.25},
	"cap_lou": {"name": "Cap'n Lou", "zone": "everglades", "pos": Vector3(-77, 0, 1), "shirt": Color(0.2, 0.4, 0.75), "skin": 0.35},
	"tammy": {"name": "Tammy", "zone": "everglades", "pos": Vector3(46, 0, 40), "shirt": Color(0.85, 0.4, 0.6), "skin": 0.2, "body": "female"},
	"moonbeam": {"name": "Moonbeam", "zone": "sedona", "pos": Vector3(-71, 0, 34), "shirt": Color(0.75, 0.55, 0.9), "skin": 0.2, "body": "female"},
	"dolores": {"name": "Dolores", "zone": "sedona", "pos": Vector3(54, 0, 44), "shirt": Color(0.9, 0.45, 0.3), "skin": 0.55, "body": "female"},
	"kai": {"name": "Kai", "zone": "sedona", "pos": Vector3(-36, 0, -6), "shirt": Color(0.3, 0.7, 0.6), "skin": 0.45},
	"ranger_bo": {"name": "Ranger Bo", "zone": "sedona", "pos": Vector3(30, 0, 8), "shirt": Color(0.45, 0.5, 0.3), "skin": 0.3},
	"mae": {"name": "Coach Mae", "zone": "texas", "pos": Vector3(-7, 0, -39), "shirt": Color(0.1, 0.1, 0.12), "skin": 0.35, "story": true, "body": "female"},
	"opal": {"name": "Miss Opal", "zone": "everglades", "pos": Vector3(70, 0, 46), "shirt": Color(0.6, 0.35, 0.2), "skin": 0.7, "story": true, "body": "female"},
	"luz": {"name": "Luz", "zone": "sedona", "pos": Vector3(34, 0, 46), "shirt": Color(0.3, 0.55, 0.75), "skin": 0.5, "story": true, "body": "female"},
	"kim": {"name": "Lifeguard Kim", "zone": "socal", "pos": Vector3(34, 0, 36), "shirt": Color(0.9, 0.2, 0.2), "skin": 0.25, "body": "female"},
}

## The main story: four chapters, one passport stamp each. The Liga Ouro buys academies, sells belts
## and rigs tournaments; every master on the road is next on its list.
const CHAPTERS := [
	{"id": "ch1", "faction": "brasil", "zone": "caceres", "name": "Chapter 1: The Gringo Arrives", "stamp": "Academia Onça", "master": "onca", "color": Color(0.95, 0.65, 0.15)},
	{"id": "ch2", "faction": "brasil", "zone": "pantanal", "name": "Chapter 2: Swamp Law", "stamp": "Fazenda Jacaré", "master": "jacare", "color": Color(0.35, 0.65, 0.3)},
	{"id": "ch3", "faction": "brasil", "zone": "chapada", "name": "Chapter 3: The Waterfall Deal", "stamp": "Cachoeira Team", "master": "cachoeira", "color": Color(0.85, 0.35, 0.25)},
	{"id": "ch4", "faction": "brasil", "zone": "rio", "name": "Chapter 4: Grande Final", "stamp": "Leão Jiu-Jitsu", "master": "leao", "color": Color(0.3, 0.55, 0.95)},
	{"id": "ch5", "faction": "brasil", "zone": "socal", "name": "Chapter 5: The Pan-American Trip", "stamp": "The Garage", "master": "dale", "color": Color(0.85, 0.3, 0.35)},
	{"id": "u1", "faction": "usa", "zone": "texas", "name": "Chapter 1: Lone Star", "stamp": "Lone Star BJJ", "master": "boone", "color": Color(0.85, 0.3, 0.3)},
	{"id": "u2", "faction": "usa", "zone": "everglades", "name": "Chapter 2: Gator Country", "stamp": "The Gator Pit", "master": "gator", "color": Color(0.35, 0.65, 0.3)},
	{"id": "u3", "faction": "usa", "zone": "sedona", "name": "Chapter 3: Red Rock", "stamp": "Vortex Jiu-Jitsu", "master": "sol", "color": Color(0.85, 0.4, 0.25)},
	{"id": "u4", "faction": "usa", "zone": "socal", "name": "Chapter 4: Coast to Coast", "stamp": "The Garage", "master": "dale", "color": Color(0.3, 0.55, 0.95)},
	{"id": "u5", "faction": "usa", "zone": "rio", "name": "Chapter 5: The Source", "stamp": "Leão Jiu-Jitsu", "master": "leao", "color": Color(0.95, 0.75, 0.2)},
]
static func chapters_for(fac: String) -> Array:
	return CHAPTERS.filter(func(c): return str(c.get("faction", "brasil")) == fac)

static func chapter_faction(ch_id: String) -> String:
	for c in CHAPTERS:
		if c.id == ch_id:
			return str(c.get("faction", "brasil"))
	return ""
const STORY_QUEST_OF_STAMP := {"Academia Onça": "s1_onca", "Fazenda Jacaré": "s2_jacare", "Cachoeira Team": "s3_cachoeira", "Leão Jiu-Jitsu": "s4_leao", "The Garage": "s5_dale"}

## Gi / No-Gi paths: everyone trains both, you specialise in one at blue belt.
const PATHS := {
	"gi": {"name": "Gi", "lineage": "Leão's lineage", "desc": "Grips, lapels and collar chokes. Slower, heavier, more control.",
		"moves": ["cross_collar", "bow_arrow", "ezekiel", "lasso_sweep", "paper_cutter"]},
	"nogi": {"name": "No-Gi", "lineage": "the Arpoador beach crew", "desc": "Scrambles, front headlocks and leg locks. Faster, slipperier, more risk.",
		"moves": ["darce", "toe_hold", "kneebar", "high_crotch", "body_lock_td"]},
}
## Need cloth to grip (collar, lapel, sleeve): not available when you roll no-gi, for you or for them.
const GI_ONLY := ["cross_collar", "bow_arrow", "ezekiel", "lasso_sweep", "paper_cutter", "baseball_choke", "worm_sweep"]
const PATH_LATE_RANKS := 5        # the other path's signatures come ~10 levels later
const PATH_MASTERY := 0.10        # +10% technique damage in your path's kit
const PATH_RETRAIN_COST := 500

const QUESTS := {
	# ---------------- Cáceres
	"terere_run": {"giver": "lurdes", "title": "Tereré Run", "min_level": 1, "xp": 60,
		"offer": "Gringo! My tereré cups blew all over town in the storm. Bring back three and I'll pour you one on the house. Cold, with lemon.",
		"done": "Perfeito! Here, drink. In Mato Grosso we drink tereré, not chimarrão. Don't let anyone from the south tell you different.",
		"obj": [{"type": "collect", "zone": "caceres", "n": 3, "text": "Tereré cups found"}]},
	"shrimping": {"giver": "kaique", "title": "Shrimping 101", "min_level": 2, "xp": 70,
		"offer": "Mestre Onça says you roll like a tourist. Do two drills at the stations. Every white belt starts there, oss.",
		"done": "Better. Your hips are waking up. Keep drilling and the techniques will come on their own.",
		"obj": [{"type": "drill", "n": 2, "text": "Drills completed"}]},
	"know_town": {"giver": "juninho", "title": "Know the Town", "min_level": 1, "xp": 70,
		"offer": "You're new, right? I'll show you around... actually, you show yourself around. Find four places in town and come tell me.",
		"done": "Ha! Now you know Cáceres better than my cousin from Cuiabá.",
		"obj": [{"type": "count_landmarks", "zone": "caceres", "n": 4, "text": "Landmarks discovered"}]},
	"lost_faixa": {"giver": "rosa", "title": "The Lost Faixa", "min_level": 3, "xp": 90,
		"offer": "My son lost his white belt by the river after practice. He cried all night. Can you look down by the water, west of here?",
		"done": "That's it! Still muddy. He'll be so happy. God bless you, querido.",
		"obj": [{"type": "reach", "pos": Vector3(-55, 0, 36), "radius": 3.0, "text": "Find the belt on the riverbank"}]},
	"river_hustler": {"giver": "bene", "title": "The Riverbank Hustler", "min_level": 5, "xp": 110, "requires": ["shrimping"],
		"offer": "That Peixe takes money from every tourist who steps on his mat. Teach him some humility, will you?",
		"done": "Ha! Peixe finally tapped to a gringo. The whole riverbank is talking about it.",
		"obj": [{"type": "beat", "ids": ["peixe"], "text": "Beat Peixe"}]},
	"first_podium": {"giver": "kaique", "title": "First Podium", "min_level": 6, "xp": 140, "requires": ["shrimping"],
		"offer": "The Copa Cáceres board is up by the academia. Every competitor in town is signed up. Get on the podium, any color.",
		"done": "A medal in your first comp! Mestre Onça pretended not to smile. I saw it.",
		"obj": [{"type": "medal", "comp": "copa_caceres", "text": "Win a medal at the Copa Cáceres"}]},
	# ---------------- Pantanal
	"jacare_watch": {"giver": "lia", "title": "Jacaré Watch", "min_level": 11, "xp": 160,
		"offer": "Count the jacarés for me? Just kidding. Check on the lagoon and the boat dock and tell me everything's calm.",
		"done": "No tourists eaten today. Excellent day in the Pantanal.",
		"obj": [{"type": "landmarks", "ids": ["p_lagoon", "p_dock"], "text": "Visit the lagoon and the dock"}]},
	"ranch_hands": {"giver": "tonhao", "title": "Ranch Hands", "min_level": 12, "xp": 220,
		"offer": "My two best hands, Zeca and Tuca, think they're too strong for jiu-jitsu. Go prove them wrong so they'll come to class.",
		"done": "They're signing up tomorrow. Strong farm boys with good technique... watch out, Brazil.",
		"obj": [{"type": "beat", "ids": ["zeca", "tuca"], "text": "Beat Zeca and Tuca"}]},
	"festival_feathers": {"giver": "ana", "title": "Feathers for the Festival", "min_level": 11, "xp": 170,
		"offer": "The festa is next week and I need arara feathers for the costumes. Only the ones they drop, never from the birds!",
		"done": "Lindas! Red, blue, gold. Come dance with us, gringo.",
		"obj": [{"type": "collect", "zone": "pantanal", "n": 4, "text": "Arara feathers found"}]},
	"sub_hunter": {"giver": "bebeto", "title": "Submission Hunter", "min_level": 13, "xp": 230,
		"offer": "Mestre Jacaré says points are for people who can't finish. Win three rolls by submission. Anywhere, anyone.",
		"done": "Three taps. Now you're starting to think like a jacaré.",
		"obj": [{"type": "sub_wins", "n": 3, "text": "Submission wins"}]},
	"swamp_medal": {"giver": "bebeto", "title": "Medal of the Swamp", "min_level": 15, "xp": 260, "requires": ["sub_hunter"],
		"offer": "The Pantanal Open is in the barn this month. Bring a medal back to the fazenda.",
		"done": "The Mestre will hang that next to his old photos. Respect.",
		"obj": [{"type": "medal", "comp": "pantanal_open", "text": "Win a medal at the Pantanal Open"}]},
	# ---------------- Chapada
	"trail_runner": {"giver": "caio", "title": "Trail Runner", "min_level": 21, "xp": 260,
		"offer": "Rita runs the plateau trail twice a day. Can you even make it once? Reach the Mirante and the cave, then come back.",
		"done": "Not bad. Rita would still beat you, but not by much.",
		"obj": [{"type": "landmarks", "ids": ["c_mirante", "c_cave"], "text": "Reach the Mirante and the cave"}]},
	"crystal_clear": {"giver": "cristal", "title": "Crystal Clear", "min_level": 21, "xp": 260,
		"offer": "My husband sells crystals but he never goes out to find them. Bring me four from the plateau.",
		"done": "Good energy in these. I'll give one to Joaquim for luck. He needs it.",
		"obj": [{"type": "collect", "zone": "chapada", "n": 4, "text": "Quartz crystals found"}]},
	"iron_grip": {"giver": "nanda", "title": "Iron Grip", "min_level": 22, "xp": 260,
		"offer": "Biro and I climb these walls every morning. Your grips are soft. Three drills at the academia, now.",
		"done": "Feel that in your forearms? That's the Chapada saying hello.",
		"obj": [{"type": "drill", "n": 3, "text": "Drills completed"}]},
	"behind_veil": {"giver": "jaci", "title": "Behind the Veil", "min_level": 23, "xp": 300,
		"offer": "My cousin Iara says there's a place behind the Véu de Noiva where you can hear your own heartbeat. Find it.",
		"done": "You found it! Iara said only locals know. Now you're a little bit local.",
		"obj": [{"type": "reach", "pos": Vector3(20, 0, -6.2), "radius": 2.5, "text": "Stand behind the waterfall"}]},
	"visiting_champion": {"giver": "caio", "title": "Visiting Champion", "min_level": 26, "xp": 320, "requires": ["trail_runner"],
		"offer": "That gaúcho from Porto Alegre keeps calling us 'warm-ups'. Shut him up, will you?",
		"done": "He took the bus home early. Bah, tchê!",
		"obj": [{"type": "beat", "ids": ["gaucho"], "text": "Beat Gaúcho"}]},
	# ---------------- Rio
	"agua_de_coco": {"giver": "jorge", "title": "Água de Coco", "min_level": 31, "xp": 400,
		"offer": "My coconut delivery fell off the truck all over the city. Bring four back to the kiosk and you drink free all summer.",
		"done": "Gelada! On the house, campeão. That's how we do it in Copacabana.",
		"obj": [{"type": "collect", "zone": "rio", "n": 4, "text": "Green coconuts found"}]},
	"kids_class": {"giver": "dandara", "title": "Kids' Class", "min_level": 31, "xp": 420,
		"offer": "Tatu wants you to help with the kids' class. Show them good habits: three drills, perfect form, no shortcuts.",
		"done": "The kids are copying your shrimp now. That's the best compliment on the morro.",
		"obj": [{"type": "drill", "n": 3, "text": "Drills completed"}]},
	"climb_corcovado": {"giver": "mike", "title": "Arms Wide Open", "min_level": 32, "xp": 450,
		"offer": "Dude, I came to Rio for jiu-jitsu but my legs are destroyed. Can you climb Corcovado and tell me if the view's worth it?",
		"done": "Worth it? Man, I'm going tomorrow. After a nap. And an açaí.",
		"obj": [{"type": "landmarks", "ids": ["r_cristo"], "text": "Reach the Corcovado summit"}]},
	"beach_session": {"giver": "rafinha", "title": "Beach Session", "min_level": 33, "xp": 460,
		"offer": "Professora Bia wants to see you roll on the sand first. Beat Dudu and Luana, then she'll take you seriously.",
		"done": "Sand in your gi, a win in your pocket. Bia's watching now.",
		"obj": [{"type": "beat", "ids": ["dudu", "luana"], "text": "Beat Dudu and Luana"}]},
	"rio_open_medal": {"giver": "rafinha", "title": "The Rio Open", "min_level": 35, "xp": 600, "requires": ["beach_session"],
		"offer": "The Rio International Open is the real thing. Teams from everywhere. Get on that podium.",
		"done": "A medal at the Rio Open. Gringo, they'll be talking about you back in Cáceres.",
		"obj": [{"type": "medal", "comp": "rio_open", "text": "Win a medal at the Rio Open"}]},
	"daily_grind": {"giver": "jorge", "title": "The Daily Grind", "min_level": 31, "xp": 500, "requires": ["agua_de_coco"],
		"offer": "Every surfer here trains every day. Win two Daily Challenges, then come drink another coco.",
		"done": "Consistency, campeão. That's the whole secret, on the mat and in the waves.",
		"obj": [{"type": "daily_wins", "n": 2, "text": "Daily Challenges won"}]},
	# ---------------- San Diego
	"sand_dollars": {"giver": "kim", "title": "Sand Dollars", "min_level": 40, "xp": 650,
		"offer": "Tourists keep taking the sand dollars home. Can you find four before they do? I'll put them back where they belong.",
		"done": "Perfect. And hey, if you ever want to train lifeguard-style, we swim at 6 a.m. Bring your gas.",
		"obj": [{"type": "collect", "zone": "socal", "n": 4, "text": "Sand dollars found"}]},
	"local_tour": {"giver": "jayden", "title": "Local Tour", "min_level": 40, "xp": 650,
		"offer": "Yo, you're the Brazilian guy everyone's talking about? Before you roll here you gotta see the spots. Pier, cliffs, tacos. Non-negotiable.",
		"done": "Okay, you're basically a local now. Don't tell anyone about the cliffs.",
		"obj": [{"type": "landmarks", "ids": ["s_pier", "s_cliffs", "s_tacos"], "text": "Visit the pier, the cliffs and Taco Truck Row"}]},
	"taco_tuesday": {"giver": "carmen", "title": "Taco Tuesday", "min_level": 41, "xp": 700,
		"offer": "Mijo, the Gold League boys eat my tacos and never pay. Every Tuesday. You look strong. Teach Tyler and Brooke some manners and the carne asada is on me.",
		"done": "Ay, they paid! With interest! Sit, eat. You remind me of my grandson.",
		"obj": [{"type": "beat", "ids": ["tyler", "brooke"], "text": "Beat Tyler and Brooke"}]},
	"no_gi_night": {"giver": "rae", "title": "No-Gi Night", "min_level": 42, "xp": 720,
		"offer": "Friday night at The Garage is no-gi, and they don't care about belts. Win three rolls by submission, any outfit. That's how you earn a seat at the table here.",
		"done": "Three taps on a Friday. Dale's crew is calling you 'the Passport' now.",
		"obj": [{"type": "sub_wins", "n": 3, "text": "Submission wins"}]},
	# ================= MAIN STORY: Passaporte do Tatame
	# ---- Chapter 1: Cáceres
	"s1_passport": {"giver": "tati", "story": true, "chapter": "ch1", "title": "A Blank Passport", "min_level": 1, "xp": 80,
		"offer": "So you're the gringo with the blank Passaporte do Tatame. Every academy that accepts you stamps it. Mestre Onça won't even look at you until this town vouches for you. Go help people. They talk.",
		"done": "Dona Lurdes hasn't stopped talking about you. Good. Here, that's the first page of your passport. Mestre Onça noticed, he just won't say it.",
		"obj": [{"type": "quests", "ids": ["terere_run", "know_town", "lost_faixa"], "n": 2, "text": "Help the town (Tereré Run, Know the Town, The Lost Faixa)"}]},
	"s1_liga": {"giver": "tati", "story": true, "chapter": "ch1", "title": "Men in Gold", "min_level": 3, "xp": 120, "requires": ["s1_passport"],
		"offer": "There's a guy in a gold gi handing out flyers at the plaza. Liga Ouro. They've been buying gyms all over Mato Grosso. Go see what he wants, and if he wants a roll, give him one.",
		"done": "Valdir talked? The Liga bought the building. Our rent doubles next month, and they're running the Copa Cáceres to show the town who's boss.",
		"obj": [{"type": "reach", "pos": Vector3(-12, 0, 14), "radius": 6.0, "text": "Find the Liga recruiter at the plaza"}, {"type": "beat", "ids": ["valdir"], "text": "Beat Valdir"}]},
	"s1_training": {"giver": "tati", "story": true, "chapter": "ch1", "title": "Two-a-Days", "min_level": 4, "xp": 150, "requires": ["s1_liga"],
		"offer": "The Copa prize pays the rent. You're our only chance and you still roll like a tourist. Drills, then beat Cida and Tiago. They'll make you sweat.",
		"done": "That's the hip I wanted to see. You're ready for the Copa.",
		"obj": [{"type": "drill", "n": 3, "text": "Drills completed"}, {"type": "beat", "ids": ["cida", "tiago"], "text": "Beat Cida and Tiago"}]},
	"s1_copa": {"giver": "tati", "story": true, "chapter": "ch1", "title": "Prize Money", "min_level": 6, "xp": 200, "requires": ["s1_training"],
		"offer": "The Copa Cáceres board is up by the academia. The Liga is sponsoring it so everyone sees their logo. Take their prize money and pay our rent with it.",
		"done": "You did it! Rent's paid for a year. Valdir looked like he swallowed a lemon. Now go knock on Mestre Onça's mat.",
		"obj": [{"type": "medal", "comp": "copa_caceres", "text": "Win a medal at the Copa Cáceres"}]},
	"s1_onca": {"giver": "tati", "story": true, "chapter": "ch1", "title": "The First Stamp", "min_level": 9, "xp": 300, "requires": ["s1_copa"], "stamp": "Academia Onça",
		"offer": "He'll roll with you now. If you survive, he stamps your passport. That's how it's always been done. Win your rolls around town first, he respects that.",
		"done": "He stamped it. In thirty years I've seen him do that four times. Mestre Jacaré in the Pantanal is next on the Liga's list. Take the bus down the Transpantaneira. And gringo... at blue belt you have to choose who you are on the mat.",
		"obj": [{"type": "beat", "ids": ["onca"], "text": "Earn Mestre Onça's stamp"}]},
	"s1_path": {"giver": "tati", "story": true, "chapter": "ch1", "title": "Gi or No-Gi", "min_level": 10, "xp": 150, "requires": ["s1_onca"], "path_choice": true,
		"offer": "Everyone trains both. But you specialise in one. The Gi is Leão's old lineage: grips, lapels, collar chokes. No-Gi is the beach crew in Rio: scrambles, front headlocks, leg locks. Your path's techniques come first and hit harder in its kit. The other comes later. Choose.",
		"done": "Good choice. Now go. The Pantanal won't wait.",
		"obj": [{"type": "path", "n": 1, "text": "Choose your path"}]},
	# ---- Chapter 2: Pantanal
	"s2_fazenda": {"giver": "iracema", "story": true, "chapter": "ch2", "title": "Swamp Law", "min_level": 11, "xp": 220,
		"offer": "Tati called. You're the gringo with the passport? Our ranch hands have been signing Liga contracts for a few reais. My husband won't ask for help, so I will. Start at the ranch. Bruna still trains with us. Roll with her.",
		"done": "Bruna says you're real. That's enough for me.",
		"obj": [{"type": "landmarks", "ids": ["p_ranch", "p_fazenda"], "text": "Visit the ranch and the fazenda"}, {"type": "beat", "ids": ["bruna"], "text": "Roll with Bruna"}]},
	"s2_contracts": {"giver": "iracema", "story": true, "chapter": "ch2", "title": "Torn Contracts", "min_level": 12, "xp": 260, "requires": ["s2_fazenda"],
		"offer": "The Liga's enforcer, Brutus, collects the signatures. Beat him in front of the boys and those contracts are just paper.",
		"done": "Brutus ran back to the Covil da Sucuri. That's where they keep everyone they 'hire'.",
		"obj": [{"type": "beat", "ids": ["brutus"], "text": "Beat Brutus"}]},
	"s2_covil": {"giver": "iracema", "story": true, "chapter": "ch2", "title": "The Sucuri's Den", "min_level": 14, "xp": 360, "requires": ["s2_contracts"],
		"offer": "The Covil da Sucuri. Old academy, gone bad, Liga money now. You can't go in alone. Bring your academy party.",
		"done": "The Sucuri tapped? The boys are coming home. I'm cooking. Don't argue.",
		"obj": [{"type": "achievement", "ids": ["raid_sucuri"], "text": "Clear the Covil da Sucuri with your party"}]},
	"s2_open": {"giver": "iracema", "story": true, "chapter": "ch2", "title": "Open in the Barn", "min_level": 15, "xp": 300, "requires": ["s2_covil"],
		"offer": "The Pantanal Open is in our barn this month. The Liga wanted to sponsor it. We said no. Bring a medal home so it stays ours.",
		"done": "That medal goes over the door. Now he'll see you.",
		"obj": [{"type": "medal", "comp": "pantanal_open", "text": "Win a medal at the Pantanal Open"}]},
	"s2_jacare": {"giver": "iracema", "story": true, "chapter": "ch2", "title": "The Second Stamp", "min_level": 17, "xp": 420, "requires": ["s2_open"], "stamp": "Fazenda Jacaré",
		"offer": "My husband is waiting on the mat. He's stubborn, he's slow to smile and he bites. Win your rolls around the swamp first.",
		"done": "Two stamps. The Liga already bought land up in the Chapada, near the waterfall. Iara will find you there.",
		"obj": [{"type": "beat", "ids": ["jacare"], "text": "Earn Mestre Jacaré's stamp"}]},
	# ---- Chapter 3: Chapada
	"s3_resort": {"giver": "iara", "story": true, "chapter": "ch3", "title": "The Waterfall Deal", "min_level": 21, "xp": 320,
		"offer": "A Liga Ouro 'resort' wants the land around Véu de Noiva, and Mestre Cachoeira's academy sits right on it. Walk the plateau with me. See what they want to sell.",
		"done": "You saw the survey stakes. They're everywhere.",
		"obj": [{"type": "count_landmarks", "zone": "chapada", "n": 4, "text": "Landmarks discovered in the Chapada"}]},
	"s3_rico": {"giver": "iara", "story": true, "chapter": "ch3", "title": "Paid in Full", "min_level": 23, "xp": 380, "requires": ["s3_resort"],
		"offer": "Rico Dourado runs the resort. He bought his black belt. Literally. Show the village what a bought belt is worth.",
		"done": "He dropped a folder when he left. Look: brackets for the Chapada Classic, with the winners already written in.",
		"obj": [{"type": "beat", "ids": ["rico"], "text": "Beat Rico Dourado"}]},
	"s3_brackets": {"giver": "iara", "story": true, "chapter": "ch3", "title": "Rigged Brackets", "min_level": 24, "xp": 380, "requires": ["s3_rico"],
		"offer": "If the brackets are rigged, the only answer is to win anyway. Finish people. No decisions for their referees. Three wins by submission.",
		"done": "Three taps. Nobody can rig that. The whole plateau is talking.",
		"obj": [{"type": "sub_wins", "n": 3, "text": "Submission wins"}]},
	"s3_veil": {"giver": "iara", "story": true, "chapter": "ch3", "title": "Behind the Waterfall", "min_level": 25, "xp": 340, "requires": ["s3_brackets"],
		"offer": "Mestre Cachoeira meditates behind the falls. Old tradition: stand where he stands before you ask for a roll.",
		"done": "You heard it, didn't you? Your own heartbeat. He's ready for you.",
		"obj": [{"type": "reach", "pos": Vector3(20, 0, -6.2), "radius": 2.5, "text": "Stand behind the waterfall"}]},
	"s3_cachoeira": {"giver": "iara", "story": true, "chapter": "ch3", "title": "The Third Stamp", "min_level": 27, "xp": 520, "requires": ["s3_veil"], "stamp": "Cachoeira Team",
		"offer": "Win your rolls in the Chapada, then roll with the Mestre. Water always finds a way.",
		"done": "Three stamps. The Liga is betting everything on Rio: their champion against Grão-Mestre Leão's academy at the Grande Final. Professora Bia is waiting at Leão's gym.",
		"obj": [{"type": "beat", "ids": ["cachoeira"], "text": "Earn Mestre Cachoeira's stamp"}]},
	# ---- Chapter 4: Rio
	"s4_lineage": {"giver": "bia", "story": true, "chapter": "ch4", "title": "Where It All Began", "min_level": 31, "xp": 450,
		"offer": "Three stamps from Mato Grosso. Leão will want to see that. But first, see Rio: the beach, the morro, the cable car. This is where jiu-jitsu grew up.",
		"done": "Now you know why we fight for this place.",
		"obj": [{"type": "count_landmarks", "zone": "rio", "n": 4, "text": "Landmarks discovered in Rio"}]},
	"s4_open": {"giver": "bia", "story": true, "chapter": "ch4", "title": "Qualifier", "min_level": 33, "xp": 550, "requires": ["s4_lineage"],
		"offer": "The Grande Final takes the Rio Open medallists. The Liga paid off half the referees. You'll have to be clearly better.",
		"done": "You're in. So is their champion.",
		"obj": [{"type": "medal", "comp": "rio_open", "text": "Win a medal at the Rio Open"}]},
	"s4_dourado": {"giver": "bia", "story": true, "chapter": "ch4", "title": "Grande Final", "min_level": 36, "xp": 700, "requires": ["s4_open"],
		"offer": "O Campeão Dourado. Every medal he owns, the Patrão paid for, but he's dangerous anyway. If you win, the Liga loses Leão's academy and the bet that pays for everything else.",
		"done": "The Patrão left the arena before the medals. The Liga's sponsors are already calling their lawyers. One thing left.",
		"obj": [{"type": "beat", "ids": ["dourado"], "text": "Beat O Campeão Dourado"}]},
	"s4_leao": {"giver": "bia", "story": true, "chapter": "ch4", "title": "The Last Stamp", "min_level": 40, "xp": 1000, "requires": ["s4_dourado"], "stamp": "Leão Jiu-Jitsu",
		"offer": "Grão-Mestre Leão stamps the passport himself. Nobody has filled one in twenty years. Win your rolls around Rio and go see him.",
		"done": "Four stamps. Your passport is full, and you're part of the lineage now, gringo. Word is a Pan-American team is putting together a trip north. America. You'll want to be on that bus.",
		"obj": [{"type": "beat", "ids": ["leao"], "text": "Earn Grão-Mestre Leão's stamp"}]},
	# ---- Chapter 5: San Diego (América do Norte)
	"s5_arrive": {"giver": "rae", "story": true, "chapter": "ch5", "title": "Passport Control", "min_level": 40, "xp": 800,
		"offer": "Welcome to America, gringo. Funny, here YOU'RE the Brazilian. I left Rio twenty years ago and opened a school by the beach. Leão called. He says the Liga's money comes from here. Walk the coast first: boardwalk, pier, the garage gyms.",
		"done": "See all the gold banners? 'Gold League USA'. Same people, new flag. The Liga is the Sterling family's business.",
		"obj": [{"type": "landmarks", "ids": ["s_boardwalk", "s_pier", "s_garage"], "text": "Visit the boardwalk, the pier and The Garage"}]},
	"s5_garage": {"giver": "rae", "story": true, "chapter": "ch5", "title": "Garage Rules", "min_level": 41, "xp": 900, "requires": ["s5_arrive"],
		"offer": "American jiu-jitsu grew up in garages and wrestling rooms. They respect results, not belts. Marcus and Kenji run the Friday crew. Earn their respect.",
		"done": "Kenji says you 'solved the leg lock problem'. From him, that's a marriage proposal.",
		"obj": [{"type": "beat", "ids": ["marcus", "kenji"], "text": "Beat Marcus and Kenji"}]},
	"s5_sterling": {"giver": "rae", "story": true, "chapter": "ch5", "title": "Gold League USA", "min_level": 43, "xp": 1000, "requires": ["s5_garage"],
		"offer": "Brock Sterling. His father bankrolls the Liga Ouro. The kid parades on the boardwalk in a gold gi. Beat him in public and the investors start asking questions.",
		"done": "The video already has a million views. 'Brazilian passport guy humbles Gold League heir.' The sponsors are running.",
		"obj": [{"type": "beat", "ids": ["sterling"], "text": "Beat Brock Sterling"}]},
	"s5_open": {"giver": "rae", "story": true, "chapter": "ch5", "title": "The Pan-American Open", "min_level": 44, "xp": 1100, "requires": ["s5_sterling"],
		"offer": "The Pan-American Open: both continents, gi and no-gi. The Gold League bought the naming rights and lost the war. Go take a medal home.",
		"done": "A medal on two continents. Dale's waiting in The Garage. He doesn't give stamps. He's never had a passport to stamp.",
		"obj": [{"type": "medal", "comp": "socal_open", "text": "Win a medal at the Pan-American Open"}]},
	"s5_dale": {"giver": "rae", "story": true, "chapter": "ch5", "title": "The Fifth Stamp", "min_level": 46, "xp": 1500, "requires": ["s5_open"], "stamp": "The Garage",
		"offer": "Win your rolls around San Diego, then go see Coach Dale. If you survive his leg locks, The Garage goes in your passport. Two continents. Nobody's done that.",
		"done": "Five stamps, two continents. The Liga Ouro is finished, and you're the bridge between Brazil and America now. Some say there's a faction war brewing over who owns jiu-jitsu. We'll see. Oss.",
		"obj": [{"type": "beat", "ids": ["dale"], "text": "Earn Coach Dale's stamp"}]},
	# ================================================================ Team USA
	# ---------------- Dry Creek, Texas (side)
	"buckle_hunt": {"giver": "dottie", "title": "Buckle Up", "min_level": 1, "xp": 60,
		"offer": "Sugar, the rodeo wind blew Daddy's prize buckles clean across town. Find me three and your pie's on the house.",
		"done": "Oh, bless your heart! Pecan or peach? Don't answer, you're getting both.",
		"obj": [{"type": "collect", "zone": "texas", "n": 3, "text": "Rodeo buckles found"}]},
	"two_step": {"giver": "earl", "title": "The Two-Step Drill", "min_level": 2, "xp": 70,
		"offer": "Coach Boone says you move like a cow on ice. Go drill at the stations in the gym. Twice. Brisket'll be ready when you're done.",
		"done": "Better. Smoke's rolling, hips are rolling. Grab a plate.",
		"obj": [{"type": "drill", "n": 2, "text": "Drills completed"}]},
	"howdy": {"giver": "wyatt", "title": "Howdy, Neighbor", "min_level": 1, "xp": 70,
		"offer": "You're the new kid, right? I'm the newer kid. Find four spots around town and come tell me about 'em.",
		"done": "Dang! You know Dry Creek better than my cousin from Austin already.",
		"obj": [{"type": "count_landmarks", "zone": "texas", "n": 4, "text": "Landmarks discovered"}]},
	"lost_rosary": {"giver": "rosita", "title": "Abuela's Rosary", "min_level": 3, "xp": 90,
		"offer": "Mijo, I lost my rosary down by the swimming hole. My grandson won't go look, he's scared of the snakes. Will you?",
		"done": "¡Gracias a Dios! Here, take some tamales. Take more. You're too skinny.",
		"obj": [{"type": "reach", "pos": Vector3(-53, 0, 16), "radius": 3.0, "text": "Find the rosary by the swimming hole"}]},
	"rodeo_clown": {"giver": "earl", "title": "Clowning Around", "min_level": 5, "xp": 110, "requires": ["two_step"],
		"offer": "Duke's been taking the back of every tourist at the rodeo grounds and bragging about it in my restaurant. Shut him up for me.",
		"done": "Duke tapped! He's eating his brisket real quiet tonight.",
		"obj": [{"type": "beat", "ids": ["duke"], "text": "Beat Duke"}]},
	# ---------------- Everglades (side)
	"gator_teeth": {"giver": "tammy", "title": "Tooth and Claw", "min_level": 11, "xp": 240,
		"offer": "I make jewelry outta shed gator teeth. They're all over the swamp if you know where to look. Bring me four?",
		"done": "Perfect! Tourists go crazy for these. Here's your cut.",
		"obj": [{"type": "collect", "zone": "everglades", "n": 4, "text": "Gator teeth found"}]},
	"python_patrol": {"giver": "ranger_dee", "title": "Python Patrol", "min_level": 12, "xp": 280,
		"offer": "Pythons are eating everything out here, and so are those hammock hermits. Walk the swamp with me: hit the ranger station, the hammock and the fish camp.",
		"done": "Good eyes. You'd make a decent ranger. Terrible pay, though.",
		"obj": [{"type": "landmarks", "ids": ["e_ranger", "e_hammock", "e_fishcamp"], "text": "Patrol the swamp"}]},
	"bait_and_switch": {"giver": "junior", "title": "Bait and Switch", "min_level": 13, "xp": 300,
		"offer": "Skeeter says nobody under fifty can beat him. Rusty says the same thing. Prove 'em both wrong and I'll take you airboating.",
		"done": "Both of 'em! Hold on to your hat, we're going fast.",
		"obj": [{"type": "beat", "ids": ["skeeter", "rusty"], "text": "Beat Skeeter and Rusty"}]},
	"sub_city": {"giver": "cap_lou", "title": "Swamp Finishes", "min_level": 14, "xp": 320,
		"offer": "Points don't mean nothing in the swamp. Go finish three people. Tap 'em.",
		"done": "Three taps. Now you're speaking the language.",
		"obj": [{"type": "sub_wins", "n": 3, "text": "Submission wins"}]},
	# ---------------- Red Rock, Sedona (side)
	"crystal_grid": {"giver": "dolores", "title": "Crystal Grid", "min_level": 21, "xp": 380,
		"offer": "Someone scattered my vortex crystals around the canyons. Bad energy, very bad. Find four for my grid?",
		"done": "I feel it already. The whole shop is humming.",
		"obj": [{"type": "collect", "zone": "sedona", "n": 4, "text": "Vortex crystals found"}]},
	"pilgrim": {"giver": "moonbeam", "title": "The Vortex Pilgrimage", "min_level": 22, "xp": 400,
		"offer": "The four great vortexes, man. Bell Rock, Cathedral, the Airport Mesa and the creek. Visit them all and come back changed.",
		"done": "You feel different, right? I can see it in your aura. Kinda orange.",
		"obj": [{"type": "landmarks", "ids": ["d_bell", "d_cathedral", "d_vortex", "d_creek"], "text": "Visit the vortexes"}]},
	"hotshots": {"giver": "ranger_bo", "title": "Hotshots", "min_level": 24, "xp": 440,
		"offer": "Ramón and Colt think nobody out-works a fire crew. Go show 'em some cardio.",
		"done": "They're still breathing hard. Good work.",
		"obj": [{"type": "beat", "ids": ["ramon", "colt"], "text": "Beat Ramón and Colt"}]},
	"canyon_flow": {"giver": "kai", "title": "Canyon Flow", "min_level": 26, "xp": 460,
		"offer": "Flow rolling, bro. Hit three sweeps and three submissions. Like water in the creek.",
		"done": "Smooth. You're basically water now.",
		"obj": [{"type": "sweep", "n": 3, "text": "Sweeps"}, {"type": "sub", "n": 3, "text": "Submissions"}]},
	# ---------------- Story: Chapter 1, Lone Star
	"u1_passport": {"giver": "mae", "story": true, "chapter": "u1", "title": "A Blank Passport", "min_level": 1, "xp": 80,
		"offer": "So you're the new white belt. See this little book? The Tatame Passport. Every real academy that accepts you stamps it, from here to Rio. Coach Boone won't look at you till this town vouches for you. Go help folks. They talk.",
		"done": "Dottie hasn't shut up about you. Good. That's page one. Boone noticed, he just won't say it.",
		"obj": [{"type": "quests", "ids": ["buckle_hunt", "howdy", "lost_rosary"], "n": 2, "text": "Help the town (Buckle Up, Howdy Neighbor, Abuela's Rosary)"}]},
	"u1_gold": {"giver": "mae", "story": true, "chapter": "u1", "title": "Men in Gold", "min_level": 3, "xp": 120, "requires": ["u1_passport"],
		"offer": "There's a kid in a gold gi handing out flyers on the square. Gold League USA. They've been franchising every garage gym in Texas. Find out what he wants, and if he wants a roll, give him one.",
		"done": "Chad talked? The Sterling family bought our building. Rent doubles next month, and they're sponsoring the Dry Creek Open so the whole county sees their logo.",
		"obj": [{"type": "reach", "pos": Vector3(-12, 0, 14), "radius": 6.0, "text": "Find the Gold League recruiter on the square"}, {"type": "beat", "ids": ["chad"], "text": "Beat Chad"}]},
	"u1_training": {"giver": "mae", "story": true, "chapter": "u1", "title": "Two-a-Days", "min_level": 4, "xp": 150, "requires": ["u1_gold"],
		"offer": "The Open's prize money pays our rent. You're our best shot and you still roll like a tourist. Drills, then beat Jolene and Travis.",
		"done": "That's the hip I wanted to see. You're ready.",
		"obj": [{"type": "drill", "n": 3, "text": "Drills completed"}, {"type": "beat", "ids": ["jolene", "travis"], "text": "Beat Jolene and Travis"}]},
	"u1_open": {"giver": "mae", "story": true, "chapter": "u1", "title": "Prize Money", "min_level": 6, "xp": 200, "requires": ["u1_training"],
		"offer": "The Dry Creek Open board is up by the gym. Gold League's paying for the trophies. Take their money and pay our rent with it.",
		"done": "You did it! Rent's paid for a year. Chad looked like he swallowed a jalapeño. Now go knock on Boone's door.",
		"obj": [{"type": "medal", "comp": "dry_creek_open", "text": "Win a medal at the Dry Creek Open"}]},
	"u1_boone": {"giver": "mae", "story": true, "chapter": "u1", "title": "The First Stamp", "min_level": 9, "xp": 300, "requires": ["u1_open"], "stamp": "Lone Star BJJ",
		"offer": "He'll roll with you now. Survive, and he stamps your passport. That's how it's always been done. Win your rolls around town first, he respects that.",
		"done": "He stamped it. Captain Gator in the Everglades is next on the Gold League's list. Catch the Greyhound east. And kid... at blue belt you have to choose who you are on the mat.",
		"obj": [{"type": "beat", "ids": ["boone"], "text": "Earn Coach Boone's stamp"}]},
	"u1_path": {"giver": "mae", "story": true, "chapter": "u1", "title": "Gi or No-Gi", "min_level": 10, "xp": 150, "requires": ["u1_boone"], "path_choice": true,
		"offer": "Everybody trains both. But you specialise in one. The Gi is the old lineage from Rio: grips, lapels, collar chokes. No-Gi is the American way: wrestling, front headlocks, leg locks. Your path's techniques come first and hit harder. Choose.",
		"done": "Good choice. Now get on that bus. The swamp won't wait.",
		"obj": [{"type": "path", "n": 1, "text": "Choose your path"}]},
	# ---------------- Story: Chapter 2, Gator Country
	"u2_dock": {"giver": "opal", "story": true, "chapter": "u2", "title": "Gator Country", "min_level": 11, "xp": 220,
		"offer": "Mae called ahead. You're the kid with the passport? The Gold League's been paying our boys to sign franchise papers. My husband's too proud to ask for help, so I'm asking. Start at the dock and the fish camp. Lacey still trains with us. Roll with her.",
		"done": "Lacey says you're the real thing. Good enough for me.",
		"obj": [{"type": "landmarks", "ids": ["e_dock", "e_fishcamp"], "text": "Visit the dock and the fish camp"}, {"type": "beat", "ids": ["lacey"], "text": "Roll with Lacey"}]},
	"u2_rex": {"giver": "opal", "story": true, "chapter": "u2", "title": "Torn Contracts", "min_level": 12, "xp": 260, "requires": ["u2_dock"],
		"offer": "Their enforcer, Rex, collects the signatures out on the Trail. Beat him in front of the boys and those contracts are just paper.",
		"done": "The contracts are in the river now. But Rex didn't run home. He ran to the Sterlings' compound.",
		"obj": [{"type": "beat", "ids": ["rex"], "text": "Beat Rex"}]},
	"u2_compound": {"giver": "opal", "story": true, "chapter": "u2", "title": "The Gold Compound", "min_level": 13, "xp": 360, "requires": ["u2_rex"],
		"offer": "Rex ran to the Gold Compound, out in the southwest corner of the swamp. Gunnar Sterling himself trains his franchise coaches there. You can't go in alone. Bring a party.",
		"done": "Sterling tapped in his own compound? The boys are tearing up their contracts. I'm cooking. Don't argue.",
		"obj": [{"type": "achievement", "ids": ["raid_gold"], "text": "Clear the Gold Compound with your party"}]},
	"u2_locals": {"giver": "opal", "story": true, "chapter": "u2", "title": "Swamp Respect", "min_level": 14, "xp": 320, "requires": ["u2_compound"],
		"offer": "Gator won't roll anybody the swamp hasn't vouched for. Marisol and Skeeter are the toughest out here. Beat 'em.",
		"done": "Marisol's grandfather would've liked you. That's high praise.",
		"obj": [{"type": "beat", "ids": ["marisol", "skeeter"], "text": "Beat Marisol and Skeeter"}]},
	"u2_open": {"giver": "opal", "story": true, "chapter": "u2", "title": "Open in the Shed", "min_level": 15, "xp": 300, "requires": ["u2_locals"],
		"offer": "The Everglades Open is in the Gator Pit this weekend. The Gold League bought half the bracket. Go medal anyway.",
		"done": "A medal in that heat? You're half gator already.",
		"obj": [{"type": "medal", "comp": "glades_open", "text": "Win a medal at the Everglades Open"}]},
	"u2_gator": {"giver": "opal", "story": true, "chapter": "u2", "title": "The Second Stamp", "min_level": 17, "xp": 420, "requires": ["u2_open"], "stamp": "The Gator Pit",
		"offer": "He's ready for you. Win your rolls around the swamp first, then step into the Pit.",
		"done": "Second stamp. Master Sol in Sedona taught Gator and Boone both. The Sterlings want his valley next. Bus leaves from the Trail.",
		"obj": [{"type": "beat", "ids": ["gator"], "text": "Earn Captain Gator's stamp"}]},
	# ---------------- Story: Chapter 3, Red Rock
	"u3_retreat": {"giver": "luz", "story": true, "chapter": "u3", "title": "The Wellness Resort", "min_level": 21, "xp": 320,
		"offer": "The Sterlings want to bulldoze half of Uptown for a 'wellness resort' with a Gold League academy in every lobby. Master Sol won't fight it. Help me show him people care. Visit Uptown and Bell Rock, and roll with Willow.",
		"done": "Willow says you flow like the creek. Sol heard about it.",
		"obj": [{"type": "landmarks", "ids": ["d_uptown", "d_bell"], "text": "Visit Uptown and Bell Rock"}, {"type": "beat", "ids": ["willow"], "text": "Roll with Willow"}]},
	"u3_skyler": {"giver": "luz", "story": true, "chapter": "u3", "title": "The Heir", "min_level": 23, "xp": 380, "requires": ["u3_retreat"],
		"offer": "Skyler Sterling himself is in town, waving permits around near Bell Rock. He fancies himself a leg locker. Humble him.",
		"done": "He ran crying to his brother Brock in San Diego. That's your next stop someday, but not yet.",
		"obj": [{"type": "beat", "ids": ["skyler"], "text": "Beat Skyler Sterling"}]},
	"u3_canyon": {"giver": "luz", "story": true, "chapter": "u3", "title": "Canyon Council", "min_level": 24, "xp": 380, "requires": ["u3_skyler"],
		"offer": "Dusty and Sage still haven't decided whose side they're on. Climb up to Cathedral Rock and roll them both. Winner decides.",
		"done": "They're with us. Sage even put a crystal on your bag. Don't ask.",
		"obj": [{"type": "landmarks", "ids": ["d_cathedral"], "text": "Climb to Cathedral Rock"}, {"type": "beat", "ids": ["dusty", "sage"], "text": "Beat Dusty and Sage"}]},
	"u3_open": {"giver": "luz", "story": true, "chapter": "u3", "title": "Desert Bracket", "min_level": 25, "xp": 360, "requires": ["u3_canyon"],
		"offer": "The Red Rock Open decides who runs the valley's kids program. Gold League or us. Go medal.",
		"done": "The kids program stays ours. Sol smiled. I saw it.",
		"obj": [{"type": "medal", "comp": "red_rock_open", "text": "Win a medal at the Red Rock Open"}]},
	"u3_sol": {"giver": "luz", "story": true, "chapter": "u3", "title": "The Third Stamp", "min_level": 27, "xp": 520, "requires": ["u3_open"], "stamp": "Vortex Jiu-Jitsu",
		"offer": "Sol is waiting at his academy. Win your rolls around the valley first. He won't say it, but he's been waiting for someone like you for a long time.",
		"done": "Third stamp. Brown belt. Brock Sterling runs the whole Gold League out of San Diego. Coach Dale's Garage is the last holdout on the coast. Fly west.",
		"obj": [{"type": "beat", "ids": ["sol"], "text": "Earn Master Sol's stamp"}]},
	# ---------------- Story: Chapter 4, Coast to Coast
	"u4_arrive": {"giver": "rae", "story": true, "chapter": "u4", "title": "Coast to Coast", "min_level": 31, "xp": 600,
		"offer": "Sol sent you? Then you're family. The Gold League's headquarters is in that gold box on the hill. Get to know the coast first: the Garage, the Boardwalk. Tyler surfs at dawn, roll with him.",
		"done": "Tyler says you're legit. On the coast, that's a passport stamp all by itself.",
		"obj": [{"type": "landmarks", "ids": ["s_garage", "s_boardwalk"], "text": "Visit the Garage and the Boardwalk"}, {"type": "beat", "ids": ["tyler"], "text": "Roll with Tyler"}]},
	"u4_garage": {"giver": "rae", "story": true, "chapter": "u4", "title": "Garage Rules", "min_level": 33, "xp": 700, "requires": ["u4_arrive"],
		"offer": "Garage rules: nobody rolls with Dale until Marcus and Kenji sign off. One crushes you, the other takes your ankles.",
		"done": "Both? Dale already knows your name.",
		"obj": [{"type": "beat", "ids": ["marcus", "kenji"], "text": "Beat Marcus and Kenji"}]},
	"u4_sterling": {"giver": "rae", "story": true, "chapter": "u4", "title": "Gold League USA", "min_level": 36, "xp": 800, "requires": ["u4_garage"],
		"offer": "Brock Sterling. The champion. The money behind every franchise from Texas to here. Beat him at his own gym and the whole league wobbles.",
		"done": "Sterling tapped. The franchise owners are calling us now, not him.",
		"obj": [{"type": "beat", "ids": ["sterling"], "text": "Beat Brock Sterling"}]},
	"u4_open": {"giver": "rae", "story": true, "chapter": "u4", "title": "Pan-American Open", "min_level": 39, "xp": 800, "requires": ["u4_sterling"],
		"offer": "The Pan-American Open is the biggest bracket in the country. Teams from both continents. Medal and every gym on the coast is free.",
		"done": "That's it. The Gold League is just a gym again.",
		"obj": [{"type": "medal", "comp": "socal_open", "text": "Win a medal at the Pan-American Open"}]},
	"u4_dale": {"giver": "rae", "story": true, "chapter": "u4", "title": "The Fourth Stamp", "min_level": 42, "xp": 1000, "requires": ["u4_open"], "stamp": "The Garage",
		"offer": "Dale's waiting. Win your rolls on the coast, then go up the hill.",
		"done": "Four stamps, coast to coast. You know where jiu-jitsu came from, right? Rio. There's an old man there called Leão. Fly south when you're ready.",
		"obj": [{"type": "beat", "ids": ["dale"], "text": "Earn Coach Dale's stamp"}]},
	# ---------------- Story: Chapter 5, The Source (Rio)
	"u5_arrive": {"giver": "bia", "story": true, "chapter": "u5", "title": "The Source", "min_level": 40, "xp": 900,
		"offer": "An American with four stamps? Rae told me about you. Welcome to where it all started. Walk the beach, climb to the morro, and roll with Dudu. Everyone does.",
		"done": "Dudu says you shoot like a wrestler and play guard like a carioca. Interesting.",
		"obj": [{"type": "landmarks", "ids": ["r_beach", "r_morro"], "text": "Visit Copacabana and the morro"}, {"type": "beat", "ids": ["dudu"], "text": "Roll with Dudu"}]},
	"u5_morro": {"giver": "bia", "story": true, "chapter": "u5", "title": "Respect the Morro", "min_level": 42, "xp": 1000, "requires": ["u5_arrive"],
		"offer": "Tatu and Baiano don't care about your passport. Beat them and the whole city will.",
		"done": "The kids on the morro are calling you 'o americano'. That's affection, I promise.",
		"obj": [{"type": "beat", "ids": ["tatu", "baiano"], "text": "Beat Tatu and Baiano"}]},
	"u5_dourado": {"giver": "bia", "story": true, "chapter": "u5", "title": "Gold on Both Shores", "min_level": 44, "xp": 1100, "requires": ["u5_morro"],
		"offer": "The Liga Ouro here and your Gold League up north? Same money. The Campeão Dourado is their poster boy. Finish this.",
		"done": "Gold on both shores, broken in one week. Leão wants to see you.",
		"obj": [{"type": "beat", "ids": ["dourado"], "text": "Beat the Campeão Dourado"}]},
	"u5_leao": {"giver": "bia", "story": true, "chapter": "u5", "title": "The Fifth Stamp", "min_level": 46, "xp": 1400, "requires": ["u5_dourado"], "stamp": "Leão Jiu-Jitsu",
		"offer": "Grão-Mestre Leão. He taught the man who taught the man who taught your coach. Win your rolls in Rio, then go to his academia.",
		"done": "He stamped it. An American, in Leão's own hand. Your passport is full. Oss.",
		"obj": [{"type": "beat", "ids": ["leao"], "text": "Earn Grão-Mestre Leão's stamp"}]},
}

static func quests_of(giver: String) -> Array:
	var out: Array = []
	for id in QUESTS:
		if QUESTS[id].giver == giver:
			out.append(id)
	return out

# ---------------------------------------------------------------- fighter personalities
# aggr: how often they take the initiative · counter: bonus to punish your misses
# finish: how hard their subs are to escape · slippery: how hard they are to finish
# cardio: stamina recovery · fav: favorite techniques (picked far more often)
# plan: scouting report shown before the roll and in the journal
const PERSONALITY := {
	"rafa": {"aggr": 0.8, "fav": ["pull_guard", "scissor_sweep"], "plan": "Friendly plaza regular. Pulls guard and tries the scissor sweep. Takes his time."},
	"cida": {"aggr": 1.0, "cardio": 1.25, "fav": ["guard_armbar", "shrimp_guard"], "plan": "Runs the riverbank every morning. Never gets tired and hunts the armbar from guard."},
	"tiago": {"aggr": 1.25, "fav": ["double_leg", "single_leg", "knee_slice"], "plan": "Wrestler. Shoots early and often, then smashes through half guard. Stop the shot."},
	"peixe": {"aggr": 0.9, "slippery": 1.25, "counter": 0.05, "fav": ["old_school", "recover_guard", "half_kimura"], "plan": "Slippery as his name. Lives in half guard, waits for your mistake and counters."},
	"onca": {"aggr": 1.15, "finish": 1.15, "fav": ["triangle", "guard_armbar", "toreando"], "plan": "The academia's jaguar. Patient, then explosive. His triangle is famous in Cáceres."},
	"bruna": {"aggr": 1.1, "fav": ["upa", "elbow_knee", "triangle"], "plan": "Never stays on the bottom long. Bridges and escapes, then attacks from guard."},
	"zeca": {"aggr": 1.2, "cardio": 0.85, "fav": ["double_leg", "mount_up", "americana"], "plan": "Ranch strength. Takes you down, climbs to mount and cranks the americana. Gasses late."},
	"tuca": {"aggr": 0.95, "counter": 0.06, "fav": ["knee_slice", "mount_up", "top_kimura"], "plan": "Heavy top game. Slow but crushing. Don't let him settle in side control."},
	"neide": {"aggr": 0.85, "finish": 1.2, "slippery": 1.15, "fav": ["triangle", "omoplata", "half_kimura"], "plan": "Dona Neide, sixty years old, black-belt guard. Her chokes are tight and she never panics."},
	"jacare": {"aggr": 1.1, "finish": 1.2, "fav": ["darce", "ezekiel", "leg_drag"], "plan": "Grinds you down from the top, then the jaws close: d'arce or ezekiel."},
	"iara": {"aggr": 1.0, "slippery": 1.15, "fav": ["berimbolo", "omoplata", "triangle"], "plan": "Fluid guard player. Spins under you for the back. Keep your base."},
	"biro": {"aggr": 1.05, "finish": 1.15, "fav": ["leg_drag", "darce", "knee_slice"], "plan": "Climber's grips. Once he holds a lapel, you won't break it. Pressure passer."},
	"joaquim": {"aggr": 0.9, "finish": 1.25, "fav": ["ezekiel", "cross_collar", "bow_arrow"], "plan": "Collar choke specialist. Protect your neck at all times."},
	"rita": {"aggr": 1.2, "cardio": 1.3, "fav": ["snap_down", "rnc", "bow_arrow"], "plan": "Trail runner. Pushes the pace for the whole match and takes the back off scrambles."},
	"gaucho": {"aggr": 1.25, "fav": ["uchi_mata", "leg_drag", "mount_up"], "plan": "Competition machine from Porto Alegre. Great takedowns, then points, points, points."},
	"cachoeira": {"aggr": 1.1, "finish": 1.2, "slippery": 1.15, "fav": ["flying_armbar", "omoplata", "cross_collar"], "plan": "Like water: attacks from everywhere. Even the flying armbar. Expect anything."},
	"dudu": {"aggr": 1.05, "cardio": 1.15, "fav": ["berimbolo", "uchi_mata", "hip_bump"], "plan": "Surfer balance and a modern guard. Loves the berimbolo."},
	"luana": {"aggr": 1.15, "fav": ["snap_down", "rnc", "bow_arrow"], "plan": "Back-take hunter with sand-trained legs. Once she's behind you, the choke comes fast."},
	"baiano": {"aggr": 1.0, "slippery": 1.2, "fav": ["flying_armbar", "triangle", "berimbolo"], "plan": "Capoeira movement. Unpredictable and very hard to hold down."},
	"tatu": {"aggr": 1.0, "counter": 0.07, "fav": ["knee_slice", "darce", "mount_up"], "plan": "Morro pressure. Heavy, patient, and he punishes every mistake."},
	"bia": {"aggr": 1.05, "finish": 1.25, "fav": ["cross_collar", "ezekiel", "bow_arrow", "omoplata"], "plan": "World-class coach. Technical and calm. Her collar chokes finish world champions."},
	"leao": {"aggr": 1.15, "finish": 1.2, "slippery": 1.2, "counter": 0.06, "fav": ["darce", "leg_drag", "bow_arrow", "flying_armbar"], "plan": "The legend. No weaknesses, no wasted motion. Everything he does, he has done ten thousand times."},
}

static func personality(o: Dictionary, id := "") -> Dictionary:
	var p: Dictionary = PERSONALITY.get(id, {})
	return {"aggr": float(p.get("aggr", 1.0)), "counter": float(p.get("counter", 0.0)), "finish": float(p.get("finish", 1.0)),
		"slippery": float(p.get("slippery", 1.0)), "cardio": float(p.get("cardio", 1.0)),
		"fav": p.get("fav", o.get("extra", []).slice(0, 2)), "plan": str(p.get("plan", ""))}
