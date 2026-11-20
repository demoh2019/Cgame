// The weather simulation stores wind in world X/Z coordinates.
// Imported models and every MultiMesh instance may have its own yaw and scale.
// Project a world-space horizontal displacement onto their local X/Z axes.
// For orthogonal bases (including nonuniform scale) this is exactly the
// inverse model transform, avoiding a per-vertex mat3 inverse operation.
vec2 aa_wind_world_to_local_xz(vec2 horizontal_world, mat4 model) {
	vec3 world_vector = vec3(horizontal_world.x, 0.0, horizontal_world.y);
	vec3 local_x_axis = model[0].xyz;
	vec3 local_z_axis = model[2].xyz;
	float local_x = dot(world_vector, local_x_axis)
		/ max(dot(local_x_axis, local_x_axis), 0.0001);
	float local_z = dot(world_vector, local_z_axis)
		/ max(dot(local_z_axis, local_z_axis), 0.0001);
	return vec2(local_x, local_z);
}
