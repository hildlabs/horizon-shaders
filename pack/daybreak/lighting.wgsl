// Light for the material stage: the shadow map, the sky's light and the light of blocks.
// The overrides it reads are declared in material.wgsl.

// A face turned to the noon sun gets SUN + SKY, a little over vanilla's full daylight (1), so
// white blocks stay just under white; one in the shade gets SKY, about half.
const SUN_INTENSITY: f32 = 0.62;
const SKY_INTENSITY: f32 = 0.52;

// The ground one shadow texel covers at camera-relative `p`, in blocks: the map's distortion
// makes texels near the camera small and far ones large.
fn shadow_texel(p: vec3<f32>) -> f32 {
    let k = frame.shadow_distortion;
    let r = length((frame.shadow_view_proj * vec4<f32>(p, 1.0)).xy);
    let d = r * k + 1.0 - k;
    return frame.shadow_center_texel * d * d;
}

// 1 where `p` is lit by `frame.light_direction`, 0 in shadow. `offset_dir` is the direction
// the point is pushed off its surface before the lookup (its normal, or the light for plants),
// and `ndl` how directly the surface faces the light (1 for plants, which face it whichever
// way they turn).
fn sun_shadow(p: vec3<f32>, offset_dir: vec3<f32>, ndl: f32) -> f32 {
    if !shadows || frame.has_shadow == 0u {
        return 1.0;
    }
    let dist = length(p);
    if dist > frame.shadow_distance {
        return 1.0;
    }
    // A surface lit at a slant drops away from the light across each shadow texel and the
    // filter's width: without an offset and a bias that grow with the slant, part of every
    // texel falls behind the surface itself and the ground shows stripes (shadow acne), worst
    // at sunrise and sunset. `zscale` is the map's depth per block.
    let ground = shadow_texel(p);
    let c = clamp(ndl, 0.05, 1.0);
    let slope = min(sqrt(1.0 - c * c) / c, 12.0);
    let s = shadow_position(p + offset_dir * ground * (1.5 + min(slope, 4.0)));
    if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) {
        return 1.0;
    }
    let m = frame.shadow_view_proj;
    let zscale = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
    let reach = select(select(2.5, 1.5, shadow_softness == 1u), 0.5, shadow_softness == 0u);
    let z = s.z - zscale * ground * (1.0 + (1.0 + reach) * slope);

    // Each compare tap is already a bilinear 2 x 2 filter. A fixed grid of them gives a smooth
    // edge with no per-pixel noise, which would crawl over textures without TAA.
    let texel = 1.0 / frame.shadow_resolution;
    var lit = 0.0;
    if shadow_softness == 0u {
        lit = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, z);
    } else if shadow_softness == 1u {
        // 2 x 2 taps a texel apart: a 4 x 4 texel tent.
        for (var i = 0; i < 4; i++) {
            let o = vec2<f32>(f32(i & 1), f32(i >> 1u)) * 2.0 - 1.0;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + o * texel, z);
        }
        lit *= 0.25;
    } else {
        // 3 x 3 taps 1.5 texels apart: twice as wide.
        for (var i = 0; i < 9; i++) {
            let o = vec2<f32>(f32(i % 3), f32(i / 3)) - 1.0;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + o * 1.5 * texel, z);
        }
        lit /= 9.0;
    }
    // The map's last tenth fades out, so its edge never shows as a line.
    return mix(lit, 1.0, smoothstep(0.9, 1.0, dist / frame.shadow_distance));
}

// The light falling on a surface of normal `n` at `p`, except the direct light's.
// `light` is the vanilla block and sky light, 0..1; `colored` the frame's coloured lights there.
fn ambient_light(p: vec3<f32>, n: vec3<f32>, light: vec2<f32>, colored: vec3<f32>) -> vec3<f32> {
    let day = daylight();
    // The sky: bluish by day, a dim blue at night, greyer in rain.
    // The shade takes the sky's blue: against the warm sun, that is what makes daylight look
    // like daylight.
    let day_sky = mix(frame.sky_color, vec3<f32>(0.9, 0.95, 1.0), 0.3) * SKY_INTENSITY;
    let night_sky = vec3<f32>(0.045, 0.06, 0.11);
    var sky = mix(night_sky, day_sky, day);
    sky = mix(sky, vec3<f32>(luminance(sky)), frame.rain * 0.6);
    // Faces turned up see more of the sky than those turned down.
    let facing = 0.8 + 0.2 * n.y;
    let from_sky = sky * (light.y * light.y) * facing * ambient_strength;
    // A torch hardly shows in daylight, as in vanilla, which takes the brighter of the two
    // lights rather than their sum: under the open daytime sky, block light (a torch in hand
    // above all) only fills in a little.
    let daylit = light.y * day;
    let from_blocks = block_light(p, light.x, colored) * (1.0 - 0.8 * daylit);

    return from_sky + from_blocks + darkest();
}

// The light of blocks at `p` for vanilla block light `level` (0..1): a warm falloff, in its
// source's colour where the manifest gives one. Horizon's dynamic lights (a torch in hand)
// already raise `level`; `colored` is their smooth, per-pixel part, in the item's colour.
fn block_light(p: vec3<f32>, level: f32, colored: vec3<f32>) -> vec3<f32> {
    // Torches, lanterns, fire, glowstone and lava: the warm light most of the world has. They
    // are not in `[[lights]]` (which only lists light of another colour), so Horizon has fewer
    // sources to spread each time the grid moves or a lamp switches.
    var tint = vec3<f32>(1.0, 0.64, 0.35);
    // Most of the world has no block light: skip the 3D texture read there.
    if colored_lights && level > 0.0 {
        let c = block_light_color(p);
        tint = mix(tint, c.rgb, clamp(c.a, 0.0, 1.0));
    }
    return (tint * pow(level, 2.2) * 1.5 + colored) * block_light_strength;
}

// A cool floor, so caves are dark but never black; the Brightness option lifts it.
fn darkest() -> vec3<f32> {
    return vec3<f32>(0.85, 0.9, 1.0) * 0.025 * (1.0 + 3.0 * frame.brightness);
}

// The Nether's and the End's light, which have no sun or sky: an ambient glow in the colour of
// the biome's fog (crimson red, warped teal, soul valley blue, basalt grey, the End's purple),
// under the light of blocks, which carries most of the picture.
fn underworld_light(p: vec3<f32>, light: vec2<f32>, colored: vec3<f32>) -> vec3<f32> {
    let fog = frame.fog_color;
    let hue = fog / max(max(fog.r, max(fog.g, fog.b)), 0.02);
    let strength = select(0.2, 0.3, frame.dimension == 1);
    let glow = mix(vec3<f32>(1.0), hue, 0.55) * strength * ambient_strength;
    return glow + block_light(p, light.x, colored) * 1.1 + darkest();
}

// The shade vanilla bakes into a face's tint (0.5 down, 1 up, 0.8 north and south, 0.6 east
// and west), to take it back out where Daybreak lights the face itself.
fn face_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if a.y > 0.99 {
        return select(0.5, 1.0, n.y > 0.0);
    }
    if a.z > 0.99 {
        return 0.8;
    }
    if a.x > 0.99 {
        return 0.6;
    }
    return 1.0;
}
