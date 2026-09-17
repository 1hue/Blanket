const float EPSILON = 1e-6;
const uint DEDUPE_WORKGROUP_SIZE = 64;
const uint FACES_WORKGROUP_SIZE = 64;
const uint OUT_MESH_WORKGROUP_SIZE = 64;
const uint EDGES_WORKGROUP_SIZE = 64;
const uint SHRINK_WORKGROUP_SIZE = 64;
const uint FILL_WORKGROUP_SIZE = 256;
const uint BOUNDARY_WORKGROUP_SIZE = 64;
const uint FLAG_BOUNDARY = 1;
const uint FLAG_BITS = 8; // Low bits are flags, the rest is the rim column slot
const uint MAX_BEVEL = 3;

struct SharedEdge {
	uvec2 faces; // Which 2 faces in index_buffer
	uvec2 apexes; // The edge wound as faces.x sees it, so fill can orient itself
	uvec2 retracted[2]; // Resultant edges, per face, in apex order
	uint crease; // 0 = coplanar, so fill closes the gap instead of building arcs
};

struct FaceEdge {
	uint twin; // Global corner across this edge, biased by one. 0 = nothing there, so boundary
	uint creased; // Non-zero when the two faces disagree enough to be worth beveling
};

struct BoundaryEdge {
	uvec2 verts;
	uint face;
	uint corner;
	uvec2 top[MAX_BEVEL + 1];
};

uint prev_corner(uint corner) {
	return (corner + 2) % 3;
}

uint next_corner(uint corner) {
	return (corner + 1) % 3;
}
