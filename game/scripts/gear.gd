class_name Gear
extends RefCounted
## Gear, WoW-style: paper-doll slots, the quality ladder, item sets with 2/4-piece bonuses, and two
## kits (gi / no-gi) like saved equipment sets. Every item carries a `look` (colour, trim, pattern)
## that dresses the sculpted fighter model, so sets have a signature style (Onça rosettes, Jacaré
## scales, Véu waves, Leão's gold mane).
##
## Gis are authored once in GIS and become two items: the jacket (<id>) and the pants (<id>_pants).

const SLOTS := ["head", "jacket", "pants", "rash", "spats", "knees", "tape"]
const SLOT_NAMES := {"head": "Head", "jacket": "Gi Jacket", "pants": "Gi Pants", "rash": "Rashguard",
	"spats": "Spats", "knees": "Knee Sleeves", "tape": "Finger Tape"}
## Paper-doll columns (left / right of the character), like the WoW character pane.
const DOLL_LEFT := ["head", "jacket", "rash", "tape"]
const DOLL_RIGHT := ["pants", "spats", "knees"]
## Which slots count (and show) in each kit. Rashguards go under the gi too.
const KITS := {"gi": ["head", "jacket", "pants", "rash", "knees", "tape"], "nogi": ["head", "rash", "spats", "knees", "tape"]}
const KIT_NAMES := {"gi": "Gi", "nogi": "No-Gi"}

const RARITY := {
	"common": {"name": "Common", "color": Color(0.92, 0.92, 0.92)},
	"uncommon": {"name": "Uncommon", "color": Color(0.2, 0.9, 0.25)},
	"rare": {"name": "Rare", "color": Color(0.25, 0.55, 1.0)},
	"epic": {"name": "Epic", "color": Color(0.7, 0.35, 1.0)},
	"legendary": {"name": "Legendary", "color": Color(1.0, 0.55, 0.1)},
}

