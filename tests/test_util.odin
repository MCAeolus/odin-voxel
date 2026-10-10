package tests

import "core:testing"
import m "../src"


@(test)
test_world_to_local_pos :: proc(t: ^testing.T) {
	test_case :: struct {
		label: string,
		world_pos, expected_chunk_pos, expected_chunk_local_pos: m.IVec3
	}
	cases := []test_case{
		{
			label = "basic",
			world_pos = m.IVec3{1,0,1},
			expected_chunk_pos = m.IVec3{0,0,0},
			expected_chunk_local_pos = m.IVec3{1,0,1}
		},
		{
			label = "basic negative",
			world_pos = m.IVec3{-1,0,-1},
			expected_chunk_pos = m.IVec3{-1,0,-1},
			expected_chunk_local_pos = m.IVec3{31,0,31}
		}
	}
	for c in cases {
		chunk_pos, chunk_local_pos := m.world_to_chunk_coord(c.world_pos)
		testing.expect_value(t, chunk_pos, c.expected_chunk_pos)
		testing.expect_value(t, chunk_local_pos, c.expected_chunk_local_pos)
	}
}
