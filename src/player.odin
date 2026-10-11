package main

import "core:c"
import "core:log"
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

update_player :: proc(controller: ^PlayerController, world: ^World, dt: f64) {
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
		move_vector += rl.Vector3{0,0,1} // strafe-right
	}
	if rl.IsKeyDown(rl.KeyboardKey.A) {
		move_vector -= rl.Vector3{0,0,1}
	}
	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		move_vector += rl.Vector3{0,1,0}
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
		move_vector -= rl.Vector3{0,1,0}
	}
	if linalg.length(move_vector) > 0 {
		move_vector = linalg.normalize(move_vector) * MOVE_SPEED * f32(dt)
	}
	// we need to rotate based on players camera X rotation

	// these are at the 'feet'
	new_position := last_position + move_vector //desired

	// center
	last_position_centered := last_position + rl.Vector3(controller.bounding_box.max + controller.bounding_box.min)/2
	new_position_centered := last_position_centered + move_vector
	// bounding check
	move_vector = aabb(world, last_position_centered, new_position_centered, controller.bounding_box) //bounded
	new_position = last_position + move_vector

	// update controller
	controller.position = new_position
	controller.camera.position = controller.position + rl.Vector3{0.4,CAMERA_Y_OFFSET,0}
	controller.camera.target += move_vector
	rl.UpdateCameraPro(&controller.camera, rl.Vector3(0), rot, 0.)
	controller.direction = controller.camera.target - controller.camera.position
}