## Gis: jacket + matching pants. attrs go on the jacket, pants_attrs on the pants.
## look: color (cloth), trim (lapels/collar/cuffs), pattern + accent + pscale (shader pattern).
const GIS := {
	"standard_gi": {"name": "Standard Gi", "rarity": "common", "attrs": {}, "pants_attrs": {},
		"look": {"color": Color(0.96, 0.96, 0.94)},
		"source": "Your first gi", "desc": "Pearl weave, a little stiff, smells like new."},
	"terere_gi": {"name": "Tereré Green Gi", "rarity": "uncommon", "attrs": {"cardio": 1}, "pants_attrs": {},
		"look": {"color": Color(0.22, 0.5, 0.3), "trim": Color(0.95, 0.85, 0.4)},
		"source": "Quest: Tereré Run", "desc": "Dona Lurdes's late husband's gi. Still smells like lemon."},
	"onca_gi": {"name": "Onça Pintada Gi", "rarity": "rare", "set": "onca", "attrs": {"grip": 2, "strength": 1}, "pants_attrs": {"grip": 1},
		"look": {"color": Color(0.9, 0.68, 0.26), "trim": Color(0.12, 0.09, 0.07), "pattern": "spots", "accent": Color(0.14, 0.1, 0.07)},
		"source": "Mestre Onça", "desc": "Gold weave with black lapels. Onça's old competition gi."},
	"pantaneiro_gi": {"name": "Pantaneiro Gi", "rarity": "rare", "attrs": {"cardio": 2, "flexibility": 1}, "pants_attrs": {"cardio": 1},
		"look": {"color": Color(0.2, 0.45, 0.5), "trim": Color(0.85, 0.7, 0.4)},
		"source": "Quest: Submission Hunter", "desc": "Light enough to dry in the Pantanal sun in ten minutes."},
	"jacare_gi": {"name": "Jacaré Hide Gi", "rarity": "epic", "set": "jacare", "attrs": {"strength": 2, "grip": 2}, "pants_attrs": {"strength": 1, "flexibility": 1},
		"look": {"color": Color(0.32, 0.4, 0.2), "trim": Color(0.62, 0.56, 0.3), "pattern": "scales", "accent": Color(0.17, 0.22, 0.1)},
		"source": "Mestre Jacaré", "desc": "Heavy, rough and impossible to grip. Like its owner."},
	"red_cliff_gi": {"name": "Red Cliff Gi", "rarity": "rare", "attrs": {"flexibility": 2, "iq": 1}, "pants_attrs": {"flexibility": 1},
		"look": {"color": Color(0.7, 0.32, 0.2), "trim": Color(0.95, 0.9, 0.8), "pattern": "stripes", "accent": Color(0.6, 0.26, 0.16)},
		"source": "Quest: Crystal Clear", "desc": "Dyed with Chapada clay. Every wash it gets redder."},
	"veu_gi": {"name": "Véu de Noiva Gi", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 2, "cardio": 2}, "pants_attrs": {"cardio": 1, "iq": 1},
		"look": {"color": Color(0.72, 0.86, 0.96), "trim": Color(0.2, 0.35, 0.55), "pattern": "waves", "accent": Color(0.95, 0.98, 1.0)},
		"source": "Mestre Cachoeira", "desc": "Flows like the waterfall. Slips every grip."},
	"copacabana_gi": {"name": "Copacabana Gi", "rarity": "rare", "attrs": {"cardio": 1, "grip": 1, "iq": 1}, "pants_attrs": {"iq": 1},
		"look": {"color": Color(0.3, 0.6, 0.9), "trim": Color(0.98, 0.85, 0.2), "pattern": "waves", "accent": Color(0.25, 0.52, 0.82)},
		"source": "Quest: Beach Session", "desc": "Sky blue with gold collar. Sand not included (it's included)."},
	"leao_gi": {"name": "Lion's Mane Gi", "rarity": "legendary", "set": "leao", "attrs": {"strength": 2, "grip": 2, "iq": 2}, "pants_attrs": {"strength": 1, "iq": 1},
		"look": {"color": Color(0.08, 0.08, 0.09), "trim": Color(0.95, 0.72, 0.2), "pattern": "mane", "accent": Color(0.85, 0.6, 0.15)},
		"source": "Grão-Mestre Leão", "desc": "Black with a gold collar. Leão wore it to his first world title."},
	"mundial_gi": {"name": "Campeão Mundial Gi", "rarity": "legendary", "set": "mundial", "attrs": {"strength": 2, "grip": 2, "cardio": 2, "flexibility": 2, "iq": 2}, "pants_attrs": {"cardio": 1, "grip": 1},
		"look": {"color": Color(0.97, 0.97, 0.95), "trim": Color(0.95, 0.72, 0.2)},
		"source": "Gold at the Campeonato Mundial", "desc": "White and gold. Only world champions wear this one."},
	# ---------------- faction war sets: bought with Honor from your faction's quartermaster
	"selecao_gi": {"name": "Seleção Gi", "rarity": "epic", "set": "selecao", "faction": "brasil", "attrs": {"cardio": 2, "flexibility": 2}, "pants_attrs": {"cardio": 1, "iq": 1},
		"look": {"color": Color(0.98, 0.84, 0.16), "trim": Color(0.08, 0.5, 0.25), "pattern": "stripes", "accent": Color(0.1, 0.55, 0.3)},
		"source": "Time Brasil quartermaster · Honor", "desc": "Canary yellow with a green collar. Wear it and the whole country rolls with you."},
	"old_glory_gi": {"name": "Old Glory Gi", "rarity": "epic", "set": "old_glory", "faction": "usa", "attrs": {"strength": 2, "grip": 2}, "pants_attrs": {"strength": 1, "iq": 1},
		"look": {"color": Color(0.1, 0.16, 0.42), "trim": Color(0.75, 0.12, 0.16), "pattern": "stripes", "accent": Color(0.95, 0.95, 0.97)},
		"source": "Team USA quartermaster · Honor", "desc": "Navy, red collar, white pinstripes. Made in a garage in Ohio."},
	# ---------------- class tier sets (WoW "tier"): class-locked, from the raid and elite bosses
	"polvo_gi": {"name": "Polvo Gi", "rarity": "epic", "set": "polvo", "class": "guard", "attrs": {"flexibility": 2, "iq": 2}, "pants_attrs": {"flexibility": 2},
		"look": {"color": Color(0.1, 0.36, 0.34), "trim": Color(0.33, 0.8, 0.5), "pattern": "waves", "accent": Color(0.2, 0.62, 0.5)},
		"source": "Guard Player tier · Covil da Sucuri, elite bosses", "desc": "Eight arms, no exits. Woven to cling."},
	"garca_gi": {"name": "Garça Real Judogi", "rarity": "epic", "set": "garca", "class": "judoka", "attrs": {"grip": 2, "strength": 2}, "pants_attrs": {"grip": 2},
		"look": {"color": Color(0.94, 0.95, 0.97), "trim": Color(0.12, 0.25, 0.6), "pattern": "feathers", "accent": Color(0.62, 0.74, 0.95), "pscale": 0.8},
		"source": "Judoka tier · Covil da Sucuri, elite bosses", "desc": "Double weave, heron-white. The collar alone weighs a kilo."},
	"tatu_gi": {"name": "Tatu Couraça Gi", "rarity": "epic", "set": "tatu", "class": "passer", "attrs": {"strength": 2, "grip": 2}, "pants_attrs": {"strength": 2},
		"look": {"color": Color(0.16, 0.14, 0.2), "trim": Color(0.66, 0.44, 0.95), "pattern": "scales", "accent": Color(0.3, 0.22, 0.42)},
		"source": "Pressure Passer tier · Covil da Sucuri, elite bosses", "desc": "Armadillo plates. You don't pass a guard in this, you flatten it."},
}

