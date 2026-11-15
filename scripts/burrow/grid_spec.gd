extends RefCounted
## Bottom-level spec of the burrow test. Everything gameplay-side is measured in CELLS
## (floats; cell (cx, cy) spans [cx, cx+1) and its centre is cx+0.5). Pixels only appear
## when something is drawn: pixel = cell * CELL_PX. Change CELL_PX and the whole stage
## (map, creature, items, effects) rescales together.
##
## Passage rules
##   - 4-direction movement only, no diagonals.
##   - An entity with footprint (w, h) may stand on anchor cell c only if every cell in
##     the rectangle [c, c + (w, h)) is OPEN and not occupied by a blocking item.
##   - Direction changes happen at cell centres; the drawn path rounds the corner with
##     CORNER_RADIUS, which always stays inside the two cells involved.
##   - Interaction (eat / attack / being hit) needs the footprints to touch edge-to-edge
##     (INTERACT_RANGE cells between them) and the actor to face the target.
##
## Three different sizes per object, deliberately kept apart
##   - footprint: integer cells it reserves in the grid (logic).
##   - body:      radius/length used for wall checks and hit contact (collision).
##   - visual:    what is drawn; may overhang the footprint during an action
##                (a lunge, a tail trailing through a corner) but never a wall.

const CELL_PX := 64.0          ## default on-screen size of one cell at 1280x720, camera zoom 1
const COLS := 17
const ROWS := 9

const SOIL := 0                ## solid, can be dug
const OPEN := 1                ## tunnel / chamber
const ROCK := 2                ## solid, cannot be dug

const CORNER_RADIUS := 0.4     ## cells; rounding of a 90 degree turn
const INTERACT_RANGE := 0      ## cells of gap allowed between two interacting footprints
const WALL_RIM := 0.07         ## cells; how far the drawn soil lip intrudes into an open cell
const BODY_MAX_HALF_WIDTH := 0.5 - WALL_RIM  ## widest a 1-cell-wide body (legs included) may be drawn

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Test map. '#' rock, '.' soil, 'o' open.
const LAYOUT: Array[String] = [
	"#################",
	"#......#........#",
	"#.ooo....o...#..#",
	"#.ooo....o..#...#",
	"#.o...ooooooo...#",
	"#.o..#o..o......#",
	"#.ooooo..o.oooo.#",
	"#....#...o.o..#.#",
	"#################",
]

const SPAWN_CELL := Vector2i(3, 3)
const SPAWN_FACING := Vector2i(-1, 0)
const FOOD_CELLS: Array[Vector2i] = [Vector2i(9, 2), Vector2i(11, 7)]
const BURR_CELL := Vector2i(14, 6)
const DEMO_DIG: Array[Vector2i] = [Vector2i(10, 6)]


static func center(cell: Vector2i, size := Vector2i.ONE) -> Vector2:
	return Vector2(cell) + Vector2(size) * 0.5


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))
