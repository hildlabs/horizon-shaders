// Where the corners of terrain are drawn, in the world and in the shadow map: leaves and plants
// in the wind, and rolling water. This file joins the material's module, so its overrides are
// read there too.
override waving: bool = true;
override wave_strength: f32 = 1.0;
override water_waves: bool = true;

// How far water's surface sinks at a wave's trough, in blocks.
const WATER_AMPLITUDE: f32 = 0.06;

// Wind at world point `p`: a slow gust over a faster sway, varying across the land.
fn wind(p: vec3<f32>, t: f32) -> vec3<f32> {
    let phase = dot(p.xz, vec2<f32>(0.37, 0.23));
    let gust = 0.6 + 0.4 * sin(t * 0.35 + p.x * 0.02 + p.z * 0.015);
    let x = sin(t * 1.9 + phase * 2.1) + 0.5 * sin(t * 3.7 + p.z * 1.3);
    let z = sin(t * 1.6 + phase * 1.7 + 1.3) + 0.5 * sin(t * 4.1 + p.x * 1.1);
    return vec3<f32>(x, 0.0, z) * gust;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    let world = p + frame.camera_position;
    let t = frame.time;

    if water_waves && input.fluid == 1u && fract(world.y) > 0.02 {
        // Only corners above the block's floor move, and only down, so water never rises
        // through what lies over it and its sides stay closed.
        p.y -= water_wave(world.xz, t) * WATER_AMPLITUDE;
        return p;
    }

    if !waving || wave_strength <= 0.0 || input.material == 0u || input.material > MAT_VINE {
        return p;
    }
    // Sheltered plants hardly move, and rain stirs them more.
    let exposed = smoothstep(0.3, 0.9, input.light.y) * (1.0 + frame.rain * 0.8);
    let w = wind(world, t) * wave_strength * exposed;
    // `uv.y` runs down the sprite: 0 at its top, 1 at its foot.
    let top = 1.0 - input.uv.y;
    switch input.material {
        case MAT_LEAVES: {
            p += (w + vec3<f32>(0.0, w.x * 0.5, 0.0)) * 0.03;
        }
        case MAT_PLANT: {
            p += w * (0.11 * top);
        }
        case MAT_TALL_LOWER: {
            p += w * (0.11 * 0.5 * top);
        }
        case MAT_TALL_UPPER: {
            p += w * (0.11 * (0.5 + 0.5 * top));
        }
        default: {
            p += w * 0.025;
        }
    }
    return p;
}
