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
	bounds_vec := bounding_box.max - bounding_box.min
	delta := new_position - last_position

	for axis in 0..<3 {
		goal_position := last_position
		goal_position[axis] += delta[axis]

		bb_min := IVec3(linalg.floor(goal_position))
		bb_max := IVec3(linalg.ceil(goal_position + bounds_vec))

		collided := false
outer:	for x in bb_min.x..<bb_max.x {
			for y in bb_min.y..<bb_max.y {
				for z in bb_min.z..<bb_max.z {
					pos := IVec3{x,y,z}
					if get_voxel(world, pos) != nil {
						collided = true
						break outer
					}
				}
			}
		}
		if !collided {
			final_movement_vector[axis] += delta[axis]
			//target_position[axis] = goal_position[axis]
		}
	}
	return
}