## Everything that isn't a gi. look as above.
const OTHER := {
	# ---------------- rashguards (under the gi at the collar, or the whole top in no-gi)
	"rash_white": {"slot": "rash", "name": "Ranked Rashguard (White)", "rarity": "common", "attrs": {},
		"look": {"color": Color(0.95, 0.95, 0.93)}, "source": "Starter gear", "desc": "Everyone starts somewhere."},
	"rash_blue": {"slot": "rash", "name": "Ranked Rashguard (Blue)", "rarity": "uncommon", "attrs": {"cardio": 1},
		"look": {"color": Color(0.15, 0.35, 0.85)}, "source": "Promotion to blue belt", "desc": "Ranked colors, blue belt edition."},
	"rash_purple": {"slot": "rash", "name": "Ranked Rashguard (Purple)", "rarity": "uncommon", "attrs": {"cardio": 1, "flexibility": 1},
		"look": {"color": Color(0.45, 0.2, 0.65)}, "source": "Promotion to purple belt", "desc": "Ranked colors, purple belt edition."},
	"rash_brown": {"slot": "rash", "name": "Ranked Rashguard (Brown)", "rarity": "rare", "attrs": {"cardio": 1, "strength": 1, "iq": 1},
		"look": {"color": Color(0.42, 0.26, 0.13)}, "source": "Promotion to brown belt", "desc": "Ranked colors, brown belt edition."},
	"rash_black": {"slot": "rash", "name": "Ranked Rashguard (Black)", "rarity": "epic", "attrs": {"cardio": 2, "strength": 1, "iq": 1},
		"look": {"color": Color(0.08, 0.08, 0.08)}, "source": "Promotion to black belt", "desc": "Ranked colors. The last one."},
	"rash_arara": {"slot": "rash", "name": "Arara Rashguard", "rarity": "rare", "attrs": {"flexibility": 1, "cardio": 1},
		"look": {"color": Color(0.9, 0.2, 0.15), "pattern": "feathers", "accent": Color(0.15, 0.4, 0.9)},
		"source": "Quest: Feathers for the Festival", "desc": "Red, blue and gold, like the birds."},
	"rash_projeto": {"slot": "rash", "name": "Projeto Social Rashguard", "rarity": "epic", "attrs": {"iq": 2, "cardio": 1},
		"look": {"color": Color(0.98, 0.8, 0.2), "pattern": "stripes", "accent": Color(0.15, 0.5, 0.25)},
		"source": "Quest: Kids' Class", "desc": "Signed by forty kids from the morro."},
	"jacare_rash": {"slot": "rash", "name": "Jacaré Hide Rashguard", "rarity": "epic", "set": "jacare", "attrs": {"strength": 1, "cardio": 1},
		"look": {"color": Color(0.26, 0.32, 0.16), "pattern": "scales", "accent": Color(0.14, 0.18, 0.08)},
		"source": "Mestre Jacaré", "desc": "Second skin, swamp edition."},
	"veu_rash": {"slot": "rash", "name": "Véu de Noiva Rashguard", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 1, "cardio": 1},
		"look": {"color": Color(0.18, 0.32, 0.52), "pattern": "waves", "accent": Color(0.7, 0.86, 0.96)},
		"source": "Mestre Cachoeira", "desc": "Cold as the pool under the falls."},
	"familia_rash": {"slot": "rash", "name": "Família Rashguard", "rarity": "rare", "set": "familia", "attrs": {"cardio": 1, "iq": 1},
		"look": {"color": Color(0.1, 0.45, 0.3), "pattern": "stripes", "accent": Color(0.98, 0.8, 0.2)},
		"source": "Team Challenge wins", "desc": "Green and gold. Everyone on the team signed the sleeve."},
	"rash_circuito": {"slot": "rash", "name": "Circuito Champion Rashguard", "rarity": "epic", "attrs": {"iq": 2, "grip": 1, "cardio": 1},
		"look": {"color": Color(0.08, 0.08, 0.1), "pattern": "stripes", "accent": Color(0.97, 0.77, 0.28)},
		"source": "Win a Circuito run", "desc": "Five matches, one life. You wore the whole road on your back."},
	"selecao_rash": {"slot": "rash", "name": "Seleção Rashguard", "rarity": "epic", "set": "selecao", "faction": "brasil", "attrs": {"cardio": 1, "flexibility": 1},
		"look": {"color": Color(0.08, 0.5, 0.25), "pattern": "stripes", "accent": Color(0.98, 0.84, 0.16)},
		"source": "Time Brasil quartermaster · Honor", "desc": "Green and gold, number 10 on the back."},
	"old_glory_rash": {"slot": "rash", "name": "Old Glory Rashguard", "rarity": "epic", "set": "old_glory", "faction": "usa", "attrs": {"strength": 1, "cardio": 1},
		"look": {"color": Color(0.95, 0.95, 0.97), "pattern": "stripes", "accent": Color(0.75, 0.12, 0.16)},
		"source": "Team USA quartermaster · Honor", "desc": "Red and white stripes. Subtle, it is not."},
	# ---------------- spats (no-gi)
	"spats_black": {"slot": "spats", "name": "Training Spats", "rarity": "common", "attrs": {},
		"look": {"color": Color(0.1, 0.1, 0.12)}, "source": "Starter gear", "desc": "Black, plain, honest."},
	"veu_spats": {"slot": "spats", "name": "Véu de Noiva Spats", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 2},
		"look": {"color": Color(0.18, 0.32, 0.52), "pattern": "waves", "accent": Color(0.7, 0.86, 0.96)},
		"source": "Mestre Cachoeira", "desc": "Matching set. The waterfall approves."},
	"familia_spats": {"slot": "spats", "name": "Família Spats", "rarity": "rare", "set": "familia", "attrs": {"flexibility": 1, "cardio": 1},
		"look": {"color": Color(0.1, 0.45, 0.3), "pattern": "stripes", "accent": Color(0.98, 0.8, 0.2)},
		"source": "Team Challenge wins", "desc": "Matching. Obviously."},
	"selecao_spats": {"slot": "spats", "name": "Seleção Spats", "rarity": "epic", "set": "selecao", "faction": "brasil", "attrs": {"flexibility": 2},
		"look": {"color": Color(0.1, 0.2, 0.55), "pattern": "stripes", "accent": Color(0.98, 0.84, 0.16)},
		"source": "Time Brasil quartermaster · Honor", "desc": "Blue like the shorts. Gold stripe down the side."},
	"old_glory_spats": {"slot": "spats", "name": "Old Glory Spats", "rarity": "epic", "set": "old_glory", "faction": "usa", "attrs": {"strength": 1, "grip": 1},
		"look": {"color": Color(0.1, 0.16, 0.42), "pattern": "stripes", "accent": Color(0.95, 0.95, 0.97)},
		"source": "Team USA quartermaster · Honor", "desc": "Navy with white stars down the leg."},
	# ---------------- knees
	"jacare_knees": {"slot": "knees", "name": "Jacaré Knee Sleeves", "rarity": "epic", "set": "jacare", "attrs": {"strength": 1, "flexibility": 1},
		"look": {"color": Color(0.2, 0.24, 0.12), "pattern": "scales", "accent": Color(0.12, 0.15, 0.07)},
		"source": "Mestre Jacaré", "desc": "Armour for the knee-slice."},
	"familia_knees": {"slot": "knees", "name": "Família Knee Sleeves", "rarity": "rare", "set": "familia", "attrs": {"cardio": 1},
		"look": {"color": Color(0.98, 0.8, 0.2)}, "source": "Team Challenge wins", "desc": "For the long nights in the team room."},
	# ---------------- head
	"onca_headband": {"slot": "head", "name": "Onça Headband", "rarity": "rare", "set": "onca", "attrs": {"iq": 1}, "piece": "Headband",
		"look": {"color": Color(0.9, 0.68, 0.26), "pattern": "spots", "accent": Color(0.14, 0.1, 0.07), "pscale": 1.6},
		"source": "Mestre Onça", "desc": "Keeps the sweat out of your eyes and the fear in theirs."},
	"leao_earguards": {"slot": "head", "name": "Lion's Ear Guards", "rarity": "legendary", "set": "leao", "attrs": {"iq": 1, "strength": 1}, "piece": "EarGuards",
		"look": {"color": Color(0.1, 0.1, 0.11), "pattern": "mane", "accent": Color(0.9, 0.65, 0.15)},
		"source": "Grão-Mestre Leão", "desc": "No cauliflower for kings."},
	# ---------------- finger tape
	"tape_basic": {"slot": "tape", "name": "Finger Tape", "rarity": "uncommon", "attrs": {"grip": 1},
		"look": {"color": Color(0.96, 0.96, 0.92)}, "source": "Quest: Shrimping 101", "desc": "Kaique's spare roll. Tape the ring and middle fingers."},
	"tape_climber": {"slot": "tape", "name": "Climber's Tape", "rarity": "rare", "attrs": {"grip": 2},
		"look": {"color": Color(0.85, 0.75, 0.55)}, "source": "Quest: Iron Grip", "desc": "Nanda swears by it on the cliffs."},
	"tape_pro": {"slot": "tape", "name": "Competition Tape", "rarity": "epic", "attrs": {"grip": 3},
		"look": {"color": Color(0.2, 0.2, 0.22)}, "source": "Gold medal at any competition", "desc": "Pre-cut strips, perfect tension, podium-tested."},
	"familia_tape": {"slot": "tape", "name": "Família Tape", "rarity": "rare", "set": "familia", "attrs": {"grip": 1, "cardio": 1},
		"look": {"color": Color(0.1, 0.45, 0.3)}, "source": "Team Challenge wins", "desc": "Green tape, gold pen: your teammates' initials."},
	"onca_tape": {"slot": "tape", "name": "Onça Claw Tape", "rarity": "rare", "set": "onca", "attrs": {"grip": 2},
		"look": {"color": Color(0.12, 0.09, 0.07)}, "source": "Mestre Onça", "desc": "Black tape. Grips like claws."},
	"leao_tape": {"slot": "tape", "name": "Lion's Paw Tape", "rarity": "legendary", "set": "leao", "attrs": {"grip": 3},
		"look": {"color": Color(0.95, 0.72, 0.2)}, "source": "Grão-Mestre Leão", "desc": "Gold tape. You will be seen."},
	"selecao_tape": {"slot": "tape", "name": "Seleção Tape", "rarity": "epic", "set": "selecao", "faction": "brasil", "attrs": {"grip": 2, "iq": 1},
		"look": {"color": Color(0.98, 0.84, 0.16)}, "source": "Time Brasil quartermaster · Honor", "desc": "Gold tape. Ordem e progresso on the thumb."},
	"old_glory_tape": {"slot": "tape", "name": "Old Glory Tape", "rarity": "epic", "set": "old_glory", "faction": "usa", "attrs": {"grip": 2, "strength": 1},
		"look": {"color": Color(0.75, 0.12, 0.16)}, "source": "Team USA quartermaster · Honor", "desc": "Red tape, wrapped tight, no excuses."},
	# ---------------- class starter kits (class-locked; given when you pick your class)
	"singlet_red": {"slot": "rash", "name": "Wrestling Singlet Top", "rarity": "common", "class": "wrestler", "attrs": {},
		"look": {"color": Color(0.78, 0.16, 0.16)}, "source": "Wrestler starter kit", "desc": "Your high school colours. Still fits. Mostly."},
	"singlet_spats": {"slot": "spats", "name": "Wrestling Singlet Shorts", "rarity": "common", "class": "wrestler", "attrs": {},
		"look": {"color": Color(0.78, 0.16, 0.16)}, "source": "Wrestler starter kit", "desc": "One-piece, technically."},
	"wrestling_ears": {"slot": "head", "name": "Wrestling Headgear", "rarity": "common", "class": "wrestler", "attrs": {}, "piece": "EarGuards",
		"look": {"color": Color(0.12, 0.12, 0.14)}, "source": "Wrestler starter kit", "desc": "Too late for your left ear."},
	"athlete_rash": {"slot": "rash", "name": "Comp Team Rashguard", "rarity": "common", "class": "athlete", "attrs": {},
		"look": {"color": Color(1.0, 0.55, 0.12)}, "source": "Athlete starter kit", "desc": "Sponsored by an açaí stand."},
	"athlete_spats": {"slot": "spats", "name": "Sprint Spats", "rarity": "common", "class": "athlete", "attrs": {},
		"look": {"color": Color(0.1, 0.1, 0.12), "pattern": "stripes", "accent": Color(1.0, 0.55, 0.12), "pscale": 1.6}, "source": "Athlete starter kit", "desc": "Compression for the 6am run."},
	"athlete_band": {"slot": "head", "name": "Sweatband", "rarity": "common", "class": "athlete", "attrs": {}, "piece": "Headband",
		"look": {"color": Color(1.0, 0.62, 0.16)}, "source": "Athlete starter kit", "desc": "Soaked by round two."},
	"guard_knees": {"slot": "knees", "name": "Guard Player's Knee Pads", "rarity": "common", "class": "guard", "attrs": {},
		"look": {"color": Color(0.2, 0.5, 0.32)}, "source": "Guard Player starter kit", "desc": "For pulling guard on concrete. Don't."},
	"judo_tape": {"slot": "tape", "name": "Judo Finger Tape", "rarity": "common", "class": "judoka", "attrs": {},
		"look": {"color": Color(0.96, 0.96, 0.92)}, "source": "Judoka starter kit", "desc": "Taped for the collar war."},
	"passer_knees": {"slot": "knees", "name": "Heavy Knee Sleeves", "rarity": "common", "class": "passer", "attrs": {},
		"look": {"color": Color(0.22, 0.16, 0.3)}, "source": "Pressure Passer starter kit", "desc": "Knee-cut insurance."},
	# ---------------- class tier set pieces (no-gi classes + gi extras)
	"polvo_knees": {"slot": "knees", "name": "Polvo Knee Sleeves", "rarity": "epic", "set": "polvo", "class": "guard", "attrs": {"flexibility": 2, "cardio": 1},
		"look": {"color": Color(0.1, 0.36, 0.34), "pattern": "waves", "accent": Color(0.2, 0.62, 0.5)}, "source": "Guard Player tier · Covil da Sucuri, elite bosses", "desc": "Suction-cup grip on every hook."},
	"polvo_tape": {"slot": "tape", "name": "Polvo Ink Tape", "rarity": "epic", "set": "polvo", "class": "guard", "attrs": {"grip": 2, "iq": 1},
		"look": {"color": Color(0.08, 0.12, 0.14)}, "source": "Guard Player tier · Covil da Sucuri, elite bosses", "desc": "Ink-black. Every finger a tentacle."},
	"garca_band": {"slot": "head", "name": "Garça Hachimaki", "rarity": "epic", "set": "garca", "class": "judoka", "attrs": {"iq": 2, "grip": 1}, "piece": "Headband",
		"look": {"color": Color(0.94, 0.95, 0.97), "pattern": "feathers", "accent": Color(0.12, 0.25, 0.6)}, "source": "Judoka tier · Covil da Sucuri, elite bosses", "desc": "One stance, one breath, one throw."},
	"garca_tape": {"slot": "tape", "name": "Garça Collar Tape", "rarity": "epic", "set": "garca", "class": "judoka", "attrs": {"grip": 3},
		"look": {"color": Color(0.12, 0.25, 0.6)}, "source": "Judoka tier · Covil da Sucuri, elite bosses", "desc": "The heron's beak. Lapels fear it."},
	"tatu_rash": {"slot": "rash", "name": "Tatu Plated Rashguard", "rarity": "epic", "set": "tatu", "class": "passer", "attrs": {"strength": 2, "cardio": 1},
		"look": {"color": Color(0.16, 0.14, 0.2), "pattern": "scales", "accent": Color(0.42, 0.3, 0.6)}, "source": "Pressure Passer tier · Covil da Sucuri, elite bosses", "desc": "Under the gi, more armour."},
	"tatu_knees": {"slot": "knees", "name": "Tatu Knee Plates", "rarity": "epic", "set": "tatu", "class": "passer", "attrs": {"strength": 1, "flexibility": 2},
		"look": {"color": Color(0.3, 0.22, 0.42), "pattern": "scales", "accent": Color(0.16, 0.14, 0.2)}, "source": "Pressure Passer tier · Covil da Sucuri, elite bosses", "desc": "Rolls up into a ball. So will they."},
	"touro_rash": {"slot": "rash", "name": "Touro Singlet Top", "rarity": "epic", "set": "touro", "class": "wrestler", "attrs": {"strength": 2, "cardio": 2},
		"look": {"color": Color(0.6, 0.07, 0.08)}, "source": "Wrestler tier · Covil da Sucuri, elite bosses", "desc": "Red rag. Bull inside."},
	"touro_spats": {"slot": "spats", "name": "Touro Singlet Shorts", "rarity": "epic", "set": "touro", "class": "wrestler", "attrs": {"strength": 2, "cardio": 1},
		"look": {"color": Color(0.5, 0.05, 0.06)}, "source": "Wrestler tier · Covil da Sucuri, elite bosses", "desc": "Low centre of gravity, high output."},
	"touro_ears": {"slot": "head", "name": "Touro Horned Headgear", "rarity": "epic", "set": "touro", "class": "wrestler", "attrs": {"iq": 1, "strength": 1}, "piece": "EarGuards",
		"look": {"color": Color(0.95, 0.75, 0.25), "pattern": "stripes", "accent": Color(0.62, 0.08, 0.08)}, "source": "Wrestler tier · Covil da Sucuri, elite bosses", "desc": "Gold straps. Head down, drive through."},
	"touro_knees": {"slot": "knees", "name": "Touro Shot Pads", "rarity": "epic", "set": "touro", "class": "wrestler", "attrs": {"strength": 1, "flexibility": 1},
		"look": {"color": Color(0.12, 0.1, 0.1)}, "source": "Wrestler tier · Covil da Sucuri, elite bosses", "desc": "For a thousand double legs."},
	"lobo_rash": {"slot": "rash", "name": "Lobo-Guará Rashguard", "rarity": "epic", "set": "lobo", "class": "athlete", "attrs": {"cardio": 2, "flexibility": 2},
		"look": {"color": Color(0.85, 0.4, 0.12), "pattern": "mane", "accent": Color(0.1, 0.08, 0.06)}, "source": "Athlete tier · Covil da Sucuri, elite bosses", "desc": "Red coat, black mane, long legs. Runs all night."},
	"lobo_spats": {"slot": "spats", "name": "Lobo-Guará Spats", "rarity": "epic", "set": "lobo", "class": "athlete", "attrs": {"cardio": 2, "strength": 1},
		"look": {"color": Color(0.1, 0.08, 0.06), "pattern": "stripes", "accent": Color(0.85, 0.4, 0.12), "pscale": 1.6}, "source": "Athlete tier · Covil da Sucuri, elite bosses", "desc": "Black stockings, like the wolf's."},
	"lobo_band": {"slot": "head", "name": "Lobo-Guará Headband", "rarity": "epic", "set": "lobo", "class": "athlete", "attrs": {"iq": 1, "cardio": 1}, "piece": "Headband",
		"look": {"color": Color(0.85, 0.4, 0.12)}, "source": "Athlete tier · Covil da Sucuri, elite bosses", "desc": "Big ears, sharper reads."},
	"lobo_tape": {"slot": "tape", "name": "Lobo-Guará Tape", "rarity": "epic", "set": "lobo", "class": "athlete", "attrs": {"grip": 2, "cardio": 1},
		"look": {"color": Color(0.1, 0.08, 0.06)}, "source": "Athlete tier · Covil da Sucuri, elite bosses", "desc": "Light grip, fast hands."},
}

