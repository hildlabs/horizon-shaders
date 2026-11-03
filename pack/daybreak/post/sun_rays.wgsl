// Sun rays and glare, at a quarter of the world's size (both are soft, so a sixteenth of the
// pixels is plenty):
// - rays: light scattered toward the camera through gaps in leaves and terrain. Each pixel
//   marches toward the sun on the screen and counts how much open sky it crosses;
// - glare: what a lens makes of looking into the sun: a bright bloom around it, a wide halo,
//   a horizontal streak and faint ghosts mirrored through the centre, all dimmed by how much
//   of the sun is hidden.
override god_rays: f32 = 0.5;
override sun_glare: f32 = 0.7;

const STEPS: i32 = 16;

// A soft disc of `radius` around `center`, in screen heights.
fn ghost(uv: vec2<f32>, center: vec2<f32>, radius: f32, aspect: f32) -> f32 {
    let d = length((uv - center) * vec2<f32>(aspect, 1.0));
    return 1.0 - smoothstep(radius * 0.4, radius, d);
}

fn post(input: PostInput) -> vec4<f32> {
    let off = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (god_rays <= 0.0 && sun_glare <= 0.0) || frame.dimension != 0 || frame.eye_in != 0u {
        return off;
    }
    let l = frame.light_direction;
    let strength = smoothstep(0.0, 0.1, l.y) * (1.0 - frame.rain);
    // How directly the camera looks toward the light: rays and glare only show facing it.
    let forward = -frame.view_inverse[2].xyz;
    let facing = smoothstep(0.2, 0.9, dot(forward, l));
    if strength * facing <= 0.0 {
        return off;
    }
    let clip = frame.projection * frame.view * vec4<f32>(l, 0.0);
    let sun_uv = vec2<f32>(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
    let aspect = frame.resolution.x / frame.resolution.y;
    let to_sun = (input.uv - sun_uv) * vec2<f32>(aspect, 1.0);
    let color = direct_light() * (0.6 + 0.4 * sun_low());
    var light = vec3<f32>(0.0);

    if god_rays > 0.0 {
        let delta = (sun_uv - input.uv) / f32(STEPS) * 0.85;
        var uv = input.uv + delta * ign(input.pixel);
        var sum = 0.0;
        var decay = 1.0;
        for (var i = 0; i < STEPS; i++) {
            uv += delta;
            sum += select(0.0, decay, depth_at(uv) == 0.0);
            decay *= 0.94;
        }
        let near = 1.0 - smoothstep(0.0, 0.9, length(to_sun));
        // Rays are light seen past something in the way. Open sky, which every step of its
        // march also sees, only gets a trace, so a clear sky doesn't wash out white.
        let own = select(1.0, 0.2, depth_at(input.uv) == 0.0);
        light += color * (sum / f32(STEPS)) * near * own * 0.6 * god_rays;
    }

    if sun_glare > 0.0 {
        // How much of the sun shows: nine taps over its disc, none past the screen's edge.
        var seen = 0.0;
        for (var i = 0; i < 9; i++) {
            let o = (vec2<f32>(f32(i % 3), f32(i / 3)) - 1.0) * vec2<f32>(0.012 / aspect, 0.012);
            let p = sun_uv + o;
            let inside = all(p >= vec2<f32>(0.0)) && all(p <= vec2<f32>(1.0));
            seen += select(0.0, 1.0, inside && depth_at(p) == 0.0);
        }
        seen /= 9.0;
        if seen > 0.0 {
            let d = length(to_sun);
            let core = exp(-d * d * 90.0) * 0.9;
            let halo = exp(-d * 5.0) * 0.28;
            let streak = exp(-abs(to_sun.y) * 70.0) * exp(-abs(to_sun.x) * 2.2) * 0.22;
            // Ghosts on the line from the sun through the centre, each its own tint.
            let axis = vec2<f32>(0.5) - sun_uv;
            var ghosts = vec3<f32>(0.0);
            ghosts += vec3<f32>(0.5, 0.8, 1.0) * ghost(input.uv, sun_uv + axis * 1.4, 0.05, aspect) * 0.08;
            ghosts += vec3<f32>(1.0, 0.75, 0.4) * ghost(input.uv, sun_uv + axis * 1.8, 0.1, aspect) * 0.05;
            ghosts += vec3<f32>(0.6, 1.0, 0.7) * ghost(input.uv, sun_uv + axis * 2.5, 0.16, aspect) * 0.035;
            light += (color * (core + halo + streak) + ghosts * luminance(color)) * seen * sun_glare;
        }
    }
    return vec4<f32>(light * strength * facing, 1.0);
}
