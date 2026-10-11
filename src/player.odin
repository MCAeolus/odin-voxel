package main

import "core:math/linalg"
import rl "vendor:raylib"


CAMERA_Y_OFFSET :: 1.6 // default bounding box max height is 1.8
MOVE_SPEED : f32 : 3.0
LOOK_SPEED : f32 : 4.0

PlayerController :: struct {
	direction: rl.Vector3,
	position: rl.Vector3,
	camera: rl.Camera3D,
	bounding_box: rl.BoundingBox,
}

update_player :: proc(controller: ^PlayerController, dt: f64) {
	last_position := controller.position

	// head swivel
	delta_swivel := rl.GetMouseDelta()
	rot := rl.Vector3{
		delta_swivel.x * LOOK_SPEED * f32(dt),
		delta_swivel.y * LOOK_SPEED * f32(dt),
		0, // roll
	}

	// positional movement
	move_vector := rl.Vector3{}
	if rl.IsKeyDown(rl.KeyboardKey.W) {
		move_vector += rl.Vector3{1,0,0} // forward == x-axis move
	}
	if rl.IsKeyDown(rl.KeyboardKey.S) {
		move_vector -= rl.Vector3{1,0,0}
	}
	if rl.IsKeyDown(rl.KeyboardKey.D) {
		move_vector += rl.Vector3{0,1,0} // strafe-right
	}
	if rl.IsKeyDown(rl.KeyboardKey.A) {
		move_vector -= rl.Vector3{0,1,0}
	}
	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		move_vector += rl.Vector3{0,0,1}
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
		move_vector -= rl.Vector3{0,0,1}
	}
	if linalg.length(move_vector) > 0 {
		move_vector = linalg.normalize(move_vector) * MOVE_SPEED * f32(dt)
	}
	new_position := last_position + move_vector
	// bounding check
	//...
	controller.position = new_position
	rl.UpdateCameraPro(&controller.camera, move_vector, rot, 0.)
	controller.direction = controller.camera.target - controller.camera.position
}
