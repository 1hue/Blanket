extends BlanketPass
class_name SmoothPass

const ITERATIONS = 5

var sum_pass: SmoothSumPass
var write_pass: SmoothWritePass


func _pre() -> void:
	sum_pass = SmoothSumPass.new(mesh, surface, params, sets)
	write_pass = SmoothWritePass.new(mesh, surface, params, sets)


## Normals must be recalculated after this
func compute() -> void:
	for i in ITERATIONS:
		sum_pass.compute()
		write_pass.compute()
