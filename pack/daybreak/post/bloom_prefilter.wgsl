// Bloom, step 1, at a quarter of the world's size: what is bright enough to glow.
// Each texel here covers 4 x 4 of the picture's; four bilinear taps read all sixteen.
fn post(input: PostInput) -> vec4<f32> {
    let px = 1.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    var weight = 0.0;
    for (var i = 0; i < 4; i++) {
        let corner = vec2<f32>(f32(i & 1), f32(i >> 1u)) * 2.0 - 1.0;
        let uv = input.uv + corner * px;
        let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
        let l = luminance(c);
        // Only the brightest part glows; the open sky far less than lights and the sun. White
        // things (clouds, snow, quartz) glow less than coloured light sources of the same
        // brightness, so a snowfield at noon doesn't haze over.
        let sky = select(1.0, 0.15, depth_at(uv) == 0.0);
        let chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
        let white = mix(0.2, 1.0, smoothstep(0.05, 0.3, chroma));
        let bright = c * smoothstep(0.82, 1.0, l) * sky * white;
        // Karis' average: a single very bright texel can't flicker the whole glow.
        let w = 1.0 / (1.0 + luminance(bright));
        sum += bright * w;
        weight += w;
    }
    return vec4<f32>(sum / weight, 1.0);
}
