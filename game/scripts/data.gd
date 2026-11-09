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
	"guard": "Closed Guard",
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
	"straight_ankle": ["athlete", "judoka"], "kneebar": ["athlete"], "toe_hold": ["athlete"],
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
	"half_kimura": {"name": "Kimura from Half", "pos": "half", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 16, "type": "sub", "rank": 1},
	# --- half guard, top
	"knee_slice": {"name": "Knee Slice Pass", "pos": "half", "role": "top", "result": ["side", true], "pts": 3, "diff": 1, "cost": 12, "type": "pass", "rank": 0},
	"top_kimura": {"name": "Kimura from Top", "pos": "half", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 1},
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
	"straight_ankle": {"name": "Straight Ankle Lock", "pos": "guard", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 14, "type": "sub", "rank": 11},
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
	"crucifix": {"name": "Crucifix Choke", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99},
	"triangle_armbar": {"name": "Triangle Armbar", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99},
	# --- spec-exclusive techniques (rank 99: only your spec knows them; see Specs)
	"chain_sub": {"name": "Armbar-Triangle Chain", "pos": "guard", "role": "bottom", "result": "sub", "pts": 0, "diff": 2, "cost": 18, "type": "sub", "rank": 99, "spec": "sub_hunter"},
	"lumberjack": {"name": "Lumberjack Sweep", "pos": "guard", "role": "bottom", "result": ["mount", true], "pts": 2, "diff": 1, "cost": 13, "type": "sweep", "rank": 99, "spec": "sweeper"},
	"worm_sweep": {"name": "Worm Guard Sweep", "pos": "guard", "role": "bottom", "result": ["side", true], "pts": 2, "diff": 2, "cost": 14, "type": "sweep", "rank": 99, "spec": "lapel_guard"},
	"blast_double": {"name": "Blast Double", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 16, "type": "takedown", "rank": 99, "spec": "chain_wrestler"},
	"tilt_back": {"name": "Tilt to the Back", "pos": "side", "role": "top", "result": ["back", true], "pts": 4, "diff": 2, "cost": 14, "type": "back", "rank": 99, "spec": "rider"},
	"peek_out": {"name": "Peek-Out Scramble", "pos": "side", "role": "bottom", "result": ["half", true], "pts": 0, "diff": 2, "cost": 12, "type": "escape", "rank": 99, "spec": "scrambler"},
	"seoi_nage": {"name": "Ippon Seoi Nage", "pos": "standing", "role": "any", "result": ["side", true], "pts": 2, "diff": 2, "cost": 16, "type": "takedown", "rank": 99, "spec": "thrower"},
	"kuzushi_snap": {"name": "Kuzushi Snap-Down", "pos": "standing", "role": "any", "result": ["back", true], "pts": 2, "diff": 3, "cost": 15, "type": "back", "rank": 99, "spec": "grip_fighter"},
	"kesa_armlock": {"name": "Kesa Gatame Armlock", "pos": "side", "role": "top", "result": "sub", "pts": 0, "diff": 2, "cost": 15, "type": "sub", "rank": 99, "spec": "newaza"},
	"heel_hook": {"name": "Inside Heel Hook", "pos": "half", "role": "bottom", "result": "sub", "pts": 0, "diff": 3, "cost": 17, "type": "sub", "rank": 99, "spec": "leg_locker"},
	"kiss_dragon": {"name": "Kiss of the Dragon", "pos": "guard", "role": "bottom", "result": ["back", true], "pts": 4, "diff": 3, "cost": 16, "type": "back", "rank": 99, "spec": "berimbolo"},
	"tech_standup": {"name": "Technical Stand-Up Reversal", "pos": "mount", "role": "bottom", "result": ["half", false], "pts": 0, "diff": 1, "cost": 10, "type": "escape", "rank": 99, "spec": "gas_tank"},
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
		return "%s Belt" % b
	return "%s Belt, %d stripe%s" % [b, s, "" if s == 1 else "s"]

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
	return "Lv %d–%d" % [lv[0], lv[1]]

const XP_PER_STRIPE := 100

# ---------------------------------------------------------------- opponents (zone 1)
# level drives AI speed, reaction windows and move choice.
const OPPONENTS := {
	"rafa": {"name": "Rafa", "title": "Plaza regular", "rank": 0, "level": 1.3, "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.78, 0.57, 0.4),
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
		"pos": Vector3(30, 0, -26), "style": "pressure", "extra": ["snap_down"],
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
		"pos": Vector3(52, 0, 22), "style": "submission", "extra": ["ezekiel", "omoplata", "cross_collar", "darce"], "zone": "pantanal",
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
}

const ZONES := {
	"caceres": {"levels": [1, 10], "name": "Cáceres", "sub": "Mato Grosso", "rank": 0, "boss": "onca", "spawn": Vector3(0, 0, 24), "collect": "Tereré cups"},
	"pantanal": {"levels": [11, 20], "name": "Pantanal Norte", "sub": "Transpantaneira", "rank": 5, "boss": "jacare", "spawn": Vector3(-82, 0, -4), "collect": "Arara feathers"},
	"chapada": {"levels": [21, 30], "name": "Chapada dos Guimarães", "sub": "Red cliffs and waterfalls", "rank": 10, "boss": "cachoeira", "spawn": Vector3(-80, 0, 40), "collect": "Quartz crystals"},
	"rio": {"levels": [31, 50], "name": "Rio de Janeiro", "sub": "Where jiu-jitsu grew up", "rank": 15, "boss": "leao", "spawn": Vector3(-84, 0, 6), "collect": "Green coconuts"},
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
		"intro": "Today's challenge: %s. %s" % [DAILY_RULES[rule].name, DAILY_RULES[rule].desc],
		"win": "Oss. Same time tomorrow?", "lose": "Tomorrow's a new day. Oss."}
	return {"date": date_str, "rule": rule, "opp": opp}

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
}

