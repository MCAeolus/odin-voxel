package main

import "core:math"
import "core:mem"
import "core:crypto/_fiat/field_curve448"
import "base:intrinsics"
import "core:math/rand"
import "core:c"
import "core:log"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"


WINDOW_WIDTH : c.int : 800
WINDOW_HEIGHT : c.int : 600

TARGET_FPS :: 60

CUBE_COLORS : [6]rl.Color : {
	rl.Color{100, 200, 200, 255},
	rl.Color{200, 100, 200, 255},
	rl.Color{200, 200, 100, 255},
	rl.Color{150, 200, 150, 255},
	rl.Color{200, 150, 150, 255},
	rl.Color{150, 200, 200, 255}
}

CHUNK_SIZE :: 32 // N x N x N chunk

IVec3 :: struct { // discrete vec3
	x, y, z: int
}

ivec_to_vec :: proc(vec: IVec3) -> (out: rl.Vector3) {
	out.x = f32(vec.x)
	out.y = f32(vec.y)
	out.z = f32(vec.z)
	return
}

World :: struct {
	chunks: map[IVec3]Chunk,
}

Chunk :: struct {
	voxels: map[IVec3]struct{},
	model: Maybe(rl.Model),
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Cube!")
	defer rl.CloseWindow()
	rl.SetTargetFPS(TARGET_FPS)

	camera := rl.Camera3D{
		position = rl.Vector3{25, 10, 25},
		target = rl.Vector3{0, 0, 0},
		up = rl.Vector3{0, 1, 0},
		fovy = 60,
		projection = rl.CameraProjection.PERSPECTIVE,
	}

	world := World{}
	// populate World
	for z in 0..<32 {
		for x in 0..<32 {
			flip_voxel(&world, IVec3{x - 16, 0, z - 16})
		}
	}
	flip_voxel(&world, IVec3{-12, 3, -13})

	for !rl.WindowShouldClose() {
		// game updates
		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			//keys := collect_keys(world.voxels)
			chunks := collect_keys(world.chunks)
			desired_chunk := rand.choice(chunks[:])
			voxels := collect_keys(world.chunks[desired_chunk].voxels)
			desired_vox := rand.choice(voxels[:])
			desired_pos := chunk_to_world_coord(desired_chunk, desired_vox)
			flip_voxel(&world, desired_pos) // evicts mesh
		}
		// render
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{60, 0, 20, 255}) // (60, 0, 8)
		/*BEGIN 3D*/ rl.BeginMode3D(camera)
		for chunk_pos, &chunk in world.chunks {
			offset := rl.Vector3{f32(chunk_pos.x * CHUNK_SIZE), f32(chunk_pos.y * CHUNK_SIZE), f32(chunk_pos.z * CHUNK_SIZE) }
			if chunk.model == nil {
				create_mesh(&chunk)
			}
			rl.DrawModel(chunk.model.?, offset, 1.0, rl.WHITE)
		}
		/*END   3D*/ rl.EndMode3D()
		rl.EndDrawing()
	}
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

get_or_create_chunk :: proc(world: ^World, chunk_position: IVec3) -> (chunk: ^Chunk) {
	ok: bool
	if chunk, ok = &world.chunks[chunk_position]; ok {
		return
	}
	world.chunks[chunk_position] = Chunk { model = nil, voxels = map[IVec3]struct{}{} }
	chunk = &world.chunks[chunk_position]
	return
}

