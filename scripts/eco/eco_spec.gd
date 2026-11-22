extends RefCounted
## Numbers and layout of the ecology test (tasks ECO-001, ECO-002).
## Rules follow the mechanism baseline in PROJECT_STATE.md, taken from the old Unity
## project's final code, with the agreed fixes (bud takes over the carried nutrient
## once; every exit path settles it exactly once). The whole life cycle is live:
##   dig nutrient soil -> moss is born -> walks straight, turns when blocked ->
##   absorbs / releases nutrient with neighbouring soil, loses HP as it walks ->
##   weak with enough nutrient: bud; out of HP without: starves ->
##   bud draws nutrient from around it -> flower -> new mosses.
## Not here: predation, heroes, magic.

const STEP_SECONDS := 1.0            ## one cell per second, shown as continuous motion
const NUTRIENT_CAPACITY := 3         ## most a moss carries
const ABSORB_AT_OR_BELOW := 1        ## carrying this or less: take 1 from a neighbour soil
const RELEASE_AT_OR_ABOVE := 2       ## carrying this or more: give the surplus away
const KEEP_ON_RELEASE := 1           ## what it keeps after releasing
const ECOLOGY_COOLDOWN_MOVES := 2    ## completed moves between two absorb / release checks
const SPAWN_MAX_SOIL_NUTRIENT := 9   ## mosses hatch from soil holding 1..9 (as in the original game)
const PREDATOR_SOIL_MIN := 10        ## soil holding 10..16 is where the first predator will hatch (not built yet)
const PREDATOR_SOIL_MAX := 16
const PLANT_SKIPS_SOIL_FROM := 11    ## buds and flowers never draw from soil holding this much or more
const DEATH_SCATTER_RING := 3        ## starved / withered nutrient returns to soil within this ring (7x7)
const SCATTER_MAX_RING := 3          ## dig leftovers go to the nearest ring of soil, up to this far
const HATCH_SECONDS := 0.7           ## pop-out animation before the first step

# --- crawler HP (weakening). Counted only on completed moves; standing still costs nothing.
const HP_INITIAL := 16
const HP_MAX := 21
const HP_COST := 1                   ## lost every HP_COST_EVERY_MOVES completed moves
const HP_COST_EVERY_MOVES := 2
const HP_HEAL_ON_ABSORB := 1         ## releasing does not heal

# --- crawler -> bud, or starvation
const BUD_HP_THRESHOLD := 2          ## HP at or below this ...
const BUD_REQUIRED_NUTRIENT := 2     ## ... and carrying at least this: becomes a bud
## Out of HP while carrying less: starves; what it carried goes to the floating pool.

# --- bud (does not move, does not attack)
const BUD_MAX_HP := 10
const BUD_RADIUS := 2                ## draws from soil within this Chebyshev radius (5x5)
const BUD_TO_FLOWER := 8             ## collected nutrient that makes it bloom
const BUD_STARVE_TICKS := 3          ## ticks in a row with nothing drawn before it loses HP
const BUD_HP_DECAY := 1

# --- flower
const FLOWER_MAX_HP := 21
const FLOWER_RADIUS := 3             ## 7x7
const FLOWER_MAX_COLLECT := 11
const FLOWER_HP_DECAY := 4           ## every tick: a flower lasts about six seconds

# --- reproduction, when the flower's HP runs out
const SPAWN_MAX := 5
const NUTRIENT_PER_SPAWN := 2        ## count = min(SPAWN_MAX, collected / NUTRIENT_PER_SPAWN)
const SPAWN_DELAY_MAX := 2.0         ## each newborn waits random(0, this) seconds before moving
## Where the leftover of a flower's collected nutrient goes (e.g. 11 collected, 5 born, 1 left).
## Decided by the user on 2026-11-19: into the floating pool, like starving and withering.
const REMAINDER_TO_POOL := true

const STAGE_TICK := 1.0              ## bud and flower act once per second

## Neighbour order for absorbing (old code: up, down, left, right).
const N4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# --- generated map (MAP-001); see eco_mapgen.gd for the nutrient rule
const GEN_COLS := 40
const GEN_ROWS := 24
const GEN_SEED := 20261119         ## default map; N in the scene rolls a new one
const GEN_ENTRANCE_COL := 20       ## entrance shaft comes down from the top border here
const GEN_ENTRANCE_DEPTH := 3      ## open cells below the top border
const GEN_DEMO_DIG_EVERY := 0.8    ## seconds between demo digs on the generated map

# --- small fixed test map (the ECO-001 / ECO-002 map), still used by the self-test.
## '#' rock, '.' soil, 'o' open.
const LAYOUT: Array[String] = [
	"#################",
	"#...............#",
	"#.....o.........#",
	"#.....o.........#",
	"#.ooooooooo.....#",
	"#.....o.........#",
	"#.....o.........#",
	"#...............#",
	"#################",
]

## Starting nutrient per cell (digit), same shape as LAYOUT. Ignored where the cell is not soil.
const NUTRIENT: Array[String] = [
	"00000000000000000",
	"00122100000122100",
	"00123400002343100",
	"00012300001232100",
	"00000000000012000",
	"00012302123200000",
	"00123403234310000",
	"00121000012100000",
	"00000000000000000",
]

## Scripted digs of the built-in demo: seconds from start, cell. The later ones open fresh
## soil after the first generation has drained the tunnels, the way a player would.
const DEMO_DIGS: Array = [
	[0.6, Vector2i(5, 3)],
	[2.6, Vector2i(7, 5)],
	[4.6, Vector2i(8, 5)],
	[7.6, Vector2i(5, 2)],
	[10.6, Vector2i(9, 5)],
	[14.6, Vector2i(5, 5)],
	[60.0, Vector2i(11, 4)],
	[61.5, Vector2i(11, 3)],
	[63.0, Vector2i(12, 3)],
	[66.0, Vector2i(12, 2)],
	[95.0, Vector2i(4, 5)],
	[97.0, Vector2i(4, 6)],
	[125.0, Vector2i(10, 5)],
	[127.0, Vector2i(10, 6)],
]
