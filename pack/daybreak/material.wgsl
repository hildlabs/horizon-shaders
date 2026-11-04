// The lit colour of each point of terrain, before Horizon's alpha test and fog.
// Vanilla's own is albedo * tint * lightmap; Daybreak lights the Overworld itself, with the
// sun or moon (shadowed), the sky and blocks, and leaves other dimensions close to vanilla.
override shadows: bool = true;
override shadow_softness: u32 = 1u;
override sun_strength: f32 = 1.0;
override ambient_strength: f32 = 1.0;
override block_light_strength: f32 = 1.0;
override colored_lights: bool = true;
override reflections: bool = true;
override water_clarity: f32 = 0.5;
override relight_entities: bool = true;

fn is_foliage(material: u32) -> bool {
    return material >= MAT_LEAVES && material <= MAT_VINE;
}

fn material(input: MaterialInput) -> Surface {
    // Marks the pixel as terrain Daybreak lit itself, for the composite's `relight_entities`
    // (translucent terrain stores nothing). Nothing reads it without shadows, so it isn't written.
    if relight_entities && shadows {
        set_surface(input.normal, 0.0, 0.0);
    }
    // Lava glows by itself.
    if input.fluid == 2u {
        return Surface(vec4<f32>(input.albedo.rgb * input.tint.rgb * 1.05, input.albedo.a));
    }
    if frame.dimension != 0 {
        // The Nether and the End: no sun, so their own glow and the light of blocks; vanilla's
        // face shade stays in the tint, since nothing else shades the faces here.
        let light = underworld_light(input.position, input.light, input.colored_light);
        var color = input.albedo.rgb * input.tint.rgb * light;
        color = max(color, input.albedo.rgb * input.tint.rgb * input.emission);
        color = mix(color, input.albedo.rgb * input.tint.rgb, frame.night_vision * 0.85);
        return Surface(vec4<f32>(shoulder(color), input.albedo.a));
    }
    if input.fluid == 1u {
        return Surface(water_surface(input));
    }

    let n = input.normal;
    let foliage = is_foliage(input.material);
    let l = frame.light_direction;

    // Direct light, eased in over the first few degrees so the terminator is soft. Never past
    // it: a face turned away from the sun, or grazed by it, can only be striped by its own
    // shadow (acne), so it gets none of the sun at all.
    let facing = dot(n, l);
    var ndl = max(facing, 0.0) * smoothstep(0.0, 0.2, facing);
    // Light shining through leaves and grass toward the eye: they glow against a low sun.
    let to_eye = normalize(-input.position);
    let through = pow(max(dot(to_eye, -l), 0.0), 4.0);
    var tint_direct = vec3<f32>(1.0);
    if input.material == MAT_LEAVES {
        // A leaf block is a cube: lit by its faces, plus what passes through it.
        ndl = ndl * 0.85 + 0.12 + through * 0.45;
        tint_direct = mix(vec3<f32>(1.0), vec3<f32>(0.85, 1.0, 0.55), through);
    } else if foliage {
        // Thin plants are lit from either side.
        ndl = 0.3 + 0.4 * abs(facing) + through * 0.4;
        tint_direct = mix(vec3<f32>(1.0), vec3<f32>(0.85, 1.0, 0.55), through);
    }
    var direct = vec3<f32>(0.0);
    if ndl > 0.0 && sun_strength > 0.0 {
        let offset = select(n, l, foliage && input.material != MAT_LEAVES);
        let slant = select(facing, 1.0, foliage && input.material != MAT_LEAVES);
        // Beyond the shadow map, the sky light says whether the sun reaches.
        let open = smoothstep(0.0, 0.4, input.light.y);
        direct = direct_light() * tint_direct * (SUN_INTENSITY * sun_strength) * ndl * open
            * sun_shadow(input.position, offset, slant);
    }

    let light = ambient_light(input.position, n, input.light, input.colored_light) + direct;
    // Keep the tint's biome colour and ambient occlusion, without vanilla's face shade:
    // the light above already shades each face by where it turns.
    let tint = input.tint.rgb / face_shade(n);
    var color = input.albedo.rgb * tint * light;
    // Glowing blocks keep their own brightness whatever light is on them.
    color = max(color, input.albedo.rgb * input.tint.rgb * input.emission);
    // Night vision shows everything as if lit.
    color = mix(color, input.albedo.rgb * input.tint.rgb, frame.night_vision * 0.85);
    return Surface(vec4<f32>(shoulder(color), input.albedo.a));
}