create_mesh :: proc(chunk: ^Chunk) {
	mesh := rl.Mesh{}
	mesh.vertexCount = c.int(24 * len(chunk.voxels))
	mesh.triangleCount = c.int(12 * len(chunk.voxels))
	//mesh.vertices = cast([^]f32) rl.MemAlloc(c.uint(mesh.vertexCount * 3 * size_of(f32)))
	//mesh.normals = cast([^]f32) rl.MemAlloc(c.uint(mesh.vertexCount * 3 * size_of(f32)))
	//mesh.colors = cast([^]u8) rl.MemAlloc(c.uint(mesh.vertexCount * 4 * size_of(u8)))
	vertices := make([dynamic]f32, 0, mesh.vertexCount * 3)
	normals := make([dynamic]f32, 0, mesh.vertexCount * 3)
	colors := make([dynamic]u8, 0, mesh.vertexCount * 4)
	indices := make([dynamic]u16, 0, mesh.triangleCount * 3)
	defer delete(vertices)
	defer delete(normals)
	defer delete(colors)
	defer delete(indices)
	i := 0
	for vox in chunk.voxels {
		gen_cube_vertices(
			&vertices, &normals, &colors, &indices,
		 	ivec_to_vec(vox), CUBE_COLORS, i
		)
		i += 1
	}
	mesh.vertices = cast([^]f32) rl.MemAlloc(u32(len(vertices) * size_of(f32)))
	mesh.normals = cast([^]f32) rl.MemAlloc(u32(len(normals) * size_of(f32)))
	mesh.colors = cast([^]u8) rl.MemAlloc(u32(len(colors) * size_of(u8)))
	mesh.indices = cast([^]u16) rl.MemAlloc(u32(len(indices) * size_of(u16)))

	mem.copy(mesh.vertices, raw_data(vertices), len(vertices) * size_of(f32))
	mem.copy(mesh.normals, raw_data(normals), len(normals) * size_of(f32))
	mem.copy(mesh.colors, raw_data(colors), len(colors) * size_of(u8))
	mem.copy(mesh.indices, raw_data(indices), len(indices) * size_of(u16))
	//mesh.vertices = raw_data(vertices)
	//mesh.normals = raw_data(normals)
	//mesh.colors = raw_data(colors)
	//mesh.indices = raw_data(indices)
	rl.UploadMesh(&mesh, false)
	chunk.model = rl.LoadModelFromMesh(mesh)
}

free_model :: proc(model: ^rl.Model) {
	rl.UnloadModel(model^)
}


flip_voxel :: proc(world: ^World, position: IVec3) {
	// convert to chunk coords
	chunk_pos, chunk_local_pos := world_to_chunk_coord(position)
	//log.infof("%v -> %v, %v", position, chunk_pos, chunk_local_pos)
 	//chunk := &world.chunks[chunk_pos]
	chunk := get_or_create_chunk(world, chunk_pos)
	if mod, ok := &chunk.model.?; ok {
		free_model(mod)
	}
	chunk.model = nil
	if _, ok := chunk.voxels[chunk_local_pos]; ok {
		delete_key(&chunk.voxels, chunk_local_pos)
	} else {
		chunk.voxels[chunk_local_pos] = struct{}{}
	}
}

// call within a draw call
draw_cube :: proc(position: rl.Vector3) {
	rl.DrawCube(position, 1.0, 1.0, 1.0, rl.WHITE)
}


