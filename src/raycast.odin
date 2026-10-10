package main

import "core:log"
import "core:math/linalg"
import rl "vendor:raylib"

raycast_voxel :: proc(world: ^World, start: rl.Vector3, direction: rl.Vector3, max_dist: f32) -> (IVec3, rl.Vector3, bool) {
	pos := IVec3(linalg.floor(start))
	step_dir := IVec3(linalg.sign(direction))
	delta := linalg.abs(1/direction)

	// distance till next voxel
	fract := start - rl.Vector3(pos)
	t_max := rl.Vector3{
		((direction.x > 0.) ? 1. - fract.x : fract.x) * delta.x,
		((direction.y > 0.) ? 1. - fract.y : fract.y) * delta.y,
		((direction.z > 0.) ? 1. - fract.z : fract.z) * delta.z,
	}
	dist: f32 = 0.
	last_move := rl.Vector3(0)

	for dist < max_dist {
		if vox := get_voxel(world, pos); vox != nil { // hit a boundary
			log.infof("hit %v, traveled %v, saw %v", pos, dist, vox)
			return pos, -linalg.normalize(last_move), true
		}
		log.infof("%v, -- %v, -- %v", t_max, pos, dist)

		if t_max.x < t_max.y && t_max.x < t_max.z { // stepping in an axis based on smallest t_max
			pos.x += step_dir.x
			dist = t_max.x
			t_max.x += delta.x
			last_move = rl.Vector3{f32(step_dir.x), 0, 0}
		} else if t_max.y < t_max.z {
			pos.y += step_dir.y
			dist = t_max.y
			t_max.y += delta.y
			last_move = rl.Vector3{0, f32(step_dir.y), 0}
		} else {
			pos.z += step_dir.z
			dist = t_max.z
			t_max.z += delta.z
			last_move = rl.Vector3{0, 0, f32(step_dir.z)}
		}
	}
	return IVec3{}, rl.Vector3(0), false // goes into space
}
