package main

import "core:math/linalg"
import rl "vendor:raylib"

/*
character moves A->B
we want to check the bounds of all blocks that might be collided with and cancel the momentum in that axis

1. move along each axis [0..2], check if IVec3(last_position + new_position[axis]) != empty block
2. if it is, then do not add for that dimension
*/

//AABB
aabb :: proc(world: ^World, last_position, new_position: rl.Vector3, bounding_box: rl.BoundingBox) -> (final_movement_vector: rl.Vector3) {
	delta := new_position - last_position
	current_position := last_position

	for axis in 0..<3 {
		if delta[axis] == 0 do continue

		goal_position := current_position
		goal_position[axis] += delta[axis]

		world_min := goal_position + bounding_box.min
		world_max := goal_position + bounding_box.max

		bb_min := IVec3(linalg.floor(world_min))
		bb_max := IVec3(linalg.ceil(world_max))

		collided := false
outer:	for x in bb_min.x..<bb_max.x {
			for y in bb_min.y..<bb_max.y {
				for z in bb_min.z..<bb_max.z {
					pos := IVec3{x,y,z}
					if get_voxel(world, pos) != VoxelKind.Air {
						collided = true
						break outer
					}
				}
			}
		}
		if !collided {
			final_movement_vector[axis] = delta[axis]
			current_position[axis] = goal_position[axis] // committed so we cant clip diagonally
		}
	}
	return
}
