#+feature dynamic-literals
package main

import "core:strings"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:math"
import "core:math/rand"
import "core:c"
import "core:log"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"


WINDOW_WIDTH : c.int : 1000 //800
WINDOW_HEIGHT : c.int : 750 //600

TARGET_FPS :: 60

CUBE_COLORS_DIRT : [6]rl.Color : {
	rl.Color{140, 42, 42, 255},
	rl.Color{140, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{160, 42, 42, 255},
	rl.Color{140, 42, 42, 255},
	rl.Color{140, 42, 42, 255},
}

CUBE_COLORS_STONE : [6]rl.Color : {
	rl.Color{118, 128, 128, 255},
	rl.Color{118, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{128, 128, 128, 255},
	rl.Color{118, 128, 128, 255},
	rl.Color{118, 128, 128, 255},
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
CHUNK_GENERATION_RADIUS :: 3

//IVec3 :: struct { // discrete vec3
//	x, y, z: int
//}
IVec3 :: [3]int

World :: struct {
	chunks: map[IVec3]Chunk,
}

Chunk :: struct {
	voxels: [32][32][32]VoxelKind, // absence is 'air'
	model: Maybe(rl.Model),
}

VoxelKind :: enum {
	Air,
	Dirt,
	Stone,
}

RenderBuffers :: struct {
	vertices: [dynamic]f32,
	normals: [dynamic]f32,
	colors: [dynamic]u8,
	indices: [dynamic]u16,
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Cube!")
	defer rl.CloseWindow()
	rl.SetTargetFPS(TARGET_FPS)

	world := World{}
	player := PlayerController{
		position = rl.Vector3{0, 1, 0}, // at feet
		direction = rl.Vector3{1, 0, 0}, // facing forward, x-axis
		camera = rl.Camera3D{
			fovy = 60,
			up = rl.Vector3{0, 1, 0},
			target = rl.Vector3{1,1.6,0},
			position = rl.Vector3{0,1.6,0},
			projection = rl.CameraProjection.PERSPECTIVE,
		},
		bounding_box = rl.BoundingBox{rl.Vector3{-0.3, 0, -0.3}, rl.Vector3{0.3, 1.8, 0.3}},
	}

	color_map := map[VoxelKind][6]rl.Color{
		VoxelKind.Dirt = CUBE_COLORS_DIRT,
		VoxelKind.Stone = CUBE_COLORS_STONE,
	}

	set_voxel(&world, IVec3{1, 0, 1}, VoxelKind.Stone)

	rl.DisableCursor()
	lt := rl.GetTime()
	for !rl.WindowShouldClose() {
		// game updates
		now := rl.GetTime()
		dt := now - lt
		lt = now
		update_player(&player, &world, dt) // handles movement, camera

		// raycast placement/deletion
		target, face, ray_ok := raycast_voxel(&world, player.camera.position, player.direction, 3)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) { // was `pressed` for once-action
			if ray_ok {
				set_voxel(&world, IVec3(target), nil)
			}
		} else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
			if ray_ok {
				set_voxel(&world, IVec3(rl.Vector3(target)+face), VoxelKind.Stone)
			}
		}

		// render
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{60, 0, 40, 255}) // (60, 0, 8)
		/*BEGIN 3D*/ rl.BeginMode3D(player.camera)
		// render around camera
		player_chunk, _ := world_to_chunk_coord(vec_to_ivec(player.position))
		for y in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
			for z in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
				for x in -CHUNK_GENERATION_RADIUS..<CHUNK_GENERATION_RADIUS {
					//c_offset := IVec3{x,y,z}
					c_pos := IVec3{player_chunk.x + x, player_chunk.y + y, player_chunk.z + z}
					chunk := get_or_create_chunk(&world, c_pos)

					offset := ivec_to_vec(IVec3{c_pos.x * CHUNK_SIZE, c_pos.y * CHUNK_SIZE, c_pos.z * CHUNK_SIZE})
					if chunk.model == nil {
						create_mesh(chunk, color_map)
					}
					rl.DrawModel(chunk.model.?, offset, 1.0, rl.WHITE)
				}
			}
		}
		if ray_ok {
			rl.DrawCube(rl.Vector3(target) + 0.5, 1.01, 1.01, 1.01, rl.Color{255, 255, 255, 10})
			rl.DrawLine3D(rl.Vector3(target) + 0.5, rl.Vector3(target) + face + 0.5, rl.GREEN)
			rl.DrawLine3D(rl.Vector3(player.camera.position), rl.Vector3(target)+ 0.5 + face, rl.SKYBLUE)
		}
		shifted_box := rl.BoundingBox{player.bounding_box.min + player.position, player.bounding_box.max + player.position}
		rl.DrawBoundingBox(shifted_box, rl.YELLOW)

		/*END   3D*/ rl.EndMode3D()
		rl.DrawFPS(10, 10)
		rl.DrawText(strings.clone_to_cstring(fmt.tprintf("%v, %v", target, face)), 550, 20, 15, rl.WHITE)
		rl.EndDrawing()
	}
}

