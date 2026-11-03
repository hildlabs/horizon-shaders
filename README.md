# Daybreak: a shader pack for Horizon

**Daybreak** is a shader pack for [Horizon](https://github.com/horizon-rust/horizon), the Rust
reimplementation of Minecraft: Java Edition. It's written in WGSL against Horizon's own shader
API (0.1). It runs inside Horizon's renderer and doesn't replace it, so Horizon's culling,
batching, LOD and meshing stay in charge, and the pack adds as little GPU time as possible.

| Effect | How | Cost |
| --- | --- | --- |
| Sun and moon shadows | 2048² distorted shadow map, normal-offset lookup, slope-scaled bias, 1/4/9-tap grid PCF (smooth edges, no noise) | the shadow pass plus up to 9 compare taps per pixel |
| Day and night light | own sun, sky and block light, wrapped diffuse, with vanilla's face shade taken back out | inside terrain's own draw: no extra pass |
| Coloured block light | soul fire blue, redstone red, copper green, froglights… (`[[lights]]`) | one 3D texture read |
| Mob shadows | mobs, chests and particles take the sun's shadow and the sky's tint in the composite, by a terrain mask (`set_surface`) and the same shadow map | 4 compare taps, only on non-terrain pixels |
| Light from held torches | Horizon's dynamic lights, in the item's colour, per pixel | Horizon's own: none from the pack |
| Waving leaves and plants | vertex stage, continuous across two-block plants | a few `sin`s per vertex |
| Water | rolling waves, Fresnel reflection (water mirror), refraction, depth absorption, sun glint | half-resolution mirror, can be turned off |
| Sky | deeper zenith, warm sunset band, sun glow; vanilla's horizon kept, so fog never seams | per sky pixel |
| Sun rays | screen-space radial march over the sky mask, **quarter resolution**, 16 dithered steps | ~1/16 of the pixels |
| Sun glare | bloom, halo, anamorphic streak and lens ghosts, dimmed by how much of the sun shows (9 taps) | in the same quarter-resolution pass |
| Haze | aerial perspective from depth: distant land fades to the sky, warm toward the sun | part of the composite |
| Bloom | Karis-averaged bright pass and a 13-tap two-ring blur, both **quarter resolution** | ~1/16 of the pixels |
| Grade | eye adaptation from the light at the camera, shoulder, S-curve, saturation, vignette, dither | one full-screen pass |

Every option is a WGSL `override` constant, so a switched-off effect is a branch on a constant:
the GPU never runs it, and nothing is recompiled with text substitution.

## Presets

The most expensive part, the shadow pass, draws the terrain in its square again each frame and
is fixed by the manifest, out of reach of any option. So Daybreak comes as four packs built
from one source by [`daybreak-build`](tools/daybreak-build), a small Rust tool, from
[`presets.toml`](presets.toml):

| Pack | Shadow map | Water mirror | Mob shadows | Budget |
| --- | --- | --- | --- | --- |
| Daybreak Low | none | off | off | 0.5 ms |
| Daybreak Medium | 1024², 64 blocks, sharp | off | on | 1.0 ms |
| Daybreak High | 2048², 96 blocks, soft | on | on | 2.0 ms |
| Daybreak Ultra | 4096², 160 blocks, very soft | on | on | 3.5 ms |

Each one's options can still be changed in the game; a preset only sets their defaults.

## Try it

1. Install the Horizon launcher and a Nightly from 2026-11-03 or newer.
2. Build the presets and install them into the game:
   ```powershell
   cargo run -p daybreak-build -- --check --install "$env:APPDATA\horizon\shaderpacks"
   ```
   For working on the shaders, link the source pack instead (it hot-reloads every save):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\link-pack.ps1
   ```
3. In the game: **Options > Horizon Settings > Shader Packs > Daybreak High (Horizon)** (or
   Low, Medium, Ultra), then **Shader Options…** for the settings.
4. For light from torches in your hand and dropped on the ground, turn on Horizon's
   **Dynamic lights** in the game's Horizon settings (it is off by default).
5. Press **F3** to see each pass's GPU time.

## Develop

```sh
cargo install --git https://github.com/horizon-rust/horizon --rev 294448014fba585f8d5d09dd8886f482493b6417 horizon-shader-api --locked
horizon-shader check pack/daybreak    # what the game, the launcher and the registry check
horizon-shader pack pack/daybreak     # writes daybreak-<version>.hshader
cargo test -p daybreak-build          # the preset tool's tests
cargo run -p daybreak-build -- --check --pack   # every preset into dist/, checked and packaged
```

A WGSL line tagged `// preset:mob-shadows` is left out of presets with `mob_shadows = false`.

| File | Stage |
| --- | --- |
| `common.wgsl` | shared: material ids, the light's colour, noise, the tone shoulder, the water wave |
| `vertex.wgsl` | wind on leaves and plants, waves on water |
| `material.wgsl`, `lighting.wgsl`, `water.wgsl` | how terrain and water are lit |
| `sky.wgsl` | the sky's colour |
| `post/*.wgsl` | bloom prefilter → bloom blur → sun rays → composite |

The API reference is Horizon's
[`docs/api/shaders-reference.md`](https://github.com/horizon-rust/horizon/blob/main/docs/api/shaders-reference.md).

## Credits

Original code, MIT licensed. The techniques come from published work: interleaved gradient noise
and the Karis average (Jimenez, *Next Generation Post Processing in Call of Duty: Advanced Warfare*,
2014), Schlick's Fresnel approximation (1994), Vogel-spiral disc sampling. No code from other
shader packs and no Minecraft assets are included.
