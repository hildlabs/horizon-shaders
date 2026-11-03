// Shared by every stage of Daybreak, put after Horizon's prelude (which declares `frame`).
// Positions are camera-relative, in blocks; directions are in world axes (x east, y up, z south).

// The manifest's [[materials]] ids.
const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_VINE: u32 = 5u;

const MOON_COLOR: vec3<f32> = vec3<f32>(0.32, 0.42, 0.72);

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
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

// A soft shoulder above 0.8, so bright light rolls off into white instead of clipping.
fn shoulder(c: vec3<f32>) -> vec3<f32> {
    let over = max(c - vec3<f32>(0.8), vec3<f32>(0.0));
    return min(c, vec3<f32>(0.8)) + 0.2 * (vec3<f32>(1.0) - exp(-over * 5.0));
}

// The height of water waves at world `xz`, 0..1 (0 the crest): two crossing swells and a
// faster chop. A function of world position only, so neighbouring blocks meet without seams.
fn water_wave(xz: vec2<f32>, t: f32) -> f32 {
    let swell = sin(xz.x * 0.9 + t * 1.3) * sin(xz.y * 0.7 + t * 1.1);
    let chop = sin((xz.x + xz.y) * 1.7 - t * 2.1) * 0.5;
    return 0.5 - (swell + chop) / 3.0;
}
