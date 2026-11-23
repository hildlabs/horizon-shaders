// Shared by every stage of Daybreak, put after Horizon's prelude (which declares `frame`).
// Positions are camera-relative, in blocks; directions are in world axes (x east, y up, z south).

// The manifest's [[materials]] ids.
const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_VINE: u32 = 5u;

const MOON_COLOR: vec3<f32> = vec3<f32>(0.32, 0.42, 0.72);

// Daybreak's lighting and grading were designed in display space. API 0.2 passes
// linear colours, so encode on entry to that existing look and decode on exit.
// The functions also accept values above white, which HDR and bright lights can use.
fn display_color(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn linear_color(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn luminance(c: vec3<f32>) -> f32 {
    // This is a display-space artistic measure used by the original grade.
    return dot(c, frame.luminance);
}

// 1 by day, 0 by night, eased across the horizon.
fn daylight() -> f32 {
    return smoothstep(-0.06, 0.12, frame.sun_direction.y);
}

// 1 with the sun on the horizon, 0 from a third of the way up.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.35, abs(frame.sun_direction.y));
}

// The colour and strength of the light from `frame.light_direction` (the sun by day, the
// moon by night). It fades to 0 as that body reaches the horizon, so the switch from sun to
// moon (and its shadow map) never pops.
fn direct_light() -> vec3<f32> {
    let l = frame.light_direction;
    let is_sun = dot(l, frame.sun_direction) > 0.0;
    // Orange only near the horizon: by mid-afternoon the light is a soft warm white, so green
    // stays green instead of turning yellow.
    let high = smoothstep(0.0, 0.28, l.y);
    let sun = mix(vec3<f32>(1.0, 0.52, 0.24), vec3<f32>(1.0, 0.94, 0.85), high);
    let color = select(MOON_COLOR * 0.16, sun, is_sun);
    let weather = 1.0 - 0.85 * max(frame.rain, frame.thunder);
    return color * smoothstep(0.0, 0.08, l.y) * weather;
}

// Interleaved gradient noise (Jimenez 2014): a cheap, well spread 0..1 value per pixel.
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// A soft shoulder above 0.8. It keeps growing so highlights above SDR white survive HDR.
fn shoulder(c: vec3<f32>) -> vec3<f32> {
    let over = max(c - vec3<f32>(0.8), vec3<f32>(0.0));
    return min(c, vec3<f32>(0.8)) + 0.2 * (vec3<f32>(1.0) - exp(-over * 3.75)) + 0.25 * over;
}

// The height of water waves at world `xz`, 0..1 (0 the crest): three swells in directions
// that line up with neither the block grid nor each other, so the surface doesn't tile into a
// checkerboard. A function of world position only, so neighbouring blocks meet without seams.
// `water_normal` (water.wgsl) takes its slope from these same three waves.
fn water_wave(xz: vec2<f32>, t: f32) -> f32 {
    let w1 = sin(dot(xz, vec2<f32>(0.42, 0.25)) + t * 1.1) * 0.45;
    let w2 = sin(dot(xz, vec2<f32>(-0.31, 0.58)) + t * 1.45) * 0.35;
    let w3 = sin(dot(xz, vec2<f32>(0.67, -0.52)) - t * 1.85) * 0.20;
    return 0.5 - (w1 + w2 + w3) * 0.5;
}
