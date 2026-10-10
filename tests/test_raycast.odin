package tests

import "core:testing"
import m "../src"
import rl "vendor:raylib"

@(test)
test_raycast :: proc(t: ^testing.T) {
	mock_world := m.World{chunks = map[m.IVec3]m.Chunk{}}
	// make a floor rad 5 around 0,0,0
	for x in -5..<5 {
		for z in -5..<5 {
			m.set_voxel(&mock_world, m.IVec3{x,0,z}, m.VoxelKind.Dirt)
		}
	}
	for coord, v in mock_world.chunks {
		for pos, vox in v.voxels {
			wpos := m.chunk_to_world_coord(coord, pos)
			testing.expect(t, wpos.y <= 0)
		}
	}
	camera_pos := rl.Vector3{0, 2, 0} // 2 blocks off the ground, center of chunk
	dir := rl.Vector3{1, -1, 0} // looking diagonally down in x direction
	// therefore, we expect to collide with the block at (2, 0, 0), ~top face
	target_block, target_face, ok := m.raycast_voxel(
		&mock_world,
	 	camera_pos,
		dir,
		5,
	)
	testing.expect(t, ok)
	testing.expect_value(t, target_block, m.IVec3{2,0,0})
	testing.expect_value(t, target_face, rl.Vector3{0,1,0})
}
