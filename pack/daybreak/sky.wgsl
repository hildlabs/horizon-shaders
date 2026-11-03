// The Overworld's sky: a deeper blue overhead, a warm band and glow around a low sun, and a
// horizon that stays vanilla's, so it meets the fog of distant terrain without a seam.
// Vanilla's sun, moon, stars and clouds are drawn over it.
override sky_style: f32 = 0.8;

fn sky(input: SkyInput) -> vec4<f32> {
    let vanilla = input.color;
    if frame.dimension != 0 || sky_style <= 0.0 {
        return vanilla;
    }
    let d = input.direction;
    let up = max(d.y, 0.0);
    let day = daylight();

    // By day: from a pale horizon to a deep zenith.
    let zenith = vec3<f32>(0.22, 0.42, 0.85);
    let horizon = vec3<f32>(0.68, 0.8, 0.95);
    var c = mix(horizon, zenith, pow(up, 0.5));
    // Around the sun, a glow, and at sunrise and sunset a warm band along the horizon on the
    // sun's side.
    let mu = max(dot(d, frame.sun_direction), 0.0);
    // A wide, faint haze and a tighter halo: vanilla's sun disc is drawn over both.
    let glow = pow(mu, 8.0) * 0.1 + pow(mu, 80.0) * 0.3;
    let side = pow(mu * 0.5 + 0.5, 3.0);
    let band = pow(1.0 - up, 4.0) * side * sun_low();
    c = mix(c, vec3<f32>(1.0, 0.48, 0.22), band * 0.85);
    c += vec3<f32>(1.0, 0.8, 0.55) * glow * day;
    // Darker as the sun sets: vanilla's own colour carries the night.
    c = mix(vanilla.rgb, c * mix(0.35, 1.0, day), day * (1.0 - frame.rain * 0.85));

    // Vanilla's colour at the horizon itself, ours from a little above it.
    let blend = smoothstep(0.0, 0.2, d.y) * sky_style;
    return vec4<f32>(mix(vanilla.rgb, clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), blend), vanilla.a);
}