## Item sets. Bonuses unlock at 2 and 4 equipped pieces (in the active kit). An effect id hooks
## into the roll (see Game.mods and RollSim).
const SETS := {
	"onca": {"name": "Onça Pintada", "pieces": ["onca_gi", "onca_gi_pants", "onca_tape", "onca_headband"],
		"bonus": {2: {"attrs": {"grip": 1}}, 4: {"effect": "pounce", "text": "Pounce: you start every new position with 1 Grip Control."}}},
	"jacare": {"name": "Couro de Jacaré", "pieces": ["jacare_gi", "jacare_gi_pants", "jacare_rash", "jacare_knees"],
		"bonus": {2: {"attrs": {"strength": 1}}, 4: {"effect": "death_roll", "text": "Death Roll: your landed sweeps and takedowns drain 15 of their stamina."}}},
	"veu": {"name": "Véu de Noiva", "pieces": ["veu_gi", "veu_gi_pants", "veu_rash", "veu_spats"],
		"bonus": {2: {"attrs": {"flexibility": 1}}, 4: {"effect": "flow", "text": "Flow: every interrupt refunds 6 stamina."}}},
	"leao": {"name": "Juba do Leão", "pieces": ["leao_gi", "leao_gi_pants", "leao_earguards", "leao_tape"],
		"bonus": {2: {"attrs": {"iq": 1}}, 4: {"effect": "roar", "text": "Roar: their casts take 10% longer."}}},
	"familia": {"name": "Família", "pieces": ["familia_rash", "familia_spats", "familia_knees", "familia_tape"],
		"bonus": {2: {"attrs": {"cardio": 1}}, 4: {"effect": "second_breath", "text": "Second Breath: Breathe restores 30 stamina instead of 20."}}},
	"mundial": {"name": "Campeão Mundial", "pieces": ["mundial_gi", "mundial_gi_pants"],
		"bonus": {2: {"effect": "champion", "text": "Champion: your techniques are 4% more likely to land."}}},
	"selecao": {"name": "Seleção (Time Brasil)", "faction": "brasil", "pieces": ["selecao_gi", "selecao_gi_pants", "selecao_rash", "selecao_spats", "selecao_tape"],
		"bonus": {2: {"attrs": {"cardio": 1}}, 4: {"mods": {"zone": {"sweep": 0.08, "sub": 0.06}, "dr": 0.03}, "text": "Jogo Bonito: sweeps hit 8% harder, submissions 6%; take 3% less damage."}}},
	"old_glory": {"name": "Old Glory (Team USA)", "faction": "usa", "pieces": ["old_glory_gi", "old_glory_gi_pants", "old_glory_rash", "old_glory_spats", "old_glory_tape"],
		"bonus": {2: {"attrs": {"strength": 1}}, 4: {"mods": {"zone": {"takedown": 0.08, "pass": 0.06}, "dr": 0.03}, "text": "Ground and Pound: takedowns hit 8% harder, passes 6%; take 3% less damage."}}},
	# class tier sets: 4-piece bonuses feed the real-time combat mods (Game.mods)
	"polvo": {"name": "Polvo (Guard Player tier)", "class": "guard", "pieces": ["polvo_gi", "polvo_gi_pants", "polvo_knees", "polvo_tape"],
		"bonus": {2: {"attrs": {"flexibility": 2}}, 4: {"mods": {"zone": {"sweep": 0.12, "sub": 0.06}}, "text": "Eight Arms: sweeps hit 12% harder, submissions 6% harder."}}},
	"garca": {"name": "Garça Real (Judoka tier)", "class": "judoka", "pieces": ["garca_gi", "garca_gi_pants", "garca_band", "garca_tape"],
		"bonus": {2: {"attrs": {"grip": 2}}, 4: {"mods": {"grip_start": 1.0, "zone": {"takedown": 0.1}}, "text": "Heron's Beak: start every fight with 1 Grip; throws and takedowns hit 10% harder."}}},
	"tatu": {"name": "Tatu Couraça (Passer tier)", "class": "passer", "pieces": ["tatu_gi", "tatu_gi_pants", "tatu_rash", "tatu_knees"],
		"bonus": {2: {"attrs": {"strength": 2}}, 4: {"mods": {"zone": {"pass": 0.12, "advance": 0.08}, "dr": 0.04}, "text": "Armour Plates: passes hit 12% harder, advances 8%; take 4% less damage."}}},
	"touro": {"name": "Touro (Wrestler tier)", "class": "wrestler", "pieces": ["touro_rash", "touro_spats", "touro_ears", "touro_knees"],
		"bonus": {2: {"attrs": {"strength": 2}}, 4: {"mods": {"zone": {"takedown": 0.14}, "dr": 0.05}, "text": "Bull Rush: takedowns hit 14% harder; take 5% less damage."}}},
	"lobo": {"name": "Lobo-Guará (Athlete tier)", "class": "athlete", "pieces": ["lobo_rash", "lobo_spats", "lobo_band", "lobo_tape"],
		"bonus": {2: {"attrs": {"cardio": 2}}, 4: {"mods": {"regen": 0.25, "zone": {"escape": 0.12}}, "text": "Long Legs: +25% Gas regeneration; escapes hit 12% harder."}}},
}

