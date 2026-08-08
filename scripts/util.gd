extends Node
class_name ComputeUtil


static func create_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding := 0) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


static func create_spec_constants(constants: Array) -> Array[RDPipelineSpecializationConstant]:
	var spec_constants: Array[RDPipelineSpecializationConstant] = []

	for i in constants.size():
		var value: Variant = constants[i]
		var components: Array = split_components(value)

		for component in components:
			var constant := RDPipelineSpecializationConstant.new()
			constant.constant_id = spec_constants.size()
			constant.value = component
			spec_constants.append(constant)

	return spec_constants


## Explode composite data types, e.g. [Vector3] -> float[3].
static func split_components(value: Variant) -> Array:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
			return [value]
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		_:
			assert(false, "Unsupported spec constant type: %s" % type_string(typeof(value)))
			return []


static func to_int16_array(bytes: PackedByteArray, signed := false) -> PackedInt32Array:
	var result := PackedInt32Array()
	@warning_ignore("integer_division")
	result.resize(bytes.size() / 2)

	for i in result.size():
		var offset := i * 2
		result[i] = bytes.decode_s16(offset) if signed else bytes.decode_u16(offset)

	return result


static func to_uint32_array(bytes: PackedByteArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	@warning_ignore("integer_division")
	result.resize(bytes.size() / 4)

	for i in result.size():
		var offset := i * 4
		result[i] = bytes.decode_u32(offset)

	return result


static func to_vector2i_array(bytes: PackedByteArray) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	@warning_ignore("integer_division")
	result.resize(bytes.size() / 8)

	for i in result.size():
		var offset := i * 8
		result[i] = Vector2i(bytes.decode_u32(offset), bytes.decode_u32(offset + 4))

	return result


static func to_vector3i_array(indices: PackedInt32Array) -> Array[Vector3i]:
	var triangles: Array[Vector3i] = []

	for i in range(0, indices.size(), 3):
		triangles.append(Vector3i(indices[i], indices[i + 1], indices[i + 2]))

	return triangles


static func oct_decode(e: Vector2) -> Vector3:
	var v := Vector3(e.x, e.y, 1.0 - absf(e.x) - absf(e.y))
	if v.z < 0.0:
		var ox := v.x
		v.x = (1.0 - absf(v.y)) * signf(ox)
		v.y = (1.0 - absf(ox)) * signf(v.y)
	return v.normalized()


static func read_normal(bytes: PackedByteArray, byte_offset := 0) -> Vector3:
	var x := bytes.decode_u16(byte_offset) / 65535.0 * 2.0 - 1.0
	var y := bytes.decode_u16(byte_offset + 2) / 65535.0 * 2.0 - 1.0
	return oct_decode(Vector2(x, y))
