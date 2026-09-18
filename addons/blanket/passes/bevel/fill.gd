# SPDX-FileCopyrightText: © 2026 1hue
# SPDX-License-Identifier: MIT

extends BlanketPass
class_name FillPass

const SIZE_PARAMS = 12


func _pre() -> void:
	version = &"out_u32" if params.out_index_stride == 4 else &"out_u16"

	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.out_color_offset)
	push_constant.encode_u32(4, params.out_custom_offset)
	push_constant.encode_u32(8, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.fill.pipelines[version])
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_edge, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.face_edge, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.FILL)
	rd.compute_list_end()
