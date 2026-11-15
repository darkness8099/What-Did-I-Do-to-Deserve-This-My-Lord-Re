extends RefCounted
## One frame of creature pose. The behaviour script fills it in, the rig draws it.
## All values are offsets from the neutral standing pose (facing +x, y down).

const FLOATS: Array[StringName] = [
	&"lift", &"body_x", &"body_y", &"body_rot", &"sx", &"sy",
	&"head_x", &"head_y", &"head_rot", &"jaw", &"lid", &"brow",
	&"look_x", &"look_y", &"tail", &"ear", &"shroom", &"glow", &"life", &"flash",
]

var lift := 0.0      ## whole creature up (+) / sunk into the ground (-), feet included
var body_x := 0.0    ## body shift relative to the feet
var body_y := 0.0
var body_rot := 0.0  ## + = nose down
var sx := 1.0        ## body squash / stretch
var sy := 1.0
var head_x := 0.0
var head_y := 0.0
var head_rot := 0.0
var jaw := 0.0       ## 0 closed .. 1 wide open
var lid := 0.0       ## 0 open .. 1 closed
var brow := 0.0      ## 0 none .. 1 angry
var look_x := 0.0
var look_y := 0.0
var tail := 0.0      ## + = raised
var ear := 0.0       ## + = perked forward
var shroom := 0.0    ## 0 upright .. 1 drooped
var glow := 1.0      ## back-mushroom glow
var life := 1.0      ## 1 alive colours .. 0 withered
var flash := 0.0     ## hit flash
var eye := 0         ## 0 normal, 1 squeezed, 2 dead, 3 happy (not blended)
## Feet: far-front, far-back, near-front, near-back. x = offset along the ground, y = lift.
var feet: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func copy() -> RefCounted:
	var p: RefCounted = get_script().new()
	for k in FLOATS:
		p.set(k, get(k))
	p.eye = eye
	p.feet = feet.duplicate()
	return p


## self = lerp(a, self, w). Feet that have to travel sideways are lifted so they step instead of slide.
func blend_from(a: RefCounted, w: float) -> void:
	for k in FLOATS:
		var va: float = a.get(k)
		var vb: float = get(k)
		set(k, lerpf(va, vb, w))
	for i in 4:
		var fa: Vector2 = a.feet[i]
		var fb: Vector2 = feet[i]
		var v := fa.lerp(fb, w)
		v.y += sin(PI * w) * minf(3.5, absf(fb.x - fa.x) * 0.5)
		feet[i] = v