get_or_create_chunk :: proc(world: ^World, chunk_position: IVec3) -> (chunk: ^Chunk) {
	ok: bool
	if chunk, ok = &world.chunks[chunk_position]; ok {
		return
	}
	world.chunks[chunk_position] = Chunk { }
	chunk = &world.chunks[chunk_position]
	for z in 0..<32 {
		for y in 0..<32 {
			for x in 0..<32 {
				world_pos := IVec3{
					chunk_position.x*CHUNK_SIZE + x,
				 	chunk_position.y*CHUNK_SIZE + y,
					chunk_position.z*CHUNK_SIZE + z,
				}

				if world_pos.y == 0 {
					chunk.voxels[x][y][z] = VoxelKind.Dirt
				} else if world_pos.y == -1 {
					chunk.voxels[x][y][z] = VoxelKind.Stone
				}
			}
		}
	}
	return
}

create_mesh :: proc(chunk: ^Chunk, color_map: map[VoxelKind][6]rl.Color) {
	neighbors := []IVec3{
		IVec3{1, 0, 0}, // Right
		IVec3{-1, 0, 0}, // Left
		IVec3{0, 1, 0}, // Up
		IVec3{0, -1, 0}, // Down
		IVec3{0, 0, 1}, // Forward
		IVec3{0, 0, -1}, // Backward
	}
	mesh := rl.Mesh{}
	vertices := make([dynamic]f32)
	normals := make([dynamic]f32)
	colors := make([dynamic]u8)
	indices := make([dynamic]u16)
	buffers := RenderBuffers{vertices, normals, colors, indices}
	defer delete(buffers.vertices)
	defer delete(buffers.normals)
	defer delete(buffers.colors)
	defer delete(buffers.indices)
	//i := 0

	for x, ix in chunk.voxels {
		for y, iy in x {
			for kind, iz in y {
				if kind == VoxelKind.Air {
					continue
				}
				c, ok := color_map[kind]
				if !ok {
					log.warnf("voxel kind '%v' has no color map", kind)
					c = CUBE_COLORS_UNKNOWN
				}
				i := 0
				for offset in neighbors {
					neighbor := IVec3{ix + offset.x, iy + offset.y, iz + offset.z}
					oob := neighbor.x < 0 || neighbor.x >= 32 || neighbor.y < 0 || neighbor.y >= 32 || neighbor.z < 0 || neighbor.z >= 32
					if !oob && chunk.voxels[neighbor.x][neighbor.y][neighbor.z] != VoxelKind.Air { // face is blocked
						continue
					}
					gen_quad_vertices(
						&buffers,
					 	rl.Vector3{f32(ix), f32(iy), f32(iz)},
						rl.Vector3(offset),
						c[i],
					)
					i += 1
				}
			}
		}
	}

	mesh.vertices = cast([^]f32) rl.MemAlloc(u32(len(buffers.vertices) * size_of(f32)))
	mesh.normals = cast([^]f32) rl.MemAlloc(u32(len(buffers.normals) * size_of(f32)))
	mesh.colors = cast([^]u8) rl.MemAlloc(u32(len(buffers.colors) * size_of(u8)))
	mesh.indices = cast([^]u16) rl.MemAlloc(u32(len(buffers.indices) * size_of(u16)))
	mesh.vertexCount = i32(len(buffers.vertices) / 3)
	mesh.triangleCount = i32(len(buffers.indices) / 3)

	mem.copy(mesh.vertices, raw_data(buffers.vertices), len(buffers.vertices) * size_of(f32))
	mem.copy(mesh.normals, raw_data(buffers.normals), len(buffers.normals) * size_of(f32))
	mem.copy(mesh.colors, raw_data(buffers.colors), len(buffers.colors) * size_of(u8))
	mem.copy(mesh.indices, raw_data(buffers.indices), len(buffers.indices) * size_of(u16))
	rl.UploadMesh(&mesh, false)
	chunk.model = rl.LoadModelFromMesh(mesh)
}

