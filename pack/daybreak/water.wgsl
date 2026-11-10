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

// Screen-space reflection: the reflected ray `r` from camera-relative `p`, marched across the
// world's picture before translucent terrain (`opaque_color` and `opaque_depth`). It costs no
// pass of its own: the mirror draws the terrain a second time, which also keeps Horizon from
// culling the world on the GPU. What the screen doesn't show (above its top, behind the
// camera) is the sky's colour, `fallback`. Twelve steps, each longer than the last, out to
// about 100 blocks, then four halvings around the first one that passes just behind something.
const SSR_STEPS: i32 = 12;
const SSR_REFINE: i32 = 4;

fn screen_of(q: vec3<f32>) -> vec3<f32> {
    let clip = frame.projection * (frame.view * vec4<f32>(q, 1.0));
    if clip.w <= 0.01 {
        return vec3<f32>(-1.0);
    }
    let ndc = clip.xyz / clip.w;
    return vec3<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, ndc.z);
}

fn screen_reflection(p: vec3<f32>, r: vec3<f32>, jitter: f32, fallback: vec3<f32>) -> vec3<f32> {
    let size = vec2<f32>(textureDimensions(opaque_color));
    var t_prev = 0.0;
    var t = 0.6 * (0.6 + 0.8 * jitter);
    for (var i = 0; i < SSR_STEPS; i++) {
        let q = p + r * t;
        let s = screen_of(q);
        if any(s.xy < vec2<f32>(0.0)) || any(s.xy > vec2<f32>(1.0)) {
            break;
        }
        let texel = vec2<i32>(min(s.xy * size, size - 1.0));
        let scene = textureLoad(opaque_depth, texel, 0);
        // Depth is reversed: the scene is nearer than the ray's point, so the ray went behind it.
        if scene > s.z {
            // Close enough behind to be what it hit, not something far in front of it.
            let gap = length(q) - distance_at(s.xy, scene);
            if gap < max(1.0, t * 0.35) {
                var lo = t_prev;
                var hi = t;
                for (var j = 0; j < SSR_REFINE; j++) {
                    let mid = 0.5 * (lo + hi);
                    let m = screen_of(p + r * mid);
                    let mt = vec2<i32>(clamp(m.xy, vec2<f32>(0.0), vec2<f32>(1.0)) * (size - 1.0));
                    if textureLoad(opaque_depth, mt, 0) > m.z {
                        hi = mid;
                    } else {
                        lo = mid;
                    }
                }
                let h = screen_of(p + r * hi);
                let uv = clamp(h.xy, vec2<f32>(0.0), vec2<f32>(1.0));
                let hit = textureLoad(opaque_color, vec2<i32>(uv * (size - 1.0)), 0).rgb;
                // Fade out toward the screen's edges, where the picture runs out.
                let edge = min(min(uv.x, 1.0 - uv.x) * 8.0, min(uv.y, 1.0 - uv.y) * 6.0);
                return mix(fallback, hit, clamp(edge, 0.0, 1.0));
            }
            // Far behind: the ray passed behind something in front of what it reflects (a
            // tree before the shore). It carries on.
        }
        t_prev = t;
        t *= 1.55;
    }
    return fallback;
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
    // Covered water (little sky light) reflects little of the sky.
    let amount = fresnel * smoothstep(0.2, 0.8, input.light.y);
    let r = reflect(-to_eye, n);
    // The sky in the reflected direction: vanilla's fog at the horizon, its sky colour above.
    var mirrored = mix(frame.fog_color, frame.sky_color, smoothstep(0.0, 0.35, r.y))
        * mix(0.15, 1.0, daylight());
    if reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
        mirrored = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
    } else if screen_reflections && top && amount > 0.02 {
        // Looking almost straight down, the reflection is a few percent: not worth the march.
        mirrored = screen_reflection(input.position, r, ign(input.screen * frame.resolution), mirrored);
    }
    color = mix(color, mirrored, amount);

    // The sun's glint.
    let h = normalize(frame.light_direction + to_eye);
    let glint = pow(max(dot(n, h), 0.0), 400.0) * 4.0;
    color += sun * glint;
    return vec4<f32>(shoulder(color), 1.0);
}
