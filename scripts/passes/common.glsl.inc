const uint OUT_MESH_WORKGROUP_SIZE = 64;
const uint FILL_WORKGROUP_SIZE = 256;
const uint BOUNDARY_WORKGROUP_SIZE = 64;
const uint FLAG_BOUNDARY = 1;
const uint MAX_BEVEL = 3;

struct SharedEdge {
	uvec2 faces; // Which 2 faces in index_buffer
	uvec2 apexes; // The edge wound as faces.x sees it, so fill can orient itself
	uvec2 retracted[2]; // Resultant edges, per face, in apex order
};

struct BoundaryEdge {
	uvec2 verts;
	uint face;
	uint corner;
	uvec2 top[MAX_BEVEL + 1];
};