## Bosses drop pieces of their set (one you don't own each win, the jacket first).
const BOSS_SET := {"onca": "onca", "jacare": "jacare", "cachoeira": "veu", "leao": "leao"}
const QUEST_LOOT := {"terere_run": "terere_gi", "shrimping": "tape_basic", "sub_hunter": "pantaneiro_gi",
	"festival_feathers": "rash_arara", "crystal_clear": "red_cliff_gi", "iron_grip": "tape_climber",
	"beach_session": "copacabana_gi", "kids_class": "rash_projeto"}
const PROMOTION_LOOT := {1: "rash_blue", 2: "rash_purple", 3: "rash_brown", 4: "rash_black"}
## Items that come as a pair: getting the jacket also gives the pants (quests, medals).
const STARTER := ["standard_gi", "standard_gi_pants", "rash_white", "spats_black"]

static var ITEMS := {}

## Item level: where a piece comes from sets how strong it is (WoW-style). Every piece adds
## Composure (flat health) and Power (% damage) from ilvl x rarity x slot, on top of its attributes.
const RARITY_MULT := {"common": 0.6, "uncommon": 0.8, "rare": 1.0, "epic": 1.25, "legendary": 1.5}
const SLOT_WEIGHT := {"jacket": 1.0, "pants": 0.8, "rash": 0.7, "spats": 0.6, "knees": 0.5, "head": 0.5, "tape": 0.5}
const RARITY_ILVL := {"common": 2, "uncommon": 6, "rare": 12, "epic": 20, "legendary": 30}
const ILVL := {"standard_gi": 1, "rash_white": 1, "spats_black": 1,
	"familia": 16, "rash_circuito": 28, "tape_pro": 22, "mundial_gi": 48,
	"polvo": 34, "garca": 34, "tatu": 34, "touro": 34, "lobo": 34, "selecao": 38, "old_glory": 38}

