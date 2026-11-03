// Water's surface for the material stage: waves, reflection, refraction and the sun's glint.

// The wave's normal at world `xz`, from the slope of `water_wave` plus a finer ripple that
// only bends the light.
fn water_normal(xz: vec2<f32>, t: f32) -> vec3<f32> {
    if !water_waves {
        return vec3<f32>(0.0, 1.0, 0.0);
    }
    let e = 0.05;
    let h = water_wave(xz, t);
    let dx = (water_wave(xz + vec2<f32>(e, 0.0), t) - h) / e;
    let dz = (water_wave(xz + vec2<f32>(0.0, e), t) - h) / e;
    let ripple = vec2<f32>(
        sin(xz.x * 4.3 + xz.y * 1.7 + t * 3.1),
        sin(xz.y * 3.9 - xz.x * 2.3 + t * 2.7),
    ) * 0.035;
    // The surface sinks by `water_wave`, so its slope is the negative.
    let slope = vec2<f32>(dx, dz) * WATER_AMPLITUDE * 2.5 - ripple;
    return normalize(vec3<f32>(slope.x, 1.0, slope.y));
}

// The distance from the camera of what lies at screen point `screen` with reversed `depth`.
fn distance_at(screen: vec2<f32>, depth: f32) -> f32 {
    if depth <= 0.0 {
        return 1e4;
    }
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return length(view.xyz / view.w);
}

fn water_surface(input: MaterialInput) -> vec4<f32> {
    let world = input.position + frame.camera_position;
    let to_eye = normalize(-input.position);
    let top = input.face == 1u;
    var n = input.normal;
    if top {
        n = water_normal(world.xz, frame.time);
        // Seen from below, the surface faces down.
        n = select(n, -n, input.normal.y < 0.0);
    }
    // What lies behind the surface, a little bent by the waves.
    let behind_size = vec2<f32>(textureDimensions(opaque_color));
    let bent = clamp(input.screen + n.xz * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let texel = vec2<i32>(min(bent * behind_size, behind_size - 1.0));
    let behind = textureLoad(opaque_color, texel, 0).rgb;
    let behind_distance = distance_at(bent, textureLoad(opaque_depth, texel, 0));
    let thickness = max(behind_distance - length(input.position), 0.0);

    // The water's own colour (the biome's tint over its texture) in the light around it.
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let ambient = ambient_light(input.position, up, input.light, input.colored_light);
    let sun = direct_light() * sun_strength * sun_shadow(input.position, up, frame.light_direction.y);
    let body = input.albedo.rgb * input.tint.rgb * (ambient + sun * 0.4);
    // Light is absorbed red first, then green: deep water turns blue, then the water's colour.
    let reach = mix(2.0, 14.0, water_clarity);
    let absorb = exp(-thickness / reach * vec3<f32>(2.2, 0.9, 0.6));
    var color = mix(body, behind, absorb);

    // Underwater, the surface overhead is mostly a window.
    if frame.eye_in == 1u {
        return vec4<f32>(mix(color, body, 0.25), 1.0);
    }

    // Reflection, by Schlick's Fresnel (water's F0 is 0.02).
    let cos_v = clamp(dot(n, to_eye), 0.0, 1.0);
    let fresnel = 0.02 + 0.98 * pow(1.0 - cos_v, 5.0);
    var mirrored = mix(frame.fog_color, frame.sky_color, 0.5) * mix(0.15, 1.0, daylight());
    if reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
        mirrored = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
    }
    // Covered water (little sky light) reflects little of the sky.
    color = mix(color, mirrored, fresnel * smoothstep(0.2, 0.8, input.light.y));

    // The sun's glint.
    let h = normalize(frame.light_direction + to_eye);
    let glint = pow(max(dot(n, h), 0.0), 400.0) * 4.0;
    color += sun * glint;
    return vec4<f32>(shoulder(color), 1.0);
}
