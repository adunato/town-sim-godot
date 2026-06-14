shader_type canvas_item;
render_mode unshaded;

uniform sampler2D terrain_type_1_texture : filter_linear, repeat_enable;
uniform sampler2D terrain_type_2_texture : filter_linear, repeat_enable;
uniform sampler2D terrain_mask : filter_nearest, repeat_disable;
uniform vec2 terrain_world_origin = vec2(0.0, 0.0);
uniform vec2 terrain_world_size = vec2(1.0, 1.0);
uniform float texture_repeat_world_size = 128.0;

varying vec2 terrain_local_position;


void vertex() {
	terrain_local_position = VERTEX;
}


void fragment() {
	vec2 surface_uv = clamp(terrain_local_position / terrain_world_size, vec2(0.0, 0.0), vec2(1.0, 1.0));
	vec2 world_position = terrain_world_origin + terrain_local_position;
	vec2 terrain_texture_uv = world_position / texture_repeat_world_size;
	float terrain_type_mask = texture(terrain_mask, surface_uv).r;
	vec4 terrain_1_color = texture(terrain_type_1_texture, terrain_texture_uv);
	vec4 terrain_2_color = texture(terrain_type_2_texture, terrain_texture_uv);
	COLOR = mix(terrain_1_color, terrain_2_color, step(0.5, terrain_type_mask));
}