gen_cube_vertices :: proc(vert_buf: ^[dynamic]f32, norm_buf: ^[dynamic]f32, color_buf: ^[dynamic]u8, ind_buf: ^[dynamic]u16, position: rl.Vector3, colors: [6]rl.Color, offset: int, w: f32 = 1, h: f32 = 1, l: f32 = 1) {
	w2 := w / 2
	h2 := h / 2
	l2 := l / 2
	//front
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[0].r, colors[0].g, colors[0].b, colors[0].a)
		append(norm_buf, 0, 0, 1)
	}
	// add indices [n, n+1, n+2, n, n+2, n+3]
	ind := u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
	 	position.x - w2, position.y - h2, position.z + l2, //bottom-left 0
		position.x + w2, position.y - h2, position.z + l2, //bottom-right 1
		position.x + w2, position.y + h2, position.z + l2, //top-right 2
		position.x - w2, position.y + h2, position.z + l2, //top-left 3
	)
	/*rlgl.Color4ub(colors[0].r, colors[0].g, colors[0].b, colors[0].a)
	rlgl.Normal3f(0, 0, 1) // face towards 'us'
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-left
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // top-right
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // top-left*/
	//back
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[1].r, colors[1].g, colors[1].b, colors[1].a)
		append(norm_buf, 0, 0, -1)
	}
	ind = u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
		position.x - w2, position.y - h2, position.z - l2, // bottom-right
		position.x - w2, position.y + h2, position.z - l2, // top-right
		position.x + w2, position.y + h2, position.z - l2, // top-left
		position.x + w2, position.y - h2, position.z - l2, // bottom-left
	)
	/*
	rlgl.Color4ub(colors[1].r, colors[1].g, colors[1].b, colors[1].a)
	rlgl.Normal3f(0,0,-1) // face away
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // bottom-right
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-left
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // bottom-left*/

	//top
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[2].r, colors[2].g, colors[2].b, colors[2].a)
		append(norm_buf, 0, 1, 0)
	}
	ind = u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
		position.x - w2, position.y + h2, position.z - l2, // top-left
		position.x - w2, position.y + h2, position.z + l2, // bottom-left
		position.x + w2, position.y + h2, position.z + l2, // bottm-right
		position.x + w2, position.y + h2, position.z - l2, // top-right
	)
	/*
	rlgl.Color4ub(colors[2].r, colors[2].g, colors[2].b, colors[2].a)
	rlgl.Normal3f(0,1,0) // face up
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-left
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // bottom-left
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // bottom-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-right*/

	//bottom
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[3].r, colors[3].g, colors[3].b, colors[3].a)
		append(norm_buf, 0, -1, 0)
	}
	ind = u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
		position.x - w2, position.y - h2, position.z - l2, // top-right
		position.x + w2, position.y - h2, position.z - l2, // top-left
		position.x + w2, position.y - h2, position.z + l2, // bottom-left
		position.x - w2, position.y - h2, position.z + l2, // bottom-right
	)
	/*
	rlgl.Color4ub(colors[3].r, colors[3].g, colors[3].b, colors[3].a)
	rlgl.Normal3f(0,-1,0) // face down
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // top-right
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // top-left
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-left
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-right*/

	//right
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[4].r, colors[4].g, colors[4].b, colors[4].a)
		append(norm_buf, 1, 0, 0)
	}
	ind = u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
		position.x + w2, position.y - h2, position.z - l2, // bottom-right
		position.x + w2, position.y + h2, position.z - l2, // top-right
		position.x + w2, position.y + h2, position.z + l2, // top-left
		position.x + w2, position.y - h2, position.z + l2, // bottom-left
	)
	/*
	rlgl.Color4ub(colors[4].r, colors[4].g, colors[4].b, colors[4].a)
	rlgl.Normal3f(1,0,0) // face right
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // bottom-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // top-left
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-left*/

	//left
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[5].r, colors[5].g, colors[5].b, colors[5].a)
		append(norm_buf, -1, 0, 0)
	}
	ind = u16(len(vert_buf) / 3)
	append(ind_buf,
		ind, ind+1, ind+2,
		ind, ind+2, ind+3,
	)
	append(vert_buf,
		position.x - w2, position.y - h2, position.z - l2, // bottom-left
		position.x - w2, position.y - h2, position.z + l2, // bottom-right
		position.x - w2, position.y + h2, position.z + l2, // top-right
		position.x - w2, position.y + h2, position.z - l2, // top-left
	)
	/*
	rlgl.Color4ub(colors[5].r, colors[5].g, colors[5].b, colors[5].a)
	rlgl.Normal3f(-1,0,0) // face left
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // bottom-left
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-right
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // top-right
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-left*/
}

draw_cube_colored :: proc(position: rl.Vector3, colors: [6]rl.Color, w: f32 = 1, h: f32 = 1, l: f32 = 1) {
	w2 := w / 2
	h2 := h / 2
	l2 := l / 2
	rlgl.Begin(rlgl.QUADS)
		//front
		rlgl.Color4ub(colors[0].r, colors[0].g, colors[0].b, colors[0].a)
		rlgl.Normal3f(0, 0, 1) // face towards 'us'
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-left
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-right
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // top-right
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // top-left

		//back
		rlgl.Color4ub(colors[1].r, colors[1].g, colors[1].b, colors[1].a)
		rlgl.Normal3f(0,0,-1) // face away
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // bottom-right
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-right
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-left
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // bottom-left

		//top
		rlgl.Color4ub(colors[2].r, colors[2].g, colors[2].b, colors[2].a)
		rlgl.Normal3f(0,1,0) // face up
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-left
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // bottom-left
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // bottom-right
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-right

		//bottom
		rlgl.Color4ub(colors[3].r, colors[3].g, colors[3].b, colors[3].a)
		rlgl.Normal3f(0,-1,0) // face down
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // top-right
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // top-left
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-left
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-right

		//right
		rlgl.Color4ub(colors[4].r, colors[4].g, colors[4].b, colors[4].a)
		rlgl.Normal3f(1,0,0) // face right
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z - l2) // bottom-right
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z - l2) // top-right
		rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // top-left
		rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-left

		//left
		rlgl.Color4ub(colors[5].r, colors[5].g, colors[5].b, colors[5].a)
		rlgl.Normal3f(-1,0,0) // face left
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z - l2) // bottom-left
		rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-right
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // top-right
		rlgl.Vertex3f(position.x - w2, position.y + h2, position.z - l2) // top-left
	rlgl.End()
}