# ---------------------------------------------------------------- academy wars
## Territories: rival academies plant flags at landmarks. Take one with a 3v3; hold it for +10% XP
## in that zone; rivals counterattack 8-16 real hours later and you have 24 hours to defend.
const TERRITORIES := {
	"t_plaza": {"name": "Praça", "zone": "caceres", "pos": Vector3(10, 0, 15), "academy": "Tatame Livre"},
	"t_river": {"name": "Riverbank", "zone": "caceres", "pos": Vector3(-44, 0, 7), "academy": "Rio Negro Team"},
	"t_market": {"name": "Feira", "zone": "caceres", "pos": Vector3(30, 0, -11), "academy": "Cuiabá Combat"},
	"t_ranch": {"name": "Cattle Ranch", "zone": "pantanal", "pos": Vector3(-40, 0, 16), "academy": "Pantanal Fight"},
	"t_dock": {"name": "Boat Dock", "zone": "pantanal", "pos": Vector3(38, 0, -28), "academy": "Jacaré BJJ"},
	"t_tower": {"name": "Ranger Tower", "zone": "pantanal", "pos": Vector3(-18, 0, -38), "academy": "Ilha Grappling"},
	"t_village": {"name": "Vila da Chapada", "zone": "chapada", "pos": Vector3(42, 0, 32), "academy": "Cachoeira Team"},
	"t_rocks": {"name": "Cidade de Pedra", "zone": "chapada", "pos": Vector3(-30, 0, -38), "academy": "Tatame Livre"},
	"t_mirante": {"name": "Mirante", "zone": "chapada", "pos": Vector3(30, 0, -60), "academy": "Rio Negro Team"},
	"t_beach": {"name": "Copacabana", "zone": "rio", "pos": Vector3(8, 0, 36), "academy": "Copacabana Top Team"},
	"t_arpoador": {"name": "Arpoador", "zone": "rio", "pos": Vector3(-68, 0, 40), "academy": "Arpoador BJJ"},
	"t_morro": {"name": "The Morro", "zone": "rio", "pos": Vector3(38, 0, -40), "academy": "Projeto Morro"},
}
const ACADEMY_COLORS := {"Tatame Livre": Color(0.9, 0.9, 0.85), "Rio Negro Team": Color(0.15, 0.15, 0.2), "Cuiabá Combat": Color(0.85, 0.3, 0.2),
	"Pantanal Fight": Color(0.3, 0.55, 0.3), "Jacaré BJJ": Color(0.4, 0.45, 0.2), "Ilha Grappling": Color(0.2, 0.6, 0.75),
	"Cachoeira Team": Color(0.5, 0.75, 0.95), "Copacabana Top Team": Color(0.95, 0.75, 0.2), "Arpoador BJJ": Color(0.95, 0.5, 0.3),
	"Projeto Morro": Color(0.6, 0.3, 0.75)}
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
	"pantanal": [Vector3(-60, 0.8, -60), Vector3(-10, 0.8, 70), Vector3(70, 0.8, -70), Vector3(84, 0.8, 10), Vector3(20, 0.8, -12), Vector3(-75, 0.8, 60)],
	"chapada": [Vector3(-66, 0.8, -12), Vector3(60, 0.8, -60), Vector3(-10, 0.8, 70), Vector3(-30, 0.8, -78), Vector3(75, 0.8, 20), Vector3(12, 0.8, -4)],
	"rio": [Vector3(-14, 0.8, 50), Vector3(44, 0.8, 46), Vector3(-82, 0.8, 40), Vector3(-40, 0.8, -46), Vector3(52, 0.8, -60), Vector3(-56, 0.8, -8)],
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
	{"id": "jobs_done", "name": "Good Neighbor", "desc": "Help out around town 10 times.", "goal": 10},
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
			"opp": {"name": nm, "title": "%s Belt" % BELTS[belt].name, "rank": r, "level": 0.0,
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
}

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
		"obj": [{"type": "reach", "pos": Vector3(-58, 0, 36), "radius": 3.0, "text": "Find the belt on the riverbank"}]},
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
