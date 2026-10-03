package main

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
	voxels: map[IVec3]struct{}, // hash set
	mesh: ^rl.Mesh
}


main :: proc() {
	context.logger = log.create_console_logger()
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
			world.voxels[IVec3{x - 16, 0, z - 16}] = struct{}{}
		}
	}

	for !rl.WindowShouldClose() {
		// game updates
		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			keys := collect_keys(world.voxels)
			delete_key(&world.voxels, rand.choice(keys[:]))
		}
		// render
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{60, 0, 20, 255}) // (60, 0, 8)
		/*BEGIN 3D*/ rl.BeginMode3D(camera)
		if (world.mesh == nil) {
			create_mesh(&world)
		}
		rl.DrawMesh(world.mesh^, rl.LoadMaterialDefault(), rl.Matrix{})
		//draw_mesh(world.mesh)
		//for vox in world.voxels {
		//	draw_cube_colored(ivec_to_vec(vox), CUBE_COLORS)
		//}
		/*END   3D*/ rl.EndMode3D()
		rl.EndDrawing()
	}
}

create_mesh :: proc(world: ^World) {
	mesh := rl.Mesh{}
	mesh.vertexCount = c.int(36 * len(world.voxels))
	mesh.triangleCount = c.int(12 * len(world.voxels))
	//mesh.vertices = cast([^]f32) rl.MemAlloc(c.uint(mesh.vertexCount * 3 * size_of(f32)))
	//mesh.normals = cast([^]f32) rl.MemAlloc(c.uint(mesh.vertexCount * 3 * size_of(f32)))
	//mesh.colors = cast([^]u8) rl.MemAlloc(c.uint(mesh.vertexCount * 4 * size_of(u8)))
	vertices := make([dynamic]f32, mesh.vertexCount * 3)
	normals := make([dynamic]f32, mesh.vertexCount * 3)
	colors := make([dynamic]u8, mesh.vertexCount * 4)
	i := 0
	for vox in world.voxels {
		gen_cube_vertices(vertices[i*36:], normals[i*36:], colors[i*36:], ivec_to_vec(vox), CUBE_COLORS)
		i += 1
	}

}


// call within a draw call
draw_cube :: proc(position: rl.Vector3) {
	rl.DrawCube(position, 1.0, 1.0, 1.0, rl.WHITE)
}


gen_cube_vertices :: proc(vert_buf: ^[dynamic]f32, norm_buf: ^[dynamic]f32, color_buf: ^[dynamic]u8, position: rl.Vector3, colors: [6]rl.Color, w: f32 = 1, h: f32 = 1, l: f32 = 1) {
	w2 := w / 2
	h2 := h / 2
	l2 := l / 2
	//front
	for _ in 0..<4 { // 4 vertices per side
		append(color_buf, colors[0].r, colors[0].g, colors[0].b, colors[0].a)
		append(norm_buf, 0, 0, 1)
	}
	append(vert_buf,
	 	position.x - w2, position.y - h2, position.z + l2, //bottom-left
		position.x + w2, position.y - h2, position.z + l2, //bottom-right
		position.x + w2, position.y + h2, position.z + l2, //top-right
		position.x - w2, position.y + h2, position.z + l2, //top-left
	)
	/*rlgl.Color4ub(colors[0].r, colors[0].g, colors[0].b, colors[0].a)
	rlgl.Normal3f(0, 0, 1) // face towards 'us'
	rlgl.Vertex3f(position.x - w2, position.y - h2, position.z + l2) // bottom-left
	rlgl.Vertex3f(position.x + w2, position.y - h2, position.z + l2) // bottom-right
	rlgl.Vertex3f(position.x + w2, position.y + h2, position.z + l2) // top-right
	rlgl.Vertex3f(position.x - w2, position.y + h2, position.z + l2) // top-left*/
	/*
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
