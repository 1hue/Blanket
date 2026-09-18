// SPDX-FileCopyrightText: © 2026 1hue
// SPDX-License-Identifier: MIT

bool is_creased(uint face_idx, uint corner) {
	FaceEdge entry = face_edges[face_idx * 3 + corner];

	return entry.twin != 0u && entry.creased != 0u;
}

bool is_retracted(uint face_idx, uint corner) {
	return is_creased(face_idx, corner) || is_creased(face_idx, prev_corner(corner));
}

uint retracted_at(uint face_idx, uint corner) {
	return sel_vertex_count + 3 * face_idx + corner;
}

// Two faces meeting at a flat edge inset within their own planes and land a hair
// apart at each shared vert. The lower face owns it, so the seam closes with no strip
uint merged_slot(uint face_idx, uint corner) {
	uint own = retracted_at(face_idx, corner);
	FaceEdge entry = face_edges[face_idx * 3 + corner];
	FaceEdge prev = face_edges[face_idx * 3 + prev_corner(corner)];

	// Either of the corner's two edges can be the flat one holding a twin
	uint twin = entry.creased == 0u && entry.twin != 0u ? entry.twin : 0u;

	if (twin == 0u) twin = prev.creased == 0u && prev.twin != 0u ? prev.twin : 0u;
	if (twin == 0u) return own;

	uint twin_face = (twin - 1) / 3;

	if (twin_face > face_idx) return own;

	// Same source vert, so whichever of the twin's corners sits on it is the pair
	uint vert = sel_faces[face_idx][corner];

	for (uint i = 0; i < 3; ++i) {
		if (sel_faces[twin_face][i] != vert) continue;

		return is_retracted(twin_face, i) ? retracted_at(twin_face, i) : own;
	}

	return own;
}
