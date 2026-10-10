#+feature dynamic-literals
package main

import "core:mem"
import "core:math"
import "core:math/rand"
import "core:c"
import "core:log"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"


WINDOW_WIDTH : c.int : 800
WINDOW_HEIGHT : c.int : 600

TARGET_FPS :: 60

CUBE_COLORS_DIRT : [6]rl.Color : {
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
}

CUBE_COLORS_STONE : [6]rl.Color : {
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
}

CUBE_COLORS_UNKNOWN : [6]rl.Color : {
	rl.Color{100, 200, 200, 255},
	rl.Color{200, 100, 200, 255},
	rl.Color{200, 200, 100, 255},
	rl.Color{150, 200, 150, 255},
	rl.Color{200, 150, 150, 255},
	rl.Color{150, 200, 200, 255}
}

CHUNK_SIZE :: 32 // N x N x N chunk
CHUNK_GENERATION_RADIUS :: 4

IVec3 :: struct { // discrete vec3
	x, y, z: int
}

World :: struct {
	chunks: map[IVec3]Chunk,
}

Chunk :: struct {
	voxels: map[IVec3]VoxelKind, // absence is 'air'
	model: Maybe(rl.Model),
}

VoxelKind :: enum {
	Dirt,
	Stone,
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

	h_set := []IVec3{
		IVec3{1,1,0},
		IVec3{1,2,0},
		IVec3{1,3,0},
		IVec3{1,4,0},
		IVec3{1,5,0},
		IVec3{2,3,-1},
		IVec3{3,1,-2},
		IVec3{3,2,-2},
		IVec3{3,3,-2},
		IVec3{3,4,-2},
		IVec3{3,5,-2},
	}
	for pos in h_set {
		set_voxel(&world, pos, VoxelKind.Stone)
	}

	color_map := map[VoxelKind][6]rl.Color{
		VoxelKind.Dirt = CUBE_COLORS_DIRT,
		VoxelKind.Stone = CUBE_COLORS_STONE,
	}

	for !rl.WindowShouldClose() {
		// game updates
		if rl.IsKeyDown(rl.KeyboardKey.SPACE) { // was `pressed` for once-action
			//keys := collect_keys(world.voxels)
			chunks := collect_keys(world.chunks)
			desired_chunk := rand.choice(chunks[:])
			voxels := collect_keys(world.chunks[desired_chunk].voxels)
			desired_vox := rand.choice(voxels[:])
			desired_pos := chunk_to_world_coord(desired_chunk, desired_vox)
			set_voxel(&world, desired_pos, VoxelKind.Stone) // evicts mesh
		}
		// render
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{60, 0, 40, 255}) // (60, 0, 8)
		/*BEGIN 3D*/ rl.BeginMode3D(camera)
		// render around camera
		camera_chunk, _ := world_to_chunk_coord(vec_to_ivec(camera.position))
		for y in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
			for z in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
				for x in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
					//c_offset := IVec3{x,y,z}
					c_pos := IVec3{x = camera_chunk.x + x, y = camera_chunk.y + y, z = camera_chunk.z + z}
					chunk := get_or_create_chunk(&world, c_pos)

					offset := ivec_to_vec(IVec3{x = c_pos.x * CHUNK_SIZE, y = c_pos.y * CHUNK_SIZE, z = c_pos.z * CHUNK_SIZE})
					if chunk.model == nil {
						create_mesh(chunk, color_map)
					}
					rl.DrawModel(chunk.model.?, offset, 1.0, rl.WHITE)
				}
			}
		}

		/*END   3D*/ rl.EndMode3D()
		rl.DrawFPS(10, 10)
		rl.EndDrawing()
	}
}

get_or_create_chunk :: proc(world: ^World, chunk_position: IVec3) -> (chunk: ^Chunk) {
	ok: bool
	if chunk, ok = &world.chunks[chunk_position]; ok {
		return
	}
	world.chunks[chunk_position] = Chunk { model = nil, voxels = map[IVec3]VoxelKind{} }
	chunk = &world.chunks[chunk_position]
	for z in 0..<32 {
		for y in 0..<32 {
			for x in 0..<32 {
				world_pos := IVec3{
					x = chunk_position.x*CHUNK_SIZE + x,
				 	y = chunk_position.y*CHUNK_SIZE + y,
					z = chunk_position.z*CHUNK_SIZE + z,
				}

				if world_pos.y == 0 {
					chunk.voxels[IVec3{x,y,z}] = VoxelKind.Dirt
				} else if world_pos.y < 0 {
					chunk.voxels[IVec3{x,y,z}] = VoxelKind.Stone
				}
			}
		}
	}
	return
}

create_mesh :: proc(chunk: ^Chunk, color_map: map[VoxelKind][6]rl.Color) {
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
	for vox, kind in chunk.voxels {
		c, ok := color_map[kind]
		if !ok {
			log.warnf("voxel kind '%v' has no color map", kind)
			c = CUBE_COLORS_UNKNOWN
		}
		gen_cube_vertices(
			&vertices, &normals, &colors, &indices,
		 	ivec_to_vec(vox), c, i
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


set_voxel :: proc(world: ^World, position: IVec3, kind: Maybe(VoxelKind)) {
	// convert to chunk coords
	chunk_pos, chunk_local_pos := world_to_chunk_coord(position)
 	//chunk := &world.chunks[chunk_pos]
	chunk := get_or_create_chunk(world, chunk_pos)
	if mod, ok := &chunk.model.?; ok {
		free_model(mod)
	}
	chunk.model = nil
	k, ok := kind.?
	if !ok {
		delete_key(&chunk.voxels, chunk_local_pos) // no-op if the key doesn't exist
	} else {
		chunk.voxels[chunk_local_pos] = k
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
