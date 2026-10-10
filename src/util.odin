package main

import "core:math"
import rl "vendor:raylib"

collect_keys :: proc(m: map[$N]$E) -> [dynamic]N {
	out := make([dynamic]N)
	for k,v in m {
		append(&out, k)
	}
	return out
}

chunk_to_world_coord :: proc(chunk_pos: IVec3, chunk_local_pos: IVec3) -> (world_pos: IVec3) {
	world_pos.x = chunk_pos.x * CHUNK_SIZE + chunk_local_pos.x
	world_pos.y = chunk_pos.y * CHUNK_SIZE + chunk_local_pos.y
	world_pos.z = chunk_pos.z * CHUNK_SIZE + chunk_local_pos.z
	return
}

world_to_chunk_coord :: proc(world_pos: IVec3) -> (chunk_pos: IVec3, chunk_local_pos: IVec3) {
	// https://odin-lang.org/docs/overview/#integer-operators
	// according to this section, integer operations in odin respect
	// euclidian operations (div/rem)
	chunk_pos = IVec3{x = math.floor_div(world_pos.x, CHUNK_SIZE), y = math.floor_div(world_pos.y, CHUNK_SIZE), z = math.floor_div(world_pos.z, CHUNK_SIZE)}
	chunk_local_pos = IVec3{x = world_pos.x %% CHUNK_SIZE, y = world_pos.y %% CHUNK_SIZE, z = world_pos.z %% CHUNK_SIZE}
	return
}

ivec_to_vec :: proc(vec: IVec3) -> (out: rl.Vector3) {
	out.x = f32(vec.x)
	out.y = f32(vec.y)
	out.z = f32(vec.z)
	return
}

vec_to_ivec :: proc(vec: rl.Vector3) -> (out: IVec3) {
	out.x = int(vec.x)
	out.y = int(vec.y)
	out.z = int(vec.z)
	return
}
