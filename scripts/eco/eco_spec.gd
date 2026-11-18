extends RefCounted
## Numbers and layout of the minimal ecology test (task ECO-001).
## Rules follow the mechanism baseline in PROJECT_STATE.md, taken from the old Unity
## project's final code. Only this slice is live here:
##   dig nutrient soil -> slime is born -> walks straight, turns when blocked ->
##   absorbs / releases nutrient with neighbouring soil -> soil amount and look change.
## Not in this slice: HP and weakening, bud, flower, reproduction, predation, heroes.

const STEP_SECONDS := 1.0            ## one cell per second, shown as continuous motion
const NUTRIENT_CAPACITY := 3         ## most a slime carries
const ABSORB_AT_OR_BELOW := 1        ## carrying this or less: take 1 from a neighbour soil
const RELEASE_AT_OR_ABOVE := 2       ## carrying this or more: give the surplus away
const KEEP_ON_RELEASE := 1           ## what it keeps after releasing
const ECOLOGY_COOLDOWN_MOVES := 2    ## completed moves between two absorb / release checks
const SPAWN_MAX_SOIL_NUTRIENT := 10  ## soil richer than this does not hatch a base slime
const SCATTER_MAX_RING := 3          ## dig leftovers go to the nearest ring of soil, up to this far
const HATCH_SECONDS := 0.7           ## pop-out animation before the first step

## Neighbour order for absorbing (old code: up, down, left, right).
const N4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

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

## Scripted digs of the built-in demo: seconds from start, cell.
const DEMO_DIGS: Array = [
	[0.6, Vector2i(5, 3)],
	[2.6, Vector2i(7, 5)],
	[4.6, Vector2i(8, 5)],
	[7.6, Vector2i(5, 2)],
	[10.6, Vector2i(9, 5)],
	[14.6, Vector2i(5, 5)],
]