## Faction quartermasters: Honor prices (Honor = every war point you earn).
const HONOR_PRICES := {"selecao_gi": 900, "selecao_gi_pants": 700, "selecao_rash": 600, "selecao_spats": 600, "selecao_tape": 450,
	"old_glory_gi": 900, "old_glory_gi_pants": 700, "old_glory_rash": 600, "old_glory_spats": 600, "old_glory_tape": 450}
const HONOR_MIN_LEVEL := 20

## Class starter kits (given when the class is picked; the no-gi classes start in no-gi).
const CLASS_KIT := {"guard": ["guard_knees"], "wrestler": ["singlet_red", "singlet_spats", "wrestling_ears"],
	"judoka": ["judo_tape"], "athlete": ["athlete_rash", "athlete_spats", "athlete_band"], "passer": ["passer_knees"]}
const CLASS_SET := {"guard": "polvo", "judoka": "garca", "passer": "tatu", "wrestler": "touro", "athlete": "lobo"}

## Class-locked pieces (starter kits, tier sets) only go on that class, like WoW armour types.
static func class_ok(id: String, st: String) -> bool:
	var c := str(ITEMS.get(id, {}).get("class", ""))
	return c == "" or c == st

static func class_of(id: String) -> String:
	return str(ITEMS.get(id, {}).get("class", ""))
