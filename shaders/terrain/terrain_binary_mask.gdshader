shader_type canvas_item;
render_mode unshaded;

uniform sampler2D terrain_type_1_texture : filter_linear, repeat_enable;
uniform sampler2D terrain_type_2_texture : filter_linear, repeat_enable;
uniform sampler2D terrain_mask : filter_linear, repeat_disable;
uniform sampler2D terrain_type_1_height : filter_linear, repeat_enable;
uniform sampler2D terrain_type_2_height : filter_linear, repeat_enable;
uniform vec2 terrain_world_origin = vec2(0.0, 0.0);
uniform vec2 terrain_world_size = vec2(1.0, 1.0);
uniform float texture_repeat_world_size = 256.0;
uniform float height_blend_influence = 1.75;
uniform float height_blend_contrast = 2.75;

varying vec2 terrain_local_position;


void vertex() {
	terrain_local_position = VERTEX;
}


void fragment() {
	vec2 surface_uv = clamp(terrain_local_position / terrain_world_size, vec2(0.0, 0.0), vec2(1.0, 1.0));
	vec2 world_position = terrain_world_origin + terrain_local_position;
	vec2 terrain_texture_uv = world_position / texture_repeat_world_size;
	float terrain_type_mask = clamp(texture(terrain_mask, surface_uv).r, 0.0, 1.0);
	float terrain_1_height = clamp((texture(terrain_type_1_height, terrain_texture_uv).r - 0.5) * height_blend_contrast + 0.5, 0.0, 1.0);
	float terrain_2_height = clamp((texture(terrain_type_2_height, terrain_texture_uv).r - 0.5) * height_blend_contrast + 0.5, 0.0, 1.0);
	float boundary_weight = 1.0 - smoothstep(0.0, 0.75, abs(terrain_type_mask - 0.5) * 2.0);
	float height_delta = terrain_2_height - terrain_1_height;
	float height_aware_mask = clamp(terrain_type_mask + height_delta * height_blend_influence * boundary_weight, 0.0, 1.0);
	vec4 terrain_1_color = texture(terrain_type_1_texture, terrain_texture_uv);
	vec4 terrain_2_color = texture(terrain_type_2_texture, terrain_texture_uv);
	COLOR = mix(terrain_1_color, terrain_2_color, height_aware_mask);
}