free_model :: proc(model: ^rl.Model) {
	rl.UnloadModel(model^)
}

get_voxel :: proc(world: ^World, position: IVec3) -> VoxelKind {
	// convert to chunk coords
	chunk_pos, chunk_local_pos := world_to_chunk_coord(position)
	//chunk := &world.chunks[chunk_pos]
	chunk := get_or_create_chunk(world, chunk_pos)
	return chunk.voxels[chunk_local_pos.x][chunk_local_pos.y][chunk_local_pos.z]
}

set_voxel :: proc(world: ^World, position: IVec3, kind: VoxelKind) {
	// convert to chunk coords
	chunk_pos, chunk_local_pos := world_to_chunk_coord(position)
 	//chunk := &world.chunks[chunk_pos]
	chunk := get_or_create_chunk(world, chunk_pos)
	if mod, ok := &chunk.model.?; ok {
		free_model(mod)
	}
	o_kind := chunk.voxels[chunk_local_pos.x][chunk_local_pos.y][chunk_local_pos.z]
	if kind == o_kind {
		return
	}
	chunk.model = nil // this should be optimized to not be unconditional
	chunk.voxels[chunk_local_pos.x][chunk_local_pos.y][chunk_local_pos.z] = kind
}

// call within a draw call
draw_cube :: proc(position: rl.Vector3) {
	rl.DrawCube(position, 1.0, 1.0, 1.0, rl.WHITE)
}

gen_quad_vertices :: proc(render_buffers: ^RenderBuffers, position: rl.Vector3, direction: rl.Vector3, color: rl.Color) {
	for _ in 0..<4 {
		append(&render_buffers.colors, color.r, color.g, color.b, color.a)
		append(&render_buffers.normals, f32(direction.x), f32(direction.y), f32(direction.z))
	}
	// indices
	ind := u16(len(render_buffers.vertices)/3)
	append(&render_buffers.indices, ind, ind+1, ind+2, ind, ind+2, ind+3)
	nml := linalg.normalize(direction)
	ref := rl.Vector3{0,1,0}
	if abs(nml.x) < abs(nml.y) {
		ref = rl.Vector3{1,0,0}
	}
	r := linalg.normalize(linalg.cross(nml, ref)) * 0.5
	u := linalg.normalize(linalg.cross(nml, r)) * 0.5
	center := position + rl.Vector3{0.5,0.5,0.5} + nml * 0.5 // center of quad face
	// 0.5 offset so block edges are on integer bounds [x, x+1], [y, y+1], etc..
	p1 := center - r - u
	append(&render_buffers.vertices, p1.x, p1.y, p1.z)
	p2 := center + r - u
	append(&render_buffers.vertices, p2.x, p2.y, p2.z)
	p3 := center + r + u
	append(&render_buffers.vertices, p3.x, p3.y, p3.z)
	p4 := center - r + u
	append(&render_buffers.vertices, p4.x, p4.y, p4.z)
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