const PROMOTION_ILVL := {1: 10, 2: 20, 3: 30, 4: 42}

static func _static_init() -> void:
	for id in GIS:
		var g: Dictionary = GIS[id]
		var base := {"rarity": g.rarity, "look": g.look, "source": g.source}
		if g.has("set"):
			base["set"] = g.set
		if g.has("class"):
			base["class"] = g["class"]
		if g.has("faction"):
			base["faction"] = g.faction
		var j := base.duplicate()
		j.merge({"slot": "jacket", "name": g.name + " Jacket", "attrs": g.attrs, "desc": g.desc, "gi": id})
		ITEMS[id] = j
		var p := base.duplicate()
		p.merge({"slot": "pants", "name": g.name + " Pants", "attrs": g.pants_attrs, "desc": "Matching pants.", "gi": id})
		ITEMS[id + "_pants"] = p
	for id in OTHER:
		ITEMS[id] = (OTHER[id] as Dictionary).duplicate(true)
	for id in ITEMS:
		ITEMS[id]["ilvl"] = _source_ilvl(id)

static func _source_ilvl(id: String) -> int:
	var it: Dictionary = ITEMS[id]
	var base := id.trim_suffix("_pants")
	if ILVL.has(base):
		return ILVL[base]
	if it.has("set") and ILVL.has(str(it.set)):
		return ILVL[str(it.set)]
	if it.has("set"):
		for boss in BOSS_SET:
			if BOSS_SET[boss] == it.set and Data.OPPONENTS.has(boss):
				return Data.display_level(float(Data.OPPONENTS[boss].level)) + 1
	for q in QUEST_LOOT:
		if QUEST_LOOT[q] == base and Data.QUESTS.has(q):
			return int(Data.QUESTS[q].get("min_level", 1)) + 2
	for b in PROMOTION_LOOT:
		if PROMOTION_LOOT[b] == id:
			return PROMOTION_ILVL[b]
	return RARITY_ILVL.get(str(it.get("rarity", "common")), 2)

# ------------------------------------------------------------------ rolled drops (WoW-style)
## Mob gear is rolled when it drops: base piece + rarity + item level (the mob's) + a Pantanal
## animal suffix that decides which two attributes it carries ("Sturdy Spats of the Caiman").
const ROLL_BASES := {
	"rash": {"name": "Rashguard"}, "spats": {"name": "Spats"}, "knees": {"name": "Knee Sleeves"},
	"tape": {"name": "Finger Tape"}, "head": {"name": "Headband", "piece": "Headband"}}
