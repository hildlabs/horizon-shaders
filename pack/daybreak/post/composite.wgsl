// The last pass, at full size: the picture with its glow and sun rays, exposure that follows
// how much light reaches the eye, a gentle filmic curve, the colour grade and a vignette.
override bloom: f32 = 0.5;
override exposure: f32 = 1.0;
override contrast: f32 = 0.12;
override saturation: f32 = 1.05;
override vignette: f32 = 0.25;
override haze: f32 = 0.6;
override relight_entities: bool = true;

// Horizon's material stage lights terrain only: mobs, block entities and particles keep
// vanilla's light, as bright in a tree's shade as in the sun, and stand out against Daybreak's
// shaded terrain. Here they get the sun's shadow and the sky's blue in the shade, by the same
// shadow map. Terrain marks itself (`set_surface` in material.wgsl); water lies on the
// mirrored plane and is left alone, as are bright pixels (flames, glowing eyes).
fn relight(c: vec3<f32>, uv: vec2<f32>, depth: f32) -> vec3<f32> {
    if !relight_entities || depth <= 0.0 || frame.dimension != 0 || frame.has_shadow == 0u {
        return c;
    }
    // Indoors, vanilla's own light already darkens what is out of the sky; don't twice.
    let weight = daylight() * smoothstep(0.3, 0.8, frame.eye_light_smooth.y)
        * smoothstep(0.0, 0.1, frame.light_direction.y) * (1.0 - frame.rain * 0.8);
    if weight <= 0.0 || luminance(c) > 0.85 {
        return c;
    }
    if surface_at(vec2<i32>(uv * frame.resolution)).present {
        return c;
    }
    let p = view_position(uv, depth);
    let dist = length(p);
    if dist > frame.shadow_distance {
        return c;
    }
    if frame.has_reflection == 1u && abs(p.y + frame.camera_position.y - frame.water_plane) < 0.15 {
        return c;
    }
    // Pushed a little toward the light so a mob doesn't shadow its own sunlit side.
    let s = shadow_position(p + frame.light_direction * 0.2);
    if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) {
        return c;
    }
    let m = frame.shadow_view_proj;
    let z = s.z - length(vec3<f32>(m[0].z, m[1].z, m[2].z)) * 0.15;
    let texel = 1.0 / frame.shadow_resolution;
    var lit = 0.0;
    for (var i = 0; i < 4; i++) {
        let o = vec2<f32>(f32(i & 1), f32(i >> 1u)) * 2.0 - 1.0;
        lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + o * texel, z);
    }
    lit = mix(lit * 0.25, 1.0, smoothstep(0.85, 1.0, dist / frame.shadow_distance));
    // In the sun a touch of its warmth, in the shade the sky's blue at the shade's brightness.
    let sun = direct_light();
    let warm = mix(vec3<f32>(1.0), sun / max(luminance(sun), 0.01), 0.25);
    let sky = mix(frame.sky_color, vec3<f32>(0.9, 0.95, 1.0), 0.3);
    let shade = sky / max(luminance(sky), 0.01) * 0.58;
    return c * mix(vec3<f32>(1.0), mix(shade, warm, lit), weight);
}

// Air between the eye and distant land: it fades toward the sky's colour with distance and
// takes the sun's warmth on the side the sun is on. What gives the land its depth.
fn aerial(c: vec3<f32>, uv: vec2<f32>, depth: f32) -> vec3<f32> {
    if haze <= 0.0 || depth <= 0.0 || frame.dimension != 0 || frame.eye_in != 0u {
        return c;
    }
    let p = view_position(uv, depth);
    let dist = length(p);
    let mu = max(dot(p / dist, frame.sun_direction), 0.0);
    let day = daylight();
    var air = mix(frame.fog_color, frame.sky_color, 0.35);
    air += vec3<f32>(1.0, 0.72, 0.45) * pow(mu, 6.0) * 0.45 * day;
    let amount = (1.0 - exp(-dist * 0.0035 * haze)) * mix(0.35, 0.75, day) * (1.0 + frame.rain * 0.5);
    return mix(c, air, clamp(amount, 0.0, 0.85));
}

fn post(input: PostInput) -> vec4<f32> {
    var c = relight(input.color.rgb, input.uv, input.depth);
    c = aerial(c, input.uv, input.depth);
    c += textureSampleLevel(bloom_b, linear_sampler, input.uv, 0.0).rgb * bloom;
    c += textureSampleLevel(rays, linear_sampler, input.uv, 0.0).rgb;

    // Deep in a cave, the eye opens a little; under the open sky, it doesn't.
    let eye = frame.eye_light_smooth;
    let lit = max(eye.x, eye.y * mix(0.3, 1.0, daylight()));
    c *= exposure * mix(1.35, 1.0, smoothstep(0.0, 0.6, lit));

    // Underwater, red goes first.
    c = mix(c, c * vec3<f32>(0.45, 0.8, 0.95), frame.in_water * 0.7);

    c = shoulder(c);
    // Contrast as an S-curve around the middle grey, so blacks and whites stay where they are.
    c = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
    c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
    c = mix(vec3<f32>(luminance(c)), c, saturation);

    if vignette > 0.0 {
        let aspect = frame.resolution.x / frame.resolution.y;
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.45, 1.15, d) * vignette;
    }
    // Half a step of 8-bit noise hides banding in skies and glows.
    c += (ign(input.pixel) - 0.5) / 255.0;
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
