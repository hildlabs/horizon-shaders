// Bloom, step 2, at a quarter of the world's size: the bright parts spread into a soft glow.
// Thirteen bilinear taps on two rings reach about 20 of the picture's pixels in one pass.
fn post(input: PostInput) -> vec4<f32> {
    let texel = 1.0 / vec2<f32>(textureDimensions(bloom_a));
    var sum = textureSampleLevel(bloom_a, linear_sampler, input.uv, 0.0).rgb * 0.2;
    for (var i = 0; i < 6; i++) {
        let a = f32(i) * 1.0471976;
        let dir = vec2<f32>(cos(a), sin(a));
        // The outer ring sits between the inner one's taps.
        let outer = vec2<f32>(cos(a + 0.5235988), sin(a + 0.5235988));
        sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + dir * 1.5 * texel, 0.0).rgb * 0.08;
        sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + outer * 4.0 * texel, 0.0).rgb * 0.0533;
    }
    return vec4<f32>(sum, 1.0);
}