const SUFFIXES := {
	"of the Jaguar": ["strength", "grip"], "of the Caiman": ["strength", "flexibility"],
	"of the Capybara": ["cardio", "flexibility"], "of the Macaw": ["flexibility", "iq"],
	"of the Anaconda": ["grip", "cardio"], "of the Owl": ["iq", "cardio"], "of the Piranha": ["strength", "iq"],
	"of the Jabiru": ["flexibility", "grip"], "of the Tapir": ["strength", "cardio"], "of the Otter": ["grip", "iq"]}
const ROLL_PREFIX := {"common": "Worn", "uncommon": "Sturdy", "rare": "Pantanal", "epic": "Mestre's"}
const ROLL_PALETTE := ["1f3a8a", "0f766e", "7c2d12", "111827", "6b21a8", "b45309", "be123c", "e5e7eb", "166534", "1e40af"]

## A new rolled piece as plain (saveable) data. lv = the dropper's display level.
static func roll(lv: int, rng: RandomNumberGenerator, elite := false, rare := false) -> Dictionary:
	var slots := ROLL_BASES.keys()
	var slot: String = slots[rng.randi() % slots.size()]
	var r := rng.randf() - (0.12 if elite else 0.0) - (0.45 if rare else 0.0)
	var rq := "common" if r > 0.55 else ("uncommon" if r > 0.17 else ("rare" if r > 0.02 else "epic"))
	var sfx: Array = SUFFIXES.keys()
	var suffix: String = sfx[rng.randi() % sfx.size()]
	var pair: Array = SUFFIXES[suffix]
	# stat points: rarity sets the base, item level adds more
	var pts: int = {"common": 1, "uncommon": 2, "rare": 3, "epic": 4}[rq] + int(lv / 12)
	var attrs := {}
	for i in pts:
		var k: String = pair[i % 2]
		attrs[k] = int(attrs.get(k, 0)) + 1
	var base: Dictionary = ROLL_BASES[slot]
	return {"slot": slot, "rarity": rq, "ilvl": maxi(1, lv + rng.randi_range(-1, 1)), "attrs": attrs,
		"name": "%s %s %s" % [ROLL_PREFIX[rq], base.name, suffix], "color": ROLL_PALETTE[rng.randi() % ROLL_PALETTE.size()],
		"piece": str(base.get("piece", ""))}

## Make a rolled piece known to the item table (on drop and when a save loads).
static func register_rolled(id: String, d: Dictionary) -> void:
	var it := {"slot": str(d.slot), "name": str(d.name), "rarity": str(d.rarity), "attrs": d.get("attrs", {}),
		"look": {"color": Color.html(str(d.get("color", "e5e7eb")))}, "ilvl": int(d.get("ilvl", 1)), "rolled": true,
		"source": "Dropped in the wild", "desc": "Nobody else has this exact one."}
	if str(d.get("piece", "")) != "":
		it["piece"] = str(d.piece)
	ITEMS[id] = it

static func ilvl(id: String) -> int:
	return int(ITEMS.get(id, {}).get("ilvl", 1))

static func _budget(id: String) -> float:
	var it: Dictionary = ITEMS[id]
	return float(ilvl(id)) * float(RARITY_MULT.get(str(it.rarity), 0.6)) * float(SLOT_WEIGHT.get(str(it.slot), 0.5))

## Flat Composure (health) this piece adds.
static func composure(id: String) -> int:
	return int(round(1.5 * _budget(id)))

## Power: % damage this piece adds (0.18% per budget point).
static func power_pct(id: String) -> float:
	return snappedf(0.18 * _budget(id), 0.1)

## One number to compare pieces in the same slot (auto-equip, upgrade arrows).
static func score(id: String) -> float:
	return _budget(id) * 2.0 + float(power(id)) * 3.0

static func power(id: String) -> int:
	var n := 0
	for k in ITEMS[id].attrs:
		n += int(ITEMS[id].attrs[k])
	return n

static func rarity_color(id: String) -> Color:
	return RARITY[ITEMS[id].rarity].color

static func look(id: String) -> Dictionary:
	return ITEMS.get(id, {}).get("look", {})

static func ilvl_text(id: String) -> String:
	return Tx.f("Item Level %d  ·  +%d Composure  ·  +%s%% Power", [ilvl(id), composure(id), str(power_pct(id))])

static func stat_text(id: String) -> String:
	var parts: Array[String] = []
	for k in Rpg.ATTR_ORDER:
		var v := int(ITEMS[id].attrs.get(k, 0))
		if v > 0:
			parts.append("+%d %s" % [v, Rpg.ATTRS[k].name])
	return ", ".join(parts) if not parts.is_empty() else "No bonus"

## Text lines for a set's bonuses, e.g. ["(2) +1 Grip", "(4) Pounce: ..."].
static func set_lines(set_id: String) -> Array:
	var out: Array = []
	var b: Dictionary = SETS[set_id].bonus
	for n in [2, 4]:
		if not b.has(n):
			continue
		var t := ""
		for k in b[n].get("attrs", {}):
			t += "+%d %s " % [int(b[n].attrs[k]), Rpg.ATTRS[k].name]
		if b[n].has("text"):
			t += str(b[n].text)
		out.append([n, t.strip_edges()])
	return out

## The full look of a boss in their own set (so Onça wears the rosettes when you fight him).
static func set_look(set_id: String) -> Dictionary:
	var lk := {"kit": "gi"}
	for pid in SETS[set_id].pieces:
		if str(ITEMS[pid].slot) == "spats":
			lk.kit = "nogi"
	for pid in SETS[set_id].pieces:
		var it: Dictionary = ITEMS[pid]
		lk[it.slot] = it.look
		if it.slot == "head":
			lk["head_piece"] = it.get("piece", "Headband")
	return lk
